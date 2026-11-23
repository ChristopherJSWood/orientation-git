import Foundation

// Data model for content.json. All game text and numbers live in that file;
// this code only defines its shape. Field semantics are documented in
// docs/CONTENT_GUIDE.md, and tools/validate.mjs lints the file.

/// A requirement on game state. Empty conditions are always met.
public struct Condition: Decodable, Equatable, Sendable {
    public var flags: [String]
    public var notFlags: [String]
    /// Each listed meter must be >= the value.
    public var minimum: [Meter: Int]
    /// Each listed meter must be <= the value.
    public var maximum: [Meter: Int]

    enum CodingKeys: String, CodingKey {
        case flags, notFlags
        case minimum = "min"
        case maximum = "max"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        flags = try c.decodeIfPresent([String].self, forKey: .flags) ?? []
        notFlags = try c.decodeIfPresent([String].self, forKey: .notFlags) ?? []
        minimum = try c.decodeMeterMap(forKey: .minimum)
        maximum = try c.decodeMeterMap(forKey: .maximum)
    }

    public func isMet(by state: GameState) -> Bool {
        for flag in flags where !state.flags.contains(flag) { return false }
        for flag in notFlags where state.flags.contains(flag) { return false }
        for (meter, value) in minimum where state.meters[meter] < value { return false }
        for (meter, value) in maximum where state.meters[meter] > value { return false }
        return true
    }
}

/// One possible result of a choice. When a choice has several, one is drawn
/// at random in proportion to `weight`.
public struct Outcome: Decodable, Sendable {
    public var text: String
    public var weight: Int
    public var effects: [Meter: Int]
    public var setFlags: [String]
    public var clearFlags: [String]
    public var counters: [String: Int]

    enum CodingKeys: String, CodingKey {
        case text, weight, effects
        case setFlags = "set"
        case clearFlags = "clear"
        case counters = "count"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.decode(String.self, forKey: .text)
        weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        effects = try c.decodeMeterMap(forKey: .effects)
        setFlags = try c.decodeIfPresent([String].self, forKey: .setFlags) ?? []
        clearFlags = try c.decodeIfPresent([String].self, forKey: .clearFlags) ?? []
        counters = try c.decodeIfPresent([String: Int].self, forKey: .counters) ?? [:]
    }
}

public struct Choice: Decodable, Sendable {
    public var label: String
    /// Minutes this choice takes (the engine adds `config.eventGap` on top).
    public var duration: Int
    /// The choice is hidden unless this is met.
    public var condition: Condition?
    public var outcomes: [Outcome]

    enum CodingKeys: String, CodingKey {
        case label, duration, outcomes
        case condition = "when"
    }
}

public struct GameEvent: Decodable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    /// Clock minutes (since midnight) during which the event can appear, inclusive.
    public var window: ClosedRange<Int>
    public var weight: Int
    /// > 0 means "forced": shown as soon as it is eligible, highest first.
    public var priority: Int
    public var repeatable: Bool
    /// Shown only when nothing else is eligible.
    public var isFiller: Bool
    /// Choosing in a final event ends the day and grades it.
    public var isFinal: Bool
    public var condition: Condition?
    public var choices: [Choice]

    enum CodingKeys: String, CodingKey {
        case id, title, text, window, weight, priority, repeatable, choices
        case isFiller = "filler"
        case isFinal = "final"
        case condition = "when"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        let bounds = try c.decode([Int].self, forKey: .window)
        guard bounds.count == 2, bounds[0] <= bounds[1] else {
            throw DecodingError.dataCorruptedError(forKey: .window, in: c, debugDescription: "window must be [from, to] with from <= to")
        }
        window = bounds[0]...bounds[1]
        weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        repeatable = try c.decodeIfPresent(Bool.self, forKey: .repeatable) ?? false
        isFiller = try c.decodeIfPresent(Bool.self, forKey: .isFiller) ?? false
        isFinal = try c.decodeIfPresent(Bool.self, forKey: .isFinal) ?? false
        condition = try c.decodeIfPresent(Condition.self, forKey: .condition)
        choices = try c.decode([Choice].self, forKey: .choices)
    }
}

/// A random twist applied at the start of the day ("Teething", "Grandma Is Visiting").
public struct DayModifier: Decodable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var text: String
    public var weight: Int
    public var effects: [Meter: Int]
    public var setFlags: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, text, weight, effects
        case setFlags = "set"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        text = try c.decode(String.self, forKey: .text)
        weight = try c.decodeIfPresent(Int.self, forKey: .weight) ?? 1
        effects = try c.decodeMeterMap(forKey: .effects)
        setFlags = try c.decodeIfPresent([String].self, forKey: .setFlags) ?? []
    }
}

public struct Ending: Decodable, Sendable {
    public enum Kind: String, Decodable, Sendable {
        /// Asleep at bedtime: graded by the four quality meters.
        case win
        /// A meter hit zero.
        case loss
        /// Reached bedtime, but the toddler was not sleepy enough.
        case soft
    }

    public var kind: Kind
    public var title: String
    public var text: String
}

public struct CounterInfo: Decodable, Identifiable, Sendable {
    public var id: String
    public var label: String
}

public struct GameConfig: Decodable, Sendable {
    public struct Grade: Decodable, Sendable {
        public var minimum: Int
        public var id: String

        enum CodingKeys: String, CodingKey {
            case id
            case minimum = "min"
        }
    }

