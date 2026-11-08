import SwiftUI
import CIAKit

struct KeysView: View {
    @Bindable var vault: KeyVault
    @Environment(\.dismiss) private var dismiss
    @State private var importing: KeyFileKind?
    @State private var isImporting = false
    @State private var removing: KeyFileKind?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("Keys stay on this device")
                            .font(.headline)
                        Text("Import your key files once. Encrypted games use them automatically; already-decrypted games need no keys.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } icon: {
                        Image(systemName: "key.fill")
                            .foregroundStyle(Color.conversionAccent)
                    }
                    .padding(.vertical, 6)
                }
                if let error = vault.error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                ForEach(KeyFileKind.allCases) { kind in
                    Section {
                        if let imported = vault.imports[kind] {
                            Label("Imported", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            LabeledContent(kind == .seeds ? "Title seeds" : "Key entries", value: "\(kind == .seeds ? imported.material.seedCount : imported.material.keyCount)")
                            LabeledContent("Updated", value: imported.date.formatted(date: .abbreviated, time: .shortened))
                        }
                        Button(vault.imports[kind] == nil ? "Import \(kind.rawValue)" : "Replace \(kind.rawValue)", systemImage: "square.and.arrow.down") {
                            importing = kind
                            isImporting = true
                        }
                        if vault.imports[kind] != nil {
                            Button("Remove imported file", role: .destructive) { removing = kind }
                        }
                    } header: {
                        Text(kind.rawValue).textCase(nil).fontDesign(.monospaced)
                    } footer: {
                        Text(explanation(kind))
                    }
                }
                Section {
                    Text("Secret keys use this device’s Keychain. Title seeds stay in protected local storage. Imported files and key values never enter conversion exports.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    NavigationLink("Acknowledgments") {
                        ScrollView {
                            Text(notices)
                                .font(.footnote)
                                .textSelection(.enabled)
                                .padding()
                        }
                        .navigationTitle("Acknowledgments")
                    }
                }
            }
            .navigationTitle("Keys")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                do {
                    if let url = try result.get().first, let kind = importing { try vault.importFile(url, kind: kind) }
                } catch { self.error = error.localizedDescription }
                importing = nil
            }
            .confirmationDialog("Remove \(removing?.rawValue ?? "keys") from this app?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    guard let kind = removing else { return }
                    do { try vault.remove(kind) } catch { self.error = error.localizedDescription }
                    removing = nil
                }
            } message: {
                Text("Your original file stays untouched. Future conversions may need you to import it again.")
            }
            .alert("Could not import keys", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt") else { return "Notices could not be loaded." }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? "Notices could not be loaded."
    }

    private func explanation(_ kind: KeyFileKind) -> String {
        switch kind {
        case .aes: "Citra/Folium-style AES key files, with or without an :AES section. These entries take priority over matching Boot9 entries."
        case .seeds: "Some games require a seed for their title. Missing seeds appear as a per-file error with the title ID."
        case .boot9: "A full or protected retail Boot9 dump. Supplies some key components; newer encryption methods may still require aes_keys.txt."
        }
    }
}
