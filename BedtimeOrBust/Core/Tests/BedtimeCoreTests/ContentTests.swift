import XCTest
@testable import BedtimeCore

final class ContentTests: XCTestCase {
    func testBundledContentLoads() throws {
        let content = try GameContent.bundled()
        XCTAssertGreaterThan(content.events.count, 20)
        XCTAssertNotNil(content.filler)
        XCTAssertTrue(content.events.contains { $0.isFinal })
        for meter in Meter.allCases { XCTAssertFalse(content.name(of: meter).isEmpty) }
        XCTAssertFalse(content.counters.isEmpty)
    }

    func testDeclaredCountersCoverEveryCounterUsed() throws {
        let content = try GameContent.bundled()
        let declared = Set(content.counters.map(\.id))
        for event in content.events {
            for choice in event.choices {
                for outcome in choice.outcomes {
                    for key in outcome.counters.keys {
                        XCTAssertTrue(declared.contains(key), "\(event.id) uses undeclared counter \(key)")
                    }
                }
            }
        }
    }

    func testUnknownMeterIsRejected() {
        let json = #"{ "text": "x", "effects": { "patience": 5 } }"#
        XCTAssertThrowsError(try JSONDecoder().decode(Outcome.self, from: Data(json.utf8)))
    }

    func testDefaultsApplyWhenFieldsAreOmitted() throws {
        let json = #"{ "id": "e", "title": "T", "text": "X", "window": [360, 400], "choices": [ { "label": "L", "duration": 5, "outcomes": [ { "text": "O" } ] } ] }"#
        let event = try JSONDecoder().decode(GameEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.weight, 1)
        XCTAssertEqual(event.priority, 0)
        XCTAssertFalse(event.repeatable)
        XCTAssertFalse(event.isFiller)
        XCTAssertFalse(event.isFinal)
        XCTAssertEqual(event.window, 360...400)
        XCTAssertEqual(event.choices[0].outcomes[0].weight, 1)
        XCTAssertTrue(event.choices[0].outcomes[0].effects.isEmpty)
    }

    func testBackwardsWindowIsRejected() {
        let json = #"{ "id": "e", "title": "T", "text": "X", "window": [400, 360], "choices": [] }"#
        XCTAssertThrowsError(try JSONDecoder().decode(GameEvent.self, from: Data(json.utf8)))
    }

    func testContentWithoutFillerIsRejected() throws {
        let bundled = try XCTUnwrap(GameContent.bundledURL)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: bundled)) as? [String: Any])
        var events = try XCTUnwrap(object["events"] as? [[String: Any]])
        events.removeAll { ($0["filler"] as? Bool) == true }
        object["events"] = events
        let broken = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try GameContent.load(from: broken)) { error in
            XCTAssertEqual(error as? ContentError, .invalid("needs exactly one filler event"))
        }
    }
}
