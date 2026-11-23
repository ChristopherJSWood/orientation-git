import BedtimeCore
import SwiftUI

extension Meter {
    var symbol: String {
        switch self {
        case .sanity: return "brain.head.profile"
        case .mood: return "face.smiling"
        case .home: return "house.fill"
        case .rep: return "bubble.left.and.bubble.right.fill"
        case .sleepy: return "moon.zzz.fill"
        }
    }

    var tint: Color {
        switch self {
        case .sanity: return .pink
        case .mood: return .orange
        case .home: return .teal
        case .rep: return .purple
        case .sleepy: return .indigo
        }
    }

    /// Whether a rise in this meter is good news. Sleepiness is neither:
    /// you want it high at bedtime but an overtired toddler is miserable.
    var higherIsBetter: Bool? {
        self == .sleepy ? nil : true
    }
}

/// Large, tappable, multi-line choice buttons.
struct ChoiceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.28 : 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 1)
            )
            .foregroundStyle(Color.primary)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// The rounded "card" every screen's main content sits on.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )
    }
}
