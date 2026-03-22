// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics

// MARK: - HiDPI Tool CLI

let version = "1.0.0"

func printUsage() {
    print("""
    HiDPI Tool v\(version)
    macOS HiDPI display management tool

    USAGE:
      hidpi <command> [options]

    COMMANDS:
      list                          List all displays and their info
      modes <displayID>             List all display modes (including HiDPI)
      current <displayID>           Show current display mode
      set <displayID> <modeNum>     Switch to a specific display mode
      find-hidpi <displayID> <W> <H>  Find HiDPI mode for given resolution

      override create <displayID> [options]   Create HiDPI override plist
        --name <name>               Display name override
        --ppmm <value>              Target pixels per millimeter (default: 10.0)
        --res <WxH>                 Add custom resolution (repeatable)
        --flexible                  Enable flexible scaling (wide resolution range)
        --preview                   Preview plist without installing
        --native <WxH>              Override native resolution

      override remove <displayID>   Remove override plist
      override show <displayID>     Show current override plist
      override dir                  Show override directory path

      virtual create [options]      Create a HiDPI virtual display
        --name <name>               Display name (default: "HiDPI Virtual Display")
        --width <W>                 Max pixel width (default: 3840)
        --height <H>                Max pixel height (default: 2160)
        --rate <Hz>                 Refresh rate (default: 60)
        --no-hidpi                  Disable HiDPI mode

      edid <displayID>              Read and parse display EDID
      redetect                      Force display redetection (SLSDetectDisplays)

    DISPLAY ID:
      Use hex (0x1234) or decimal format. Use 'list' to find display IDs.
      Use 'main' for the main display.

    EXAMPLES:
      hidpi list
      hidpi modes main
      hidpi override create main --flexible
      hidpi override create 0x12345678 --res 2560x1440 --res 1920x1080
      hidpi virtual create --width 5120 --height 2880 --name "5K HiDPI"
      hidpi set main 42
    """)
}

// MARK: - Argument Parsing Helpers

func parseDisplayID(_ arg: String) -> CGDirectDisplayID? {
    if arg.lowercased() == "main" {
        return CGMainDisplayID()
    }
    if arg.lowercased().hasPrefix("0x") {
        return UInt32(arg.dropFirst(2), radix: 16)
    }
    return UInt32(arg)
}

func parseResolution(_ arg: String) -> (width: Int, height: Int)? {
    let parts = arg.lowercased().split(separator: "x")
    guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
    return (w, h)
}

// MARK: - Command Handlers

func cmdList() {
    let displays = DisplayManager.listDisplays()
    if displays.isEmpty {
        print("No displays found.")
        return
    }
    print("Found \(displays.count) display(s):\n")
    for displayID in displays {
        DisplayManager.printDisplaySummary(displayID: displayID)

        let (vendorID, productID) = DisplayManager.getVendorProductID(for: displayID)
        let hasOverride = DisplayOverride.overrideExists(vendorID: vendorID, productID: productID)
        print("  Override: \(hasOverride ? "installed" : "none")")

        let modes = DisplayManager.getDisplayModes(for: displayID)
        let hiDPIModes = modes.filter { $0.isHiDPI }
        print("  Modes: \(modes.count) total, \(hiDPIModes.count) HiDPI")
        print()
    }
}

func cmdModes(_ displayArg: String) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }

    let currentMode = DisplayManager.getCurrentMode(for: displayID)
    let modes = DisplayManager.getDisplayModes(for: displayID)

    if modes.isEmpty {
        print("No modes found for display 0x\(String(displayID, radix: 16))")
        return
    }

    print("Display 0x\(String(displayID, radix: 16)) - \(modes.count) modes (current: \(currentMode)):\n")

    // Group by HiDPI
    let standardModes = modes.filter { !$0.isHiDPI }
    let hiDPIModes = modes.filter { $0.isHiDPI }

    if !standardModes.isEmpty {
        print("Standard modes:")
        for mode in standardModes {
            let marker = mode.modeNumber == currentMode ? " <-- current" : ""
            print("\(mode.description)\(marker)")
        }
    }

    if !hiDPIModes.isEmpty {
        print("\nHiDPI modes:")
        for mode in hiDPIModes {
            let marker = mode.modeNumber == currentMode ? " <-- current" : ""
            print("\(mode.description)\(marker)")
        }
    }
}

func cmdCurrent(_ displayArg: String) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }

    let modeNumber = DisplayManager.getCurrentMode(for: displayID)
    let modes = DisplayManager.getDisplayModes(for: displayID)
    if let mode = modes.first(where: { $0.modeNumber == modeNumber }) {
        print("Current mode for display 0x\(String(displayID, radix: 16)):")
        print(mode.description)
    } else {
        print("Current mode: \(modeNumber)")
    }
}

