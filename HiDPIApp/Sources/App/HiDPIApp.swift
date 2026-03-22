// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import SwiftUI

@main
struct HiDPIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appDelegate.displayManager)
        }
    }
}
