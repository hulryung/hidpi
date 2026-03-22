// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// MARK: - DisplayOverride

/// Manages macOS display override plists for enabling HiDPI resolutions
struct DisplayOverride {

    // MARK: - Constants

    static let overrideBasePath = "/Library/Displays/Contents/Resources/Overrides"

    static let standardHiDPIResolutions: [(width: Int, height: Int)] = [
        (1920, 1080),
        (2560, 1440),
        (3008, 1692),
        (3360, 1890),
        (3840, 2160),
        (1600, 900),
        (1680, 1050),
        (2048, 1152),
        (2304, 1296),
        (2560, 1600),
        (2880, 1620),
        (2880, 1800),
        (3200, 1800),
        (4096, 2304),
        (5120, 2880),
        (6016, 3384)
    ]

    // MARK: - Path Helpers

    /// Returns the override directory path for a given vendor ID (hex-formatted).
    static func overrideDirPath(vendorID: UInt32) -> String {
        let hex = String(format: "%x", vendorID)
        return "\(overrideBasePath)/DisplayVendorID-\(hex)"
    }

    /// Returns the override file path for a given vendor/product ID pair (hex-formatted).
    static func overrideFilePath(vendorID: UInt32, productID: UInt32) -> String {
        let productHex = String(format: "%x", productID)
        return "\(overrideDirPath(vendorID: vendorID))/DisplayProductID-\(productHex)"
    }

    // MARK: - Resolution Encoding

    /// Encodes a resolution as 8 bytes: (width*2) big-endian UInt32 + (height*2) big-endian UInt32.
    /// This is the format macOS expects in the scale-resolutions array.
    static func encodeScaleResolution(width: Int, height: Int) -> Data {
        var data = Data(count: 8)
        let scaledWidth = UInt32(width * 2)
        let scaledHeight = UInt32(height * 2)
        data[0] = UInt8((scaledWidth >> 24) & 0xFF)
        data[1] = UInt8((scaledWidth >> 16) & 0xFF)
        data[2] = UInt8((scaledWidth >> 8) & 0xFF)
        data[3] = UInt8(scaledWidth & 0xFF)
        data[4] = UInt8((scaledHeight >> 24) & 0xFF)
        data[5] = UInt8((scaledHeight >> 16) & 0xFF)
        data[6] = UInt8((scaledHeight >> 8) & 0xFF)
        data[7] = UInt8(scaledHeight & 0xFF)
        return data
    }

    // MARK: - Plist Generation

    /// Builds a display override plist dictionary from the given configuration.
    static func generateOverridePlist(config: OverrideConfig) -> [String: Any] {
        var plist: [String: Any] = [:]

        plist["DisplayVendorID"] = Int(config.vendorID)
        plist["DisplayProductID"] = Int(config.productID)

        // Build scale-resolutions array
        let resolutions = config.resolutions.isEmpty ? standardHiDPIResolutions : config.resolutions
        var scaleResolutions: [Data] = []
        for res in resolutions {
            scaleResolutions.append(encodeScaleResolution(width: res.width, height: res.height))
        }
        plist["scale-resolutions"] = scaleResolutions

        // Optional target-default-ppmm
        if config.targetPPMM > 0 {
            plist["target-default-ppmm"] = config.targetPPMM
        }

        // Optional display name
        if let name = config.displayName {
            plist["DisplayProductName"] = name
        }

        // Optional native pixel dimensions
        if let nativeWidth = config.nativeWidth, let nativeHeight = config.nativeHeight {
            plist["DisplayPixelDimensions"] = [
                "Width": nativeWidth,
                "Height": nativeHeight
            ]
        }

        return plist
    }