    public var startClock: Int
    public var bedtimeClock: Int
    public var startMeters: Meters
    public var eventGap: Int
    public var sleepyEvery: Int
    public var drainEvery: [Meter: Int]
    public var overtiredAt: Int
    public var overtiredMoodEvery: Int
    public var asleepThreshold: Int
    public var grades: [Grade]

    enum CodingKeys: String, CodingKey {
        case startClock, bedtimeClock, startMeters, eventGap, sleepyEvery, drainEvery
        case overtiredAt, overtiredMoodEvery, asleepThreshold, grades
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startClock = try c.decode(Int.self, forKey: .startClock)
        bedtimeClock = try c.decode(Int.self, forKey: .bedtimeClock)
        startMeters = try c.decode(Meters.self, forKey: .startMeters)
        eventGap = try c.decodeIfPresent(Int.self, forKey: .eventGap) ?? 0
        sleepyEvery = try c.decode(Int.self, forKey: .sleepyEvery)
        drainEvery = try c.decodeMeterMap(forKey: .drainEvery)
        overtiredAt = try c.decode(Int.self, forKey: .overtiredAt)
        overtiredMoodEvery = try c.decode(Int.self, forKey: .overtiredMoodEvery)
        asleepThreshold = try c.decode(Int.self, forKey: .asleepThreshold)
        grades = try c.decode([Grade].self, forKey: .grades)
    }
}

public enum ContentError: Error, Equatable, CustomStringConvertible {
    case missingResource
    case invalid(String)

    public var description: String {
        switch self {
        case .missingResource: return "content.json is missing from the BedtimeCore bundle"
        case .invalid(let reason): return "content.json is invalid: \(reason)"
        }
    }
}

public struct GameContent: Decodable, Sendable {
    /// Ending IDs the engine itself can produce, besides the grade IDs.
    public static let engineEndingIDs = ["meltdown", "ballpit", "groupchat", "second_wind"]

    public var version: Int
    public var config: GameConfig
    public var meterNames: [Meter: String]
    public var counters: [CounterInfo]
    public var modifiers: [DayModifier]
    public var events: [GameEvent]
    public var endings: [String: Ending]

    enum CodingKeys: String, CodingKey {
        case version, config, counters, modifiers, events, endings
        case meterNames = "meters"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        config = try c.decode(GameConfig.self, forKey: .config)
        let names = try c.decode([String: String].self, forKey: .meterNames)
        var meterNames: [Meter: String] = [:]
        for meter in Meter.allCases { meterNames[meter] = names[meter.rawValue] ?? meter.rawValue.capitalized }
        self.meterNames = meterNames
        counters = try c.decodeIfPresent([CounterInfo].self, forKey: .counters) ?? []
        modifiers = try c.decode([DayModifier].self, forKey: .modifiers)
        events = try c.decode([GameEvent].self, forKey: .events)
        endings = try c.decode([String: Ending].self, forKey: .endings)
        try validateEngineInvariants()
    }

    /// Location of the content.json bundled with this package.
    public static var bundledURL: URL? {
        Bundle.module.url(forResource: "content", withExtension: "json")
    }

    /// Loads the content.json bundled with this package.
    public static func bundled() throws -> GameContent {
        guard let url = bundledURL else { throw ContentError.missingResource }
        return try load(from: Data(contentsOf: url))
    }

    public static func load(from data: Data) throws -> GameContent {
        try JSONDecoder().decode(GameContent.self, from: data)
    }

    public var filler: GameEvent? { events.first { $0.isFiller } }

    public func name(of meter: Meter) -> String { meterNames[meter] ?? meter.rawValue }

    /// Only the guarantees the engine relies on to never crash. Authoring
    /// mistakes (typos in flags, overlong text...) are caught by tools/validate.mjs.
    private func validateEngineInvariants() throws {
        if modifiers.isEmpty { throw ContentError.invalid("needs at least one modifier") }
        if events.filter(\.isFiller).count != 1 { throw ContentError.invalid("needs exactly one filler event") }
        if !events.contains(where: \.isFinal) { throw ContentError.invalid("needs a final (bedtime) event") }
        if config.grades.isEmpty { throw ContentError.invalid("needs at least one grade") }
        var ids = Set<String>()
        for event in events {
            if !ids.insert(event.id).inserted { throw ContentError.invalid("duplicate event id \(event.id)") }
            if event.choices.isEmpty { throw ContentError.invalid("event \(event.id) has no choices") }
            if !event.choices.contains(where: { $0.condition == nil }) {
                throw ContentError.invalid("event \(event.id) needs at least one unconditional choice")
            }
            for choice in event.choices {
                if choice.outcomes.isEmpty { throw ContentError.invalid("a choice in \(event.id) has no outcomes") }
                if choice.duration < 1 { throw ContentError.invalid("a choice in \(event.id) takes no time") }
                if choice.outcomes.contains(where: { $0.weight < 1 }) { throw ContentError.invalid("non-positive weight in \(event.id)") }
            }
        }
        for id in Self.engineEndingIDs + config.grades.map(\.id) where endings[id] == nil {
            throw ContentError.invalid("missing ending \(id)")
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes `{ "mood": 5, "sanity": -3 }`, rejecting unknown meter names.
    func decodeMeterMap(forKey key: Key) throws -> [Meter: Int] {
        guard let raw = try decodeIfPresent([String: Int].self, forKey: key) else { return [:] }
        var result: [Meter: Int] = [:]
        for (name, value) in raw {
            guard let meter = Meter(rawValue: name) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Unknown meter \"\(name)\"")
            }
            result[meter] = value
        }
        return result
    }
}
