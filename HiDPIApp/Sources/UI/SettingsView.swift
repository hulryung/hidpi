// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

// MARK: - SettingsView

/// Settings window content with tabs for Displays, Virtual Displays, and General configuration.
struct SettingsView: View {
    @EnvironmentObject var displayManager: DisplayManager

    var body: some View {
        TabView {
            DisplaysSettingsTab(displayManager: displayManager)
                .tabItem {
                    Label("Displays", systemImage: "display.2")
                }

            VirtualDisplaysTab()
                .tabItem {
                    Label("Virtual Displays", systemImage: "rectangle.on.rectangle")
                }

            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
        }
        .frame(width: 580, height: 500)
    }
}

// MARK: - Displays Settings Tab

struct DisplaysSettingsTab: View {
    @ObservedObject var displayManager: DisplayManager
    @State private var selectedDisplayID: CGDirectDisplayID?

    var body: some View {
        HSplitView {
            displaySidebar
                .frame(minWidth: 160, maxWidth: 200)

            displayDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selectedDisplayID == nil {
                selectedDisplayID = displayManager.displays.first?.id
            }
        }
    }

    // MARK: - Sidebar

    private var displaySidebar: some View {
        List(displayManager.displays, selection: $selectedDisplayID) { display in
            HStack(spacing: 8) {
                Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(display.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    Text(display.displayIDHex)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .tag(display.id)
        }
        .listStyle(.sidebar)
    }

    // MARK: - Detail

    private var displayDetail: some View {
        Group {
            if let display = displayManager.displays.first(where: { $0.id == selectedDisplayID }) {
                DisplaySettingsDetail(display: display, displayManager: displayManager)
            } else {
                VStack {
                    Text("Select a display")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Display Settings Detail

struct DisplaySettingsDetail: View {
    @ObservedObject var display: DisplayInfo
    @ObservedObject var displayManager: DisplayManager
    @State private var flexibleScaling: Bool = false
    @State private var customResolutionsText: String = ""
    @State private var overrideError: String?
    @State private var overrideSuccess: Bool = false
    @State private var selectedRotation: Int = 0

    var body: some View {
        ScrollView {
            Form {
                displayInfoSection
                overrideSection
                hdrSection
                rotationSection
                brightnessSection
            }
            .formStyle(.grouped)
        }
        .onAppear { loadDisplayState() }
        .onChange(of: display.id) { _ in loadDisplayState() }
    }

    private func loadDisplayState() {
        let settings = SettingsManager.shared.settingsForDisplay(
            vendorID: display.vendorID,
            productID: display.productID
        )
        flexibleScaling = settings.flexibleScaling
        customResolutionsText = settings.customResolutions
            .map { "\($0.width)x\($0.height)" }
            .joined(separator: ", ")
        selectedRotation = display.rotation
        overrideError = nil
        overrideSuccess = false
    }

    // MARK: - Display Info Section

    private var displayInfoSection: some View {
        GroupBox("Display Information") {
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Name", value: display.name)
                infoRow("Display ID", value: display.displayIDHex)
                infoRow("Vendor ID", value: "0x\(String(format: "%04X", display.vendorID))")
                infoRow("Product ID", value: "0x\(String(format: "%04X", display.productID))")
                infoRow("Available Modes", value: "\(display.modes.count) (\(display.hiDPIModes.count) HiDPI)")
                if let current = display.currentMode {
                    if display.screenDiagonalInches > 0 {
                        infoRow("Current Mode", value: current.detailStringWithPPI(
                            screenDiagonalInches: display.screenDiagonalInches
                        ))
                    } else {
                        infoRow("Current Mode", value: current.detailString)
                    }
                }
                if display.screenDiagonalInches > 0 {
                    infoRow("Screen Size", value: String(format: "%.1f\"", display.screenDiagonalInches))
                    infoRow("Native PPI", value: "\(Int(display.nativePPI))")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Override Section

    private var overrideSection: some View {
        GroupBox("Display Override") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: display.hasOverride ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(display.hasOverride ? .green : .secondary)
                    Text(display.hasOverride ? "Override installed" : "No override installed")
                        .font(.subheadline)
                }

                Toggle("Enable Flexible Scaling", isOn: $flexibleScaling)
                    .onChange(of: flexibleScaling) { newValue in
                        SettingsManager.shared.updateSettings(
                            vendorID: display.vendorID,
                            productID: display.productID
                        ) { $0.flexibleScaling = newValue }
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Resolutions")
                        .font(.subheadline)
                    TextField("e.g. 1920x1080, 2560x1440, 3008x1692", text: $customResolutionsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("Comma-separated WxH format")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if let error = overrideError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if overrideSuccess {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Override applied. Displays will redetect.")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 12) {
                    Button(display.hasOverride ? "Reinstall Override" : "Install Override") {
                        installOverride()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if display.hasOverride {
                        Button("Remove Override", role: .destructive) {
                            removeOverride()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Restore Backup") {
                            restoreBackup()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - HDR Section

    @ViewBuilder
    private var hdrSection: some View {
        if display.supportsHDR {
            GroupBox("HDR") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("High Dynamic Range")
                            .font(.subheadline)
                        Text("Enable HDR output for this display")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { display.hdrEnabled },
                        set: { _ in
                            displayManager.toggleHDR(displayID: display.id)
                        }
                    ))
                    .toggleStyle(.switch)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Rotation Section

    private var rotationSection: some View {
        GroupBox("Rotation") {
            HStack {
                Text("Screen Rotation")
                    .font(.subheadline)
                Spacer()
                Picker("", selection: $selectedRotation) {
                    Text("0°").tag(0)
                    Text("90°").tag(90)
                    Text("180°").tag(180)
                    Text("270°").tag(270)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: selectedRotation) { angle in
                    displayManager.setRotation(displayID: display.id, angle: angle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Brightness Section

    private var brightnessSection: some View {
        GroupBox("Brightness") {
            VStack(alignment: .leading, spacing: 8) {
                BrightnessSliderRow(
                    label: "Software Brightness",
                    icon: "sun.max",
                    displayID: display.id
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Override Actions

    private func installOverride() {
        overrideError = nil
        overrideSuccess = false

        let customRes = parseCustomResolutions(customResolutionsText)

        // Save custom resolutions to settings
        SettingsManager.shared.updateSettings(
            vendorID: display.vendorID,
            productID: display.productID
        ) { settings in
            settings.customResolutions = customRes.map {
                DisplaySettings.Resolution(width: $0.width, height: $0.height)
            }
            settings.overrideInstalled = true
            settings.flexibleScaling = flexibleScaling
        }

        var config = OverrideConfig(
            vendorID: display.vendorID,
            productID: display.productID,
            displayName: display.name
        )
        config.resolutions = customRes

        let plist: [String: Any]
        if flexibleScaling {
            plist = DisplayOverride.generateFlexibleScalingPlist(config: config)
        } else {
            plist = DisplayOverride.generateOverridePlist(config: config)
        }

        do {
            try DisplayOverride.installAndRedetect(
                vendorID: display.vendorID,
                productID: display.productID,
                plist: plist
            )
            overrideSuccess = true

            // Refresh displays after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                displayManager.refreshDisplays()
            }
        } catch {
            overrideError = error.localizedDescription
        }
    }

    private func removeOverride() {
        overrideError = nil
        overrideSuccess = false

        do {
            try DisplayOverride.removeAndRedetect(
                vendorID: display.vendorID,
                productID: display.productID
            )

            SettingsManager.shared.updateSettings(
                vendorID: display.vendorID,
                productID: display.productID
            ) { $0.overrideInstalled = false }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                displayManager.refreshDisplays()
            }
        } catch {
            overrideError = error.localizedDescription
        }
    }

    private func restoreBackup() {
        overrideError = nil
        overrideSuccess = false

        do {
            try DisplayOverride.restoreFromBackupWithAdminPrivileges(
                vendorID: display.vendorID,
                productID: display.productID
            )
            DisplayOverride.reinitializeDisplays()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                displayManager.refreshDisplays()
            }
        } catch {
            overrideError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func parseCustomResolutions(_ text: String) -> [(width: Int, height: Int)] {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        return text.split(separator: ",")
            .compactMap { segment -> (width: Int, height: Int)? in
                let parts = segment.trimmingCharacters(in: .whitespaces)
                    .lowercased()
                    .split(separator: "x")
                guard parts.count == 2,
                      let w = Int(parts[0]),
                      let h = Int(parts[1]),
                      w > 0, h > 0
                else { return nil }
                return (width: w, height: h)
            }
    }

    private func infoRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .textSelection(.enabled)
        }
        .font(.subheadline)
    }
}

// MARK: - Brightness Slider Row

struct BrightnessSliderRow: View {
    let label: String
    let icon: String
    let displayID: CGDirectDisplayID

    @State private var brightness: Double = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
            HStack(spacing: 8) {
                Image(systemName: "sun.min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $brightness, in: 0.2...1.0, step: 0.05) { editing in
                    if !editing {
                        BrightnessController.shared.setSoftwareBrightness(
                            displayID: displayID,
                            brightness: Float(brightness)
                        )
                    }
                }
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(Int(brightness * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 36)
            }
        }
    }
}

// MARK: - Virtual Displays Tab

struct VirtualDisplaysTab: View {
    @ObservedObject private var virtualManager = VirtualDisplayManager.shared
    @ObservedObject private var settingsManager = SettingsManager.shared
    @State private var newName = "Virtual Display"
    @State private var newWidth = "3840"
    @State private var newHeight = "2160"
    @State private var newHiDPI = true
    @State private var newRefreshRate = "60"

    var body: some View {
        Form {
            GroupBox("Create Virtual Display") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Name")
                            .frame(width: 80, alignment: .trailing)
                        TextField("Display name", text: $newName)
                            .textFieldStyle(.roundedBorder)
                    }
                    HStack {
                        Text("Resolution")
                            .frame(width: 80, alignment: .trailing)
                        TextField("Width", text: $newWidth)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("x")
                        TextField("Height", text: $newHeight)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("@")
                        TextField("Hz", text: $newRefreshRate)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 50)
                        Text("Hz")
                    }
                    HStack {
                        Text("")
                            .frame(width: 80, alignment: .trailing)
                        Toggle("HiDPI / Retina", isOn: $newHiDPI)
                    }
                    HStack {
                        Text("")
                            .frame(width: 80)
                        Button("Create") {
                            createVirtualDisplay()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }

            GroupBox("Active Virtual Displays") {
                if virtualManager.activeDisplays.isEmpty && settingsManager.virtualDisplayConfigs.isEmpty {
                    Text("No virtual displays")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(settingsManager.virtualDisplayConfigs) { config in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(config.name)
                                        .font(.subheadline.bold())
                                    Text("\(config.width)x\(config.height) @\(config.refreshRate)Hz\(config.hiDPI ? " HiDPI" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()

                                let isActive = virtualManager.activeDisplays.contains { $0.displayID != 0 }
                                Circle()
                                    .fill(isActive ? .green : .orange)
                                    .frame(width: 8, height: 8)

                                Button(role: .destructive) {
                                    removeVirtualDisplay(config: config)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func createVirtualDisplay() {
        guard let w = Int(newWidth), let h = Int(newHeight), let hz = Int(newRefreshRate),
              w > 0, h > 0, hz > 0 else { return }

        let config = VirtualDisplayConfig(
            name: newName,
            width: w,
            height: h,
            hiDPI: newHiDPI,
            refreshRate: hz
        )

        // Save config for persistence
        settingsManager.addVirtualDisplayConfig(config)

        // Create the actual virtual display
        let _ = virtualManager.createVirtualDisplay(
            name: newName,
            width: w,
            height: h,
            hiDPI: newHiDPI,
            refreshRate: hz
        )
    }

    private func removeVirtualDisplay(config: VirtualDisplayConfig) {
        // Remove from persistence
        settingsManager.removeVirtualDisplayConfig(id: config.id)

        // Disconnect all (simplified; ideally match by config)
        virtualManager.disconnectAll()

        // Recreate remaining
        for remaining in settingsManager.virtualDisplayConfigs {
            let _ = virtualManager.createVirtualDisplay(
                name: remaining.name,
                width: remaining.width,
                height: remaining.height,
                hiDPI: remaining.hiDPI,
                refreshRate: remaining.refreshRate
            )
        }
    }
}

// MARK: - General Settings Tab

struct GeneralSettingsTab: View {
    @State private var launchAtLogin = AppDelegate.isLaunchAtLoginEnabled

    var body: some View {
        Form {
            GroupBox("Startup") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { newValue in
                            AppDelegate.setLaunchAtLogin(newValue)
                        }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }

            GroupBox("About") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("HiDPI")
                            .font(.headline)
                        Text("v\(appVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text("Manage HiDPI resolutions for external displays on macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Uses private macOS frameworks. Not available on the App Store.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }
}
