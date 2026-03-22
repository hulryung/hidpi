// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics
import IOKit

// MARK: - CoreGraphics Private APIs (CGS*)

/// Display mode description structure matching CGSGetDisplayModeDescriptionOfLength
/// Layout verified by raw byte analysis:
///   0x00: modeNumber, 0x04: flags, 0x08: width, 0x0C: height,
///   0x10: bitsPerSample, 0x14: bytesPerRow, 0x18: bitsPerPixel,
///   0x1C: samplesPerPixel, 0x20: reserved1, 0x24: refreshRate,
///   0x28: ioFlags, 0x2C: ioFlags2
struct CGSDisplayModeDescription {
    var modeNumber: Int32 = 0
    var flags: UInt32 = 0
    var width: Int32 = 0         // rendered ("look like") width
    var height: Int32 = 0        // rendered ("look like") height
    var bitsPerSample: UInt32 = 0
    var bytesPerRow: UInt32 = 0  // backing store bytes per row (key for HiDPI detection)
    var bitsPerPixel: Int32 = 0  // typically 32
    var samplesPerPixel: UInt32 = 0
    var reserved1: UInt32 = 0
    var refreshRate: Int32 = 0   // Hz (integer)
    var ioFlags: UInt32 = 0
    var ioFlags2: UInt32 = 0
    // padding to fill 0xD0 bytes total (48 bytes used above, need 160 more)
    var padding: (UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                  UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64, UInt64,
                  UInt64, UInt64, UInt64, UInt64) = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)

    /// Backing pixel width (actual hardware pixels per row)
    var backingWidth: Int32 {
        guard bitsPerPixel > 0 else { return width }
        return Int32(bytesPerRow / UInt32(bitsPerPixel / 8))
    }

    /// Pixel density: 2.0 = HiDPI (Retina), 1.0 = standard
    var density: Float {
        guard width > 0 else { return 1.0 }
        return Float(backingWidth) / Float(width)
    }

    /// Whether this mode is HiDPI (backing resolution > rendered resolution)
    var isHiDPI: Bool { density >= 2.0 }

    /// Native-like flag (bit 25 in flags = 0x2000000)
    var isNativeFlag: Bool { flags & 0x2000000 != 0 }
}

// CGS Display mode functions from CoreGraphics
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

// MARK: - CoreDisplay

@_silgen_name("CoreDisplay_DisplayCreateInfoDictionary")
func CoreDisplay_DisplayCreateInfoDictionary(_ displayID: CGDirectDisplayID) -> CFDictionary?

// MARK: - IOAVService (EDID)

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
