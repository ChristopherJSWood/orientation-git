import SwiftUI

struct RootView: View {
    @Environment(GameStore.self) private var store

    var body: some View {
        ZStack {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
            if let error = store.loadError {
                ContentUnavailableView(
                    "The day could not start",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                switch store.screen {
                case .title:
                    TitleView()
                case .dayIntro:
                    DayIntroView()
                case .event, .outcome:
                    PlayView()
                case .ending:
                    EndView()
                }
            }
        }
        .animation(.snappy, value: store.screen)
    }
}
