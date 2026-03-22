// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics
import AppKit

// MARK: - BrightnessKeyMonitor

/// Monitors keyboard brightness keys (F1/F2) and syncs the built-in display brightness
/// to external monitors via DDC/CI.
final class BrightnessKeyMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let ddcController = DDCController.shared
    private let brightnessController = BrightnessController.shared

    /// Cached DDC-capable external monitor services with their max brightness values.
    private var ddcServices: [(service: CFTypeRef, maxBrightness: UInt16)] = []

    // MARK: - Start / Stop

    func start() {
        discoverDDCServices()
        setupEventTap()
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Re-discover DDC services (call when displays connect/disconnect).
    func refreshServices() {
        ddcServices.removeAll()
        discoverDDCServices()
    }

    // MARK: - DDC Service Discovery

    private func discoverDDCServices() {
        let services = ddcController.findAVServices()
        for svc in services {
            // Only keep services that respond to DDC brightness reads (external monitors).
            if let brightness = ddcController.getBrightness(service: svc.service) {
                ddcServices.append((service: svc.service, maxBrightness: max(brightness.max, 100)))
                NSLog("[BrightnessKeyMonitor] Found DDC display, brightness: %d/%d", brightness.current, brightness.max)
            }
            IOObjectRelease(svc.port)
        }
        NSLog("[BrightnessKeyMonitor] Discovered %d DDC-capable display(s)", ddcServices.count)
    }

    // MARK: - Event Tap

    private func setupEventTap() {
        // NX_SYSDEFINED = 14
        let eventMask: CGEventMask = 1 << 14

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: brightnessEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[BrightnessKeyMonitor] Failed to create event tap — grant Accessibility permission in System Settings")
            promptAccessibilityPermission()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[BrightnessKeyMonitor] Event tap started")
    }

    private func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Event Handling

    fileprivate func handleEvent(_ event: CGEvent, type: CGEventType) {
        // Re-enable tap if the system disabled it
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return
        }

        // NX_SYSDEFINED = 14
        guard type.rawValue == 14,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == 8 else { return }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF0000) >> 16
        let keyFlags = (data1 & 0x0000FF00) >> 8
        let isKeyDown = (keyFlags & 0x0A) != 0

        guard isKeyDown else { return }

        // NX_KEYTYPE_BRIGHTNESS_UP = 2, NX_KEYTYPE_BRIGHTNESS_DOWN = 3
        guard keyCode == 2 || keyCode == 3 else { return }

        // Small delay to let macOS update the built-in brightness first
        DispatchQueue.global(qos: .userInteractive).asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.syncBrightnessToExternalDisplays()
        }
    }

    // MARK: - Brightness Sync

    private func syncBrightnessToExternalDisplays() {
        // Find built-in display and read its current brightness (0.0 – 1.0)
        let builtInID = findBuiltInDisplayID()
        guard let builtInBrightness = brightnessController.getBuiltInBrightness(displayID: builtInID) else {
            return
        }

        // DDC hardware brightness for external monitors
        for svc in ddcServices {
            let ddcValue = UInt16(builtInBrightness * Float(svc.maxBrightness))
            ddcController.setBrightness(service: svc.service, value: ddcValue)
        }

        // Software dimming (gamma) for external displays to supplement DDC at low brightness.
        // DDC brightness 0 is often still too bright on external monitors,
        // so we apply gamma dimming below 50% to achieve a darker minimum.
        let softwareThreshold: Float = 0.5
        let gammaFactor: Float = builtInBrightness < softwareThreshold
            ? max(builtInBrightness / softwareThreshold, 0.0)
            : 1.0

        for displayID in findExternalDisplayIDs() {
            brightnessController.setSoftwareBrightness(displayID: displayID, brightness: gammaFactor)
        }

        NSLog("[BrightnessKeyMonitor] Synced brightness %.0f%% (DDC) gamma=%.2f to external display(s)",
              builtInBrightness * 100, gammaFactor)
    }

    private func findBuiltInDisplayID() -> CGDirectDisplayID {
        for d in onlineDisplays() {
            if CGDisplayIsBuiltin(d) != 0 { return d }
        }
        return CGMainDisplayID()
    }

    private func findExternalDisplayIDs() -> [CGDirectDisplayID] {
        return onlineDisplays().filter { CGDisplayIsBuiltin($0) == 0 && CGDisplayBounds($0).width > 1 }
    }

    private func onlineDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &displayCount)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetOnlineDisplayList(displayCount, &displays, &displayCount)
        return Array(displays.prefix(Int(displayCount)))
    }

    deinit {
        stop()
    }
}

// MARK: - C Callback

private func brightnessEventTapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let userInfo = userInfo {
        let monitor = Unmanaged<BrightnessKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
        monitor.handleEvent(event, type: type)
    }
    return Unmanaged.passUnretained(event)
}
