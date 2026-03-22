// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics
import IOKit

// MARK: - DisplayManager

/// Manages all connected displays, enumerating modes and applying configuration changes.
class DisplayManager: ObservableObject {

    @Published var displays: [DisplayInfo] = []
    @Published var pendingRollback: RollbackInfo?

    let settingsManager = SettingsManager.shared

    /// Tracks a pending mode change that can be rolled back
    struct RollbackInfo {
        let displayID: CGDirectDisplayID
        let previousModeID: Int32
        let newModeID: Int32
        let timer: Timer
        let deadline: Date
    }

    init() {
        refreshDisplays()
    }

    // MARK: - Display Enumeration

    /// Enumerate all connected displays and populate the `displays` array.
    func refreshDisplays() {
        var displayCount: UInt32 = 0
        let _ = CGSGetDisplayList(0, nil, &displayCount)
        guard displayCount > 0 else {
            DispatchQueue.main.async { self.displays = [] }
            return
        }

        var displayIDs = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        let _ = CGSGetDisplayList(displayCount, &displayIDs, &displayCount)

        var newDisplays: [DisplayInfo] = []

        for displayID in displayIDs.prefix(Int(displayCount)) {
            // Skip dummy/null displays (1x1, no vendor)
            let bounds = CGDisplayBounds(displayID)
            if bounds.width <= 1 && bounds.height <= 1 { continue }

            let vendorID = CGDisplayVendorNumber(displayID)
            let productID = CGDisplayModelNumber(displayID)
            let name = displayName(for: displayID)
            let isMain = CGDisplayIsMain(displayID) != 0
            let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
            let modes = enumerateModes(for: displayID)
            let currentModeID = currentMode(for: displayID)
            let supportsHDR = SLSDisplaySupportsHDRMode(displayID)
            let hdrEnabled = SLSDisplayIsHDRModeEnabled(displayID)
            let hasOverride = checkOverrideExists(vendorID: vendorID, productID: productID)

            let info = DisplayInfo(
                id: displayID,
                vendorID: vendorID,
                productID: productID,
                name: name,
                isMain: isMain,
                isBuiltIn: isBuiltIn,
                isVirtual: false,
                currentModeID: currentModeID,
                modes: modes,
                bounds: bounds,
                hasOverride: hasOverride,
                supportsHDR: supportsHDR,
                hdrEnabled: hdrEnabled
            )

            // Estimate screen diagonal from EDID or known panel sizes
            if let edid = readEDID(for: displayID), let size = edid.physicalSize {
                info.estimateScreenDiagonal(widthCm: size.widthCm, heightCm: size.heightCm)
            } else if let nativeMode = modes.first(where: { $0.flags & 0x2000000 != 0 }),
                      let diag = KnownDisplaySize.estimateDiagonal(
                          nativeWidth: Int(nativeMode.backingWidth),
                          nativeHeight: Int(nativeMode.backingHeight),
                          vendorID: vendorID
                      ) {
                info.screenDiagonalInches = diag
            } else {
                // Fallback: estimate from bounds (highest mode backing resolution)
                let maxMode = modes.max(by: { $0.backingWidth * $0.backingHeight < $1.backingWidth * $1.backingHeight })
                if let m = maxMode {
                    if let diag = KnownDisplaySize.estimateDiagonal(
                        nativeWidth: Int(m.backingWidth),
                        nativeHeight: Int(m.backingHeight),
                        vendorID: vendorID
                    ) {
                        info.screenDiagonalInches = diag
                    }
                }
            }

            // Apply saved settings
            applySettingsForDisplay(info)

            newDisplays.append(info)
        }

        DispatchQueue.main.async {
            self.displays = newDisplays
        }
    }

    // MARK: - Mode Setting

