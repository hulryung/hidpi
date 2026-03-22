// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics

// MARK: - Display Override (HiDPI scale-resolutions plist)

struct DisplayOverride {

    /// Base path for display override plists
    static let overrideBasePath = "/Library/Displays/Contents/Resources/Overrides"

    /// Standard HiDPI resolutions to add
    static let standardHiDPIResolutions: [(width: Int, height: Int)] = [
        (1920, 1080), (2560, 1440), (3008, 1692), (3360, 1890), (3840, 2160),
        (1600, 900),  (1680, 1050), (2048, 1152), (2304, 1296), (2560, 1600),
        (2880, 1620), (2880, 1800), (3200, 1800), (4096, 2304), (4480, 2520),
        (5120, 2880), (6016, 3384), (6144, 3456),
    ]

    /// Generate an override directory path
    static func overrideDirPath(vendorID: UInt32) -> String {
        return "\(overrideBasePath)/DisplayVendorID-\(String(vendorID, radix: 16))"
    }

    /// Generate an override file path
    static func overrideFilePath(vendorID: UInt32, productID: UInt32) -> String {
        return "\(overrideDirPath(vendorID: vendorID))/DisplayProductID-\(String(productID, radix: 16))"
    }

    /// Encode a resolution as a scale-resolutions entry (big-endian packed data)
    /// Each entry is 8 bytes: width (4 bytes BE) + height (4 bytes BE) at 2x
    static func encodeScaleResolution(width: Int, height: Int) -> Data {
        // The actual pixel dimensions (2x for HiDPI)
        let pixelWidth = UInt32(width * 2).bigEndian
        let pixelHeight = UInt32(height * 2).bigEndian
        var data = Data()
        withUnsafeBytes(of: pixelWidth) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: pixelHeight) { data.append(contentsOf: $0) }
        return data
    }

    /// Generate override plist dictionary
    static func generateOverridePlist(
        vendorID: UInt32,
        productID: UInt32,
        resolutions: [(width: Int, height: Int)]? = nil,
        displayName: String? = nil,
        targetPPMM: Float? = nil,
        nativeWidth: Int? = nil,
        nativeHeight: Int? = nil
    ) -> [String: Any] {
        let resToUse = resolutions ?? standardHiDPIResolutions

        // Build scale-resolutions array
        let scaleResolutions: [Data] = resToUse.map { res in
            encodeScaleResolution(width: res.width, height: res.height)
        }

        var plist: [String: Any] = [
            "DisplayProductID": Int(productID),
            "DisplayVendorID": Int(vendorID),
            "scale-resolutions": scaleResolutions,
        ]

        // target-default-ppmm controls the default DPI behavior
        // Higher values push macOS to treat the display as higher density
        if let ppmm = targetPPMM {
            plist["target-default-ppmm"] = ppmm
        }

        if let name = displayName {
            plist["DisplayProductName"] = name
        }

        // Native resolution override (DisplayPixelDimensions)
        if let w = nativeWidth, let h = nativeHeight {
            var pixelDims = Data()
            let pw = UInt32(w).bigEndian
            let ph = UInt32(h).bigEndian
            withUnsafeBytes(of: pw) { pixelDims.append(contentsOf: $0) }
            withUnsafeBytes(of: ph) { pixelDims.append(contentsOf: $0) }
            plist["DisplayPixelDimensions"] = pixelDims
        }

        return plist
    }

    /// Install override plist to system location (requires root)
    static func installOverride(
        vendorID: UInt32,
        productID: UInt32,
        plist: [String: Any]
    ) throws {
        let dirPath = overrideDirPath(vendorID: vendorID)
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)

        // Create vendor directory
        try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)

        // Write plist
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: filePath))

        print("Override installed: \(filePath)")
    }

    /// Remove override plist
    static func removeOverride(vendorID: UInt32, productID: UInt32) throws {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)
        if FileManager.default.fileExists(atPath: filePath) {
            try FileManager.default.removeItem(atPath: filePath)
            print("Override removed: \(filePath)")
        } else {
            print("No override found at: \(filePath)")
        }
    }

    /// Check if an override exists
    static func overrideExists(vendorID: UInt32, productID: UInt32) -> Bool {
        return FileManager.default.fileExists(atPath: overrideFilePath(vendorID: vendorID, productID: productID))
    }

    /// Read existing override plist
    static func readOverride(vendorID: UInt32, productID: UInt32) -> [String: Any]? {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)
        guard let data = FileManager.default.contents(atPath: filePath) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    /// Generate flexible scaling override with wide resolution range
    static func generateFlexibleScalingPlist(
        vendorID: UInt32,
        productID: UInt32,
        minWidth: Int = 640,
        minHeight: Int = 480,
        maxWidth: Int = 7680,
        maxHeight: Int = 4320,
        displayName: String? = nil
    ) -> [String: Any] {
        // Generate resolutions from min to max in useful increments
        var resolutions: [(width: Int, height: Int)] = []

        // Common aspect ratio resolutions
        let widths = stride(from: minWidth, through: maxWidth, by: 160)
        for w in widths {
            // 16:9
            let h9 = w * 9 / 16
            if h9 >= minHeight && h9 <= maxHeight {
                resolutions.append((w, h9))
            }
            // 16:10
            let h10 = w * 10 / 16
            if h10 >= minHeight && h10 <= maxHeight {
                resolutions.append((w, h10))
            }
        }

        // Add standard resolutions
        resolutions.append(contentsOf: standardHiDPIResolutions)

        // Deduplicate
        var seen = Set<String>()
        resolutions = resolutions.filter { res in
            let key = "\(res.width)x\(res.height)"
            return seen.insert(key).inserted
        }

        return generateOverridePlist(
            vendorID: vendorID,
            productID: productID,
            resolutions: resolutions,
            displayName: displayName,
            targetPPMM: 10.0 // High ppmm for flexible scaling
        )
    }

    /// Preview override plist as XML string
    static func previewOverride(_ plist: [String: Any]) -> String {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else {
            return "(failed to serialize)"
        }
        return String(data: data, encoding: .utf8) ?? "(encoding error)"
    }
}
