import SwiftUI
import WidgetKit

@MainActor
final class InterfaceSettings: ObservableObject {
    @Published private(set) var language = DockL10n.selection()

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--language-ko-preview") { choose(.ko, synchronize: false) }
        else if arguments.contains("--language-en-preview") { choose(.en, synchronize: false) }
        #endif
    }

    func choose(_ next: DockLanguage, synchronize: Bool = true) {
        guard language != next else { return }
        DockL10n.save(next)
        language = next
        WidgetCenter.shared.reloadAllTimelines()
        if synchronize { WatchSync.shared.syncLanguage() }
    }

    var locale: Locale { Locale(identifier: DockL10n.resolved(language)) }
}

enum SetupStep: String, Codable, CaseIterable {
    case welcome, connection, preferences
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

enum SetupRoute: String, Codable, CaseIterable {
    case demo, bridge, cloud, later
}

/// A local setup draft contains preferences only. Consent and credentials never belong here.
struct SetupProgress: Codable, Equatable {
    var version = 1
    var step = SetupStep.welcome
    var route: SetupRoute?
    var foregroundAutoRefresh = true
    var completed = false

    var canContinue: Bool { step == .welcome || route != nil }
    mutating func advance() {
        guard canContinue else { return }
        switch step {
        case .welcome: step = .connection
        case .connection: step = .preferences
        case .preferences: break
        }
    }
    mutating func back() {
        switch step {
        case .welcome: break
        case .connection: step = .welcome
        case .preferences: step = .connection
        }
    }
}

enum SetupStore {
    static let key = "firstRunSetup.v1"
    static func load(in defaults: UserDefaults = .standard) -> SetupProgress {
        guard let data = defaults.data(forKey: key), data.count <= 2048,
              let state = try? JSONDecoder().decode(SetupProgress.self, from: data),
              state.step != .preferences || state.route != nil,
              state.version == 1, !state.completed || (state.step == .preferences && state.route != nil)
        else { return SetupProgress(foregroundAutoRefresh: RefreshSettings.foregroundEnabled(in: defaults)) }
        return state
    }
    @discardableResult
    static func save(_ progress: SetupProgress, in defaults: UserDefaults = .standard) -> Bool {
        guard progress.version == 1, progress.step != .preferences || progress.route != nil,
              !progress.completed || (progress.step == .preferences && progress.route != nil),
              let data = try? JSONEncoder().encode(progress), data.count <= 2048 else { return false }
        defaults.set(data, forKey: key)
        return defaults.data(forKey: key) == data
    }
    static func finish(_ draft: SetupProgress, in defaults: UserDefaults = .standard) -> Bool {
        guard draft.step == .preferences, draft.route != nil else { return false }
        var completed = draft
        completed.completed = true
        guard save(completed, in: defaults) else { return false }
        defaults.set(draft.foregroundAutoRefresh, forKey: RefreshSettings.foregroundKey)
        return true
    }
}

func setupText(_ key: String) -> String { DockL10n.text(key, table: "Setup") }
func setupFormat(_ key: String, _ argument: CVarArg) -> String {
    DockL10n.format(key, argument, table: "Setup")
}

struct InterfaceLanguagePicker: View {
    @ObservedObject var settings: InterfaceSettings
    var body: some View {
        Picker(setupText("Language"), selection: Binding(get: { settings.language }, set: { settings.choose($0) })) {
            Text(setupText("Use device language")).tag(DockLanguage.system)
            Text("English").tag(DockLanguage.en)
            Text("한국어").tag(DockLanguage.ko)
        }.accessibilityIdentifier("interface-language")
    }
}

struct FirstRunView: View {
    @ObservedObject var settings: InterfaceSettings
    let revisit: Bool
    let finish: (SetupRoute) -> Void
    let cancel: () -> Void
    @State private var progress: SetupProgress
    @State private var saveFailed = false
    @AccessibilityFocusState private var headingFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(settings: InterfaceSettings, revisit: Bool = false, previewStep: SetupStep? = nil,
         finish: @escaping (SetupRoute) -> Void, cancel: @escaping () -> Void = {}) {
        self.settings = settings
        self.revisit = revisit
        self.finish = finish
        self.cancel = cancel
        var state = SetupStore.load()
        if revisit || state.completed {
            state = SetupProgress(foregroundAutoRefresh: RefreshSettings.foregroundEnabled())
        }
        if let previewStep {
            state.step = previewStep
            state.route = .demo
        }
        _progress = State(initialValue: state)
    }

    private var title: String {
        switch progress.step {
        case .welcome: return setupText("A little clarity before your next prompt.")
        case .connection: return setupText("Choose how to get started.")
        case .preferences: return setupText("Make it work your way.")
        }
    }

