import WorkspaceState
import XCTest

final class MigrationTests: XCTestCase {

    /// Round-trip a representative v1 fixture and verify the v2 shape.
    func test_v1_to_v2_basic_shape() throws {
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
        XCTAssertFalse(result.alreadyV2)
        XCTAssertGreaterThan(result.slotsTouched, 0)

        // The output must parse as JSON and be version 2.
        let outData = Data(result.outputJSON.utf8)
        guard let root = try JSONSerialization.jsonObject(with: outData) as? [String: Any] else {
            return XCTFail("output is not a JSON object")
        }
        XCTAssertEqual(root["version"] as? Int, 2)
        XCTAssertEqual(root["_doc_note"] as? String, "edit me")  // unknown key preserved

        guard let spaces = root["spaces"] as? [String: Any],
              let slot1 = spaces["1"] as? [String: Any] else {
            return XCTFail("missing spaces.1")
        }
        XCTAssertEqual(slot1["name"]               as? String, "stream")
        XCTAssertEqual(slot1["color"]              as? String, "#cba6f7")
        XCTAssertEqual(slot1["stableLogicalLabel"] as? String, "stream")
        XCTAssertNil(slot1["icon"], "legacy icon field should be removed")

        let spec = slot1["iconSpec"] as? [String: Any] ?? [:]
        XCTAssertEqual(spec["kind"]       as? String, "nerdFont")
        XCTAssertEqual(spec["codepoint"]  as? String, "\\uf0a0")
        XCTAssertEqual(spec["fontFamily"] as? String, "JetBrainsMono Nerd Font")
        XCTAssertEqual(spec["userOverridden"] as? Bool, false)
    }

    /// Empty icon string → kind=none, fallbacks attached for downstream use.
    func test_empty_icon_yields_kind_none() throws {
        let v1 = """
        { "version": 1, "spaces": { "1": { "name": "stream", "color": "#000000", "icon": "" } } }
        """
        let result = try Migration.migrate(jsonData: Data(v1.utf8))
        let outData = Data(result.outputJSON.utf8)
        guard
            let root = try JSONSerialization.jsonObject(with: outData) as? [String: Any],
            let spaces = root["spaces"] as? [String: Any],
            let slot1 = spaces["1"] as? [String: Any],
            let spec = slot1["iconSpec"] as? [String: Any]
        else { return XCTFail() }
        XCTAssertEqual(spec["kind"] as? String, "none")
        XCTAssertEqual(spec["fallbackSfSymbol"] as? String, "play.fill")
    }

    /// Idempotent: running migration on a v2 file produces no further touches.
    func test_idempotent_on_v2() throws {
        let v1 = """
        { "version": 1, "spaces": { "1": { "name": "stream", "color": "#000000", "icon": "" } } }
        """
        let first  = try Migration.migrate(jsonData: Data(v1.utf8))
        let second = try Migration.migrate(jsonData: Data(first.outputJSON.utf8))
        XCTAssertTrue(second.alreadyV2)
        XCTAssertEqual(second.slotsTouched, 0)
    }

    /// Numerical key ordering: "10" must come after "9", not after "1".
    func test_spaces_ordered_numerically() throws {
        var spaces: [String: Any] = [:]
        for i in 1...12 {
            spaces["\(i)"] = ["name": "ws\(i)", "color": "#000000", "icon": ""]
        }
        let root: [String: Any] = ["version": 1, "spaces": spaces]
        let data = try JSONSerialization.data(withJSONObject: root)
        let result = try Migration.migrate(jsonData: data)

        // Find the order in which the keys appear in the rendered output. The
        // numerical ordering means "10","11","12" appear AFTER "9".
        let nine    = result.outputJSON.range(of: "\"9\":")
        let ten     = result.outputJSON.range(of: "\"10\":")
        let twelve  = result.outputJSON.range(of: "\"12\":")
        XCTAssertNotNil(nine);   XCTAssertNotNil(ten);   XCTAssertNotNil(twelve)
        XCTAssertLessThan(nine!.lowerBound,   ten!.lowerBound)
        XCTAssertLessThan(ten!.lowerBound,    twelve!.lowerBound)
    }
}

final class RenamePreservesOverrideTests: XCTestCase {
    /// The store decoder must preserve `userOverridden=true` across a load /
    /// re-save cycle — that's the invariant the postmortem demands. The
    /// workspace CLI's rename flow only touches `name`; `iconSpec` stays put.
    func test_decoder_preserves_user_overridden_flag() throws {
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

        let store = WorkspaceStateStore(configURL: tmp)
        let config = try store.load()
        let slot = try XCTUnwrap(config.slots.first)
        XCTAssertEqual(slot.name, "custom")
        XCTAssertEqual(slot.stableLogicalLabel, "stream")
        XCTAssertTrue(slot.iconSpec.userOverridden)
        XCTAssertEqual(slot.iconSpec.kind, .sfSymbol)
        XCTAssertEqual(slot.iconSpec.symbolName, "star.fill")

        // Re-encode and verify the override survives.
        let encoded = store.encodeJSON(config)
        XCTAssertTrue(encoded.contains("\"userOverridden\": true"))
        XCTAssertTrue(encoded.contains("\"symbolName\": \"star.fill\""))
    }
}
