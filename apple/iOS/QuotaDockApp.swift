import SwiftUI
import WidgetKit

@MainActor
final class DockModel: ObservableObject {
    @Published var snapshot = SnapshotStore.load()
    @Published var status = "Pair your HTTPS bridge or explore demo data."
    @Published var busy = false
    @Published var demo = false
    let cloud = CloudModel()
    var pairingRevision = 0

    init() {
        cloud.onSwitch = { [weak self] in self?.clearReadings() }
        cloud.onSnapshot = { [weak self] next in
            guard let self, !self.demo else { return }
            try? SnapshotStore.save(next)
            self.snapshot = next
            WatchSync.shared.send(next)
            WidgetCenter.shared.reloadAllTimelines()
        }
        if ProcessInfo.processInfo.arguments.contains("--demo") {
            demo = true
            snapshot = .preview
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--unknown-preview") {
            demo = true
            snapshot = Snapshot(schemaVersion: 1, generatedAt: Date(), demo: true,
                                providers: Snapshot.preview.providers.filter { $0.id == .grok })
        }
        #endif
    }

    func clearReadings() {
        pairingRevision += 1
        SnapshotStore.clear()
        CloudCache.clear()
        snapshot = nil
        demo = false
        WatchSync.shared.send(Snapshot(schemaVersion: 1, generatedAt: Date(), demo: false, providers: []))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func refresh(automatic: Bool = false) async {
        guard !busy, !demo else { return }
        if cloud.session != nil {
            let revision = cloud.revision
            await cloud.read()
            guard revision == cloud.revision, !demo else { return }
            await cloud.refresh(force: !automatic)
            return
        }
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
            guard revision == pairingRevision, !demo else { return }
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
                .tint(DockTheme.mint)
                .task {
                    WatchSync.shared.start()
                    if RefreshSettings.foregroundEnabled() { await model.refresh(automatic: true) }
                }
                .onChange(of: scenePhase) { _, phase in
                    model.cloud.foreground = phase == .active
                    if phase == .active && RefreshSettings.foregroundEnabled() { Task { await model.refresh(automatic: true) } }
                }
        }
    }
}

struct DockView: View {
    @ObservedObject var model: DockModel
    @State private var showPairing = false
    @State private var showSettings = false
    @State private var showCloudPreview = false
    @State private var showBatchPreview = false
    @State private var showSurfacePreview = false
    private var surfacePreview: String? {
        #if DEBUG
        return ["widgets", "widgets-overview", "widgets-accessories", "watch", "watch-stale", "accessibility"].first {
            ProcessInfo.processInfo.arguments.contains("--\($0)-preview")
        }
        #else
        return nil
        #endif
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NavigationLink("Optional cloud account") { CloudView(model: model.cloud) }
                    if model.demo || model.snapshot?.demo == true {
                        Text("DEMO · sample data, not your account").font(.headline).foregroundStyle(DockTheme.mint)
                    }
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    if model.cloud.session != nil && !model.demo {
                        CloudReadingsView(model: model.cloud)
                    } else if let snapshot = model.snapshot {
                        ForEach(snapshot.providers) { ProviderCard(provider: $0, demo: snapshot.demo) }
                    } else {
                        ContentUnavailableView("No readings yet", systemImage: "chart.bar", description: Text("Pair a bridge to see remaining allowances."))
                    }
                    Text("Bars show remaining allowance, never a sum. Reset times are informational. Widgets update when the OS allows; Watch uses the last iPhone transfer.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button(model.demo ? "Leave demo" : "Explore demo") {
                        model.demo.toggle()
                        model.snapshot = model.demo ? .preview : SnapshotStore.load()
                        if !model.demo && RefreshSettings.foregroundEnabled() { Task { await model.refresh(automatic: true) } }
                    }
                }.padding()
            }.background(DockTheme.background)
                .navigationTitle("QuotaDock")
                .refreshable { await model.refresh() }
                .toolbar {
                    Button("Settings", systemImage: "gearshape") { showSettings = true }
                    Button("Pair", systemImage: "link") { showPairing = true }
                    Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                        .disabled(model.busy || model.demo)
                }
                .sheet(isPresented: $showPairing) { PairingView(model: model) }
                .sheet(isPresented: $showSettings) { SettingsView() }
                .sheet(isPresented: $showCloudPreview) { NavigationStack { CloudView(model: model.cloud) } }
                .sheet(isPresented: $showBatchPreview) {
                    #if DEBUG
                    CloudBatchPreview()
                    #endif
                }
                .fullScreenCover(isPresented: $showSurfacePreview) {
                    #if DEBUG
                    switch surfacePreview ?? "widgets" {
                    case "accessibility": QuotaAccessibilityPreview()
                    case "watch", "watch-stale": WatchSurfacePreview()
                    default: WidgetSurfacePreview()
                    }
                    #endif
                }
                .onAppear {
                    #if DEBUG
                    showSettings = ProcessInfo.processInfo.arguments.contains("--settings-preview")
                    showCloudPreview = ProcessInfo.processInfo.arguments.contains("--cloud-preview")
                    showBatchPreview = ProcessInfo.processInfo.arguments.contains("--batch-preview")
                    showSurfacePreview = surfacePreview != nil
                    #endif
                }
        }
    }
}

