import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showEnglish") private var showEnglish = false
    @State private var confirmReset = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    DatePicker("Testtermin", selection: $store.examDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "de_DE"))
                } footer: {
                    Text("Der Tagesplan verteilt die neuen Fragen so, dass du \(Store.bufferDays) Tage vor dem Test alle kennst.")
                }
                Section {
                    Toggle("Englisch immer zeigen", isOn: $showEnglish)
                } footer: {
                    Text("Sonst blendest du die Übersetzung mit „EN“ bei jeder Frage ein.")
                }
                Section {
                    Button("Fortschritt zurücksetzen", role: .destructive) { confirmReset = true }
                        .confirmationDialog("Gesamten Fortschritt und alle Probetests löschen?",
                                            isPresented: $confirmReset, titleVisibility: .visible) {
                            Button("Alles löschen", role: .destructive) { store.resetAll() }
                        }
                }
                Section {
                    Text("Fragen, Antworten und Bilder: Gesamtfragenkatalog zum Test „Leben in Deutschland“ und zum „Einbürgerungstest“, Bundesamt für Migration und Flüchtlinge, Stand 07.05.2025. Lösungen, Übersetzungen und Erklärungen: github.com/bitesinbyte/leben-in-deutschland (MIT). Nur zur privaten Nutzung.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Quellen")
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } }
            }
        }
    }
}
