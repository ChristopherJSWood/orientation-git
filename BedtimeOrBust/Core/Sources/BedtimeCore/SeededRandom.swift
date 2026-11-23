import Foundation

/// mulberry32: a tiny, fast 32-bit PRNG. It is not cryptographic. It was chosen
/// because it is trivial to reproduce bit-for-bit in JavaScript (see
/// `mulberry32` in tools/engine.mjs), which lets the two engines share golden
/// traces. Its whole state is one `UInt32`, so saving a game saves the RNG too.
public struct SeededRandom: Codable, Equatable, Sendable {
    public private(set) var state: UInt32

    public init(seed: UInt32) {
        state = seed
    }

    /// Returns a value in [0, 1). Exactly matches the JavaScript reference.
    public mutating func next() -> Double {
        state = state &+ 0x6D2B_79F5
        let a = state
        var t = (a ^ (a >> 15)) &* (1 | a)
        t = (t &+ ((t ^ (t >> 7)) &* (61 | t))) ^ t
        return Double(t ^ (t >> 14)) / 4_294_967_296.0
    }
}
