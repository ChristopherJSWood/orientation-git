import BedtimeCore
import Foundation
import Observation

/// Lifetime totals shown on the title screen.
struct PlayerStats: Codable, Equatable {
    var daysPlayed = 0
    var daysWon = 0
    var bestScore = 0
    var endingsSeen: Set<String> = []
}

/// A saved in-progress day. `contentVersion` lets us drop saves made with
/// incompatible content after an update instead of crashing on them.
private struct SavedGame: Codable {
    var contentVersion: Int
    var state: GameState
}

/// App state: owns the engine, drives screen flow and persistence.
/// All rules live in BedtimeCore; this type only orchestrates.
@MainActor
@Observable
final class GameStore {
    enum Screen: Equatable {
        case title
        case dayIntro
        case event
        case outcome(StepResult)
        case ending
    }

    let content: GameContent?
    let loadError: String?
    private(set) var engine: GameEngine?
    private(set) var screen: Screen = .title
    private(set) var stats: PlayerStats
    private(set) var hasSavedGame: Bool

    private let defaults: UserDefaults
    private static let saveKey = "bedtime.savedGame.v1"
    private static let statsKey = "bedtime.stats.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        do {
            content = try GameContent.bundled()
            loadError = nil
        } catch {
            content = nil
            loadError = String(describing: error)
        }
        if let data = defaults.data(forKey: Self.statsKey),
           let saved = try? JSONDecoder().decode(PlayerStats.self, from: data) {
            stats = saved
        } else {
            stats = PlayerStats()
        }
        hasSavedGame = defaults.data(forKey: Self.saveKey) != nil
    }

    // MARK: - Flow

    func newDay(seed: UInt32 = .random(in: .min ... .max)) {
        guard let content else { return }
        engine = GameEngine(content: content, seed: seed)
        screen = .dayIntro
        save()
    }

    func resume() {
        guard let content,
              let data = defaults.data(forKey: Self.saveKey),
              let saved = try? JSONDecoder().decode(SavedGame.self, from: data),
              saved.contentVersion == content.version
        else {
            discardSave()
            newDay()
            return
        }
        let restored = GameEngine(content: content, restoring: saved.state)
        // A save that points at an event that no longer exists is unusable.
        guard restored.isOver || restored.currentEvent != nil else {
            discardSave()
            newDay()
            return
        }
        engine = restored
        screen = restored.isOver ? .ending : .event
    }

    func beginDay() {
        screen = .event
    }

    func choose(_ index: Int) {
        guard var current = engine else { return }
        guard let result = try? current.choose(index) else { return }
        engine = current
        screen = .outcome(result)
        if current.isOver { record(current) }
        save()
    }

    func continueAfterOutcome() {
        guard let engine else {
            screen = .title
            return
        }
        screen = engine.isOver ? .ending : .event
    }

    func backToTitle() {
        screen = .title
    }

    // MARK: - Sharing

    func shareText() -> String {
        guard let engine, let ending = engine.ending else { return "Bedtime or Bust" }
        let m = engine.state.meters
        let verdict: String
        switch ending.kind {
        case .win: verdict = "made it to bedtime"
        case .soft: verdict = "made it to bedtime, but the toddler did not"
        case .loss: verdict = "did not make it to bedtime"
        }
        return """
        I \(verdict) in Bedtime or Bust: "\(ending.title)" (\(engine.score)/400).
        🧠 \(m.sanity)  🙂 \(m.mood)  🏠 \(m.home)  📱 \(m.rep)  🌙 \(m.sleepy)
        """
    }

    // MARK: - Persistence

    private func record(_ finished: GameEngine) {
        stats.daysPlayed += 1
        if finished.ending?.kind == .win { stats.daysWon += 1 }
        stats.bestScore = max(stats.bestScore, finished.ending?.kind == .win ? finished.score : 0)
        if let id = finished.state.endingID { stats.endingsSeen.insert(id) }
        if let data = try? JSONEncoder().encode(stats) { defaults.set(data, forKey: Self.statsKey) }
    }

    private func save() {
        guard let engine else { return }
        if engine.isOver {
            discardSave()
            return
        }
        let saved = SavedGame(contentVersion: engine.content.version, state: engine.state)
        if let data = try? JSONEncoder().encode(saved) {
            defaults.set(data, forKey: Self.saveKey)
            hasSavedGame = true
        }
    }

    private func discardSave() {
        defaults.removeObject(forKey: Self.saveKey)
        hasSavedGame = false
    }
}
