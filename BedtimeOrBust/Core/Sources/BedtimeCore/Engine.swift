import Foundation

/// Everything needed to resume a day exactly where it left off. It is
/// `Codable`, so the app can persist it after every choice; the RNG state is
/// included, so a restored game continues identically.
public struct GameState: Codable, Equatable, Sendable {
    public internal(set) var seed: UInt32
    public internal(set) var rng: SeededRandom
    /// Minutes since midnight.
    public internal(set) var clock: Int
    public internal(set) var meters: Meters
    public internal(set) var flags: Set<String>
    public internal(set) var counters: [String: Int]
    public internal(set) var seen: Set<String>
    public internal(set) var lastEventID: String?
    public internal(set) var currentEventID: String?
    public internal(set) var modifierID: String
    public internal(set) var step: Int
    public internal(set) var endingID: String?
}

/// What happened after a choice, for the outcome screen.
public struct StepResult: Equatable, Sendable {
    public let eventID: String
    public let choiceIndex: Int
    public let outcomeIndex: Int
    public let text: String
    /// Net change per meter, including passive drift. Unchanged meters are omitted.
    public let deltas: [Meter: Int]
    /// Minutes that passed (choice duration + event gap).
    public let minutes: Int
    public let endingID: String?
}

public enum GameError: Error, Equatable {
    case gameOver
    case invalidChoice(Int)
}

/// The rules. This is a line-for-line port of `Game` in tools/engine.mjs,
/// which is the executable spec; ConformanceTests replays golden traces from
/// it. If you change a rule here, change it there and regenerate the traces.
public struct GameEngine: Sendable {
    public let content: GameContent
    public private(set) var state: GameState
    private let eventIndex: [String: Int]

    /// Starts a new day. The seed fully determines the day for a given
    /// sequence of choices.
    public init(content: GameContent, seed: UInt32) {
        self.content = content
        eventIndex = Self.makeIndex(content.events)
        var rng = SeededRandom(seed: seed)
        let modifier = content.modifiers[Self.weightedPick(content.modifiers, weight: { $0.weight }, rng: &rng)]
        state = GameState(
            seed: seed,
            rng: rng,
            clock: content.config.startClock,
            meters: content.config.startMeters,
            flags: [],
            counters: [:],
            seen: [],
            lastEventID: nil,
            currentEventID: nil,
            modifierID: modifier.id,
            step: 0,
            endingID: nil
        )
        apply(effects: modifier.effects, setting: modifier.setFlags, clearing: [], counters: [:])
        state.currentEventID = nextEvent().id
    }

    /// Resumes a saved day.
    public init(content: GameContent, restoring state: GameState) {
        self.content = content
        eventIndex = Self.makeIndex(content.events)
        self.state = state
    }

    // MARK: - Queries

    public var currentEvent: GameEvent? { state.currentEventID.flatMap(event(withID:)) }
    public var modifier: DayModifier? { content.modifiers.first { $0.id == state.modifierID } }
    public var ending: Ending? { state.endingID.flatMap { content.endings[$0] } }
    public var isOver: Bool { state.endingID != nil }

    /// Sum of the four quality meters (0...400); ranks an asleep ending.
    public var score: Int { Meter.quality.reduce(0) { $0 + state.meters[$1] } }

    /// 0...1 progress from wake-up to bedtime, for the clock bar.
    public var dayProgress: Double {
        let cfg = content.config
        let span = Double(cfg.bedtimeClock - cfg.startClock)
        guard span > 0 else { return 1 }
        return Swift.min(1, Swift.max(0, Double(state.clock - cfg.startClock) / span))
    }

    public func event(withID id: String) -> GameEvent? {
        eventIndex[id].map { content.events[$0] }
    }

    /// The choices the player can see for `event` (default: the current event).
    public func visibleChoices(for event: GameEvent? = nil) -> [Choice] {
        guard let event = event ?? currentEvent else { return [] }
        return event.choices.filter { $0.condition?.isMet(by: state) ?? true }
    }

    // MARK: - Playing

