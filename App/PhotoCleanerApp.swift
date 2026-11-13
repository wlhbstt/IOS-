import SwiftUI

@main
struct PhotoCleanerApp: App {
    @UIApplicationDelegateAdaptor(AnalysisAppDelegate.self) private var delegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(delegate.library)
                .task { await delegate.library.becameActive() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await delegate.library.becameActive() } }
                    else if phase == .background { delegate.library.enteredBackground() }
                }
        }
    }
}
