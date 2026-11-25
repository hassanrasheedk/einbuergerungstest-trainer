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
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.refreshPlan(); Task { await store.syncNow() }
            case .background: Task { await store.syncNow() }
            default: break
            }
        }
    }
}
