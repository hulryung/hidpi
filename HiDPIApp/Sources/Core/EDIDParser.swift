// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// MARK: - EDIDParser

/// Parses raw EDID (Extended Display Identification Data) binary data
struct EDIDParser {

    let data: Data

    // MARK: - Validation

    /// Checks for the standard 8-byte EDID header: 00 FF FF FF FF FF FF 00
    var isValid: Bool {
        guard data.count >= 128 else { return false }
        let header: [UInt8] = [0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00]
        for i in 0..<8 {
            if data[i] != header[i] {
                return false
            }
        }
        return true
    }

    // MARK: - Manufacturer & Product

    /// Vendor ID from bytes 8-9 (big-endian PNP compressed format)
    var vendorID: UInt16 {
        guard data.count >= 10 else { return 0 }
        return UInt16(data[8]) << 8 | UInt16(data[9])
    }

    /// Product ID from bytes 10-11 (little-endian)
    var productID: UInt16 {
        guard data.count >= 12 else { return 0 }
        return UInt16(data[10]) | UInt16(data[11]) << 8
    }

    /// Serial number from bytes 12-15 (little-endian)
    var serialNumber: UInt32 {
        guard data.count >= 16 else { return 0 }
        return UInt32(data[12])
            | UInt32(data[13]) << 8
            | UInt32(data[14]) << 16
            | UInt32(data[15]) << 24
    }

    /// Year of manufacture: byte 17 + 1990
    var yearOfManufacture: Int {
        guard data.count >= 18 else { return 0 }
        return Int(data[17]) + 1990
    }

    /// EDID version from bytes 18-19 as "major.minor"
    var edidVersion: String {
        guard data.count >= 20 else { return "0.0" }
        return "\(data[18]).\(data[19])"
    }

    /// Decodes the PNP compressed 3-letter manufacturer code from the vendor ID.
    /// The 16-bit vendor ID encodes three 5-bit characters (A=1, B=2, ..., Z=26).
    var manufacturerName: String {
        let id = vendorID
        let c1 = (id >> 10) & 0x1F
        let c2 = (id >> 5) & 0x1F
        let c3 = id & 0x1F

        var name = ""
        for code in [c1, c2, c3] {
            let value = Int(code) + 64  // 1 -> 'A' (65)
            guard let scalar = UnicodeScalar(value) else {
                name.append("?")
                continue
            }
            name.append(Character(scalar))
        }
        return name
    }

    // MARK: - Detailed Timing Descriptor

    /// Parses the preferred (first) Detailed Timing Descriptor at byte offset 54.
    /// Returns the active resolution and calculated refresh rate.
    var preferredTiming: (width: Int, height: Int, refreshRate: Double)? {
        guard data.count >= 54 + 18 else { return nil }
        let offset = 54

        // Pixel clock in 10 kHz units (little-endian, bytes 0-1)
        let pixelClock = Int(data[offset]) | (Int(data[offset + 1]) << 8)
        guard pixelClock > 0 else { return nil }
        let pixelClockHz = Double(pixelClock) * 10000.0

        // Horizontal active pixels: byte 2 (lower 8 bits) + upper nibble of byte 4
        let hActiveLow = Int(data[offset + 2])
        let hActiveHigh = Int(data[offset + 4] >> 4) & 0x0F
        let hActive = (hActiveHigh << 8) | hActiveLow

        // Horizontal blanking: byte 3 (lower 8 bits) + lower nibble of byte 4
        let hBlankLow = Int(data[offset + 3])
        let hBlankHigh = Int(data[offset + 4]) & 0x0F
        let hBlank = (hBlankHigh << 8) | hBlankLow

        // Vertical active lines: byte 5 (lower 8 bits) + upper nibble of byte 7
        let vActiveLow = Int(data[offset + 5])
        let vActiveHigh = Int(data[offset + 7] >> 4) & 0x0F
        let vActive = (vActiveHigh << 8) | vActiveLow

        // Vertical blanking: byte 6 (lower 8 bits) + lower nibble of byte 7
        let vBlankLow = Int(data[offset + 6])
        let vBlankHigh = Int(data[offset + 7]) & 0x0F
        let vBlank = (vBlankHigh << 8) | vBlankLow

        guard hActive > 0, vActive > 0 else { return nil }

        let hTotal = Double(hActive + hBlank)
        let vTotal = Double(vActive + vBlank)

        guard hTotal > 0, vTotal > 0 else { return nil }

        let refreshRate = pixelClockHz / (hTotal * vTotal)

        return (width: hActive, height: vActive, refreshRate: refreshRate)
    }

