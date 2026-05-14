import Foundation
import Testing
import WorkspaceState

@Suite("v1 → v2 spaces.json migration")
struct MigrationTests {

    /// Round-trip a representative v1 fixture and verify the v2 shape.
    @Test func v1_to_v2_basic_shape() throws {
        let v1 = """
        {
          "version": 1,
          "palette": "catppuccin-mocha",
          "_doc_note": "edit me",
          "spaces": {
            "1": { "name": "stream", "color": "#cba6f7", "icon": "\u{F0A0}" },
            "2": { "name": "hub",    "color": "#f5c2e7", "icon": "" }
          }
        }
        """
        let result = try Migration.migrate(jsonData: Data(v1.utf8))
        #expect(!result.alreadyV2)
        #expect(result.slotsTouched > 0)

        // The output must parse as JSON and be version 2.
        let outData = Data(result.outputJSON.utf8)
        let root = try #require(
            try JSONSerialization.jsonObject(with: outData) as? [String: Any]
        )
        #expect(root["version"]   as? Int    == 2)
        #expect(root["_doc_note"] as? String == "edit me")  // unknown key preserved

        let spaces = try #require(root["spaces"] as? [String: Any])
        let slot1  = try #require(spaces["1"]   as? [String: Any])
        #expect(slot1["name"]               as? String == "stream")
        #expect(slot1["color"]              as? String == "#cba6f7")
        #expect(slot1["stableLogicalLabel"] as? String == "stream")
        #expect(slot1["icon"] == nil, "legacy icon field should be removed")

        let spec = slot1["iconSpec"] as? [String: Any] ?? [:]
        #expect(spec["kind"]           as? String == "nerdFont")
        #expect(spec["codepoint"]      as? String == "\\uf0a0")
        #expect(spec["fontFamily"]     as? String == "JetBrainsMono Nerd Font")
        #expect(spec["userOverridden"] as? Bool   == false)
    }

    /// Empty icon string → kind=none, fallbacks attached for downstream use.
    @Test func empty_icon_yields_kind_none() throws {
        let v1 = """
        { "version": 1, "spaces": { "1": { "name": "stream", "color": "#000000", "icon": "" } } }
        """
        let result = try Migration.migrate(jsonData: Data(v1.utf8))
        let outData = Data(result.outputJSON.utf8)
        let root   = try #require(try JSONSerialization.jsonObject(with: outData) as? [String: Any])
        let spaces = try #require(root["spaces"] as? [String: Any])
        let slot1  = try #require(spaces["1"]   as? [String: Any])
        let spec   = try #require(slot1["iconSpec"] as? [String: Any])
        #expect(spec["kind"]             as? String == "none")
        #expect(spec["fallbackSfSymbol"] as? String == "play.fill")
    }

    /// Idempotent: running migration on a v2 file produces no further touches.
    @Test func idempotent_on_v2() throws {
        let v1 = """
        { "version": 1, "spaces": { "1": { "name": "stream", "color": "#000000", "icon": "" } } }
        """
        let first  = try Migration.migrate(jsonData: Data(v1.utf8))
        let second = try Migration.migrate(jsonData: Data(first.outputJSON.utf8))
        #expect(second.alreadyV2)
        #expect(second.slotsTouched == 0)
    }

    /// Numerical key ordering: "10" must come after "9", not after "1".
    @Test func spaces_ordered_numerically() throws {
        var spaces: [String: Any] = [:]
        for i in 1...12 {
            spaces["\(i)"] = ["name": "ws\(i)", "color": "#000000", "icon": ""]
        }
        let root: [String: Any] = ["version": 1, "spaces": spaces]
        let data = try JSONSerialization.data(withJSONObject: root)
        let result = try Migration.migrate(jsonData: data)

        // Find the order in which the keys appear in the rendered output.
        // Numerical ordering means "10","11","12" appear AFTER "9".
        let nine    = try #require(result.outputJSON.range(of: "\"9\":"))
        let ten     = try #require(result.outputJSON.range(of: "\"10\":"))
        let twelve  = try #require(result.outputJSON.range(of: "\"12\":"))
        #expect(nine.lowerBound < ten.lowerBound)
        #expect(ten.lowerBound  < twelve.lowerBound)
    }
}

@Suite("Decoder preserves user-overridden flag")
struct RenamePreservesOverrideTests {
    /// The store decoder must preserve `userOverridden=true` across a load /
    /// re-save cycle — that's the invariant the postmortem demands. The
    /// workspace CLI's rename flow only touches `name`; `iconSpec` stays put.
    @Test func decoder_preserves_user_overridden_flag() throws {
        let v2 = """
        {
          "version": 2,
          "spaces": {
            "1": {
              "name": "custom",
              "color": "#abcdef",
              "stableLogicalLabel": "stream",
              "iconSpec": {
                "kind": "sfSymbol",
                "symbolName": "star.fill",
                "userOverridden": true
              }
            }
          }
        }
        """
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ws-spaces-\(UUID().uuidString).json")
        try Data(v2.utf8).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let store  = WorkspaceStateStore(configURL: tmp)
        let config = try store.load()
        let slot   = try #require(config.slots.first)
        #expect(slot.name                == "custom")
        #expect(slot.stableLogicalLabel  == "stream")
        #expect(slot.iconSpec.userOverridden)
        #expect(slot.iconSpec.kind       == .sfSymbol)
        #expect(slot.iconSpec.symbolName == "star.fill")

        // Re-encode and verify the override survives.
        let encoded = store.encodeJSON(config)
        #expect(encoded.contains("\"userOverridden\": true"))
        #expect(encoded.contains("\"symbolName\": \"star.fill\""))
    }
}
