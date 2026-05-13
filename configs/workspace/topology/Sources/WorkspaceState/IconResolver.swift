import Foundation

public enum IconTargetSurface: Sendable {
    /// Native AppKit / SwiftUI surfaces — can render SF Symbols by name.
    case nativeAppKit
    /// Font-driven surfaces — SketchyBar, tmux, terminal pickers. Render
    /// Nerd Font glyphs by codepoint; no SF Symbol support.
    case fontDriven
}

public struct ResolvedIcon: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case sfSymbol
        case glyph
        case text
        case empty
    }

    public let kind: Kind
    public let value: String

    public static let empty = ResolvedIcon(kind: .empty, value: "")
}

public enum IconResolver {
    /// Apply the documented fallback chain:
    ///   1. userOverridden (if it resolves on this surface)
    ///   2. SF Symbol on native surfaces (kind == .sfSymbol with valid name)
    ///   3. Nerd Font codepoint on font-driven surfaces (kind == .nerdFont, font available)
    ///   4. fallbackSfSymbol on native surfaces
    ///   5. fallbackText
    ///   6. .empty
    public static func resolve(
        spec: IconSpec,
        availableFonts: Set<String>,
        targetSurface: IconTargetSurface,
        sfSymbolExists: (String) -> Bool = { _ in true }
    ) -> ResolvedIcon {
        // 1. User override has first dibs — but it only wins if the explicit kind
        //    actually resolves on this surface.
        if spec.userOverridden {
            if let r = directResolve(spec: spec,
                                     availableFonts: availableFonts,
                                     targetSurface: targetSurface,
                                     sfSymbolExists: sfSymbolExists) {
                return r
            }
            // Fall through to the rest of the chain so an override pointing at an
            // unavailable surface still degrades gracefully.
        }

        // 2 + 3: the spec's own kind, if it resolves.
        if !spec.userOverridden,
           let r = directResolve(spec: spec,
                                 availableFonts: availableFonts,
                                 targetSurface: targetSurface,
                                 sfSymbolExists: sfSymbolExists) {
            return r
        }

        // 4. fallbackSfSymbol on native surfaces.
        if targetSurface == .nativeAppKit,
           let name = spec.fallbackSfSymbol,
           sfSymbolExists(name) {
            return ResolvedIcon(kind: .sfSymbol, value: name)
        }

        // 5. fallbackText.
        if let text = spec.fallbackText, !text.isEmpty {
            return ResolvedIcon(kind: .text, value: text)
        }

        return .empty
    }

    static func directResolve(
        spec: IconSpec,
        availableFonts: Set<String>,
        targetSurface: IconTargetSurface,
        sfSymbolExists: (String) -> Bool
    ) -> ResolvedIcon? {
        switch spec.kind {
        case .sfSymbol:
            guard targetSurface == .nativeAppKit,
                  let name = spec.symbolName,
                  sfSymbolExists(name) else { return nil }
            return ResolvedIcon(kind: .sfSymbol, value: name)

        case .nerdFont:
            guard targetSurface == .fontDriven,
                  let escaped = spec.codepoint,
                  let scalar  = IconCodepoint.decode(escaped) else { return nil }
            // Font availability check: if a fontFamily is named, require it.
            if let family = spec.fontFamily, !availableFonts.contains(family) {
                return nil
            }
            return ResolvedIcon(kind: .glyph, value: String(scalar))

        case .text:
            if let text = spec.fallbackText, !text.isEmpty {
                return ResolvedIcon(kind: .text, value: text)
            }
            if let scalar = spec.codepoint.flatMap(IconCodepoint.decode) {
                return ResolvedIcon(kind: .text, value: String(scalar))
            }
            return nil

        case .none:
            return .empty
        }
    }
}
