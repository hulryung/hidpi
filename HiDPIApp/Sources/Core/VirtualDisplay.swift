// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics

// MARK: - VirtualDisplayManager

/// Manages virtual HiDPI displays using Apple's private CGVirtualDisplay API,
/// discovered through runtime introspection of the CoreGraphics framework.
///
/// The CGVirtualDisplay private framework exposes several Objective-C classes
/// (CGVirtualDisplay, CGVirtualDisplayDescriptor, CGVirtualDisplayMode,
/// CGVirtualDisplaySettings) that are not part of any public SDK. These classes
/// are loaded at runtime via NSClassFromString to avoid direct linkage against
/// private frameworks.
///
/// Retaining the CGVirtualDisplay instance keeps the virtual display connected.
/// Releasing it causes the system to automatically disconnect the display.
final class VirtualDisplayManager: ObservableObject {

    // MARK: - Singleton

    static let shared = VirtualDisplayManager()

    // MARK: - Published State

    /// Tracks all currently active virtual displays and their system-assigned IDs.
    @Published var activeDisplays: [(display: AnyObject, displayID: CGDirectDisplayID)] = []

    // MARK: - Private Properties

    private let workQueue = DispatchQueue(label: "com.hidpi.virtualdisplay", qos: .userInitiated)

    private init() {}

    // MARK: - Runtime Availability

    /// Checks whether the CGVirtualDisplay private classes are available on this system.
    var isAvailable: Bool {
        NSClassFromString("CGVirtualDisplay") != nil
    }

    // MARK: - Create Virtual Display

    /// Creates a new virtual display with the specified parameters.
    ///
    /// This method dynamically loads the private CGVirtualDisplay classes and
    /// configures them using Key-Value Coding (KVC). The virtual display remains
    /// active as long as the returned CGVirtualDisplay object is retained in
    /// the `activeDisplays` array.
    ///
    /// - Parameters:
    ///   - name: Human-readable display name shown in System Settings.
    ///   - width: Maximum pixel width of the virtual display.
    ///   - height: Maximum pixel height of the virtual display.
    ///   - hiDPI: Whether the display should advertise HiDPI/Retina support.
    ///   - refreshRate: Refresh rate in Hz (default 60).
    ///   - vendorID: Vendor identifier embedded in the virtual display metadata.
    ///   - productID: Product identifier embedded in the virtual display metadata.
    ///   - serialNum: Serial number embedded in the virtual display metadata.
    /// - Returns: The `CGDirectDisplayID` assigned by the system, or `nil` on failure.
    func createVirtualDisplay(
        name: String,
        width: Int,
        height: Int,
        hiDPI: Bool = true,
        refreshRate: Int = 60,
        vendorID: UInt32 = 0x1234,
        productID: UInt32 = 0x5678,
        serialNum: UInt32 = 0
    ) -> CGDirectDisplayID? {

        // Resolve private Objective-C classes at runtime via introspection
        guard let runtimeClasses = loadPrivateClasses() else {
            return nil
        }

        // Build the display descriptor with resolution, physical size, and identity
        let descriptor = buildDescriptor(
            using: runtimeClasses,
            name: name,
            width: width,
            height: height,
            refreshRate: refreshRate,
            vendorID: vendorID,
            productID: productID,
            serialNum: serialNum,
            hiDPI: hiDPI
        )

        // Instantiate the virtual display from the descriptor
        guard let display = instantiateDisplay(
            using: runtimeClasses,
            descriptor: descriptor
        ) else {
            return nil
        }

        // Configure HiDPI via the settings object
        configureSettings(
            on: display,
            using: runtimeClasses,
            hiDPI: hiDPI
        )

        // Extract the system-assigned display ID and track the display
        guard let displayID = extractDisplayID(from: display) else {
            return nil
        }

        activeDisplays.append((display: display, displayID: displayID))

        let displayName = descriptor.value(forKey: "name") ?? name
        print("[VirtualDisplay] Created '\(displayName)' -- ID \(displayID) (0x\(String(displayID, radix: 16)))")

        return displayID
    }

    // MARK: - Disconnect

    /// Disconnects a single virtual display by its display ID.
    /// Removing the CGVirtualDisplay object from retention causes the system to disconnect it.
    func disconnectVirtualDisplay(displayID: CGDirectDisplayID) {
        activeDisplays.removeAll { $0.displayID == displayID }
    }

    /// Disconnects all active virtual displays.
    func disconnectAll() {
        activeDisplays.removeAll()
    }

    // MARK: - Private: Runtime Class Loading

    /// Container for the four private Objective-C classes needed to create a virtual display.
    private struct RuntimeClasses {
        let descriptor: NSObject.Type
        let mode: NSObject.Type
        let settings: NSObject.Type
        let display: NSObject.Type
    }

    /// Dynamically loads the private CGVirtualDisplay classes via NSClassFromString.
    private func loadPrivateClasses() -> RuntimeClasses? {
        guard
            let descriptorCls = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
            let modeCls = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
            let settingsCls = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
            let displayCls = NSClassFromString("CGVirtualDisplay") as? NSObject.Type
        else {
            print("[VirtualDisplay] CGVirtualDisplay private classes not found on this system")
            return nil
        }

        return RuntimeClasses(
            descriptor: descriptorCls,
            mode: modeCls,
            settings: settingsCls,
            display: displayCls
        )
    }

    // MARK: - Private: Descriptor Construction

