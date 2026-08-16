import SwiftUI
import SwiftData

@main
struct ClaudeBotApp: App {
    @State private var settings = SettingsStore()
    @State private var viewModel: ChatViewModel?

    var body: some Scene {
        WindowGroup {
            Group {
                if let viewModel {
                    ContentView(viewModel: viewModel)
                } else {
                    AppColors.darkBg.ignoresSafeArea()
                        .task {
                            viewModel = ChatViewModel(settings: settings)
                        }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

struct ContentView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        ZStack {
            if viewModel.showSettings {
                SettingsView(viewModel: viewModel)
            } else {
                ChatView(viewModel: viewModel)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.showSettings)
    }
}
