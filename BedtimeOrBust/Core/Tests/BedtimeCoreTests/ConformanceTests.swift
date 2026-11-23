import XCTest
@testable import BedtimeCore

/// Replays traces recorded from the JavaScript reference engine
/// (tools/golden.mjs). Passing proves the Swift engine implements the same
/// rules, RNG and content semantics, step for step.
final class ConformanceTests: XCTestCase {
    struct Golden: Decodable {
        struct RNGSamples: Decodable {
            let seed0: [Double]
            let seedMax: [Double]
        }

        struct ClockCase: Decodable {
            let minutes: Int
            let text: String

            init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                minutes = try c.decode(Int.self)
                text = try c.decode(String.self)
            }
        }

        struct Step: Decodable {
            let e: String
            let n: Int
            let c: Int
            let o: Int
            let clock: Int
            let m: [Int]
        }

        struct Snapshot: Decodable {
            let clock: Int
            let meters: [String: Int]
            let flags: [String]
            let counters: [String: Int]
            let modifierId: String
            let step: Int
            let endingId: String?
        }

        struct Trace: Decodable {
            let seed: UInt32
            let modifierId: String
            let steps: [Step]
            let finalState: Snapshot

            enum CodingKeys: String, CodingKey {
                case seed, modifierId, steps
                case finalState = "final"
            }
        }

        let meters: [String]
        let rng: RNGSamples
        let clockFormat: [ClockCase]
        let traces: [Trace]
    }

    private func loadGolden() throws -> Golden {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "golden", withExtension: "json", subdirectory: "Fixtures"),
            "Fixtures/golden.json missing from the test bundle"
        )
        return try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
    }

    /// The same RNG-free policy tools/golden.mjs uses.
    private func policyIndex(seed: UInt32, step: Int, count: Int) -> Int {
        (Int(seed) + step * 31) % count
    }

    func testMeterOrderMatchesReference() throws {
        XCTAssertEqual(try loadGolden().meters, Meter.allCases.map(\.rawValue))
    }

    func testRandomNumberGeneratorMatchesReference() throws {
        let golden = try loadGolden()
        var zero = SeededRandom(seed: 0)
        for expected in golden.rng.seed0 { XCTAssertEqual(zero.next(), expected, accuracy: 1e-15) }
        var top = SeededRandom(seed: .max)
        for expected in golden.rng.seedMax { XCTAssertEqual(top.next(), expected, accuracy: 1e-15) }
    }

    func testClockFormatMatchesReference() throws {
        for testCase in try loadGolden().clockFormat {
            XCTAssertEqual(Clock.format(testCase.minutes), testCase.text, "minutes \(testCase.minutes)")
        }
    }

    func testGoldenTracesReplayIdentically() throws {
        let content = try GameContent.bundled()
        let golden = try loadGolden()
        XCTAssertGreaterThanOrEqual(golden.traces.count, 10)
        for trace in golden.traces {
            try replay(trace, content: content)
        }
    }

    private func replay(_ trace: Golden.Trace, content: GameContent) throws {
        var engine = GameEngine(content: content, seed: trace.seed)
        XCTAssertEqual(engine.state.modifierID, trace.modifierId, "seed \(trace.seed): modifier")

        for (i, expected) in trace.steps.enumerated() {
            let where_ = "seed \(trace.seed) step \(i)"
            guard let event = engine.currentEvent else {
                return XCTFail("\(where_): Swift engine ended early")
            }
            guard event.id == expected.e else {
                return XCTFail("\(where_): event \(event.id), reference \(expected.e)")
            }
            let count = engine.visibleChoices().count
            XCTAssertEqual(count, expected.n, "\(where_): visible choice count")
            let pick = policyIndex(seed: trace.seed, step: engine.state.step, count: count)
            XCTAssertEqual(pick, expected.c, "\(where_): policy index")

            let result = try engine.choose(pick)
            XCTAssertEqual(result.outcomeIndex, expected.o, "\(where_): outcome")
            XCTAssertEqual(engine.state.clock, expected.clock, "\(where_): clock")
            guard engine.state.meters.values == expected.m else {
                return XCTFail("\(where_): meters \(engine.state.meters.values), reference \(expected.m)")
            }
        }

        let snap = trace.finalState
        XCTAssertTrue(engine.isOver, "seed \(trace.seed): reference ended, Swift did not")
        XCTAssertEqual(engine.state.endingID, snap.endingId, "seed \(trace.seed): ending")
        XCTAssertEqual(engine.state.step, snap.step, "seed \(trace.seed): steps")
        XCTAssertEqual(engine.state.clock, snap.clock, "seed \(trace.seed): final clock")
        XCTAssertEqual(engine.state.flags, Set(snap.flags), "seed \(trace.seed): flags")
        XCTAssertEqual(engine.state.counters, snap.counters, "seed \(trace.seed): counters")
        for meter in Meter.allCases {
            XCTAssertEqual(engine.state.meters[meter], snap.meters[meter.rawValue], "seed \(trace.seed): \(meter)")
        }
    }
}
