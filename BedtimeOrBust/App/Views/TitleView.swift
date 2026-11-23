import SwiftUI

struct TitleView: View {
    @Environment(GameStore.self) private var store
    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 64))
                .foregroundStyle(.indigo)
                .accessibilityHidden(true)
            Text("Bedtime or Bust")
                .font(.largeTitle.bold())
            Text("One day. One toddler. One goal:\nmake it to 7:30 PM.")
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()

            VStack(spacing: 12) {
                if store.hasSavedGame {
                    Button {
                        store.resume()
                    } label: {
                        Text("Continue today").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        store.newDay()
                    } label: {
                        Text("Start a new day").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        store.newDay()
                    } label: {
                        Text("Start the day").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                Button("How to play") { showingHelp = true }
                    .padding(.top, 4)
            }
            .controlSize(.large)

            if store.stats.daysPlayed > 0 {
                Text("Days survived: \(store.stats.daysWon) of \(store.stats.daysPlayed) · Best score: \(store.stats.bestScore)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .sheet(isPresented: $showingHelp) { HowToPlayView() }
    }
}

struct HowToPlayView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("The goal") {
                    Text("Get from 6:00 AM to bedtime at 7:30 PM. Each card is a moment of your day; every choice costs time and moves your meters.")
                }
                Section("Your meters") {
                    Label("Sanity: yours. Hits zero, you hide in the pantry. Game over.", systemImage: "brain.head.profile")
                    Label("Toddler Mood: hits zero, a meltdown. Survivable, but costly.", systemImage: "face.smiling")
                    Label("House: hits zero, the house is condemned. Game over.", systemImage: "house.fill")
                    Label("Reputation: what the other parents think. Hits zero, you're removed from the group chat. Game over.", systemImage: "bubble.left.and.bubble.right.fill")
                }
                Section("Bedtime") {
                    Label("Sleepiness rises all day. Naps lower it. At bedtime it must be 50 or more, or your toddler gets a second wind. Above 80 they're overtired, and their mood drops fast.", systemImage: "moon.zzz.fill")
                }
                Section("Grading") {
                    Text("If they're asleep at bedtime, your day is graded by the total of Sanity, Mood, House and Reputation.")
                }
            }
            .navigationTitle("How to play")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
