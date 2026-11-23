import XCTest
@testable import BedtimeCore

final class EngineTests: XCTestCase {
    private var content: GameContent!

    override func setUpWithError() throws {
        content = try GameContent.bundled()
    }

    /// Plays a whole day, picking choices with a separate seeded RNG.
    @discardableResult
    private func playDay(seed: UInt32, maxSteps: Int = 200) throws -> GameEngine {
        var engine = GameEngine(content: content, seed: seed)
        var picker = SeededRandom(seed: seed ^ 0x9E37_79B9)
        var steps = 0
        while !engine.isOver {
            steps += 1
            XCTAssertLessThan(steps, maxSteps, "seed \(seed): day never ended")
            if steps >= maxSteps { break }
            let count = engine.visibleChoices().count
            XCTAssertGreaterThan(count, 0, "seed \(seed): event \(engine.currentEvent?.id ?? "nil") has no visible choices")
            try engine.choose(Int(picker.next() * Double(count)))
        }
        return engine
    }

    func testKnownFirstValueOfMulberry32() {
        // Widely published first output of mulberry32 seeded with 0.
        var rng = SeededRandom(seed: 0)
        XCTAssertEqual(rng.next(), 0.26642920868471265, accuracy: 1e-15)
    }

    func testRandomValuesStayInUnitInterval() {
        var rng = SeededRandom(seed: 12345)
        for _ in 0..<10_000 {
            let v = rng.next()
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThan(v, 1)
        }
    }

    func testMetersClampOnEveryWrite() {
        var meters = Meters(sanity: 150, mood: -20, home: 50, rep: 50, sleepy: 0)
        XCTAssertEqual(meters.sanity, 100)
        XCTAssertEqual(meters.mood, 0)
        meters[.home] += 500
        meters[.rep] -= 500
        XCTAssertEqual(meters.home, 100)
        XCTAssertEqual(meters.rep, 0)
    }

    func testDayStartsAtWakeUpWithAModifier() {
        let engine = GameEngine(content: content, seed: 1)
        XCTAssertEqual(engine.state.clock, content.config.startClock)
        XCTAssertEqual(engine.currentEvent?.id, "wake")
        XCTAssertNotNil(engine.modifier)
        XCTAssertFalse(engine.isOver)
    }

    func testSameSeedAndChoicesGiveSameDay() throws {
        let a = try playDay(seed: 777)
        let b = try playDay(seed: 777)
        XCTAssertEqual(a.state, b.state)
    }

    func testSeedsProduceVariety() {
        let modifiers = Set((0..<60).map { GameEngine(content: content, seed: UInt32($0)).state.modifierID })
        XCTAssertGreaterThanOrEqual(modifiers.count, 5)
    }

    func testEveryDayTerminatesWithAKnownEnding() throws {
        for seed in UInt32(0)..<300 {
            let engine = try playDay(seed: seed &* 2_654_435_761)
            XCTAssertTrue(engine.isOver)
            let id = try XCTUnwrap(engine.state.endingID)
            XCTAssertNotNil(content.endings[id], "unknown ending \(id)")
            for meter in Meter.allCases {
                XCTAssertTrue(Meters.range.contains(engine.state.meters[meter]))
            }
        }
    }

    func testBedtimeIsForcedOnceTheClockPassesIt() throws {
        for seed in UInt32(0)..<100 {
            var engine = GameEngine(content: content, seed: seed)
            var picker = SeededRandom(seed: seed)
            while !engine.isOver {
                if engine.state.clock >= content.config.bedtimeClock, engine.state.meters.mood > 0 {
                    XCTAssertEqual(engine.currentEvent?.isFinal, true, "seed \(seed) at \(Clock.format(engine.state.clock))")
                }
                try engine.choose(Int(picker.next() * Double(engine.visibleChoices().count)))
            }
        }
    }

    func testInvalidChoiceThrowsAndChangesNothing() {
        var engine = GameEngine(content: content, seed: 3)
        let before = engine.state
        XCTAssertThrowsError(try engine.choose(99)) { error in
            XCTAssertEqual(error as? GameError, .invalidChoice(99))
        }
        XCTAssertEqual(engine.state, before)
    }

    func testChoosingAfterTheEndThrows() throws {
        var engine = try playDay(seed: 5)
        XCTAssertThrowsError(try engine.choose(0)) { error in
            XCTAssertEqual(error as? GameError, .gameOver)
        }
    }

    func testSaveAndRestoreContinuesIdentically() throws {
        var uninterrupted = GameEngine(content: content, seed: 2024)
        var interrupted = GameEngine(content: content, seed: 2024)
        var picker = SeededRandom(seed: 1)
        var picks: [Int] = []
        for _ in 0..<6 where !uninterrupted.isOver {
            let i = Int(picker.next() * Double(uninterrupted.visibleChoices().count))
            picks.append(i)
            try uninterrupted.choose(i)
            try interrupted.choose(i)
        }
        let saved = try JSONEncoder().encode(interrupted.state)
        var restored = GameEngine(content: content, restoring: try JSONDecoder().decode(GameState.self, from: saved))
        XCTAssertEqual(restored.state, uninterrupted.state)
        while !uninterrupted.isOver {
            let i = Int(picker.next() * Double(uninterrupted.visibleChoices().count))
            let a = try uninterrupted.choose(i)
            let b = try restored.choose(i)
            XCTAssertEqual(a, b)
        }
        XCTAssertEqual(restored.state, uninterrupted.state)
    }

    func testDeltasReportNetChange() throws {
        var engine = GameEngine(content: content, seed: 11)
        let before = engine.state.meters
        let result = try engine.choose(0)
        for meter in Meter.allCases {
            XCTAssertEqual(before[meter] + (result.deltas[meter] ?? 0), engine.state.meters[meter])
        }
        XCTAssertEqual(engine.state.clock, content.config.startClock + result.minutes)
    }

    func testClockFormatting() {
        XCTAssertEqual(Clock.format(360), "6:00 AM")
        XCTAssertEqual(Clock.format(725), "12:05 PM")
        XCTAssertEqual(Clock.format(1170), "7:30 PM")
        XCTAssertEqual(Clock.format(0), "12:00 AM")
        XCTAssertEqual(Clock.format(-1), "11:59 PM")
    }
}
