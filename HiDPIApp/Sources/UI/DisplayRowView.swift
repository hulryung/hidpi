// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

// MARK: - DisplayRowView

/// A reusable row view for a single display in the menu bar popover.
/// Shows display info with an expandable section listing available resolutions.
struct DisplayRowView: View {
    @ObservedObject var display: DisplayInfo
    var displayManager: DisplayManager
    var onSelectMode: (Int32) -> Void

    @State private var isExpanded = false
    @State private var brightness: Double = 1.0

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                quickControls
                modesList
            }
        } label: {
            displayHeader
        }
    }

    // MARK: - Header

    private var displayHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: display.isBuiltIn ? "laptopcomputer" : "display")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(display.name)
                    .font(.headline)
                    .lineLimit(1)

                if let current = display.currentMode {
                    Text(current.detailString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // HDR indicator
            if display.supportsHDR {
                Text("HDR")
                    .font(.caption2.bold())
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(display.hdrEnabled ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.1))
                    .foregroundStyle(display.hdrEnabled ? .orange : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Quick Controls

    private var quickControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            // HDR toggle
            if display.supportsHDR {
                HStack {
                    Image(systemName: "sun.max.circle")
                        .foregroundStyle(.orange)
                        .frame(width: 16)
                    Text("HDR")
                        .font(.caption)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { display.hdrEnabled },
                        set: { _ in
                            displayManager.toggleHDR(displayID: display.id)
                        }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 4)
            }

            // Software brightness slider
            HStack(spacing: 6) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Slider(value: $brightness, in: 0.2...1.0, step: 0.05) { editing in
                    if !editing {
                        BrightnessController.shared.setSoftwareBrightness(
                            displayID: display.id,
                            brightness: Float(brightness)
                        )
                    }
                }
                .controlSize(.mini)
                Image(systemName: "sun.max")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("\(Int(brightness * 100))%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 30)
            }
            .padding(.horizontal, 4)

            Divider()
        }
    }

    // MARK: - Modes List

    private var modesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            let groupedHiDPI = groupedModes(from: display.hiDPIModes)
            let groupedStandard = groupedModes(from: display.standardModes)

            if !groupedHiDPI.isEmpty {
                sectionHeader("HiDPI")
                ForEach(groupedHiDPI, id: \.id) { mode in
                    modeRow(mode)
                }
            }

            if !groupedStandard.isEmpty {
                sectionHeader("Standard")
                ForEach(groupedStandard.prefix(8), id: \.id) { mode in
                    modeRow(mode)
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .padding(.leading, 4)
    }

    private func modeRow(_ mode: DisplayMode) -> some View {
        let isFavorite = displayManager.isFavorite(for: display, modeID: mode.id)

        return Button {
            onSelectMode(mode.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .opacity(mode.id == display.currentModeID ? 1.0 : 0.0)
                    .frame(width: 14)

                Text(mode.resolution)
                    .font(.system(.body, design: .monospaced))

                Text("@\(mode.refreshRate)Hz")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if mode.isVRR {
                    Text("VRR")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, 3)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .background(
            mode.id == display.currentModeID
                ? Color.accentColor.opacity(0.1)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contextMenu {
            Button {
                displayManager.toggleFavorite(for: display, modeID: mode.id)
            } label: {
                Label(
                    isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: isFavorite ? "star.slash" : "star"
                )
            }
            Button {
                displayManager.savePreferredMode(for: display)
            } label: {
                Label("Set as Preferred Mode", systemImage: "pin")
            }
        }
    }

    // MARK: - Mode Grouping

    /// Groups modes by unique resolution string, keeping only the highest refresh rate per resolution.
    private func groupedModes(from modes: [DisplayMode]) -> [DisplayMode] {
        var bestByResolution: [String: DisplayMode] = [:]
        for mode in modes {
            let key = mode.resolution
            if let existing = bestByResolution[key] {
                if mode.refreshRate > existing.refreshRate {
                    bestByResolution[key] = mode
                }
                if mode.id == display.currentModeID {
                    bestByResolution[key] = mode
                }
            } else {
                bestByResolution[key] = mode
            }
        }

        return bestByResolution.values
            .sorted { lhs, rhs in
                if lhs.width != rhs.width { return lhs.width > rhs.width }
                if lhs.height != rhs.height { return lhs.height > rhs.height }
                return lhs.refreshRate > rhs.refreshRate
            }
    }
}
