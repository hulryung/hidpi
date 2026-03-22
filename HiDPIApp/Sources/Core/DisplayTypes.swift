// Copyright (c) 2026 dkkang
// Licensed under the MIT License. See LICENSE file for details.

import Foundation
import CoreGraphics

// MARK: - Display Mode

/// Parsed display mode information
struct DisplayMode: Identifiable, Hashable {
    let id: Int32           // modeNumber
    let width: Int32        // rendered ("look like") width
    let height: Int32       // rendered ("look like") height
    let backingWidth: Int32 // actual backing pixel width
    let backingHeight: Int32
    let bitsPerPixel: Int32
    let refreshRate: Int32  // Hz
    let density: Float      // 2.0 = HiDPI
    let isHiDPI: Bool
    let isVRR: Bool
    let isProMotion: Bool
    let flags: UInt32

    var resolution: String {
        "\(width)x\(height)"
    }

    var detailString: String {
        let hidpi = isHiDPI ? " HiDPI" : ""
        let vrr = isVRR ? " VRR" : ""
        return "\(width)x\(height) @ \(refreshRate)Hz\(hidpi)\(vrr)"
    }

    /// Calculate effective PPI for a given physical screen diagonal (inches).
    /// For HiDPI modes, this is the "looks like" PPI (logical resolution / physical size).
    func effectivePPI(screenDiagonalInches: Double) -> Double {
        guard screenDiagonalInches > 0 else { return 0 }
        let diag = sqrt(Double(width * width + height * height))
        return diag / screenDiagonalInches
    }

    /// PPI detail string including effective PPI for a given screen size.
    func detailStringWithPPI(screenDiagonalInches: Double) -> String {
        let ppi = effectivePPI(screenDiagonalInches: screenDiagonalInches)
        let hidpi = isHiDPI ? " HiDPI" : ""
        let vrr = isVRR ? " VRR" : ""
        return "\(width)x\(height) @ \(refreshRate)Hz\(hidpi)\(vrr) (\(Int(ppi)) PPI)"
    }
}

// MARK: - Display Info

/// Represents a connected display
class DisplayInfo: ObservableObject, Identifiable {
    let id: CGDirectDisplayID
    let vendorID: UInt32
    let productID: UInt32

    @Published var name: String
    @Published var isMain: Bool
    @Published var isBuiltIn: Bool
    @Published var isVirtual: Bool
    @Published var currentModeID: Int32
    @Published var modes: [DisplayMode]
    @Published var bounds: CGRect
    @Published var hasOverride: Bool
    @Published var supportsHDR: Bool
    @Published var hdrEnabled: Bool
    @Published var rotation: Int = 0          // 0, 90, 180, 270
    @Published var screenDiagonalInches: Double = 0  // estimated or user-set

    var hiDPIModes: [DisplayMode] { modes.filter(\.isHiDPI) }
    var standardModes: [DisplayMode] { modes.filter { !$0.isHiDPI } }
    var currentMode: DisplayMode? { modes.first { $0.id == currentModeID } }

    var displayIDHex: String { "0x\(String(id, radix: 16))" }
    var settingsKey: String { "\(vendorID)-\(productID)" }

    /// Estimated physical PPI based on native resolution and screen diagonal
    var nativePPI: Double {
        guard screenDiagonalInches > 0 else { return 0 }
        let diag = sqrt(Double(bounds.width * bounds.width + bounds.height * bounds.height))
        return diag / screenDiagonalInches
    }

    /// Estimate screen diagonal from EDID physical size (cm) or known panel info
    func estimateScreenDiagonal(widthCm: Int, heightCm: Int) {
        guard widthCm > 0 || heightCm > 0 else { return }
        let diag = sqrt(Double(widthCm * widthCm + heightCm * heightCm))
        screenDiagonalInches = diag / 2.54
    }

