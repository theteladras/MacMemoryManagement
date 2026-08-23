import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var autoCleanup = AutoCleanupSettings.shared
    @ObservedObject private var flaggingRules = FlaggingRulesStore.shared
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var apiKey: String = ""
    @State private var savedConfirmation = false
    @State private var isRunningNow = false
    @State private var showingAddRule = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                automaticCleanupCard
                flaggingRulesCard
                duplicateScanLocationsCard
                appBehaviorCard
                safetyRatingsCard
                deletionCard
                aiAssistCard
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
        .onAppear { apiKey = KeychainService.loadAPIKey() ?? "" }
        .sheet(isPresented: $showingAddRule) { AddFlaggingRuleSheet() }
    }

    // MARK: - Automatic Cleanup

    private var automaticCleanupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(symbolName: "clock.badge.checkmark.fill", tint: .teal, title: "Automatic Cleanup")

            Toggle(isOn: $autoCleanup.isEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Periodically check for cleanup opportunities")
                        .font(.system(.body, design: .rounded))
                    Text("Runs while MacMemClean is open — it never launches itself in the background. Findings always need your approval before anything is deleted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .onChange(of: autoCleanup.isEnabled) { enabled in
                if enabled { BackgroundCleanupScheduler.shared.requestNotificationAuthorizationIfNeeded() }
            }

            if autoCleanup.isEnabled {
                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("CHECK EVERY").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
                    Picker("", selection: $autoCleanup.frequencyDays) {
                        Text("Day").tag(1)
                        Text("3 Days").tag(3)
                        Text("Week").tag(7)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("AGGRESSIVENESS").font(.caption2.weight(.bold)).foregroundStyle(.secondary).tracking(0.5)
                    Picker("", selection: $autoCleanup.aggressiveness) {
                        ForEach(CleanupAggressiveness.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text(autoCleanup.aggressiveness.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $autoCleanup.autoEmptyTrash) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatically empty old Trash items")
                                .font(.system(.body, design: .rounded))
                            Text("Deleted directly during each check — no review step, since putting something in the Trash already means you decided to remove it. Still logged in History.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)

                    if autoCleanup.autoEmptyTrash {
                        HStack {
                            Text("Older than").foregroundStyle(.secondary)
                            Stepper("\(autoCleanup.trashAgeThresholdDays) days", value: $autoCleanup.trashAgeThresholdDays, in: 1...180)
                                .font(.system(.callout, design: .rounded).weight(.semibold))
                        }
                        .font(.callout)
                    }
                }

                HStack {
                    if let last = autoCleanup.lastRunDate {
                        Text("Last checked \(last, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never checked yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(isRunningNow ? "Checking…" : "Run Now") {
                        Task {
                            isRunningNow = true
                            await BackgroundCleanupScheduler.shared.checkAndRunIfDue(force: true)
                            isRunningNow = false
                        }
                    }
                    .disabled(isRunningNow)
                }
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: autoCleanup.isEnabled)
    }

    // MARK: - Flagging Rules

    private var flaggingRulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconChip(symbolName: "flag.fill", tint: .yellow, size: 28)
                Text("Custom Flagging Rules")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                InfoButton(text: "Override what the safety assessor decides for matching items. \"Never Delete\" always shows the item for review but never pre-selects it, even if it would otherwise be marked safe. \"Treat as Junk\" pre-selects it as safe to remove, even outside the usual cache/log locations. Rules apply everywhere in the app, immediately.")
                Spacer()
                Button {
                    showingAddRule = true
                } label: {
                    Label("Add Rule", systemImage: "plus")
                }
            }

            if flaggingRules.rules.isEmpty {
                Text("No custom rules yet. Add one to always protect or always flag files by name pattern, file type, or exact path.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            } else {
                VStack(spacing: 8) {
                    ForEach(flaggingRules.rules) { rule in
                        flaggingRuleRow(rule)
                    }
                }
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: flaggingRules.rules)
    }

    private func flaggingRuleRow(_ rule: FlaggingRule) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { flaggingRules.setEnabled(rule.id, $0) }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Label(rule.treatment.label, systemImage: rule.treatment.symbolName)
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(rule.treatment.tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(rule.treatment.tint.opacity(0.12), in: Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(rule.pattern)
                    .font(.system(.callout, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rule.matchType.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                flaggingRules.remove(rule.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .opacity(rule.isEnabled ? 1 : 0.5)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Duplicate Scan Locations

    private var duplicateScanLocationsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconChip(symbolName: "doc.on.doc.fill", tint: .yellow, size: 28)
                Text("Duplicate Scan Locations")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                InfoButton(text: "Which folders the Duplicates scan compares files across. Defaults to Downloads, Documents & Desktop — add or remove folders to match where you actually keep things, like an external drive or a Projects folder.")
                Spacer()
                Button {
                    chooseDuplicateScanFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
            }

            if appSettings.duplicateScanRoots.isEmpty {
                Text("No folders configured — Duplicates won't find anything until you add at least one.")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else {
                VStack(spacing: 6) {
                    ForEach(appSettings.duplicateScanRoots, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(systemName: "folder.fill").foregroundStyle(.yellow)
                            Text(url.path)
                                .font(.system(.callout, design: .rounded))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                appSettings.removeDuplicateScanRoot(url)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                if appSettings.duplicateScanRoots != AppSettings.defaultDuplicateScanRoots {
                    Button("Reset to Defaults") { appSettings.resetDuplicateScanRoots() }
                        .font(.caption)
                }
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: appSettings.duplicateScanRoots)
    }

    private func chooseDuplicateScanFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls { appSettings.addDuplicateScanRoot(url) }
        }
    }

    // MARK: - App Behavior

    private var appBehaviorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader(symbolName: "gearshape.2.fill", tint: .indigo, title: "App Behavior")

            Toggle(isOn: $appSettings.menuBarOnlyMode) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Menu bar only")
                        .font(.system(.body, design: .rounded))
                    Text("Hides the Dock icon — MacMemClean lives purely in the menu bar (\(Image(systemName: "wind"))). Reopen the window anytime from the menu bar dropdown's \"Open MacMemClean\".")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Keep history for").font(.system(.body, design: .rounded))
                    Spacer()
                    Stepper("\(appSettings.historyRetentionDays) days", value: $appSettings.historyRetentionDays, in: 7...365, step: 7)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .fixedSize()
                        .onChange(of: appSettings.historyRetentionDays) { _ in
                            DeletionHistoryStore.shared.applyRetentionNow()
                            StorageHistoryStore.shared.applyRetentionNow()
                        }
                }
                Text("Applies to both the Deletion History log and the storage trend chart on Overview — entries older than this are trimmed automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .cardStyle()
    }

    // MARK: - Safety Ratings

    private var safetyRatingsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(symbolName: "checkmark.shield.fill", tint: .green, title: "Safety Ratings")

            Text("Every item found by a scan is rated automatically:")
                .font(.callout)
                .foregroundStyle(.secondary)
            ForEach([SafetyLevel.safe, .caution, .personal], id: \.self) { level in
                HStack(alignment: .top, spacing: 8) {
                    SafetyBadge(level: level)
                    Text(safetyExplanation(level))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Only \"Safe\" items are ever pre-selected after a scan — you always choose personal or caution items by hand.")
                .font(.callout.weight(.semibold))
        }
        .cardStyle()
    }

    // MARK: - Deletion

    private var deletionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(symbolName: "trash.fill", tint: .red, title: "Deletion")

            Picker("", selection: $appState.deleteMode) {
                Text("Move to Trash (recommended)").tag(DeleteMode.trash)
                Text("Delete permanently").tag(DeleteMode.permanent)
            }
            .labelsHidden()
            .pickerStyle(.radioGroup)
            Text("This only sets the default toggle in the review screen — every deletion still requires your confirmation there.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    // MARK: - AI Assist

    private var aiAssistCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            cardHeader(symbolName: "sparkles", tint: .purple, title: "AI Assist", useBrandGradient: true)

            Text("Add an Anthropic API key to enable the AI Assist buttons throughout the app — explaining files, summarizing scans, and suggesting what's safe to clean up. Only metadata (name, path, size, dates) is ever sent — never file contents. Stored in the macOS Keychain only.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Link(destination: URL(string: "https://console.anthropic.com/settings/keys")!) {
                Label("Get an API key at console.anthropic.com", systemImage: "arrow.up.forward.app")
            }
            .font(.callout)

            SecureField("sk-ant-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Save") {
                    KeychainService.saveAPIKey(apiKey)
                    savedConfirmation = true
                }
                .buttonStyle(.gradient)
                .disabled(apiKey.isEmpty)

                if AIAssistService.isAvailable {
                    Button("Remove Key", role: .destructive) {
                        KeychainService.clearAPIKey()
                        apiKey = ""
                    }
                }

                if savedConfirmation {
                    Label("Saved", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Shared

    private func cardHeader(symbolName: String, tint: Color, title: String, useBrandGradient: Bool = false) -> some View {
        HStack(spacing: 10) {
            IconChip(symbolName: symbolName, tint: tint, size: 28, useBrandGradient: useBrandGradient)
            Text(title).font(.system(.title3, design: .rounded).weight(.bold))
            Spacer()
        }
    }

    private func safetyExplanation(_ level: SafetyLevel) -> String {
        switch level {
        case .safe: return "Caches, logs, and build artifacts the system or an app will regenerate on its own."
        case .caution: return "Large/old files, app leftovers, or duplicates that are probably fine to remove — worth a quick glance."
        case .personal: return "Photos, videos, audio, or documents that may be irreplaceable — always requires your explicit selection."
        }
    }
}
