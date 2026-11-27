import SwiftUI

@main
struct EinbuergerungTrainerApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            TabView {
                TodayView()
                    .tabItem { Label("Heute", systemImage: "calendar") }
                PracticeView()
                    .tabItem { Label("Üben", systemImage: "rectangle.stack") }
                ExamTabView()
                    .tabItem { Label("Prüfung", systemImage: "timer") }
                CatalogView()
                    .tabItem { Label("Katalog", systemImage: "books.vertical") }
            }
            .tint(.ink)
            .environment(store)
            .task { await store.syncNow() }
        }
        // Sync at checkpoints, like Anki: when the app opens (fetch the other device's progress)
        // and when it goes to the background (send this session's answers). Not per question.
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.refreshPlan(); Task { await store.syncNow() }
            case .background:
                // Ask iOS for a few seconds so the request can finish after the app leaves the screen.
                let task = UIApplication.shared.beginBackgroundTask(withName: "sync")
                Task {
                    await store.syncIfNeeded()
                    UIApplication.shared.endBackgroundTask(task)
                }
            default: break
            }
        }
    }
}
