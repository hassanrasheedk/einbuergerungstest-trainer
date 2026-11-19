import SwiftUI

@main
struct EinbuergerungTrainerApp: App {
    @State private var store = Store()

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
        }
    }
}
