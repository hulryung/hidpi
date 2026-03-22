// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation

// DisplaySettings and VirtualDisplayConfig are defined in DisplayTypes.swift

// MARK: - Root Settings Container

private struct SettingsContainer: Codable {
    var displays: [String: DisplaySettings] = [:]
    var virtualDisplays: [VirtualDisplayConfig] = []
}

// MARK: - Settings Manager

final class SettingsManager: ObservableObject {

    static let shared = SettingsManager()

    @Published var displaySettings: [String: DisplaySettings] = [:]
    @Published var virtualDisplayConfigs: [VirtualDisplayConfig] = []

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.hidpiapp.settingsmanager", qos: .utility)

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDirectory = appSupport.appendingPathComponent("HiDPIApp", isDirectory: true)
        self.fileURL = appDirectory.appendingPathComponent("settings.json")

        // Ensure the directory exists
        try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)

        loadSettings()
    }

    // MARK: - Load

    func loadSettings() {
        queue.sync { [self] in
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                let container = try decoder.decode(SettingsContainer.self, from: data)
                DispatchQueue.main.async {
                    self.displaySettings = container.displays
                    self.virtualDisplayConfigs = container.virtualDisplays
                }
            } catch {
                print("[SettingsManager] Failed to load settings: \(error)")
            }
        }
    }

    // MARK: - Save

    func saveSettings() {
        let container = SettingsContainer(
            displays: displaySettings,
            virtualDisplays: virtualDisplayConfigs
        )
        queue.async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(container)
                try data.write(to: self.fileURL, options: .atomic)
            } catch {
                print("[SettingsManager] Failed to save settings: \(error)")
            }
        }
    }

    // MARK: - Per-Display Access

    /// Returns the settings for a display identified by vendor and product ID.
    /// If no settings exist yet, a default entry is created, persisted, and returned.
    func settingsForDisplay(vendorID: UInt32, productID: UInt32) -> DisplaySettings {
        let key = "\(vendorID)-\(productID)"
        if let existing = displaySettings[key] {
            return existing
        }
        let newSettings = DisplaySettings(displayID: key)
        displaySettings[key] = newSettings
        saveSettings()
        return newSettings
    }

    /// Mutates the settings for a given display in-place and auto-saves.
    func updateSettings(vendorID: UInt32, productID: UInt32, update: (inout DisplaySettings) -> Void) {
        let key = "\(vendorID)-\(productID)"
        var settings = displaySettings[key] ?? DisplaySettings(displayID: key)
        update(&settings)
        displaySettings[key] = settings
        saveSettings()
    }

    // MARK: - Virtual Display Configs

    func addVirtualDisplayConfig(_ config: VirtualDisplayConfig) {
        virtualDisplayConfigs.append(config)
        saveSettings()
    }

    func removeVirtualDisplayConfig(id: UUID) {
        virtualDisplayConfigs.removeAll { $0.id == id }
        saveSettings()
    }
}
