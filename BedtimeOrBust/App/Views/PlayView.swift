import BedtimeCore
import SwiftUI

struct PlayView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let engine = store.engine {
            VStack(spacing: 0) {
                HUDView(engine: engine)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                ScrollView {
                    Group {
                        switch store.screen {
                        case .outcome(let result):
                            OutcomeCard(result: result, engine: engine)
                        default:
                            if let event = engine.currentEvent {
                                EventCard(event: event, choices: engine.visibleChoices())
                            }
                        }
                    }
                    .padding()
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
                }
            }
            .sensoryFeedback(.selection, trigger: engine.state.step)
        }
    }
}

/// Clock, day progress and meters.
struct HUDView: View {
    let engine: GameEngine

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(Clock.format(engine.state.clock))
                    .font(.title2.bold().monospacedDigit())
                    .contentTransition(.numericText())
                Spacer()
                if let modifier = engine.modifier {
                    Text(modifier.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
            ProgressView(value: engine.dayProgress) {
                EmptyView()
            } currentValueLabel: {
                Text("Bedtime \(Clock.format(engine.content.config.bedtimeClock))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .tint(.indigo)
            .accessibilityLabel("Progress to bedtime")

            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Meter.quality, id: \.self) { meter in
                    MeterBar(meter: meter, value: engine.state.meters[meter], name: engine.content.name(of: meter), danger: 20)
                }
            }
            MeterBar(
                meter: .sleepy,
                value: engine.state.meters.sleepy,
                name: "\(engine.content.name(of: .sleepy)) (needs \(engine.content.config.asleepThreshold)+ at bedtime)",
                danger: nil
            )
        }
    }
}

struct MeterBar: View {
    let meter: Meter
    let value: Int
    let name: String
    /// At or below this value the bar turns red. nil: never.
    let danger: Int?

    private var isDanger: Bool { danger.map { value <= $0 } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: meter.symbol)
                    .foregroundStyle(meter.tint)
                    .frame(width: 18)
                Text(name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(value)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isDanger ? Color.red : Color.secondary)
                    .contentTransition(.numericText())
            }
            ProgressView(value: Double(value), total: 100)
                .tint(isDanger ? Color.red : meter.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(value) out of 100\(isDanger ? ", critical" : "")")
    }
}

struct EventCard: View {
    @Environment(GameStore.self) private var store
    let event: GameEvent
    let choices: [Choice]

    var body: some View {
        VStack(spacing: 16) {
            Card {
                Text(event.title).font(.title2.bold())
                Text(event.text).font(.body)
            }
            ForEach(Array(choices.enumerated()), id: \.offset) { index, choice in
                Button {
                    withAnimation(.snappy) { store.choose(index) }
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(choice.label)
                        Spacer(minLength: 8)
                        Text("\(choice.duration) min")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(ChoiceButtonStyle())
                .accessibilityHint("Takes about \(choice.duration) minutes")
            }
        }
        .id(event.id)
    }
}

struct OutcomeCard: View {
    @Environment(GameStore.self) private var store
    let result: StepResult
    let engine: GameEngine

    var body: some View {
        VStack(spacing: 16) {
            Card {
                if let event = engine.event(withID: result.eventID) {
                    Text(event.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(result.text).font(.title3)
                if !result.deltas.isEmpty {
                    DeltaRow(deltas: result.deltas, content: engine.content)
                }
                Text("\(result.minutes) minutes pass. It's now \(Clock.format(engine.state.clock)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                withAnimation(.snappy) { store.continueAfterOutcome() }
            } label: {
                Text(engine.isOver ? "How did the day end?" : "Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .id("outcome-\(engine.state.step)")
    }
}

/// "+6 Toddler Mood  −3 Sanity" chips.
struct DeltaRow: View {
    let deltas: [Meter: Int]
    let content: GameContent

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(Meter.allCases.filter { deltas[$0] != nil }, id: \.self) { meter in
                let delta = deltas[meter] ?? 0
                let good: Bool? = meter.higherIsBetter.map { $0 == (delta > 0) }
                Label {
                    Text("\(delta > 0 ? "+" : "−")\(abs(delta)) \(content.name(of: meter))")
                } icon: {
                    Image(systemName: meter.symbol)
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(chipColor(good).opacity(0.15)))
                .foregroundStyle(chipColor(good))
            }
        }
    }

    private func chipColor(_ good: Bool?) -> Color {
        switch good {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return .indigo
        }
    }
}

/// Minimal wrapping layout for chips (iOS 16+ Layout protocol).
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
