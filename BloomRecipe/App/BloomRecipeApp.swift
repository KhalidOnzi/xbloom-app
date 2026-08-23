import SwiftData
import SwiftUI

@main
struct BloomRecipeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
        }
        .modelContainer(for: SavedBrew.self)
    }
}