    /// Generates a flexible scaling plist with a wide range of resolutions across multiple
    /// aspect ratios, from 640x480 to 7680x4320. Uses ppmm=10.0 for broad compatibility.
    static func generateFlexibleScalingPlist(config: OverrideConfig) -> [String: Any] {
        var plist: [String: Any] = [:]

        plist["DisplayVendorID"] = Int(config.vendorID)
        plist["DisplayProductID"] = Int(config.productID)

        // Wide range of resolutions in multiple aspect ratios
        let flexibleResolutions: [(width: Int, height: Int)] = [
            // 4:3
            (640, 480),
            (800, 600),
            (1024, 768),
            (1280, 960),
            (1600, 1200),
            (2048, 1536),
            // 16:10
            (1280, 800),
            (1440, 900),
            (1680, 1050),
            (1920, 1200),
            (2560, 1600),
            (2880, 1800),
            (3200, 2000),
            (3840, 2400),
            // 16:9
            (1280, 720),
            (1600, 900),
            (1920, 1080),
            (2048, 1152),
            (2304, 1296),
            (2560, 1440),
            (2880, 1620),
            (3008, 1692),
            (3200, 1800),
            (3360, 1890),
            (3840, 2160),
            (4096, 2304),
            (4480, 2520),
            (5120, 2880),
            (5760, 3240),
            (6016, 3384),
            (6400, 3600),
            (7680, 4320),
            // 21:9
            (2560, 1080),
            (3440, 1440),
            (3840, 1600),
            (5120, 2160)
        ]

        var scaleResolutions: [Data] = []
        for res in flexibleResolutions {
            scaleResolutions.append(encodeScaleResolution(width: res.width, height: res.height))
        }
        plist["scale-resolutions"] = scaleResolutions
        plist["target-default-ppmm"] = Float(10.0)

        if let name = config.displayName {
            plist["DisplayProductName"] = name
        }

        if let nativeWidth = config.nativeWidth, let nativeHeight = config.nativeHeight {
            plist["DisplayPixelDimensions"] = [
                "Width": nativeWidth,
                "Height": nativeHeight
            ]
        }

        return plist
    }

    // MARK: - Install / Remove

    /// Installs a display override plist by creating the vendor directory and writing the XML plist.
    static func installOverride(vendorID: UInt32, productID: UInt32, plist: [String: Any]) throws {
        let dirPath = overrideDirPath(vendorID: vendorID)
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)

        let fileManager = FileManager.default

