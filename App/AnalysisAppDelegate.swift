import BackgroundTasks
import UIKit

@MainActor
final class AnalysisAppDelegate: NSObject, UIApplicationDelegate {
    static let taskIdentifier = "com.localphototools.PhotoCleaner.analysis"
    let library = LibraryStore()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.taskIdentifier, using: .main) { [weak self] task in
            guard let processing = task as? BGProcessingTask, let self else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in await self.library.runScheduledAnalysis(processing) }
        }
        return true
    }
}
