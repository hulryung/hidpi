// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics
import IOKit

// MARK: - CGSDisplayModeDescription

/// Display mode description structure (layout verified via byte dump analysis)
///
/// Offsets:
///   0x00: modeNumber (Int32)     0x04: flags (UInt32)
///   0x08: width (Int32)          0x0C: height (Int32)
///   0x10: bitsPerSample (UInt32) 0x14: bytesPerRow (UInt32)
///   0x18: bitsPerPixel (Int32)   0x1C: samplesPerPixel (UInt32)
///   0x20: reserved (UInt32)      0x24: refreshRate (Int32)
///   0x28: ioFlags (UInt32)       0x2C: ioFlags2 (UInt32)
struct CGSDisplayModeDescription {
    var modeNumber: Int32 = 0
    var flags: UInt32 = 0
    var width: Int32 = 0
    var height: Int32 = 0
    var bitsPerSample: UInt32 = 0
    var bytesPerRow: UInt32 = 0
    var bitsPerPixel: Int32 = 0
    var samplesPerPixel: UInt32 = 0
    var reserved1: UInt32 = 0
    var refreshRate: Int32 = 0
    var ioFlags: UInt32 = 0
    var ioFlags2: UInt32 = 0
    // Padding to 0xD0 bytes total
    var padding: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                  UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                  UInt64, UInt64, UInt64, UInt64) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

    /// Backing pixel width derived from bytesPerRow
    var backingWidth: Int32 {
        guard bitsPerPixel > 0 else { return width }
        return Int32(bytesPerRow / UInt32(bitsPerPixel / 8))
    }

    /// Pixel density (2.0 = HiDPI/Retina)
    var density: Float {
        guard width > 0 else { return 1.0 }
        return Float(backingWidth) / Float(width)
    }

    var isHiDPI: Bool { density >= 2.0 }
    var isNativeFlag: Bool { flags & 0x2000000 != 0 }
}

// MARK: - CoreGraphics Private APIs (CGS*)

@_silgen_name("CGSGetNumberOfDisplayModes")
func CGSGetNumberOfDisplayModes(_ display: CGDirectDisplayID, _ count: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSGetDisplayModeDescriptionOfLength")
func CGSGetDisplayModeDescriptionOfLength(_ display: CGDirectDisplayID, _ modeNumber: Int32, _ desc: UnsafeMutablePointer<CGSDisplayModeDescription>, _ length: Int32) -> CGError

@_silgen_name("CGSGetCurrentDisplayMode")
func CGSGetCurrentDisplayMode(_ display: CGDirectDisplayID, _ modeNumber: UnsafeMutablePointer<Int32>) -> CGError

@_silgen_name("CGSConfigureDisplayMode")
func CGSConfigureDisplayMode(_ configRef: UnsafeMutableRawPointer?, _ display: CGDirectDisplayID, _ modeNumber: Int32) -> CGError

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ configRef: UnsafeMutableRawPointer?, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

@_silgen_name("CGSGetDisplayList")
func CGSGetDisplayList(_ maxDisplays: UInt32, _ displays: UnsafeMutablePointer<CGDirectDisplayID>?, _ displayCount: UnsafeMutablePointer<UInt32>?) -> CGError

@_silgen_name("CGSessionCopyCurrentDictionary")
func CGSessionCopyCurrentDictionary() -> CFDictionary?

@_silgen_name("CGSetDisplayTransferByTable")
func CGSetDisplayTransferByTable(_ display: CGDirectDisplayID, _ tableSize: UInt32, _ redTable: UnsafePointer<Float>, _ greenTable: UnsafePointer<Float>, _ blueTable: UnsafePointer<Float>) -> CGError

// MARK: - SkyLight Private APIs (SLS*)

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> Int32

@_silgen_name("SLSDetectDisplays")
func SLSDetectDisplays()

@_silgen_name("SLSCopyDisplayInfoDictionary")
func SLSCopyDisplayInfoDictionary(_ displayID: CGDirectDisplayID) -> CFDictionary?

@_silgen_name("SLSSetDisplayRotation")
func SLSSetDisplayRotation(_ displayID: CGDirectDisplayID, _ angle: Float) -> CGError

@_silgen_name("SLSDisplaySetUnderscan")
func SLSDisplaySetUnderscan(_ displayID: CGDirectDisplayID, _ value: Int32) -> CGError

@_silgen_name("SLSDisplaySupportsHDRMode")
func SLSDisplaySupportsHDRMode(_ displayID: CGDirectDisplayID) -> Bool

@_silgen_name("SLSDisplayIsHDRModeEnabled")
func SLSDisplayIsHDRModeEnabled(_ displayID: CGDirectDisplayID) -> Bool

@_silgen_name("SLSDisplaySetHDRModeEnabled")
func SLSDisplaySetHDRModeEnabled(_ displayID: CGDirectDisplayID, _ enabled: Bool) -> CGError

@_silgen_name("SLSIsDisplayModeVRR")
func SLSIsDisplayModeVRR(_ displayID: CGDirectDisplayID, _ modeNumber: Int32) -> Bool

@_silgen_name("SLSIsDisplayModeProMotion")
func SLSIsDisplayModeProMotion(_ displayID: CGDirectDisplayID, _ modeNumber: Int32) -> Bool

@_silgen_name("SLSGetDisplayModeMinRefreshRate")
func SLSGetDisplayModeMinRefreshRate(_ displayID: CGDirectDisplayID) -> Int32

// MARK: - CoreDisplay

@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func CoreDisplay_DisplayCreateInfoDictionary(_ displayID: CGDirectDisplayID) -> CFDictionary?

// MARK: - IOAVService (EDID / I2C / DDC)

@_silgen_name("IOAVServiceCreateWithService")
func IOAVServiceCreateWithService(_ allocator: CFAllocator?, _ service: io_service_t) -> Unmanaged<CFTypeRef>?

@_silgen_name("IOAVServiceCopyEDID")
func IOAVServiceCopyEDID(_ service: CFTypeRef, _ edid: UnsafeMutablePointer<CFData?>) -> kern_return_t

@_silgen_name("IOAVServiceSetVirtualEDIDMode")
func IOAVServiceSetVirtualEDIDMode(_ service: CFTypeRef, _ mode: UInt32) -> kern_return_t

@_silgen_name("IOAVServiceReadI2C")
func IOAVServiceReadI2C(_ service: CFTypeRef, _ address: UInt32, _ offset: UInt32, _ data: UnsafeMutablePointer<UInt8>, _ length: UInt32) -> kern_return_t

@_silgen_name("IOAVServiceWriteI2C")
func IOAVServiceWriteI2C(_ service: CFTypeRef, _ address: UInt32, _ offset: UInt32, _ data: UnsafePointer<UInt8>, _ length: UInt32) -> kern_return_t
