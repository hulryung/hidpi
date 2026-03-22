// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics
import IOKit

// MARK: - DisplayServices Private Framework Declarations

@_silgen_name("DisplayServicesGetBrightness")
func DisplayServicesGetBrightness(_ display: CGDirectDisplayID, _ brightness: UnsafeMutablePointer<Float>) -> Int32

@_silgen_name("DisplayServicesSetBrightness")
func DisplayServicesSetBrightness(_ display: CGDirectDisplayID, _ brightness: Float) -> Int32

// MARK: - BrightnessController

final class BrightnessController: ObservableObject {

    static let shared = BrightnessController()

    /// Tracks the current software brightness factor per display (0.0 to 1.0).
    private var softwareBrightnessValues: [CGDirectDisplayID: Float] = [:]

    /// Stores the original (unmodified) gamma tables so brightness can be restored.
    private var originalGammaTables: [CGDirectDisplayID: (red: [Float], green: [Float], blue: [Float], count: UInt32)] = [:]

    private let queue = DispatchQueue(label: "com.hidpi.brightnesscontroller", qos: .userInteractive)

    private init() {}

    // MARK: - Software Brightness (Gamma Table Manipulation)

    /// Returns the current software brightness factor for a display.
    /// Defaults to 1.0 if no adjustment has been applied.
    func getSoftwareBrightness(displayID: CGDirectDisplayID) -> Float {
        return queue.sync {
            softwareBrightnessValues[displayID] ?? 1.0
        }
    }

    /// Sets software brightness by scaling the display's gamma table.
    /// - Parameters:
    ///   - displayID: The target display.
    ///   - brightness: A value between 0.0 (fully dimmed) and 1.0 (original brightness).
    func setSoftwareBrightness(displayID: CGDirectDisplayID, brightness: Float) {
        let clampedBrightness = min(max(brightness, 0.0), 1.0)

        queue.sync {
            softwareBrightnessValues[displayID] = clampedBrightness
        }

        applyGammaTable(displayID: displayID, factor: clampedBrightness)
    }

    /// Resets the software brightness to 1.0 (no dimming) for a display.
    func resetSoftwareBrightness(displayID: CGDirectDisplayID) {
        queue.sync {
            softwareBrightnessValues[displayID] = 1.0
            originalGammaTables[displayID] = nil
        }

        CGDisplayRestoreColorSyncSettings()
    }

    /// Captures and caches the original gamma table for a display (before any brightness adjustment).
    private func getOriginalGammaTable(displayID: CGDirectDisplayID) -> (red: [Float], green: [Float], blue: [Float], count: UInt32)? {
        if let cached = queue.sync(execute: { originalGammaTables[displayID] }) {
            return cached
        }

        let capacity: UInt32 = 256
        var sampleCount: UInt32 = 0
        var redTable = [Float](repeating: 0, count: Int(capacity))
        var greenTable = [Float](repeating: 0, count: Int(capacity))
        var blueTable = [Float](repeating: 0, count: Int(capacity))

        let result = CGGetDisplayTransferByTable(
            displayID,
            capacity,
            &redTable,
            &greenTable,
            &blueTable,
            &sampleCount
        )

        guard result == .success else {
            NSLog("BrightnessController: Failed to get gamma table for display \(displayID), error: \(result.rawValue)")
            return nil
        }

        let table = (red: redTable, green: greenTable, blue: blueTable, count: sampleCount)
        queue.sync { originalGammaTables[displayID] = table }
        return table
    }

    /// Applies brightness by scaling the original (unmodified) gamma table by the given factor.
    private func applyGammaTable(displayID: CGDirectDisplayID, factor: Float) {
        guard let original = getOriginalGammaTable(displayID: displayID) else { return }

        var redTable = original.red
        var greenTable = original.green
        var blueTable = original.blue
        let sampleCount = original.count

        for i in 0..<Int(sampleCount) {
            redTable[i] *= factor
            greenTable[i] *= factor
            blueTable[i] *= factor
        }

        let setResult = CGSetDisplayTransferByTable(
            displayID,
            sampleCount,
            &redTable,
            &greenTable,
            &blueTable
        )

        if setResult != .success {
            NSLog("BrightnessController: Failed to set gamma table for display \(displayID), error: \(setResult.rawValue)")
        }
    }

    // MARK: - Built-in Display Brightness (CoreBrightness / DisplayServices)

    /// Gets the brightness of a built-in display using the DisplayServices private framework.
    /// Returns nil if the display is not built-in or the call fails.
    func getBuiltInBrightness(displayID: CGDirectDisplayID) -> Float? {
        guard isBuiltInDisplay(displayID) else {
            return nil
        }

        var brightness: Float = 0.0
        let result = DisplayServicesGetBrightness(displayID, &brightness)

        guard result == 0 else {
            NSLog("BrightnessController: Failed to get built-in brightness for display \(displayID), error: \(result)")
            return nil
        }

        return brightness
    }

    /// Sets the brightness of a built-in display using the DisplayServices private framework.
    /// - Parameters:
    ///   - displayID: The target display (must be built-in).
    ///   - brightness: A value between 0.0 and 1.0.
    /// - Returns: `true` if the brightness was set successfully.
    @discardableResult
    func setBuiltInBrightness(displayID: CGDirectDisplayID, brightness: Float) -> Bool {
        guard isBuiltInDisplay(displayID) else {
            NSLog("BrightnessController: Display \(displayID) is not a built-in display")
            return false
        }

        let clampedBrightness = min(max(brightness, 0.0), 1.0)
        let result = DisplayServicesSetBrightness(displayID, clampedBrightness)

        if result != 0 {
            NSLog("BrightnessController: Failed to set built-in brightness for display \(displayID), error: \(result)")
            return false
        }

        return true
    }

    // MARK: - Display Identification

    /// Returns whether the given display is a built-in (internal) display.
    func isBuiltInDisplay(_ displayID: CGDirectDisplayID) -> Bool {
        return CGDisplayIsBuiltin(displayID) != 0
    }
}
