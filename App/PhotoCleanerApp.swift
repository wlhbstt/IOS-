import SwiftUI

@main
struct PhotoCleanerApp: App {
    @StateObject private var library = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .task { await library.reload() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await library.reload() } }
                    else { library.pause() }
                }
        }
    }
}
