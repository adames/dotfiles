import AdaptersAppKit
import DisplayTopology
import Foundation
import LayoutPolicy

/// The on-disk payload of `~/.cache/workspace/topology.json` — combines the
/// raw display snapshot, the derived layout policy set, and the accessibility
/// state into one document. Consumers (SketchyBar plugins, ensure-spaces,
/// the recenter shell script) read either this JSON or the flattened
/// `layout.env` companion.
struct EnrichedTopology: Codable {
    let topology: TopologySnapshot
    let policies: LayoutPolicySet
    let accessibility: AccessibilityState
}

extension AccessibilityState: Codable {
    enum CodingKeys: String, CodingKey {
        case reduceMotion, increaseContrast
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            reduceMotion:     try c.decode(Bool.self, forKey: .reduceMotion),
            increaseContrast: try c.decode(Bool.self, forKey: .increaseContrast)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reduceMotion,     forKey: .reduceMotion)
        try c.encode(increaseContrast, forKey: .increaseContrast)
    }
}