struct SettingsView: View {
    @AppStorage(RefreshSettings.foregroundKey) private var foregroundAutoRefresh = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("앱을 열 때 새로고침", isOn: $foregroundAutoRefresh)
                } footer: {
                    Text("끄면 앱에서는 버튼 또는 아래로 당겨 수동으로 새로고침합니다. 연결 실패 시 마지막 관측값과 시간을 유지합니다.")
                }
                Section("위젯과 Watch") {
                    Text("위젯은 저장된 마지막 관측값만 읽으며, 서버나 AI 계정에 직접 접속하지 않습니다. 업데이트 시점은 OS가 결정합니다.")
                    Text("Watch도 iPhone에서 받은 마지막 관측값을 표시합니다.")
                }
                Section("클라우드 자동 수집") {
                    Text("로컬 수집기가 켜져 있어야 합니다. Free는 2시간, Plus는 1시간, Pro는 20·30·60·120분 중 선택한 간격이 지났는지 서버가 검사합니다. 클라우드 화면에서 자동 수집을 끌 수 있습니다.")
                    Text("수집 간격은 iOS 백그라운드 실행이나 위젯 새로고침을 보장하지 않습니다.")
                }
                Section("Codex") {
                    Text("Free 플랜 지원은 사용 환경과 출시 단계에 따라 다릅니다. 측정 불가는 Unknown이며, 한도 소진이나 이용 자격 없음을 뜻하지 않습니다.")
                }
            }.navigationTitle("설정")
                .toolbar { Button("완료") { dismiss() } }
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
                Text("Use a trusted HTTPS bridge without cloud. Token stays in this device’s Keychain. Widgets read only sanitized cache. Never enter provider credentials. Saving switches away from cloud and clears readings.")
                if let error { Text(error).foregroundStyle(.orange) }
                Button("Save pairing") {
                    do {
                        try PairingStore.save(Pairing(baseURL: url.trimmingCharacters(in: .whitespacesAndNewlines), token: token))
                        let old = model.cloud.client
                        model.cloud.clear()
                        if let old { Task { _ = try? await old.request("v2/auth/logout", method: "POST", body: [:]) } }
                        token = ""
                        dismiss()
                        Task { await model.refresh() }
                    } catch { self.error = "Could not save. Use a valid HTTPS URL and token; check signing entitlements." }
                }
                Button("Forget pairing", role: .destructive) {
                    PairingStore.remove()
                    model.clearReadings()
                    model.status = "Pairing removed. Offline Watch/widgets may retain rendered content until next transfer."
                    dismiss()
                }
            }.navigationTitle("Pair bridge")
                .toolbar { Button("Cancel") { token = ""; dismiss() } }
        }
    }
}

#Preview { DockView(model: { let model = DockModel(); model.demo = true; model.snapshot = .preview; return model }()) }