    private var previewTypeSize: DynamicTypeSize {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--large-text-preview") { return .accessibility3 }
        #endif
        return dynamicTypeSize
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("QUOTADOCK").font(.caption.weight(.semibold)).tracking(2)
                        Spacer()
                        Text(setupFormat("Step %@ of 3", String(progress.step.index + 1)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(title).font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($headingFocused)
                        .accessibilityIdentifier("setup-heading")
                    switch progress.step {
                    case .welcome: welcome
                    case .connection: connection
                    case .preferences: preferences
                    }
                    if saveFailed {
                        Text(setupText("Could not remember setup on this device. Retry or continue for this session; setup may appear again after restarting."))
                            .font(.callout).foregroundStyle(.orange).accessibilityIdentifier("setup-save-error")
                    }
                }.padding(24).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(DockTheme.background)
            .safeAreaInset(edge: .bottom) { actions }
            .navigationTitle(setupText(revisit ? "Review setup" : "Welcome"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if progress.step != .welcome {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(setupText("Back"), systemImage: "chevron.left") {
                            progress.back(); remember(); headingFocused = true
                        }
                    }
                }
                if revisit {
                    ToolbarItem(placement: .topBarTrailing) { Button(setupText("Cancel"), action: cancel) }
                }
            }
            .onChange(of: progress.route) { _, _ in remember() }
            .onChange(of: progress.foregroundAutoRefresh) { _, _ in remember() }
        }
        .environment(\.locale, settings.locale)
        .environment(\.dynamicTypeSize, previewTypeSize)
        .interactiveDismissDisabled(!revisit)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(setupText("Your AI allowances, together. Keep each account and quota window separate, with the original observation time."))
                .foregroundStyle(.secondary)
            InterfaceLanguagePicker(settings: settings).pickerStyle(.menu)
                .padding(.vertical, 8)
            Divider()
            explanation("laptopcomputer", "Your provider credentials stay on your computer.",
                        "A local CodexBar collector reads supported accounts. QuotaDock receives sanitized usage, not your Claude, OpenAI, Gemini or Grok password.")
            explanation("chart.bar", "Unknown is not zero.",
                        "When a provider cannot report usage, we show Unknown. Reset times are information, not a promise of more quota.")
            Text(setupText("No provider login, payment or system permission is requested during setup."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var connection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(setupText("Nothing connects until you explicitly finish the relevant connection screen. You can change this later."))
                .foregroundStyle(.secondary)
            route(.demo, icon: "play.circle", title: "Explore demo", detail: "See clearly labelled sample data. No account, collector or network connection needed.")
            route(.bridge, icon: "link", title: "Pair my own bridge", detail: "Use a trusted HTTPS bridge and its pairing token. This is not your AI service password.")
            route(.cloud, icon: "icloud", title: "Optional cloud account", detail: "Review the server and two separate consents, then use Sign in with Apple. The server also stores account, session, consent and billing metadata.")
            route(.later, icon: "clock", title: "Connect later", detail: "Open the dashboard without connecting. Existing connections and cached observations are not deleted.")
            Divider().padding(.top, 8)
            explanation("desktopcomputer", "Fresh readings need an online collector.",
                        "A server alone cannot fetch your subscription allowance. Your local computer and supported provider sessions must be available.")
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 24) {
            Toggle(setupText("Refresh when I open the app"), isOn: $progress.foregroundAutoRefresh)
                .accessibilityIdentifier("setup-foreground-refresh")
            Text(setupText("On by default. Turn it off to use the refresh button or pull to refresh. Changing this does not change your collector's background setting or spend a manual refresh allowance."))
                .font(.callout).foregroundStyle(.secondary)
            Divider()
            explanation("rectangle.on.rectangle", "Widgets remember the last reading.",
                        "Add QuotaDock from the Home Screen, Today View or Lock Screen widget gallery after setup. iOS decides when to refresh widgets; exact intervals are not guaranteed.")
            explanation("applewatch", "Watch follows your iPhone.",
                        "Install the companion Watch app, open both apps and refresh on iPhone. Transfers may be delayed. Small surfaces show the first account per provider, not account totals.")
            explanation("lock.shield", "You stay in control.",
                        "Language and setup choices are saved locally. Choosing cloud here is not consent, login or a subscription purchase. You can revisit setup in Settings.")
            if progress.route == .demo {
                Text(setupText("You will open DEMO data, not your account. Demo never overwrites your saved observations."))
                    .font(.callout).foregroundStyle(DockTheme.mint)
            }
        }
    }

    private func explanation(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title3).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(setupText(title)).font(.headline).fixedSize(horizontal: false, vertical: true)
                Text(setupText(detail)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func route(_ value: SetupRoute, icon: String, title: String, detail: String) -> some View {
        Button {
            progress.route = value
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon).font(.title3).frame(width: 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(setupText(title)).font(.headline)
                    Text(setupText(detail)).font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: progress.route == value ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(progress.route == value ? DockTheme.mint : .secondary)
                    .accessibilityHidden(true)
            }.padding(.vertical, 14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(progress.route == value ? [.isSelected] : [])
        .accessibilityIdentifier("setup-route-\(value.rawValue)")
        .overlay(alignment: .bottom) { Divider() }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                if progress.step == .preferences { complete() }
                else { progress.advance(); remember(); headingFocused = true }
            } label: {
                Text(setupText(progress.step == .preferences ? "Finish setup" : "Continue"))
                    .font(.headline).frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent).tint(DockTheme.mint)
            .disabled(!progress.canContinue).accessibilityIdentifier("setup-continue")
            if saveFailed && progress.step == .preferences, let route = progress.route {
                Button(setupText("Continue for this session")) { finish(route) }
                    .accessibilityIdentifier("setup-session-only")
            }
            if progress.step == .welcome {
                Button(setupText("Explore demo without login")) {
                    progress.route = .demo; progress.step = .preferences; remember(); headingFocused = true
                }.accessibilityIdentifier("setup-explore-demo")
            }
        }.padding(.horizontal, 24).padding(.vertical, 12)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
            .background(DockTheme.background)
    }

    private func remember() {
        // A revisited wizard is a draft; Cancel must not reset a completed first run.
        guard !revisit else { return }
        saveFailed = !SetupStore.save(progress)
    }

    private func complete() {
        guard let route = progress.route else { return }
        guard SetupStore.finish(progress) else { saveFailed = true; return }
        finish(route)
    }
}
