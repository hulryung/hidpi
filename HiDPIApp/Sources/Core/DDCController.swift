// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics
import IOKit

// MARK: - VCP Codes

/// Standard DDC/CI Virtual Control Panel (VCP) codes.
enum VCPCode: UInt8 {
    case brightness  = 0x10
    case contrast    = 0x12
    case inputSource = 0x60
    case volume      = 0x62
    case powerMode   = 0xD6
}

// MARK: - DDCController

/// Communicates with external monitors over the DDC/CI protocol using I2C via IOAVService.
///
/// DDC/CI (Display Data Channel / Command Interface) allows reading and writing
/// monitor settings such as brightness, contrast, input source, and power mode.
/// Communication happens over the I2C bus at the standard DDC slave address 0x37.
final class DDCController {

    // MARK: - Constants

    /// Standard DDC/CI I2C slave address.
    private static let ddcAddress: UInt32 = 0x37

    /// DDC/CI host-to-display offset (command register).
    private static let ddcOffset: UInt32 = 0x51

    /// Delay between I2C write and read to give the monitor time to respond.
    private static let readDelayMicroseconds: UInt32 = 100_000 // 100 ms

    /// Expected length of a DDC/CI VCP reply from the display.
    private static let ddcReplyLength: UInt32 = 12

    // MARK: - Singleton

    static let shared = DDCController()

    private init() {}

    // MARK: - Service Discovery

    /// Finds all available I2C/AV services suitable for DDC communication.
    ///
    /// Tries `DCPAVServiceProxy` first (Apple Silicon / modern Macs), then falls
    /// back to `IOFramebufferI2CInterface` (Intel Macs).
    ///
    /// - Returns: An array of (service, port) tuples. The `service` is an
    ///   `IOAVService` `CFTypeRef` and `port` is the underlying `io_service_t`.
    func findAVServices() -> [(service: CFTypeRef, port: io_service_t)] {
        var results: [(service: CFTypeRef, port: io_service_t)] = []

        // Try DCPAVServiceProxy (Apple Silicon / modern displays)
        results.append(contentsOf: servicesForClassName("DCPAVServiceProxy"))

        // Fallback: IOFramebufferI2CInterface (Intel)
        if results.isEmpty {
            results.append(contentsOf: servicesForClassName("IOFramebufferI2CInterface"))
        }

        return results
    }

    // MARK: - VCP Read

    /// Reads a VCP value from the monitor.
    ///
    /// DDC/CI read protocol:
    /// 1. Write `[0x01, code]` to address 0x37, offset 0x51.
    /// 2. Wait ~40 ms for the monitor to prepare the response.
    /// 3. Read 11 bytes from address 0x37, offset 0x51.
    /// 4. Parse the response to extract current and maximum values.
    ///
    /// - Parameters:
    ///   - service: The `IOAVService` reference obtained from `findAVServices()`.
    ///   - code: The VCP code to read.
    /// - Returns: A tuple of `(current, max)` values, or `nil` on failure.
    func readVCPValue(service: CFTypeRef, code: VCPCode) -> (current: UInt16, max: UInt16)? {
        // Build the DDC/CI "Get VCP Feature" request: [length | 0x80, 0x01, code]
        var request: [UInt8] = [0x82, 0x01, code.rawValue]
        appendChecksum(to: &request, destination: Self.ddcAddress)

        // Write the request
        let writeResult = IOAVServiceWriteI2C(
            service,
            Self.ddcAddress,
            Self.ddcOffset,
            &request,
            UInt32(request.count)
        )

        guard writeResult == KERN_SUCCESS else {
            print("[DDC] I2C write failed for VCP 0x\(String(code.rawValue, radix: 16)): \(writeResult)")
            return nil
        }

        // Wait for the monitor to process the request
        usleep(Self.readDelayMicroseconds)

        // Read the response
        var reply = [UInt8](repeating: 0, count: Int(Self.ddcReplyLength))
        let readResult = IOAVServiceReadI2C(
            service,
            Self.ddcAddress,
            Self.ddcOffset,
            &reply,
            Self.ddcReplyLength
        )

        guard readResult == KERN_SUCCESS else {
            print("[DDC] I2C read failed for VCP 0x\(String(code.rawValue, radix: 16)): \(readResult)")
            return nil
        }

        return parseDDCReply(reply, expectedCode: code)
    }

    // MARK: - VCP Write

