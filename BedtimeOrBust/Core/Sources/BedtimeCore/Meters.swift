import Foundation

/// The five gauges the game tracks. Every value is an integer clamped to 0...100.
///
/// The declaration order is significant: it matches `METERS` in
/// `tools/engine.mjs`, and golden traces store meters in this order.
public enum Meter: String, CaseIterable, Codable, Sendable {
    case sanity, mood, home, rep, sleepy

    /// The meters that decide the end-of-day grade. Sleepiness only gates bedtime.
    public static let quality: [Meter] = [.sanity, .mood, .home, .rep]
}

/// A full set of meter values. Writes go through the subscript, which clamps,
/// so no code path can push a meter outside 0...100.
public struct Meters: Codable, Equatable, Sendable {
    public private(set) var sanity: Int
    public private(set) var mood: Int
    public private(set) var home: Int
    public private(set) var rep: Int
    public private(set) var sleepy: Int

    public static let range = 0...100

    public init(sanity: Int, mood: Int, home: Int, rep: Int, sleepy: Int) {
        self.sanity = Self.clamp(sanity)
        self.mood = Self.clamp(mood)
        self.home = Self.clamp(home)
        self.rep = Self.clamp(rep)
        self.sleepy = Self.clamp(sleepy)
    }

    public subscript(meter: Meter) -> Int {
        get {
            switch meter {
            case .sanity: return sanity
            case .mood: return mood
            case .home: return home
            case .rep: return rep
            case .sleepy: return sleepy
            }
        }
        set {
            let value = Self.clamp(newValue)
            switch meter {
            case .sanity: sanity = value
            case .mood: mood = value
            case .home: home = value
            case .rep: rep = value
            case .sleepy: sleepy = value
            }
        }
    }

    /// Values in `Meter.allCases` order (the golden-trace format).
    public var values: [Int] { Meter.allCases.map { self[$0] } }

    static func clamp(_ value: Int) -> Int {
        Swift.min(range.upperBound, Swift.max(range.lowerBound, value))
    }
}
