import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var autoCleanup = AutoCleanupSettings.shared
    @State private var apiKey: String = ""
    @State private var savedConfirmation = false
    @State private var isRunningNow = false
    @State private var launchAtLogin = LaunchAtLoginService.isEnabled

    var body: some View {
        Form {
            Section("General") {
                Toggle(isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        if LaunchAtLoginService.setEnabled(newValue) { launchAtLogin = newValue }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at Login")
                        Text("MacMemClean lives in the menu bar (\(Image(systemName: "wind")) icon at the top of the screen) so automatic cleanup checks keep running even with the window closed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Automatic Cleanup") {
                Toggle(isOn: $autoCleanup.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Periodically check for cleanup opportunities")
                        Text("Runs while MacMemClean is open — it never launches itself in the background. Findings always need your approval before anything is deleted.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: autoCleanup.isEnabled) { enabled in
                    if enabled { BackgroundCleanupScheduler.shared.requestNotificationAuthorizationIfNeeded() }
                }

                if autoCleanup.isEnabled {
                    Picker("Check every", selection: $autoCleanup.frequencyDays) {
                        Text("Day").tag(1)
                        Text("3 Days").tag(3)
                        Text("Week").tag(7)
                    }
                    .pickerStyle(.segmented)

                    Picker("Aggressiveness", selection: $autoCleanup.aggressiveness) {
                        ForEach(CleanupAggressiveness.allCases) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(autoCleanup.aggressiveness.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

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

            Section("Permissions") {
                HStack {
                    IconChip(
                        symbolName: appState.permissions.hasFullDiskAccess ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                        tint: appState.permissions.hasFullDiskAccess ? .green : .orange,
                        size: 28
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Full Disk Access")
                            .font(.system(.body, design: .rounded))
                        Text(appState.permissions.hasFullDiskAccess ? "Granted" : "Not granted")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Manage…") {
                        withAnimation { appState.selectedSection = .permissions }
                    }
                }
            }

            Section("Safety Ratings") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Every item found by a scan is rated automatically:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach([SafetyLevel.safe, .caution, .personal], id: \.self) { level in
                        HStack(alignment: .top, spacing: 8) {
                            SafetyBadge(level: level)
                            Text(safetyExplanation(level))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Only \"Safe\" items are ever pre-selected after a scan — you always choose personal or caution items by hand.")
                        .font(.caption.weight(.semibold))
                }
            }

            Section("Deletion") {
                Picker("Default deletion", selection: $appState.deleteMode) {
                    Text("Move to Trash (recommended)").tag(DeleteMode.trash)
                    Text("Delete permanently").tag(DeleteMode.permanent)
                }
                .pickerStyle(.radioGroup)
                Text("This only sets the default toggle in the review screen — every deletion still requires your confirmation there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI Assist (optional)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add an Anthropic API key to enable \"Ask AI what this is\" in the review screen. Only a file's name, path, size and dates are ever sent — never file contents. Stored in the macOS Keychain only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("sk-ant-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Save") {
                            KeychainService.saveAPIKey(apiKey)
                            savedConfirmation = true
                        }
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
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            apiKey = KeychainService.loadAPIKey() ?? ""
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