    /// Returns recommended HiDPI resolutions sorted by suitability for this display.
    /// Each entry includes the mode and effective PPI.
    var recommendedHiDPIModes: [(mode: DisplayMode, ppi: Double, tag: String)] {
        guard screenDiagonalInches > 0 else {
            return hiDPIModes.map { ($0, 0, "") }
        }

        return hiDPIModes.compactMap { mode -> (DisplayMode, Double, String)? in
            let ppi = mode.effectivePPI(screenDiagonalInches: screenDiagonalInches)
            let tag: String
            if ppi >= 100 && ppi <= 115 {
                tag = "Recommended"
            } else if ppi >= 85 && ppi < 100 {
                tag = "Large"
            } else if ppi >= 115 && ppi <= 130 {
                tag = "More Space"
            } else if ppi < 85 {
                tag = "Very Large"
            } else {
                tag = "Dense"
            }
            return (mode, ppi, tag)
        }.sorted { $0.1 < $1.1 }
    }

    init(
        id: CGDirectDisplayID,
        vendorID: UInt32 = 0,
        productID: UInt32 = 0,
        name: String = "Unknown",
        isMain: Bool = false,
        isBuiltIn: Bool = false,
        isVirtual: Bool = false,
        currentModeID: Int32 = 0,
        modes: [DisplayMode] = [],
        bounds: CGRect = .zero,
        hasOverride: Bool = false,
        supportsHDR: Bool = false,
        hdrEnabled: Bool = false
    ) {
        self.id = id
        self.vendorID = vendorID
        self.productID = productID
        self.name = name
        self.isMain = isMain
        self.isBuiltIn = isBuiltIn
        self.isVirtual = isVirtual
        self.currentModeID = currentModeID
        self.modes = modes
        self.bounds = bounds
        self.hasOverride = hasOverride
        self.supportsHDR = supportsHDR
        self.hdrEnabled = hdrEnabled
    }
}

// MARK: - Override Config

/// Configuration for generating a Display Override plist
struct OverrideConfig {
    var vendorID: UInt32
    var productID: UInt32
    var displayName: String?
    var targetPPMM: Float = 10.0
    var resolutions: [(width: Int, height: Int)] = []
    var flexibleScaling: Bool = false
    var nativeWidth: Int?
    var nativeHeight: Int?
}

// MARK: - App Settings

/// Persisted per-display settings
struct DisplaySettings: Codable {
    var displayID: String       // vendorID-productID as key
    var preferredModeID: Int32?
    var overrideInstalled: Bool = false
    var flexibleScaling: Bool = false
    var customResolutions: [Resolution] = []
    var autoApplyOnConnect: Bool = true
    var favoriteResolutions: [Int32] = []
    var screenDiagonalInches: Double?  // user-provided or EDID-estimated

    struct Resolution: Codable, Hashable {
        var width: Int
        var height: Int
    }
}

// MARK: - Virtual Display Config

/// Configuration for a persistent virtual display (auto-recreated on app start)
struct VirtualDisplayConfig: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var width: Int
    var height: Int
    var hiDPI: Bool = true
    var refreshRate: Int = 60
}

// MARK: - Known Display Sizes

/// Common display panel sizes for auto-detection by resolution
enum KnownDisplaySize {
    /// Estimate screen diagonal inches from native resolution and vendor/product hints
    static func estimateDiagonal(nativeWidth: Int, nativeHeight: Int, vendorID: UInt32) -> Double? {
        // Common 4K panels
        if nativeWidth == 3840 && nativeHeight == 2160 {
            return 27.0  // Most common 4K monitor size
        }
        // 5K panels (Apple Studio Display, LG UltraFine 5K)
        if nativeWidth == 5120 && nativeHeight == 2880 {
            return 27.0
        }
        // 1440p panels
        if nativeWidth == 2560 && nativeHeight == 1440 {
            return 27.0
        }
        // Ultrawide 3440x1440
        if nativeWidth == 3440 && nativeHeight == 1440 {
            return 34.0
        }
        // Ultrawide 5120x2160
        if nativeWidth == 5120 && nativeHeight == 2160 {
            return 34.0
        }
        // 1080p
        if nativeWidth == 1920 && nativeHeight == 1080 {
            return 24.0
        }
        return nil
    }
}
