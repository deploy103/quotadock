import SwiftUI
import WidgetKit

@MainActor
final class DockModel: ObservableObject {
    @Published var snapshot = SnapshotStore.load()
    @Published var status = "Pair your HTTPS bridge or explore demo data."
    @Published var busy = false
    @Published var demo = false
    var pairingRevision = 0

    init() {
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            demo = true
            snapshot = .preview
        }
    }

    func refresh() async {
        guard !busy, !demo else { return }
        busy = true
        let revision = pairingRevision
        defer { busy = false }
        do {
            let next = try await BridgeClient().fetch(PairingStore.load())
            guard revision == pairingRevision, !demo else { return }
            try SnapshotStore.save(next)
            snapshot = next
            status = "Updated · bridge may serve a cached reading."
            WatchSync.shared.send(next)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            status = "Refresh unavailable. Showing cached data, if any. Check pairing and connection."
        }
    }
}

@main
struct QuotaDockApp: App {
    @StateObject private var model = DockModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            DockView(model: model)
                .preferredColorScheme(.dark).tint(DockTheme.mint)
                .task { WatchSync.shared.start(); await model.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await model.refresh() } }
                }
        }
    }
}

struct DockView: View {
    @ObservedObject var model: DockModel
    @State private var showPairing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if model.demo || model.snapshot?.demo == true {
                        Text("DEMO · sample data, not your account").font(.headline).foregroundStyle(DockTheme.mint)
                    }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    if let snapshot = model.snapshot {
                        ForEach(snapshot.providers) { ProviderCard(provider: $0, demo: snapshot.demo) }
                    } else {
                        ContentUnavailableView("No readings yet", systemImage: "chart.bar", description: Text("Pair a bridge to see remaining allowances."))
                    }
                    Text("Bars show remaining allowance, never a sum. Reset times are informational. Widgets update when the OS allows; Watch uses the last iPhone transfer.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(model.demo ? "Leave demo" : "Explore demo") {
                        model.demo.toggle()
                        model.snapshot = model.demo ? .preview : SnapshotStore.load()
                        if !model.demo { Task { await model.refresh() } }
                    }
                }.padding()
            }.background(DockTheme.graphite)
                .navigationTitle("QuotaDock")
                .refreshable { await model.refresh() }
                .toolbar {
                    Button("Pair", systemImage: "link") { showPairing = true }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                        .disabled(model.busy || model.demo)
                }
                .sheet(isPresented: $showPairing) { PairingView(model: model) }
        }
    }
}

struct PairingView: View {
    @ObservedObject var model: DockModel
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("HTTPS bridge base URL") {
                    TextField("https://bridge.example.com", text: $url)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Pairing token", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Text("Use a trusted HTTPS bridge. Token stays in this device’s Keychain, shared only with the iPhone widget. Never enter provider credentials.")
                if let error { Text(error).foregroundStyle(.orange) }
                Button("Save pairing") {
                    do {
                        try PairingStore.save(Pairing(baseURL: url.trimmingCharacters(in: .whitespacesAndNewlines), token: token))
                        model.pairingRevision += 1
                        SnapshotStore.clear()
                        model.snapshot = nil
                        model.demo = false
                        token = ""
                        dismiss()
                        Task { await model.refresh() }
                    } catch { self.error = "Could not save. Use a valid HTTPS URL and token; check signing entitlements." }
                }
                Button("Forget pairing", role: .destructive) {
                    model.pairingRevision += 1
                    PairingStore.remove()
                    SnapshotStore.clear()
                    model.snapshot = nil
                    model.demo = false
                    model.status = "Pairing removed. Watch may retain its last reading until the next transfer."
                    WidgetCenter.shared.reloadAllTimelines()
                    dismiss()
                }
            }.navigationTitle("Pair bridge")
                .toolbar { Button("Cancel") { token = ""; dismiss() } }
        }
    }
}

#Preview { DockView(model: { let model = DockModel(); model.demo = true; model.snapshot = .preview; return model }()) }
