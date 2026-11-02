//
//  AppIconTests.swift
//  RiffMemoTests
//

import Foundation
import ImageIO
import Testing
import UIKit

/// WAS-111: App Store Connect rejects a build whose app icon is missing or has an
/// alpha channel. That only shows up at upload time, so these tests catch it locally:
///
/// 1. Each AppIcon slot (default, dark, tinted) names a 1024×1024 PNG that exists.
/// 2. The default icon has no alpha channel.
/// 3. The built app points at the icon and opens on the dark `Ground` launch color.
///
/// The icon PNGs come from `docs/design/app-icon/render.sh`. Edit the SVGs there, not the PNGs.
struct AppIconTests {

    // MARK: - Source asset catalog

    @Test func everyIconSlotNamesA1024PNGThatExists() throws {
        let slots = try Self.iconSlots()
        #expect(slots.count == 3, "Expected default, dark and tinted slots, found \(slots.count)")

        for slot in slots {
            let filename = try #require(
                slot["filename"] as? String,
                "AppIcon slot \(Self.appearance(of: slot)) has no image. Run docs/design/app-icon/render.sh."
            )
            let url = Self.iconSetDirectory.appendingPathComponent(filename)
            let properties = try Self.imageProperties(at: url)

            let width = properties[kCGImagePropertyPixelWidth] as? Int
            let height = properties[kCGImagePropertyPixelHeight] as? Int
            #expect(width == 1024 && height == 1024, "\(filename) must be 1024×1024, is \(width ?? 0)×\(height ?? 0)")
        }
    }

    @Test func coversDefaultDarkAndTintedAppearances() throws {
        let appearances = Set(try Self.iconSlots().map(Self.appearance(of:)))
        #expect(appearances == ["default", "dark", "tinted"])
    }

    @Test func defaultIconHasNoAlphaChannel() throws {
        let slot = try #require(
            try Self.iconSlots().first { Self.appearance(of: $0) == "default" },
            "No default AppIcon slot"
        )
        let filename = try #require(slot["filename"] as? String, "Default AppIcon slot has no image")
        let properties = try Self.imageProperties(at: Self.iconSetDirectory.appendingPathComponent(filename))

        let hasAlpha = properties[kCGImagePropertyHasAlpha] as? Bool ?? false
        #expect(!hasAlpha, "\(filename) has an alpha channel. App Store Connect rejects it.")
    }

    // MARK: - Built app

    /// In app-hosted unit tests `Bundle.main` is the host app (RiffMemo.app).
    @Test func builtAppUsesTheAppIcon() throws {
        let icons = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")
    }

    @Test func launchScreenUsesTheGroundColor() throws {
        let launch = try #require(
            Bundle.main.infoDictionary?["UILaunchScreen"] as? [String: Any],
            "UILaunchScreen is missing. It comes from RiffMemo/RiffMemo-Info.plist."
        )
        let colorName = try #require(launch["UIColorName"] as? String)
        #expect(colorName == "Ground")
        #expect(UIColor(named: colorName, in: .main, compatibleWith: nil) != nil, "Color \(colorName) is not in the asset catalog")
    }

    // MARK: - Helpers

    /// `.../RiffMemo/RiffMemoTests/AppIconTests.swift` → `.../AppIcon.appiconset`.
    private static let iconSetDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("RiffMemo/App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

    private static func iconSlots() throws -> [[String: Any]] {
        let data = try Data(contentsOf: iconSetDirectory.appendingPathComponent("Contents.json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["images"] as? [[String: Any]], "AppIcon Contents.json has no images array")
    }

    /// "default" when the slot has no luminosity appearance, else its value ("dark", "tinted").
    private static func appearance(of slot: [String: Any]) -> String {
        let appearances = slot["appearances"] as? [[String: String]] ?? []
        return appearances.first { $0["appearance"] == "luminosity" }?["value"] ?? "default"
    }

    private static func imageProperties(at url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "Cannot read \(url.lastPathComponent)")
        return try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            "No image properties for \(url.lastPathComponent)"
        )
    }
}