        // Create directory if needed
        if !fileManager.fileExists(atPath: dirPath) {
            try fileManager.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        // Serialize to XML plist
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: URL(fileURLWithPath: filePath))
    }

    /// Removes a display override plist file.
    static func removeOverride(vendorID: UInt32, productID: UInt32) throws {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: filePath) {
            try fileManager.removeItem(atPath: filePath)
        }
    }

    // MARK: - Query

    /// Returns true if an override plist exists for the given vendor/product ID pair.
    static func overrideExists(vendorID: UInt32, productID: UInt32) -> Bool {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)
        return FileManager.default.fileExists(atPath: filePath)
    }

    /// Reads and returns the override plist dictionary, or nil if not found.
    static func readOverride(vendorID: UInt32, productID: UInt32) -> [String: Any]? {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)

        guard let data = FileManager.default.contents(atPath: filePath) else {
            return nil
        }

        guard let plist = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }

        return plist
    }

    // MARK: - Backup

    /// Copies an existing override plist to a .bak file before modifying.
    static func backupOverride(vendorID: UInt32, productID: UInt32) throws {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)
        let backupPath = filePath + ".bak"
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: filePath) else {
            return
        }

        // Remove old backup if present
        if fileManager.fileExists(atPath: backupPath) {
            try fileManager.removeItem(atPath: backupPath)
        }

        try fileManager.copyItem(atPath: filePath, toPath: backupPath)
    }

    // MARK: - Preview

    /// Serializes a plist dictionary to an XML string for preview purposes.
    static func previewAsXML(_ plist: [String: Any]) -> String {
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        ) else {
            return "<!-- Failed to serialize plist -->"
        }
        return String(data: data, encoding: .utf8) ?? "<!-- Failed to decode XML data -->"
    }

    // MARK: - Restore from Backup

    /// Restores a display override plist from its .bak file.
    static func restoreFromBackup(vendorID: UInt32, productID: UInt32) throws {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)
        let backupPath = filePath + ".bak"
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: backupPath) else {
            throw NSError(
                domain: "DisplayOverride",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No backup found at \(backupPath)"]
            )
        }

        // Remove current override if present
        if fileManager.fileExists(atPath: filePath) {
            try fileManager.removeItem(atPath: filePath)
        }

        try fileManager.copyItem(atPath: backupPath, toPath: filePath)
    }

    /// Restores from backup using admin privileges (AppleScript).
    static func restoreFromBackupWithAdminPrivileges(vendorID: UInt32, productID: UInt32) throws {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)
        let backupPath = filePath + ".bak"

        guard FileManager.default.fileExists(atPath: backupPath) else {
            throw NSError(
                domain: "DisplayOverride",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "No backup found"]
            )
        }

        let shellCommand = "cp '\(backupPath)' '\(filePath)' && chmod 644 '\(filePath)'"
        try executeWithAdminPrivileges(shellCommand)
    }

    // MARK: - Install with Redetect

    /// Installs override and triggers display redetection for changes to take effect.
    static func installAndRedetect(vendorID: UInt32, productID: UInt32, plist: [String: Any]) throws {
        // Backup existing override first
        try? backupOverride(vendorID: vendorID, productID: productID)

        // Install with admin privileges
        try installWithAdminPrivileges(vendorID: vendorID, productID: productID, plist: plist)

        // Trigger redetect so macOS picks up the new override
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SLSDetectDisplays()
        }
    }

    /// Removes override and triggers display redetection.
    static func removeAndRedetect(vendorID: UInt32, productID: UInt32) throws {
        try removeWithAdminPrivileges(vendorID: vendorID, productID: productID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            SLSDetectDisplays()
        }
    }

    /// Removes a display override plist using AppleScript to obtain admin privileges.
    static func removeWithAdminPrivileges(vendorID: UInt32, productID: UInt32) throws {
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)

        guard FileManager.default.fileExists(atPath: filePath) else { return }

        let shellCommand = "rm -f '\(filePath)'"
        try executeWithAdminPrivileges(shellCommand)
    }

    // MARK: - Sonoma+ Compatibility

    /// On macOS Sonoma and later, display override changes may require a more aggressive
    /// reinitialization. This method forces a display reconfiguration cycle.
    static func reinitializeDisplays() {
        if #available(macOS 14.0, *) {
            // On Sonoma+, we may need to toggle a display off and on
            // to force the system to re-read overrides.
            // SLSDetectDisplays() is usually sufficient, but we add a delay
            // and call it twice as a workaround for stubborn cases.
            SLSDetectDisplays()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                SLSDetectDisplays()
            }
        } else {
            SLSDetectDisplays()
        }
    }

    // MARK: - Privileged Helper

    /// Executes a shell command with admin privileges via AppleScript.
    private static func executeWithAdminPrivileges(_ shellCommand: String) throws {
        let appleScript = "do shell script \"\(shellCommand)\" with administrator privileges"

        guard let script = NSAppleScript(source: appleScript) else {
            throw NSError(
                domain: "DisplayOverride",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript"]
            )
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        if let error = errorInfo {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw NSError(
                domain: "DisplayOverride",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }

    // MARK: - Privileged Install

    /// Installs a display override plist using AppleScript to obtain admin privileges.
    /// The plist is first written to a temporary location, then moved with elevated rights.
    static func installWithAdminPrivileges(vendorID: UInt32, productID: UInt32, plist: [String: Any]) throws {
        let dirPath = overrideDirPath(vendorID: vendorID)
        let filePath = overrideFilePath(vendorID: vendorID, productID: productID)

        // Write plist to a temp file first
        let tempDir = NSTemporaryDirectory()
        let tempFile = (tempDir as NSString).appendingPathComponent("DisplayOverride-\(UUID().uuidString).plist")

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: URL(fileURLWithPath: tempFile))

        // Build the shell command to run with admin privileges
        let shellCommand = "mkdir -p '\(dirPath)' && cp '\(tempFile)' '\(filePath)' && chmod 644 '\(filePath)'"

        let appleScript = "do shell script \"\(shellCommand)\" with administrator privileges"

        guard let script = NSAppleScript(source: appleScript) else {
            // Clean up temp file
            try? FileManager.default.removeItem(atPath: tempFile)
            throw NSError(
                domain: "DisplayOverride",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create AppleScript"]
            )
        }

        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)

        // Clean up temp file
        try? FileManager.default.removeItem(atPath: tempFile)

        if let error = errorInfo {
            let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
            throw NSError(
                domain: "DisplayOverride",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: message]
            )
        }
    }
}
