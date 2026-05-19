import Foundation

public enum IconTargetSurface: Sendable {
    /// Native AppKit / SwiftUI surfaces — can render SF Symbols by name.
    case nativeAppKit
    /// Text-based surfaces — simplified rendering, no custom fonts.
    case textBased
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
    ///   3. fallbackSfSymbol on native surfaces
    ///   4. fallbackText
    ///   5. .empty
    public static func resolve(
        spec: IconSpec,
        availableFonts: Set<String>,
        targetSurface: IconTargetSurface,
        sfSymbolExists: (String) -> Bool = { _ in true }
    ) -> ResolvedIcon {
        // 1. User override has first dibs
        if spec.userOverridden,
           let r = directResolve(spec: spec,
                                 targetSurface: targetSurface,
                                 sfSymbolExists: sfSymbolExists) {
            return r
        }

        // 2: the spec's own kind, if it resolves.
        if !spec.userOverridden,
           let r = directResolve(spec: spec,
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
        targetSurface: IconTargetSurface,
        sfSymbolExists: (String) -> Bool
    ) -> ResolvedIcon? {
        switch spec.kind {
        case .sfSymbol:
            guard targetSurface == .nativeAppKit,
                  let name = spec.symbolName,
                  sfSymbolExists(name) else { return nil }
            return ResolvedIcon(kind: .sfSymbol, value: name)

        case .text:
            if let text = spec.fallbackText, !text.isEmpty {
                return ResolvedIcon(kind: .text, value: text)
            }
            return nil

        case .none, .nerdFont:
            // nerdFont is deprecated, treat as empty
            return nil
        }
    }
}