    /// Applies the visible choice at `index` and advances the day.
    @discardableResult
    public mutating func choose(_ index: Int) throws -> StepResult {
        guard !isOver, let event = currentEvent else { throw GameError.gameOver }
        let choices = visibleChoices(for: event)
        guard choices.indices.contains(index) else { throw GameError.invalidChoice(index) }
        let choice = choices[index]
        let before = state.meters

        var outcomeIndex = 0
        if choice.outcomes.count > 1 {
            outcomeIndex = Self.weightedPick(choice.outcomes, weight: { $0.weight }, rng: &state.rng)
        }
        let outcome = choice.outcomes[outcomeIndex]
        apply(effects: outcome.effects, setting: outcome.setFlags, clearing: outcome.clearFlags, counters: outcome.counters)
        let minutes = choice.duration + content.config.eventGap
        advance(minutes: minutes)

        state.seen.insert(event.id)
        state.lastEventID = event.id
        state.step += 1

        var endingID: String?
        if state.meters.sanity <= 0 {
            endingID = "meltdown"
        } else if state.meters.home <= 0 {
            endingID = "ballpit"
        } else if state.meters.rep <= 0 {
            endingID = "groupchat"
        } else if event.isFinal {
            endingID = bedtimeEnding()
        }

        if let endingID {
            state.endingID = endingID
            state.currentEventID = nil
        } else {
            state.currentEventID = nextEvent().id
        }

        var deltas: [Meter: Int] = [:]
        for meter in Meter.allCases where state.meters[meter] != before[meter] {
            deltas[meter] = state.meters[meter] - before[meter]
        }
        return StepResult(
            eventID: event.id,
            choiceIndex: index,
            outcomeIndex: outcomeIndex,
            text: outcome.text,
            deltas: deltas,
            minutes: minutes,
            endingID: endingID
        )
    }

    // MARK: - Rules

    private mutating func apply(effects: [Meter: Int], setting: [String], clearing: [String], counters: [String: Int]) {
        for (meter, delta) in effects { state.meters[meter] += delta }
        for flag in setting { state.flags.insert(flag) }
        for flag in clearing { state.flags.remove(flag) }
        for (counter, delta) in counters { state.counters[counter, default: 0] += delta }
    }

    /// Passive drift while time passes. Ticks count from the start of the day
    /// so drift does not depend on how time is chunked into events.
    private mutating func advance(minutes: Int) {
        let cfg = content.config
        let t0 = state.clock - cfg.startClock
        let t1 = t0 + minutes
        func ticks(_ every: Int) -> Int { every > 0 ? t1 / every - t0 / every : 0 }

        state.meters[.sleepy] += ticks(cfg.sleepyEvery)
        for meter in Meter.allCases {
            if let every = cfg.drainEvery[meter] { state.meters[meter] -= ticks(every) }
        }
        if state.meters.sleepy >= cfg.overtiredAt {
            state.meters[.mood] -= ticks(cfg.overtiredMoodEvery)
        }
        state.clock += minutes
    }

    private func bedtimeEnding() -> String {
        let cfg = content.config
        if state.meters.sleepy < cfg.asleepThreshold { return "second_wind" }
        let total = score
        for grade in cfg.grades where total >= grade.minimum { return grade.id }
        return cfg.grades[cfg.grades.count - 1].id
    }

    private mutating func nextEvent() -> GameEvent {
        let candidates = content.events.filter { event in
            !event.isFiller
                && (event.repeatable || !state.seen.contains(event.id))
                && event.id != state.lastEventID
                && event.window.contains(state.clock)
                && (event.condition?.isMet(by: state) ?? true)
                && !visibleChoices(for: event).isEmpty
        }
        var best: GameEvent?
        for event in candidates where event.priority > 0 {
            if let current = best, event.priority <= current.priority { continue }
            best = event
        }
        if let best { return best }

        let pool = candidates.filter { $0.priority <= 0 }
        if pool.isEmpty {
            // GameContent validation guarantees exactly one filler event.
            return content.filler ?? content.events[0]
        }
        return pool[Self.weightedPick(pool, weight: { $0.weight }, rng: &state.rng)]
    }

    /// One RNG draw; returns an index chosen in proportion to `weight`.
    static func weightedPick<T>(_ items: [T], weight: (T) -> Int, rng: inout SeededRandom) -> Int {
        var total = 0.0
        for item in items { total += Double(weight(item)) }
        let r = rng.next() * total
        var accumulated = 0.0
        for (index, item) in items.enumerated() {
            accumulated += Double(weight(item))
            if r < accumulated { return index }
        }
        return items.count - 1
    }

    private static func makeIndex(_ events: [GameEvent]) -> [String: Int] {
        var index: [String: Int] = [:]
        for (i, event) in events.enumerated() { index[event.id] = i }
        return index
    }
}

/// "6:05 AM"-style formatting, identical to formatClock in tools/engine.mjs.
public enum Clock {
    public static func format(_ minutes: Int) -> String {
        let m = ((minutes % 1440) + 1440) % 1440
        let hour24 = m / 60
        let minute = m % 60
        let suffix = hour24 < 12 ? "AM" : "PM"
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return "\(hour12):\(minute < 10 ? "0" : "")\(minute) \(suffix)"
    }
}