    /// Apply a display mode using a proper display configuration transaction.
    /// Returns `true` on success.
    @discardableResult
    func setDisplayMode(displayID: CGDirectDisplayID, modeNumber: Int32) -> Bool {
        var configRef: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&configRef) == .success,
              let config = configRef else {
            NSLog("[HiDPI] Failed to begin display configuration")
            return false
        }

        let configPtr = UnsafeMutableRawPointer(config)
        let err = CGSConfigureDisplayMode(configPtr, displayID, modeNumber)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            NSLog("[HiDPI] CGSConfigureDisplayMode failed: \(err.rawValue)")
            return false
        }

        let completeErr = CGCompleteDisplayConfiguration(config, .permanently)
        if completeErr == .success {
            NSLog("[HiDPI] Switched display 0x%x to mode %d", displayID, modeNumber)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshDisplays()
            }
            return true
        } else {
            NSLog("[HiDPI] CGCompleteDisplayConfiguration failed: \(completeErr.rawValue)")
            return false
        }
    }

    // MARK: - Mode Setting with Safety Rollback

    /// Applies a display mode with a 15-second timer. If not confirmed, rolls back.
    @discardableResult
    func setModeWithRollback(displayID: CGDirectDisplayID, modeNumber: Int32) -> Bool {
        let previousModeID = currentMode(for: displayID)

        guard setDisplayMode(displayID: displayID, modeNumber: modeNumber) else {
            return false
        }

        // Cancel any existing rollback
        cancelRollback()

        // Start 15-second rollback timer
        let timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            NSLog("[HiDPI] Rollback timer expired — reverting display 0x%x to mode %d", displayID, previousModeID)
            self?.setDisplayMode(displayID: displayID, modeNumber: previousModeID)
            DispatchQueue.main.async {
                self?.pendingRollback = nil
            }
        }

        DispatchQueue.main.async {
            self.pendingRollback = RollbackInfo(
                displayID: displayID,
                previousModeID: previousModeID,
                newModeID: modeNumber,
                timer: timer,
                deadline: Date().addingTimeInterval(15)
            )
        }

        return true
    }

    /// Confirms the current mode change, cancelling the rollback timer.
    func confirmModeChange() {
        cancelRollback()
    }

    /// Manually reverts to the previous mode.
    func revertModeChange() {
        guard let rollback = pendingRollback else { return }
        rollback.timer.invalidate()
        setDisplayMode(displayID: rollback.displayID, modeNumber: rollback.previousModeID)
        DispatchQueue.main.async {
            self.pendingRollback = nil
        }
    }

    private func cancelRollback() {
        pendingRollback?.timer.invalidate()
        DispatchQueue.main.async {
            self.pendingRollback = nil
        }
    }

    // MARK: - HDR Control

    /// Toggle HDR mode for a display. Returns the new HDR state.
    @discardableResult
    func toggleHDR(displayID: CGDirectDisplayID) -> Bool {
        let currentlyEnabled = SLSDisplayIsHDRModeEnabled(displayID)
        let newState = !currentlyEnabled
        let result = SLSDisplaySetHDRModeEnabled(displayID, newState)
        if result == .success {
            NSLog("[HiDPI] HDR %@ for display 0x%x", newState ? "enabled" : "disabled", displayID)
            if let display = displays.first(where: { $0.id == displayID }) {
                DispatchQueue.main.async {
                    display.hdrEnabled = newState
                }
            }
            return newState
        }
        NSLog("[HiDPI] Failed to set HDR mode: \(result.rawValue)")
        return currentlyEnabled
    }

    // MARK: - Screen Rotation

    /// Set display rotation (0, 90, 180, 270 degrees).
    @discardableResult
    func setRotation(displayID: CGDirectDisplayID, angle: Int) -> Bool {
        let validAngles = [0, 90, 180, 270]
        guard validAngles.contains(angle) else {
            NSLog("[HiDPI] Invalid rotation angle: \(angle)")
            return false
        }

        let result = SLSSetDisplayRotation(displayID, Float(angle))
        if result == .success {
            NSLog("[HiDPI] Set rotation to %d° for display 0x%x", angle, displayID)
            if let display = displays.first(where: { $0.id == displayID }) {
                DispatchQueue.main.async {
                    display.rotation = angle
                }
            }
            return true
        }
        NSLog("[HiDPI] Failed to set rotation: \(result.rawValue)")
        return false
    }

    // MARK: - EDID Reading

    /// Read EDID data for a display using IOAVService.
    func readEDID(for displayID: CGDirectDisplayID) -> EDIDParser? {
        // Try to find the IOAVService for this display via DCPAVServiceProxy
        guard let matching = IOServiceMatching("DCPAVServiceProxy") else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var port = IOIteratorNext(iterator)
        while port != IO_OBJECT_NULL {
            defer { port = IOIteratorNext(iterator) }

            guard let avServiceUnmanaged = IOAVServiceCreateWithService(kCFAllocatorDefault, port) else {
                IOObjectRelease(port)
                continue
            }
            let avService = avServiceUnmanaged.takeRetainedValue()

            var edidData: CFData?
            let kr = IOAVServiceCopyEDID(avService, &edidData)
            guard kr == KERN_SUCCESS, let cfData = edidData else {
                IOObjectRelease(port)
                continue
            }

            let data = cfData as Data
            let parser = EDIDParser(data: data)

            // Match EDID vendor/product to the display
            if parser.isValid {
                // Return first valid EDID found (imperfect matching for multi-display)
                IOObjectRelease(port)
                return parser
            }

            IOObjectRelease(port)
        }

        return nil
    }

    // MARK: - Settings Integration

    /// Apply saved settings for a display (auto-apply preferred mode, screen diagonal).
    func applySettingsForDisplay(_ display: DisplayInfo) {
        let settings = settingsManager.settingsForDisplay(
            vendorID: display.vendorID,
            productID: display.productID
        )

        // Restore screen diagonal
        if let diagonal = settings.screenDiagonalInches {
            display.screenDiagonalInches = diagonal
        }

        // Auto-apply preferred mode on connect
        if settings.autoApplyOnConnect, let preferredMode = settings.preferredModeID {
            if display.currentModeID != preferredMode &&
               display.modes.contains(where: { $0.id == preferredMode }) {
                NSLog("[HiDPI] Auto-applying preferred mode %d for %@", preferredMode, display.name)
                setDisplayMode(displayID: display.id, modeNumber: preferredMode)
            }
        }
    }

    /// Save current mode as preferred for a display.
    func savePreferredMode(for display: DisplayInfo) {
        settingsManager.updateSettings(
            vendorID: display.vendorID,
            productID: display.productID
        ) { settings in
            settings.preferredModeID = display.currentModeID
        }
    }

    /// Toggle a mode as favorite.
    func toggleFavorite(for display: DisplayInfo, modeID: Int32) {
        settingsManager.updateSettings(
            vendorID: display.vendorID,
            productID: display.productID
        ) { settings in
            if let idx = settings.favoriteResolutions.firstIndex(of: modeID) {
                settings.favoriteResolutions.remove(at: idx)
            } else {
                settings.favoriteResolutions.append(modeID)
            }
        }
    }

    func isFavorite(for display: DisplayInfo, modeID: Int32) -> Bool {
        let settings = settingsManager.settingsForDisplay(
            vendorID: display.vendorID,
            productID: display.productID
        )
        return settings.favoriteResolutions.contains(modeID)
    }

    // MARK: - Redetect

    /// Force the system to redetect displays, then refresh our list.
    func redetectDisplays() {
        SLSDetectDisplays()
        refreshDisplays()
    }

    // MARK: - Info Dictionary

    /// Return the CoreDisplay info dictionary for a given display, if available.
    func getDisplayInfo(for displayID: CGDirectDisplayID) -> [String: Any]? {
        guard let cfDict = CoreDisplay_DisplayCreateInfoDictionary(displayID) else {
            return nil
        }
        return cfDict as? [String: Any]
    }

    // MARK: - Private Helpers

    /// Resolve a human-readable display name from the CoreDisplay info dictionary.
    private func displayName(for displayID: CGDirectDisplayID) -> String {
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0

        if let dict = getDisplayInfo(for: displayID) {
            if let nameDict = dict["DisplayProductName"] as? [String: String],
               let name = nameDict["en_US"] ?? nameDict.values.first {
                // Replace generic "Color LCD" with a meaningful name
                if name == "Color LCD" && isBuiltIn {
                    return builtInDisplayName()
                }
                return name
            }
        }
        return isBuiltIn ? builtInDisplayName() : "Display \(displayID)"
    }

    /// Return a descriptive name for the built-in display based on Mac model.
    private func builtInDisplayName() -> String {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let hw = String(cString: model)

        if hw.contains("MacBookPro") { return "MacBook Pro Built-in Display" }
        if hw.contains("MacBookAir") { return "MacBook Air Built-in Display" }
        if hw.contains("MacBook") { return "MacBook Built-in Display" }
        if hw.contains("iMac") { return "iMac Built-in Display" }
        return "Built-in Display"
    }

    /// Enumerate all modes for a display by walking the private CGS APIs.
    private func enumerateModes(for displayID: CGDirectDisplayID) -> [DisplayMode] {
        var modeCount: Int32 = 0
        let _ = CGSGetNumberOfDisplayModes(displayID, &modeCount)
        guard modeCount > 0 else { return [] }

        let descLength = Int32(MemoryLayout<CGSDisplayModeDescription>.size)
        var modes: [DisplayMode] = []

        for i in 0..<modeCount {
            var desc = CGSDisplayModeDescription()
            let err = CGSGetDisplayModeDescriptionOfLength(displayID, i, &desc, descLength)
            guard err == .success else { continue }

            // HiDPI detection via backing width calculation
            let backingWidth: Int32
            if desc.bitsPerPixel > 0 {
                backingWidth = Int32(desc.bytesPerRow / UInt32(desc.bitsPerPixel / 8))
            } else {
                backingWidth = desc.width
            }
            let density: Float = desc.width > 0 ? Float(backingWidth) / Float(desc.width) : 1.0
            let isHiDPI = density >= 2.0

            // Compute backing height proportionally
            let backingHeight: Int32
            if desc.width > 0 && isHiDPI {
                backingHeight = desc.height * (backingWidth / desc.width)
            } else {
                backingHeight = desc.height
            }

            let isVRR = SLSIsDisplayModeVRR(displayID, desc.modeNumber)
            let isProMotion = SLSIsDisplayModeProMotion(displayID, desc.modeNumber)

            let mode = DisplayMode(
                id: desc.modeNumber,
                width: desc.width,
                height: desc.height,
                backingWidth: backingWidth,
                backingHeight: backingHeight,
                bitsPerPixel: desc.bitsPerPixel,
                refreshRate: desc.refreshRate,
                density: density,
                isHiDPI: isHiDPI,
                isVRR: isVRR,
                isProMotion: isProMotion,
                flags: desc.flags
            )
            modes.append(mode)
        }

        return modes
    }

    /// Read the current mode number for a display.
    private func currentMode(for displayID: CGDirectDisplayID) -> Int32 {
        var modeNumber: Int32 = 0
        let _ = CGSGetCurrentDisplayMode(displayID, &modeNumber)
        return modeNumber
    }

    /// Check whether a display override plist exists on disk.
    private func checkOverrideExists(vendorID: UInt32, productID: UInt32) -> Bool {
        let vendorHex = String(format: "%x", vendorID)
        let productHex = String(format: "%x", productID)
        let path = "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-\(vendorHex)/DisplayProductID-\(productHex)"
        return FileManager.default.fileExists(atPath: path)
    }
}
