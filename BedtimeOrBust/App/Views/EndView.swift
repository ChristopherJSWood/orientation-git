import BedtimeCore
import SwiftUI

struct EndView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let engine = store.engine, let ending = engine.ending {
            ScrollView {
                VStack(spacing: 16) {
                    Text(badge(for: ending.kind))
                        .font(.subheadline.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(color(for: ending.kind))
                        .padding(.top, 24)
                    Text(ending.title)
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Card {
                        Text(ending.text).font(.body)
                        if ending.kind == .win {
                            Text("Score: \(engine.score) / 400")
                                .font(.headline.monospacedDigit())
                        }
                        Text("Day ended at \(Clock.format(engine.state.clock)) after \(engine.state.step) decisions.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Card {
                        Text("Final meters").font(.headline)
                        ForEach(Meter.allCases, id: \.self) { meter in
                            MeterBar(meter: meter, value: engine.state.meters[meter], name: engine.content.name(of: meter), danger: meter == .sleepy ? nil : 0)
                        }
                    }
                    ReceiptCard(engine: engine)
                    VStack(spacing: 12) {
                        ShareLink(item: store.shareText()) {
                            Label("Share your day", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        Button {
                            store.newDay()
                        } label: {
                            Text("Try another day").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Back to title") { store.backToTitle() }
                    }
                    .controlSize(.large)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal)
            }
        }
    }

    private func badge(for kind: Ending.Kind) -> String {
        switch kind {
        case .win: return "Asleep by bedtime"
        case .soft: return "Still awake"
        case .loss: return "Game over"
        }
    }

    private func color(for kind: Ending.Kind) -> Color {
        switch kind {
        case .win: return .green
        case .soft: return .orange
        case .loss: return .red
        }
    }
}

/// The satirical end-of-day receipt.
struct ReceiptCard: View {
    let engine: GameEngine

    var body: some View {
        Card {
            Text("Today's receipt").font(.headline)
            ForEach(engine.content.counters) { counter in
                HStack {
                    Text(counter.label)
                    Spacer()
                    Text("\(engine.state.counters[counter.id] ?? 0)").monospacedDigit()
                }
                .font(.callout)
            }
            Divider()
            HStack {
                Text("Crises survived").font(.callout.weight(.semibold))
                Spacer()
                Text("\(engine.state.step)").font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
    }
}