    // MARK: - Display Name

    /// Scans the four 18-byte descriptor blocks starting at offset 54 for a
    /// Display Product Name descriptor (tag 0xFC).
    var displayName: String? {
        guard data.count >= 128 else { return nil }

        for i in 0..<4 {
            let offset = 54 + (i * 18)
            guard offset + 18 <= data.count else { continue }

            // Non-timing descriptors have bytes 0-1 == 0x00 0x00
            guard data[offset] == 0x00, data[offset + 1] == 0x00 else { continue }

            // Tag is at byte 3 of the descriptor
            let tag = data[offset + 3]
            guard tag == 0xFC else { continue }

            // Name string is in bytes 5-17 (13 bytes), terminated by newline (0x0A)
            var nameBytes: [UInt8] = []
            for j in 5..<18 {
                let byte = data[offset + j]
                if byte == 0x0A { break }
                nameBytes.append(byte)
            }

            if let name = String(bytes: nameBytes, encoding: .ascii) {
                return name.trimmingCharacters(in: .whitespaces)
            }
        }

        return nil
    }

    // MARK: - Physical Size

    /// Physical display size from bytes 21-22 (width cm, height cm).
    /// Returns nil if both values are zero.
    var physicalSize: (widthCm: Int, heightCm: Int)? {
        guard data.count >= 23 else { return nil }
        let w = Int(data[21])
        let h = Int(data[22])
        guard w > 0 || h > 0 else { return nil }
        return (widthCm: w, heightCm: h)
    }

    // MARK: - Max Pixel Clock

    /// Reads the maximum pixel clock from a Display Range Limits descriptor (tag 0xFD).
    /// The value at byte 9 of the descriptor represents max pixel clock in units of 10 MHz.
    /// Returns the value in MHz, or nil if no range limits descriptor is found.
    var maxPixelClock: Int? {
        guard data.count >= 128 else { return nil }

        for i in 0..<4 {
            let offset = 54 + (i * 18)
            guard offset + 18 <= data.count else { continue }

            // Non-timing descriptors: bytes 0-1 == 0x00 0x00
            guard data[offset] == 0x00, data[offset + 1] == 0x00 else { continue }

            // Tag 0xFD = Display Range Limits
            let tag = data[offset + 3]
            guard tag == 0xFD else { continue }

            // Byte 9 of the descriptor (offset + 9) is max pixel clock in 10 MHz units
            let maxClockValue = Int(data[offset + 9])
            guard maxClockValue > 0 else { return nil }
            return maxClockValue * 10
        }

        return nil
    }

    // MARK: - Summary

    /// Prints a formatted summary of the parsed EDID data.
    func printSummary() {
        print("=== EDID Summary ===")
        print("Valid: \(isValid)")
        print("Manufacturer: \(manufacturerName) (0x\(String(format: "%04X", vendorID)))")
        print("Product ID: 0x\(String(format: "%04X", productID))")
        print("Serial: \(serialNumber)")
        print("Year: \(yearOfManufacture)")
        print("EDID Version: \(edidVersion)")

        if let name = displayName {
            print("Display Name: \(name)")
        }

        if let size = physicalSize {
            print("Physical Size: \(size.widthCm) cm x \(size.heightCm) cm")
        }

        if let timing = preferredTiming {
            print("Preferred Timing: \(timing.width)x\(timing.height) @ \(String(format: "%.2f", timing.refreshRate)) Hz")
        }

        if let maxClock = maxPixelClock {
            print("Max Pixel Clock: \(maxClock) MHz")
        }

        print("====================")
    }
}
