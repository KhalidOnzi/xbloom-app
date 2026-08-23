import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack(path: $model.path) {
                CaptureView()
                    .navigationDestination(for: AppRoute.self) { route in
                        switch route {
                        case .analyze:
                            AnalyzeView()
                        case .profile:
                            ProfileView()
                        case .recipe:
                            RecipeReviewView()
                        }
                    }
            }
            .tabItem {
                Label("Scan", systemImage: "camera.viewfinder")
            }
            .tag(0)

            NavigationStack {
                HistoryView()
            }
            .tabItem {
                Label("History", systemImage: "book.closed")
            }
            .tag(1)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "slider.horizontal.3")
            }
            .tag(2)
        }
        .tint(BloomTheme.roast)
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .modelContainer(for: SavedBrew.self, inMemory: true)
}