    /// Builds a CGVirtualDisplayDescriptor configured with the provided parameters.
    private func buildDescriptor(
        using classes: RuntimeClasses,
        name: String,
        width: Int,
        height: Int,
        refreshRate: Int,
        vendorID: UInt32,
        productID: UInt32,
        serialNum: UInt32,
        hiDPI: Bool
    ) -> NSObject {
        let descriptor = classes.descriptor.init()

        // Basic display properties set via KVC on the private class
        descriptor.setValue(workQueue, forKey: "queue")
        descriptor.setValue(name, forKey: "name")
        descriptor.setValue(width, forKey: "maxPixelsWide")
        descriptor.setValue(height, forKey: "maxPixelsHigh")

        // Compute physical dimensions in millimeters.
        // Assume a 27-inch diagonal to derive a plausible physical size
        // from the pixel dimensions, matching typical desktop monitor density.
        let physicalSize = computePhysicalSize(width: width, height: height, diagonalInches: 27.0)
        descriptor.setValue(NSValue(size: physicalSize), forKey: "sizeInMillimeters")

        // Display identity metadata
        descriptor.setValue(vendorID, forKey: "vendorID")
        descriptor.setValue(productID, forKey: "productID")
        descriptor.setValue(serialNum, forKey: "serialNum")

        // Build and attach a display mode
        let mode = buildMode(using: classes, width: width, height: height, refreshRate: refreshRate)
        descriptor.setValue([mode], forKey: "modes")

        // Set hiDPI on the descriptor if the property exists
        if descriptor.responds(to: NSSelectorFromString("setHiDPI:")) {
            descriptor.setValue(hiDPI, forKey: "hiDPI")
        }

        return descriptor
    }

    // MARK: - Private: Mode Construction

    /// Creates a CGVirtualDisplayMode with the specified dimensions and refresh rate.
    /// Tries the designated initializer first, falling back to KVC property assignment.
    private func buildMode(
        using classes: RuntimeClasses,
        width: Int,
        height: Int,
        refreshRate: Int
    ) -> NSObject {
        let initSelector = NSSelectorFromString("initWithWidth:height:refreshRate:")

        // Attempt the designated initializer via performSelector
        if classes.mode.instancesRespond(to: initSelector),
           let allocated = classes.mode.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
           let initialized = allocated.perform(
               initSelector,
               with: width as NSNumber,
               with: height as NSNumber
           )?.takeUnretainedValue() as? NSObject {

            // The initializer may only accept width and height; set refreshRate separately
            if initialized.responds(to: NSSelectorFromString("setRefreshRate:")) {
                initialized.setValue(refreshRate, forKey: "refreshRate")
            }
            return initialized
        }

        // Fallback: construct via default init + KVC property assignment
        let mode = classes.mode.init()
        mode.setValue(width, forKey: "width")
        mode.setValue(height, forKey: "height")
        mode.setValue(refreshRate, forKey: "refreshRate")
        return mode
    }

    // MARK: - Private: Display Instantiation

    /// Allocates and initializes a CGVirtualDisplay from the given descriptor.
    private func instantiateDisplay(
        using classes: RuntimeClasses,
        descriptor: NSObject
    ) -> NSObject? {
        let initSelector = NSSelectorFromString("initWithDescriptor:")

        guard classes.display.instancesRespond(to: initSelector) else {
            print("[VirtualDisplay] CGVirtualDisplay does not respond to initWithDescriptor:")
            return nil
        }

        guard
            let allocated = classes.display.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
            let instance = allocated.perform(initSelector, with: descriptor)?.takeUnretainedValue() as? NSObject
        else {
            print("[VirtualDisplay] Failed to instantiate CGVirtualDisplay")
            return nil
        }

        return instance
    }

    // MARK: - Private: Settings Application

    /// Creates a CGVirtualDisplaySettings object and applies it to the display.
    private func configureSettings(
        on display: NSObject,
        using classes: RuntimeClasses,
        hiDPI: Bool
    ) {
        let settings = classes.settings.init()

        if settings.responds(to: NSSelectorFromString("setHiDPI:")) {
            settings.setValue(hiDPI, forKey: "hiDPI")
        }

        let applySelector = NSSelectorFromString("applySettings:")
        if display.responds(to: applySelector) {
            _ = display.perform(applySelector, with: settings)
        }
    }

    // MARK: - Private: Display ID Extraction

    /// Reads the system-assigned display ID from the CGVirtualDisplay instance.
    private func extractDisplayID(from display: NSObject) -> CGDirectDisplayID? {
        guard let rawValue = display.value(forKey: "displayID") else {
            print("[VirtualDisplay] Unable to read displayID property")
            return nil
        }

        guard let numericID = rawValue as? NSNumber else {
            print("[VirtualDisplay] displayID has unexpected type: \(type(of: rawValue))")
            return nil
        }

        let displayID = numericID.uint32Value

        guard displayID != 0 else {
            print("[VirtualDisplay] System returned display ID 0; creation likely failed")
            return nil
        }

        return displayID
    }

    // MARK: - Private: Physical Size Calculation

    /// Converts pixel dimensions to a physical size in millimeters given an assumed diagonal.
    private func computePhysicalSize(width: Int, height: Int, diagonalInches: Double) -> CGSize {
        let diagonalPixels = sqrt(Double(width * width + height * height))
        let pixelsPerInch = diagonalPixels / diagonalInches
        let widthMM = Double(width) / pixelsPerInch * 25.4
        let heightMM = Double(height) / pixelsPerInch * 25.4
        return CGSize(width: widthMM, height: heightMM)
    }
}
