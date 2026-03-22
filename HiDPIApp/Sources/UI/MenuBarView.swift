// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

// MARK: - MenuBarView

/// The main popover view shown when clicking the menu bar icon.
/// Lists all connected displays with expandable resolution sections.
struct MenuBarView: View {
    @ObservedObject var displayManager: DisplayManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            // Rollback confirmation banner
            if let rollback = displayManager.pendingRollback {
                RollbackBannerView(
                    deadline: rollback.deadline,
                    onConfirm: { displayManager.confirmModeChange() },
                    onRevert: { displayManager.revertModeChange() }
                )
                Divider()
            }

            displayList
            Divider()
            bottomBar
        }
        .frame(width: 360)
        .frame(minHeight: 200)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("HiDPI")
                .font(.headline)
            Spacer()
            Text("\(displayManager.displays.count) display\(displayManager.displays.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Display List

    private var displayList: some View {
        Group {
            if displayManager.displays.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "display.trianglebadge.exclamationmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("No displays detected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 100)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(displayManager.displays) { display in
                            DisplayRowView(
                                display: display,
                                displayManager: displayManager
                            ) { modeID in
                                NSLog("[HiDPI] User selected mode %d for display 0x%x", modeID, display.id)
                                displayManager.setModeWithRollback(
                                    displayID: display.id,
                                    modeNumber: modeID
                                )
                            }
                            .padding(.horizontal, 12)

                            if display.id != displayManager.displays.last?.id {
                                Divider()
                                    .padding(.horizontal, 16)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                displayManager.redetectDisplays()
            } label: {
                Label("Redetect", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Rollback Banner

struct RollbackBannerView: View {
    let deadline: Date
    let onConfirm: () -> Void
    let onRevert: () -> Void

    @State private var timeRemaining: Int = 15

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Keep this resolution?")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(timeRemaining)s")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Revert") {
                    onRevert()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Keep") {
                    onConfirm()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .onAppear {
            startCountdown()
        }
    }

    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let remaining = Int(deadline.timeIntervalSinceNow)
            if remaining <= 0 {
                timer.invalidate()
                timeRemaining = 0
            } else {
                timeRemaining = remaining
            }
        }
    }
}
