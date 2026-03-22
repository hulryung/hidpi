// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import AppKit
import SwiftUI
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    let displayManager = DisplayManager()
    private let displayMonitor = DisplayMonitor()
    private let virtualDisplayManager = VirtualDisplayManager.shared
    private let brightnessKeyMonitor = BrightnessKeyMonitor()
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMonitoring()
        setupMenuBar()
        setupClickOutsideMonitor()
        restoreVirtualDisplays()
        brightnessKeyMonitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        displayMonitor.stopMonitoring()
        brightnessKeyMonitor.stop()
    }

    // MARK: - Display Monitoring

    private func setupMonitoring() {
        displayMonitor.onDisplaysChanged = { [weak self] in
            self?.displayManager.refreshDisplays()
            self?.brightnessKeyMonitor.refreshServices()
        }
        displayMonitor.startMonitoring()
    }

    // MARK: - Virtual Display Restoration

    private func restoreVirtualDisplays() {
        let configs = SettingsManager.shared.virtualDisplayConfigs
        guard !configs.isEmpty else { return }

        for config in configs {
            NSLog("[HiDPI] Restoring virtual display: %@", config.name)
            let _ = virtualDisplayManager.createVirtualDisplay(
                name: config.name,
                width: config.width,
                height: config.height,
                hiDPI: config.hiDPI,
                refreshRate: config.refreshRate
            )
        }

        // Refresh displays after virtual displays are created
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.displayManager.refreshDisplays()
        }
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "display", accessibilityDescription: "HiDPI")
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .semitransient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView(displayManager: displayManager)
        )
        self.popover = popover
    }

    private func setupClickOutsideMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if self?.popover?.isShown == true {
                self?.popover?.performClose(nil)
            }
        }
    }

    @objc private func togglePopover() {
        guard let popover = popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring to front
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Login at Start

    static func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("[HiDPI] Failed to set launch at login: %@", error.localizedDescription)
            }
        }
    }

    static var isLaunchAtLoginEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
