// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// MARK: - EDID Parser (Implements VESA E-EDID standard (Enhanced Extended Display Identification Data))

struct EDIDParser {
    let data: Data

    var isValid: Bool {
        guard data.count >= 128 else { return false }
        // Check EDID header: 00 FF FF FF FF FF FF 00
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        return data.prefix(8).elementsEqual(header)
    }

    var vendorID: UInt16 {
        guard data.count >= 10 else { return 0 }
        return UInt16(data[8]) << 8 | UInt16(data[9])
    }

    var productID: UInt16 {
        guard data.count >= 12 else { return 0 }
        return UInt16(data[11]) << 8 | UInt16(data[10]) // little-endian
    }

    var serialNumber: UInt32 {
        guard data.count >= 16 else { return 0 }
        return UInt32(data[12]) | UInt32(data[13]) << 8 | UInt32(data[14]) << 16 | UInt32(data[15]) << 24
    }

    var yearOfManufacture: Int {
        guard data.count >= 18 else { return 0 }
        return Int(data[17]) + 1990
    }

    var edidVersion: String {
        guard data.count >= 20 else { return "?" }
        return "\(data[18]).\(data[19])"
    }

    /// Decode manufacturer ID from PNP compressed ID
    var manufacturerName: String {
        let id = vendorID
        guard let s1 = UnicodeScalar(((id >> 10) & 0x1F) + 0x40),
              let s2 = UnicodeScalar(((id >> 5) & 0x1F) + 0x40),
              let s3 = UnicodeScalar((id & 0x1F) + 0x40) else { return "???" }
        return String([Character(s1), Character(s2), Character(s3)])
    }

    /// Parse preferred timing (first Detailed Timing Descriptor)
    var preferredTiming: (width: Int, height: Int, refreshRate: Double)? {
        guard data.count >= 54 + 18 else { return nil }
        let offset = 54 // First DTD starts at byte 54

        let pixelClock = (Int(data[offset + 1]) << 8 | Int(data[offset])) * 10000 // in Hz
        guard pixelClock > 0 else { return nil }

        let hActive = Int(data[offset + 2]) | (Int(data[offset + 4] & 0xF0) << 4)
        let hBlanking = Int(data[offset + 3]) | (Int(data[offset + 4] & 0x0F) << 8)
        let vActive = Int(data[offset + 5]) | (Int(data[offset + 7] & 0xF0) << 4)
        let vBlanking = Int(data[offset + 6]) | (Int(data[offset + 7] & 0x0F) << 8)

        let hTotal = hActive + hBlanking
        let vTotal = vActive + vBlanking
        let refreshRate = Double(pixelClock) / Double(hTotal * vTotal)

        return (hActive, vActive, refreshRate)
    }

    /// Parse display name from descriptor blocks
    var displayName: String? {
        guard data.count >= 128 else { return nil }
        // Scan descriptor blocks (4 blocks starting at offset 54, each 18 bytes)
        for i in 0..<4 {
            let offset = 54 + i * 18
            // Monitor name descriptor: tag = 0xFC
            if data[offset] == 0 && data[offset + 1] == 0 && data[offset + 3] == 0xFC {
                let nameBytes = data[(offset + 5)..<(offset + 18)]
                let name = String(bytes: nameBytes, encoding: .ascii)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: "")
                return name
            }
        }
        return nil
    }

    /// Get physical size in cm from EDID
    var physicalSize: (widthCm: Int, heightCm: Int)? {
        guard data.count >= 23 else { return nil }
        let w = Int(data[21])
        let h = Int(data[22])
        guard w > 0 && h > 0 else { return nil }
        return (w, h)
    }

    func printSummary() {
        guard isValid else {
            print("Invalid EDID data (\(data.count) bytes)")
            return
        }
        print("EDID Summary:")
        print("  Manufacturer: \(manufacturerName)")
        print("  Vendor ID:    0x\(String(vendorID, radix: 16, uppercase: true))")
        print("  Product ID:   0x\(String(productID, radix: 16, uppercase: true))")
        print("  Serial:       \(serialNumber)")
        print("  Year:         \(yearOfManufacture)")
        print("  EDID Version: \(edidVersion)")
        if let name = displayName {
            print("  Name:         \(name)")
        }
        if let size = physicalSize {
            print("  Physical:     \(size.widthCm)cm x \(size.heightCm)cm")
        }
        if let timing = preferredTiming {
            print("  Preferred:    \(timing.width)x\(timing.height) @ \(String(format: "%.1f", timing.refreshRate))Hz")
        }
        print("  Base64:       \(data.prefix(128).base64EncodedString())")
    }
}