    /// Writes a VCP value to the monitor.
    ///
    /// DDC/CI write protocol:
    /// Write `[length | 0x80, 0x03, code, valueHigh, valueLow]` to address 0x37, offset 0x51.
    ///
    /// - Parameters:
    ///   - service: The `IOAVService` reference.
    ///   - code: The VCP code to write.
    ///   - value: The 16-bit value to set.
    /// - Returns: `true` if the write succeeded.
    @discardableResult
    func writeVCPValue(service: CFTypeRef, code: VCPCode, value: UInt16) -> Bool {
        let highByte = UInt8((value >> 8) & 0xFF)
        let lowByte  = UInt8(value & 0xFF)

        // Build the DDC/CI "Set VCP Feature" command: [length | 0x80, 0x03, code, high, low]
        var command: [UInt8] = [0x84, 0x03, code.rawValue, highByte, lowByte]
        appendChecksum(to: &command, destination: Self.ddcAddress)

        let result = IOAVServiceWriteI2C(
            service,
            Self.ddcAddress,
            Self.ddcOffset,
            &command,
            UInt32(command.count)
        )

        if result != KERN_SUCCESS {
            print("[DDC] I2C write failed for VCP 0x\(String(code.rawValue, radix: 16)) value \(value): \(result)")
        }

        return result == KERN_SUCCESS
    }

    // MARK: - Convenience Methods

    /// Sets the brightness of the monitor (0–100 typical).
    func setBrightness(service: CFTypeRef, value: UInt16) {
        writeVCPValue(service: service, code: .brightness, value: value)
    }

    /// Reads the current and maximum brightness from the monitor.
    func getBrightness(service: CFTypeRef) -> (current: UInt16, max: UInt16)? {
        readVCPValue(service: service, code: .brightness)
    }

    /// Sets the contrast of the monitor.
    func setContrast(service: CFTypeRef, value: UInt16) {
        writeVCPValue(service: service, code: .contrast, value: value)
    }

    /// Sets the input source of the monitor (value depends on monitor model).
    func setInputSource(service: CFTypeRef, value: UInt16) {
        writeVCPValue(service: service, code: .inputSource, value: value)
    }

    // MARK: - Private Helpers

    /// Iterates IOKit services matching the given class name and wraps each in an IOAVService.
    private func servicesForClassName(_ className: String) -> [(service: CFTypeRef, port: io_service_t)] {
        var results: [(service: CFTypeRef, port: io_service_t)] = []

        guard let matching = IOServiceMatching(className) else {
            return results
        }

        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard kr == KERN_SUCCESS else {
            return results
        }

        defer { IOObjectRelease(iterator) }

        var port = IOIteratorNext(iterator)
        while port != IO_OBJECT_NULL {
            if let avServiceUnmanaged = IOAVServiceCreateWithService(kCFAllocatorDefault, port) {
                let avService = avServiceUnmanaged.takeRetainedValue()
                results.append((service: avService, port: port))
            } else {
                IOObjectRelease(port)
            }
            port = IOIteratorNext(iterator)
        }

        return results
    }

    /// Appends a DDC/CI XOR checksum byte to the command buffer.
    ///
    /// The checksum is computed as: `(destination << 1) XOR all command bytes`.
    private func appendChecksum(to buffer: inout [UInt8], destination: UInt32) {
        var checksum = UInt8((destination << 1) & 0xFF)
        for byte in buffer {
            checksum ^= byte
        }
        buffer.append(checksum)
    }

    /// Parses a DDC/CI VCP reply and extracts the current and maximum values.
    ///
    /// Standard DDC/CI reply format (11 bytes):
    ///   [0]: source address (0x6E)
    ///   [1]: length | 0x80
    ///   [2]: 0x02 (VCP reply opcode)
    ///   [3]: result code (0x00 = no error)
    ///   [4]: VCP code
    ///   [5]: VCP type code
    ///   [6]: max value high byte
    ///   [7]: max value low byte
    ///   [8]: current value high byte
    ///   [9]: current value low byte
    ///  [10]: checksum
    private func parseDDCReply(_ reply: [UInt8], expectedCode: VCPCode) -> (current: UInt16, max: UInt16)? {
        guard reply.count >= 11 else {
            print("[DDC] Reply too short: \(reply.count) bytes")
            return nil
        }

        // Verify this is a VCP reply (opcode 0x02)
        guard reply[2] == 0x02 else {
            print("[DDC] Unexpected reply opcode: 0x\(String(reply[2], radix: 16))")
            return nil
        }

        // Check result code
        guard reply[3] == 0x00 else {
            print("[DDC] VCP reply error code: 0x\(String(reply[3], radix: 16))")
            return nil
        }

        // Verify the VCP code matches
        guard reply[4] == expectedCode.rawValue else {
            print("[DDC] VCP code mismatch: expected 0x\(String(expectedCode.rawValue, radix: 16)), got 0x\(String(reply[4], radix: 16))")
            return nil
        }

        let maxValue     = (UInt16(reply[6]) << 8) | UInt16(reply[7])
        let currentValue = (UInt16(reply[8]) << 8) | UInt16(reply[9])

        return (current: currentValue, max: maxValue)
    }
}