func cmdSetMode(_ displayArg: String, _ modeArg: String) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }
    guard let modeNumber = Int32(modeArg) else {
        print("Error: Invalid mode number '\(modeArg)'")
        return
    }

    if DisplayManager.setDisplayMode(displayID: displayID, modeNumber: modeNumber) {
        print("Switched display 0x\(String(displayID, radix: 16)) to mode \(modeNumber)")
    } else {
        print("Error: Failed to switch display mode")
    }
}

func cmdFindHiDPI(_ displayArg: String, _ resArg: String) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }
    guard let res = parseResolution(resArg) else {
        print("Error: Invalid resolution '\(resArg)'. Use format: WxH (e.g. 1920x1080)")
        return
    }

    if let mode = DisplayManager.findHiDPIMode(displayID: displayID, width: Int32(res.width), height: Int32(res.height)) {
        print("Found HiDPI mode:")
        print(mode.description)
    } else {
        print("No HiDPI mode found for \(res.width)x\(res.height)")
        print("Tip: Create a display override to add HiDPI resolutions:")
        print("  hidpi override create \(displayArg) --res \(res.width)x\(res.height)")
    }
}

func cmdOverrideCreate(_ displayArg: String, _ args: ArraySlice<String>) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }

    let (vendorID, productID) = DisplayManager.getVendorProductID(for: displayID)

    var name: String?
    var ppmm: Float = 10.0
    var customResolutions: [(width: Int, height: Int)] = []
    var flexible = false
    var preview = false
    var nativeWidth: Int?
    var nativeHeight: Int?

    var i = args.startIndex
    while i < args.endIndex {
        switch args[i] {
        case "--name":
            i += 1; if i < args.endIndex { name = args[i] }
        case "--ppmm":
            i += 1; if i < args.endIndex { ppmm = Float(args[i]) ?? 10.0 }
        case "--res":
            i += 1
            if i < args.endIndex, let res = parseResolution(args[i]) {
                customResolutions.append(res)
            }
        case "--flexible":
            flexible = true
        case "--preview":
            preview = true
        case "--native":
            i += 1
            if i < args.endIndex, let res = parseResolution(args[i]) {
                nativeWidth = res.width
                nativeHeight = res.height
            }
        default:
            break
        }
        i += 1
    }

    let plist: [String: Any]
    if flexible {
        plist = DisplayOverride.generateFlexibleScalingPlist(
            vendorID: vendorID,
            productID: productID,
            displayName: name
        )
    } else {
        let resolutions = customResolutions.isEmpty ? nil : customResolutions
        plist = DisplayOverride.generateOverridePlist(
            vendorID: vendorID,
            productID: productID,
            resolutions: resolutions,
            displayName: name,
            targetPPMM: ppmm,
            nativeWidth: nativeWidth,
            nativeHeight: nativeHeight
        )
    }

    if preview {
        print("Override plist preview:\n")
        print(DisplayOverride.previewOverride(plist))
        print("\nTo install, run again without --preview (requires sudo)")
        return
    }

    do {
        try DisplayOverride.installOverride(vendorID: vendorID, productID: productID, plist: plist)
        print("\nOverride installed successfully.")
        print("Redetecting displays...")
        DisplayManager.redetectDisplays()
        print("Done. You may need to log out and back in for changes to take effect.")
    } catch {
        if (error as NSError).domain == NSCocoaErrorDomain && (error as NSError).code == NSFileWriteNoPermissionError {
            print("Error: Permission denied. Run with sudo:")
            print("  sudo hidpi override create \(displayArg) \(args.joined(separator: " "))")
            print("\nAlternatively, preview the plist first:")
            print("  hidpi override create \(displayArg) \(args.joined(separator: " ")) --preview")
        } else {
            print("Error: \(error)")
        }
    }
}

func cmdOverrideRemove(_ displayArg: String) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }

    let (vendorID, productID) = DisplayManager.getVendorProductID(for: displayID)

    do {
        try DisplayOverride.removeOverride(vendorID: vendorID, productID: productID)
        print("Redetecting displays...")
        DisplayManager.redetectDisplays()
    } catch {
        print("Error: \(error)")
    }
}

func cmdOverrideShow(_ displayArg: String) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }

    let (vendorID, productID) = DisplayManager.getVendorProductID(for: displayID)
    let filePath = DisplayOverride.overrideFilePath(vendorID: vendorID, productID: productID)

    if let plist = DisplayOverride.readOverride(vendorID: vendorID, productID: productID) {
        print("Override file: \(filePath)\n")
        print(DisplayOverride.previewOverride(plist))
    } else {
        print("No override found at: \(filePath)")
    }
}

