import BedtimeCore
import SwiftUI

struct DayIntroView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        if let engine = store.engine, let modifier = engine.modifier {
            VStack(spacing: 20) {
                Spacer()
                Text("Today's forecast")
                    .font(.subheadline.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Card {
                    Text(modifier.title).font(.title.bold())
                    Text(modifier.text).font(.body)
                    if !modifier.effects.isEmpty {
                        DeltaRow(deltas: modifier.effects, content: engine.content)
                    }
                }
                Text("Bedtime is \(Clock.format(engine.content.config.bedtimeClock)). Sleepiness needs to be \(engine.content.config.asleepThreshold) or higher when it arrives.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    store.beginDay()
                } label: {
                    Text("It's \(Clock.format(engine.state.clock)). Begin.").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }
}
