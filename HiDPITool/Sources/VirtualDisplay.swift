// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics

// MARK: - CGVirtualDisplay API Access
//
// This module interfaces with Apple's private CGVirtualDisplay API, which provides
// the ability to create software-defined displays on macOS 13+. The API surface
// was discovered through runtime introspection of the CoreGraphics framework
// (class-dump / NSClassFromString enumeration). The key classes are:
//
//   - CGVirtualDisplayDescriptor: configures display properties (resolution, IDs, name)
//   - CGVirtualDisplayMode: defines a supported resolution/refresh-rate combination
//   - CGVirtualDisplaySettings: runtime settings such as HiDPI toggle
//   - CGVirtualDisplay: the display instance itself, identified by a CGDirectDisplayID

// MARK: - Runtime Class Loader

/// Loads the private CGVirtualDisplay classes from the CoreGraphics framework at runtime.
/// Returns nil if any required class is unavailable (e.g., macOS < 13).
private func loadVirtualDisplayClasses() -> (
    descriptor: NSObject.Type,
    mode: NSObject.Type,
    settings: NSObject.Type,
    display: NSObject.Type
)? {
    guard let descriptorCls = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
          let modeCls       = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type,
          let settingsCls   = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
          let displayCls    = NSClassFromString("CGVirtualDisplay") as? NSObject.Type else {
        return nil
    }
    return (descriptorCls, modeCls, settingsCls, displayCls)
}

// MARK: - Descriptor Configuration

/// Populates a CGVirtualDisplayDescriptor instance with the given parameters.
private func configureDescriptor(
    _ descriptor: NSObject,
    name: String,
    width: UInt32,
    height: UInt32,
    vendorID: UInt32,
    productID: UInt32,
    serialNum: UInt32,
    hiDPI: Bool
) {
    descriptor.setValue(DispatchQueue.main, forKey: "queue")
    descriptor.setValue(name, forKey: "name")
    descriptor.setValue(width, forKey: "maxPixelsWide")
    descriptor.setValue(height, forKey: "maxPixelsHigh")

    // Compute a physical size in millimeters that yields a sensible PPI.
    // A 27-inch diagonal is a reasonable default for a desktop display.
    let diagonalInches: Float = 27.0
    let aspect = Float(width) / Float(height)
    let heightMM = diagonalInches * 25.4 / sqrt(aspect * aspect + 1.0)
    let widthMM  = heightMM * aspect
    descriptor.setValue(CGSize(width: CGFloat(widthMM), height: CGFloat(heightMM)),
                        forKey: "sizeInMillimeters")

    descriptor.setValue(vendorID, forKey: "vendorID")
    descriptor.setValue(productID, forKey: "productID")
    descriptor.setValue(serialNum, forKey: "serialNum")

    if descriptor.responds(to: NSSelectorFromString("setHiDPI:")) {
        descriptor.setValue(hiDPI, forKey: "hiDPI")
    }
}

// MARK: - Mode Creation

/// Creates a CGVirtualDisplayMode for the specified resolution and refresh rate.
/// Tries the designated initializer first, then falls back to property assignment.
private func buildDisplayMode(
    using modeClass: NSObject.Type,
    width: UInt32,
    height: UInt32,
    refreshRate: Float
) -> NSObject {
    let selector = NSSelectorFromString("initWithWidth:height:refreshRate:")
    if let result = modeClass.perform(selector,
                                       with: width as NSNumber,
                                       with: height as NSNumber),
       let modeObj = result.takeUnretainedValue() as? NSObject {
        return modeObj
    }
    // Fallback: allocate and set properties individually
    let fallback = modeClass.init()
    fallback.setValue(width, forKey: "width")
    fallback.setValue(height, forKey: "height")
    fallback.setValue(refreshRate, forKey: "refreshRate")
    return fallback
}

// MARK: - Display Instantiation

/// Creates and returns a CGVirtualDisplay from a configured descriptor.
private func instantiateDisplay(
    using displayClass: NSObject.Type,
    descriptor: NSObject
) -> NSObject? {
    let selector = NSSelectorFromString("initWithDescriptor:")
    if let result = displayClass.perform(selector, with: descriptor) {
        return result.takeUnretainedValue() as? NSObject
    }
    let obj = displayClass.init()
    obj.setValue(descriptor, forKey: "descriptor")
    return obj
}

// MARK: - Virtual Display Manager

