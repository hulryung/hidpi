// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics

// MARK: - Display Mode Info

struct DisplayModeInfo {
    let modeNumber: Int32
    let width: Int32             // rendered ("look like") width
    let height: Int32            // rendered ("look like") height
    let backingWidth: Int32      // actual backing pixel width
    let backingHeight: Int32     // actual backing pixel height (estimated)
    let bitsPerPixel: Int32
    let refreshRate: Int32       // Hz
    let density: Float           // backingWidth / width (2.0 = HiDPI)
    let isHiDPI: Bool
    let flags: UInt32
    let ioFlags: UInt32

    var description: String {
        let hiDPILabel = isHiDPI ? " [HiDPI]" : ""
        let resInfo: String
        if isHiDPI {
            resInfo = "\(width)x\(height) (backed by \(backingWidth)x\(backingHeight))"
        } else {
            resInfo = "\(width)x\(height)"
        }
        return String(format: "  Mode %3d: %@ @ %dHz, %dbpp%@",
                      modeNumber, resInfo, refreshRate, bitsPerPixel, hiDPILabel)
    }
}

// MARK: - Display Manager

struct DisplayManager {

    /// List all connected displays
    static func listDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        let _ = CGSGetDisplayList(32, &displays, &displayCount)
        return Array(displays.prefix(Int(displayCount)))
    }

    /// Get all display modes for a display
    static func getDisplayModes(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        var modeCount: Int32 = 0
        guard CGSGetNumberOfDisplayModes(displayID, &modeCount) == .success else {
            return []
        }

        var modes: [DisplayModeInfo] = []
        for i in 0..<modeCount {
            var desc = CGSDisplayModeDescription()
            let err = CGSGetDisplayModeDescriptionOfLength(displayID, i, &desc, Int32(MemoryLayout<CGSDisplayModeDescription>.size))
            if err == .success {
                let bw = desc.backingWidth
                // Estimate backing height from density
                let density = desc.density
                let bh = Int32(Float(desc.height) * density)

                modes.append(DisplayModeInfo(
                    modeNumber: desc.modeNumber,
                    width: desc.width,
                    height: desc.height,
                    backingWidth: bw,
                    backingHeight: bh,
                    bitsPerPixel: desc.bitsPerPixel,
                    refreshRate: desc.refreshRate,
                    density: density,
                    isHiDPI: desc.isHiDPI,
                    flags: desc.flags,
                    ioFlags: desc.ioFlags
                ))
            }
        }
        return modes
    }

    /// Get current display mode number
    static func getCurrentMode(for displayID: CGDirectDisplayID) -> Int32 {
        var mode: Int32 = 0
        let _ = CGSGetCurrentDisplayMode(displayID, &mode)
        return mode
    }

    /// Switch display mode
    static func setDisplayMode(displayID: CGDirectDisplayID, modeNumber: Int32) -> Bool {
        let err = CGSConfigureDisplayMode(nil, displayID, modeNumber)
        return err == .success
    }

    /// Find best HiDPI mode matching target "look like" resolution
    static func findHiDPIMode(displayID: CGDirectDisplayID, width: Int32, height: Int32) -> DisplayModeInfo? {
        let modes = getDisplayModes(for: displayID)
        // Look for HiDPI mode where the rendered resolution matches the target
        return modes.first { mode in
            mode.isHiDPI && mode.width == width && mode.height == height
        }
    }

    /// Get display info dictionary via CoreDisplay
    static func getDisplayInfo(for displayID: CGDirectDisplayID) -> [String: Any]? {
        guard let cfDict = CoreDisplay_DisplayCreateInfoDictionary(displayID) else { return nil }
        return cfDict as? [String: Any]
    }

    /// Get display info dictionary via SkyLight
    static func getSLSDisplayInfo(for displayID: CGDirectDisplayID) -> [String: Any]? {
        guard let cfDict = SLSCopyDisplayInfoDictionary(displayID) else { return nil }
        return cfDict as? [String: Any]
    }

    /// Trigger display redetection via SkyLight private API
    static func redetectDisplays() {
        SLSDetectDisplays()
    }

    /// Get vendor/product ID from display
    static func getVendorProductID(for displayID: CGDirectDisplayID) -> (vendorID: UInt32, productID: UInt32) {
        let vendorID = CGDisplayVendorNumber(displayID)
        let productID = CGDisplayModelNumber(displayID)
        return (UInt32(vendorID), UInt32(productID))
    }

    /// Get EDID data from display via IOAVService
    static func getEDID(for displayID: CGDirectDisplayID) -> Data? {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("DCPAVServiceProxy") ?? IOServiceMatching("IOFramebufferI2CInterface")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            if let avService = IOAVServiceCreateWithService(kCFAllocatorDefault, service)?.takeRetainedValue() {
                var edidData: CFData?
                if IOAVServiceCopyEDID(avService, &edidData) == KERN_SUCCESS, let edid = edidData {
                    IOObjectRelease(service)
                    return edid as Data
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        return nil
    }

    /// Print display summary
    static func printDisplaySummary(displayID: CGDirectDisplayID) {
        let (vendorID, productID) = getVendorProductID(for: displayID)
        let currentMode = getCurrentMode(for: displayID)
        let isMain = CGDisplayIsMain(displayID) != 0
        let isBuiltIn = CGDisplayIsBuiltin(displayID) != 0
        let bounds = CGDisplayBounds(displayID)

        print("Display 0x\(String(displayID, radix: 16))")
        print("  Main: \(isMain), Built-in: \(isBuiltIn)")
        print("  VendorID: 0x\(String(vendorID, radix: 16)), ProductID: 0x\(String(productID, radix: 16))")
        print("  Bounds: \(Int(bounds.width))x\(Int(bounds.height)) at (\(Int(bounds.origin.x)),\(Int(bounds.origin.y)))")
        print("  Current mode: \(currentMode)")

        if SLSDisplaySupportsHDRMode(displayID) {
            let hdrEnabled = SLSDisplayIsHDRModeEnabled(displayID)
            print("  HDR: supported, enabled=\(hdrEnabled)")
        }
    }
}