func cmdVirtualCreate(_ args: ArraySlice<String>) {
    var name = "HiDPI Virtual Display"
    var width: UInt32 = 3840
    var height: UInt32 = 2160
    var rate: Float = 60.0
    var hiDPI = true

    var i = args.startIndex
    while i < args.endIndex {
        switch args[i] {
        case "--name":
            i += 1; if i < args.endIndex { name = args[i] }
        case "--width":
            i += 1; if i < args.endIndex { width = UInt32(args[i]) ?? 3840 }
        case "--height":
            i += 1; if i < args.endIndex { height = UInt32(args[i]) ?? 2160 }
        case "--rate":
            i += 1; if i < args.endIndex { rate = Float(args[i]) ?? 60.0 }
        case "--no-hidpi":
            hiDPI = false
        default:
            break
        }
        i += 1
    }

    guard let result = VirtualDisplayManager.createVirtualDisplay(
        name: name,
        width: width,
        height: height,
        hiDPI: hiDPI,
        refreshRate: rate
    ) else {
        print("Failed to create virtual display")
        return
    }

    print("\nVirtual display is active. Display ID: 0x\(String(result.displayID, radix: 16))")
    print("Press Ctrl+C to disconnect the virtual display.")

    // Keep the process alive to maintain the virtual display
    // The display object must stay retained
    let _ = result.display
    let semaphore = DispatchSemaphore(value: 0)

    signal(SIGINT) { _ in
        print("\nDisconnecting virtual display...")
        exit(0)
    }

    semaphore.wait()
}

func cmdEDID(_ displayArg: String) {
    guard let displayID = parseDisplayID(displayArg) else {
        print("Error: Invalid display ID '\(displayArg)'")
        return
    }

    if let edidData = DisplayManager.getEDID(for: displayID) {
        let parser = EDIDParser(data: edidData)
        parser.printSummary()
    } else {
        // Fallback: try to get info from CoreDisplay
        print("Direct EDID read failed. Trying CoreDisplay info dict...")
        if let info = DisplayManager.getDisplayInfo(for: displayID) {
            print("Display info:")
            for (key, value) in info.sorted(by: { $0.key < $1.key }) {
                print("  \(key): \(value)")
            }
        } else {
            print("No EDID data available for display 0x\(String(displayID, radix: 16))")
        }
    }
}

func cmdRedetect() {
    print("Redetecting displays...")
    DisplayManager.redetectDisplays()
    print("Done.")
}

// MARK: - Main Entry Point

let args = CommandLine.arguments
guard args.count > 1 else {
    printUsage()
    exit(0)
}

let command = args[1].lowercased()

switch command {
case "list":
    cmdList()

case "modes":
    guard args.count > 2 else { print("Usage: hidpi modes <displayID>"); exit(1) }
    cmdModes(args[2])

case "current":
    guard args.count > 2 else { print("Usage: hidpi current <displayID>"); exit(1) }
    cmdCurrent(args[2])

case "set":
    guard args.count > 3 else { print("Usage: hidpi set <displayID> <modeNumber>"); exit(1) }
    cmdSetMode(args[2], args[3])

case "find-hidpi":
    guard args.count > 3 else { print("Usage: hidpi find-hidpi <displayID> <WxH>"); exit(1) }
    cmdFindHiDPI(args[2], args[3])

case "override":
    guard args.count > 2 else { print("Usage: hidpi override <create|remove|show|dir> ..."); exit(1) }
    let subcommand = args[2].lowercased()
    switch subcommand {
    case "create":
        guard args.count > 3 else { print("Usage: hidpi override create <displayID> [options]"); exit(1) }
        cmdOverrideCreate(args[3], args[4...])
    case "remove":
        guard args.count > 3 else { print("Usage: hidpi override remove <displayID>"); exit(1) }
        cmdOverrideRemove(args[3])
    case "show":
        guard args.count > 3 else { print("Usage: hidpi override show <displayID>"); exit(1) }
        cmdOverrideShow(args[3])
    case "dir":
        print(DisplayOverride.overrideBasePath)
    default:
        print("Unknown override subcommand: \(subcommand)")
    }

case "virtual":
    guard args.count > 2 else { print("Usage: hidpi virtual create [options]"); exit(1) }
    if args[2].lowercased() == "create" {
        cmdVirtualCreate(args[3...])
    } else {
        print("Unknown virtual subcommand: \(args[2])")
    }

case "edid":
    guard args.count > 2 else { print("Usage: hidpi edid <displayID>"); exit(1) }
    cmdEDID(args[2])

case "redetect":
    cmdRedetect()

case "help", "--help", "-h":
    printUsage()

case "version", "--version", "-v":
    print("HiDPI Tool v\(version)")

default:
    print("Unknown command: \(command)")
    printUsage()
    exit(1)
}