struct VirtualDisplayManager {

    /// Create a virtual display using Apple's private CGVirtualDisplay API
    /// (discovered via runtime introspection of CoreGraphics on macOS 13+).
    ///
    /// - Parameters:
    ///   - name: Human-readable display name.
    ///   - width: Maximum horizontal pixel count.
    ///   - height: Maximum vertical pixel count.
    ///   - hiDPI: Whether to advertise HiDPI support.
    ///   - refreshRate: Target refresh rate in Hz.
    ///   - vendorID: USB-style vendor identifier for the virtual display.
    ///   - productID: USB-style product identifier for the virtual display.
    ///   - serialNum: Serial number embedded in the display descriptor.
    /// - Returns: A tuple of the retained display object and its `CGDirectDisplayID`, or nil on failure.
    @discardableResult
    static func createVirtualDisplay(
        name: String = "HiDPI Virtual Display",
        width: UInt32 = 3840,
        height: UInt32 = 2160,
        hiDPI: Bool = true,
        refreshRate: Float = 60.0,
        vendorID: UInt32 = 0x1234,
        productID: UInt32 = 0x5678,
        serialNum: UInt32 = 0x0001
    ) -> (display: AnyObject, displayID: CGDirectDisplayID)? {

        // 1. Load private classes
        guard let classes = loadVirtualDisplayClasses() else {
            print("Error: CGVirtualDisplay APIs not available (requires macOS 13+)")
            return nil
        }

        // 2. Build the descriptor
        let descriptor = classes.descriptor.init()
        configureDescriptor(descriptor,
                            name: name,
                            width: width,
                            height: height,
                            vendorID: vendorID,
                            productID: productID,
                            serialNum: serialNum,
                            hiDPI: hiDPI)

        // 3. Attach a display mode
        let mode = buildDisplayMode(using: classes.mode,
                                    width: width,
                                    height: height,
                                    refreshRate: refreshRate)
        descriptor.setValue([mode], forKey: "modes")

        // 4. Instantiate the virtual display
        guard let display = instantiateDisplay(using: classes.display, descriptor: descriptor) else {
            print("Error: Failed to instantiate CGVirtualDisplay")
            return nil
        }

        // 5. Apply HiDPI settings
        let settings = classes.settings.init()
        settings.setValue(hiDPI, forKey: "hiDPI")
        display.perform(NSSelectorFromString("applySettings:"), with: settings)

        // 6. Retrieve the assigned display ID
        guard let displayID = display.value(forKey: "displayID") as? CGDirectDisplayID,
              displayID != 0 else {
            print("Error: Virtual display was created but has displayID 0")
            return nil
        }

        print("Virtual display created: ID=0x\(String(displayID, radix: 16)), "
              + "\(width)x\(height) @ \(refreshRate)Hz, HiDPI=\(hiDPI)")
        return (display, displayID)
    }

    /// Convenience wrapper: create a HiDPI virtual display and install a
    /// display-override plist so that macOS offers scaled HiDPI resolutions.
    @discardableResult
    static func createHiDPIVirtualDisplay(
        name: String = "HiDPI Virtual Display",
        width: Int = 3840,
        height: Int = 2160,
        scaledWidth: Int = 1920,
        scaledHeight: Int = 1080,
        refreshRate: Float = 60.0
    ) -> (display: AnyObject, displayID: CGDirectDisplayID)? {

        let vid: UInt32 = 0x1234
        let pid: UInt32 = 0x5678

        guard let result = createVirtualDisplay(
            name: name,
            width: UInt32(width),
            height: UInt32(height),
            hiDPI: true,
            refreshRate: refreshRate,
            vendorID: vid,
            productID: pid
        ) else {
            return nil
        }

        // Build a set of useful scaled resolutions for the override plist
        let resolutions = [
            (scaledWidth, scaledHeight),
            (width / 2, height / 2),
            (1920, 1080), (2560, 1440), (3840, 2160),
        ]
        let plist = DisplayOverride.generateOverridePlist(
            vendorID: vid,
            productID: pid,
            resolutions: resolutions,
            displayName: name,
            targetPPMM: 10.0
        )

        do {
            try DisplayOverride.installOverride(vendorID: vid, productID: pid, plist: plist)
        } catch {
            print("Warning: Failed to install override: \(error)")
            print("Override plist preview:")
            print(DisplayOverride.previewOverride(plist))
        }

        return result
    }
}
