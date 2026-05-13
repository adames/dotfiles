import WorkspaceState
import XCTest

final class IconCodepointTests: XCTestCase {
    func test_decode_roundtrip_bmp() {
        let escaped = "\\uf0b1"
        let scalar = IconCodepoint.decode(escaped)
        XCTAssertNotNil(scalar)
        XCTAssertEqual(scalar?.value, 0xF0B1)
        XCTAssertEqual(IconCodepoint.encode(scalar!), "\\uf0b1")
    }

    func test_decode_supplementary_pua() {
        let escaped = "\\u{F0001}"
        let scalar = IconCodepoint.decode(escaped)
        XCTAssertNotNil(scalar)
        XCTAssertEqual(scalar?.value, 0xF0001)
        XCTAssertTrue(IconCodepoint.isPrivateUseArea(scalar!))
    }

    func test_decode_malformed_returns_nil() {
        XCTAssertNil(IconCodepoint.decode(""))
        XCTAssertNil(IconCodepoint.decode("f0b1"))
        XCTAssertNil(IconCodepoint.decode("\\unotaherx"))
        XCTAssertNil(IconCodepoint.decode("\\u{}"))
    }
}

final class IconResolverTests: XCTestCase {
    let fontsWithNerd: Set<String> = ["JetBrainsMono Nerd Font"]
    let fontsWithoutNerd: Set<String> = ["Helvetica"]

    func sfExists(_ name: String) -> Bool { return name != "missing.symbol" }

    func test_override_wins_when_kind_resolves_on_surface() {
        let spec = IconSpec(
            kind: .sfSymbol,
            symbolName: "star.fill",
            fallbackText: "WK",
            userOverridden: true
        )
        let r = IconResolver.resolve(
            spec: spec,
            availableFonts: fontsWithoutNerd,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        XCTAssertEqual(r.kind, .sfSymbol)
        XCTAssertEqual(r.value, "star.fill")
    }

    func test_native_prefers_sf_symbol() {
        let spec = IconSpec(
            kind: .sfSymbol,
            symbolName: "play.fill",
            fallbackText: "ST"
        )
        let r = IconResolver.resolve(
            spec: spec,
            availableFonts: fontsWithNerd,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        XCTAssertEqual(r.kind, .sfSymbol)
        XCTAssertEqual(r.value, "play.fill")
    }

    func test_font_driven_renders_nerd_glyph_when_font_present() {
        let spec = IconSpec(
            kind: .nerdFont,
            codepoint: "\\uf0b1",
            fontFamily: "JetBrainsMono Nerd Font",
            fallbackText: "WK"
        )
        let r = IconResolver.resolve(
            spec: spec,
            availableFonts: fontsWithNerd,
            targetSurface: .fontDriven,
            sfSymbolExists: sfExists(_:)
        )
        XCTAssertEqual(r.kind, .glyph)
        let expected = String(Unicode.Scalar(0xF0B1)!)
        XCTAssertEqual(r.value, expected)
    }

    func test_missing_font_falls_through_to_fallback_text() {
        let spec = IconSpec(
            kind: .nerdFont,
            codepoint: "\\uf0b1",
            fontFamily: "JetBrainsMono Nerd Font",
            fallbackSfSymbol: "play.fill",
            fallbackText: "ST"
        )
        let r = IconResolver.resolve(
            spec: spec,
            availableFonts: fontsWithoutNerd,
            targetSurface: .fontDriven,
            sfSymbolExists: sfExists(_:)
        )
        // Font missing → direct resolve fails → fallbackSfSymbol skipped (font-driven
        // surface can't render SF Symbols) → fallbackText.
        XCTAssertEqual(r.kind, .text)
        XCTAssertEqual(r.value, "ST")
    }

    func test_invalid_codepoint_falls_back_through_chain() {
        let spec = IconSpec(
            kind: .nerdFont,
            codepoint: "\\unothex",  // malformed
            fontFamily: "JetBrainsMono Nerd Font",
            fallbackSfSymbol: "play.fill",
            fallbackText: "ST"
        )
        let r = IconResolver.resolve(
            spec: spec,
            availableFonts: fontsWithNerd,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        // Native surface: invalid codepoint → fallback SF symbol resolves.
        XCTAssertEqual(r.kind, .sfSymbol)
        XCTAssertEqual(r.value, "play.fill")
    }

    func test_none_kind_returns_empty() {
        let spec = IconSpec(kind: .none)
        let r = IconResolver.resolve(
            spec: spec,
            availableFonts: fontsWithNerd,
            targetSurface: .nativeAppKit,
            sfSymbolExists: sfExists(_:)
        )
        XCTAssertEqual(r.kind, .empty)
    }
}
