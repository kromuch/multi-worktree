import SwiftUI
import MWTKit

@main
struct MultiWorktreeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("MultiWorktree", systemImage: "arrow.triangle.branch") {
            ContentView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)
    }
}
