import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showEnglish") private var showEnglish = false
    @State private var confirmReset = false
    @State private var codeInput = ""
    @State private var codeInvalid = false
    @State private var confirmLeave = false

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
                syncSection
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

    @ViewBuilder
    private var syncSection: some View {
        if let code = store.syncCode {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Sync-Code (auf dem anderen Gerät eingeben)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(Store.prettyCode(code))
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .textSelection(.enabled)
                }
                .padding(.vertical, 2)
                Button("Code kopieren") { UIPasteboard.general.string = Store.prettyCode(code) }
                HStack {
                    if store.isSyncing {
                        Text("Synchronisiere …").foregroundStyle(.secondary)
                    } else if let error = store.syncError {
                        Text(error).foregroundStyle(.red)
                    } else if let last = store.lastSync {
                        Text("Zuletzt synchronisiert: \(last.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Noch nicht synchronisiert").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Jetzt") { Task { await store.syncNow() } }
                        .disabled(store.isSyncing)
                }
                Button("Sync auf diesem Gerät beenden", role: .destructive) { confirmLeave = true }
                    .confirmationDialog("Sync auf diesem Gerät beenden? Dein Fortschritt bleibt hier gespeichert.",
                                        isPresented: $confirmLeave, titleVisibility: .visible) {
                        Button("Sync beenden", role: .destructive) { store.leaveSync() }
                    }
            } header: {
                Text("Synchronisieren")
            } footer: {
                Text("Fortschritt, Markierungen, Probetests und Testtermin werden mit der Web-Version abgeglichen.")
            }
        } else {
            Section {
                Button("Sync-Code erstellen") { store.createSyncCode() }
                TextField("XXXXX-XXXXX-XXXXX-XXXXX", text: $codeInput)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit(join)
                Button("Mit Code verbinden", action: join)
                    .disabled(codeInput.isEmpty)
                if codeInvalid {
                    Text("Der Code hat 20 Zeichen.").foregroundStyle(.red).font(.footnote)
                }
            } header: {
                Text("Synchronisieren")
            } footer: {
                Text("Halte Fortschritt zwischen dieser App und der Web-Version gleich. Erstelle einen Code hier oder gib den Code aus dem Browser ein. Wer den Code kennt, sieht deinen Lernstand.")
            }
        }
    }

    private func join() {
        codeInvalid = !store.joinSync(code: codeInput)
        if !codeInvalid { codeInput = "" }
    }
}
