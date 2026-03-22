// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics

// MARK: - DisplayMonitor

/// Watches for display connect / disconnect / mode-change events
/// via `CGDisplayRegisterReconfigurationCallback`.
class DisplayMonitor {

    /// Called on the main thread whenever displays are added, removed, or reconfigured.
    var onDisplaysChanged: (() -> Void)?

    private var isMonitoring = false

    // MARK: - Start / Stop

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, context)
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        let context = Unmanaged.passUnretained(self).toOpaque()
        CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, context)
    }

    deinit {
        stopMonitoring()
    }
}

// MARK: - C Callback

/// Top-level C function used as the reconfiguration callback.
/// The `userInfo` pointer carries the `DisplayMonitor` instance.
private func displayReconfigurationCallback(
    _ displayID: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo = userInfo else { return }

    // Only react to meaningful topology / mode changes.
    let relevantFlags: CGDisplayChangeSummaryFlags = [
        .addFlag,
        .removeFlag,
        .setModeFlag
    ]
    guard !flags.intersection(relevantFlags).isEmpty else { return }

    // The "begin" flag is sent before the change completes; wait for the
    // matching call without the begin flag so we act on the final state.
    if flags.contains(.beginConfigurationFlag) { return }

    let monitor = Unmanaged<DisplayMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        monitor.onDisplaysChanged?()
    }
}
