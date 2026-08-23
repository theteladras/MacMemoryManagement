import SwiftUI

/// The single mandatory confirmation screen every deletion in the app passes through.
/// Shows exactly what will be removed, grouped and itemized, before anything happens — including
/// a per-item safety read (safe / caution / personal) so photos, documents, and other personal
/// files never blend into "junk" just because they showed up in a scan.
struct ReviewSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State var manifest: ReviewManifest
    @State private var excludedIDs: Set<String> = []
    @State private var permanentDelete = false
    @State private var acknowledgedPersonal = false
    @State private var isDeleting = false
    @State private var result: DeleteResult?
    @State private var aiExplanation: [String: String] = [:]
    @State private var aiLoadingID: String?
    @State private var showingKeySetupFor: ScanItem?

    private var itemsToDelete: [ScanItem] {
        manifest.items.filter { !excludedIDs.contains($0.id) }
    }
    private var totalBytes: Int64 { itemsToDelete.reduce(0) { $0 + $1.sizeBytes } }
    private var personalItemsIncluded: [ScanItem] { itemsToDelete.filter { $0.safety.level == .personal } }
    private var needsAcknowledgment: Bool { !personalItemsIncluded.isEmpty && !acknowledgedPersonal }

    var body: some View {
        VStack(spacing: 0) {
            header

            if let result {
                resultSummary(result)
            } else {
                if manifest.requiresAdmin {
                    adminWarningBanner
                }
                if !personalItemsIncluded.isEmpty {
                    personalWarningBanner
                }
                itemList
                footer
            }
        }
        .frame(width: 660, height: 600)
        .task {
            permanentDelete = appState.deleteMode == .permanent
            excludedIDs = manifest.preExcludedIDs
        }
        .sheet(item: $showingKeySetupFor) { item in
            AIKeySetupSheet(onSaved: { Task { await explain(item) } })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                IconChip(symbolName: "checklist", tint: .indigo, size: 30)
                Text(manifest.title)
                    .font(.system(.title2, design: .rounded).weight(.bold))
            }
            Text("Review exactly what will be removed. Nothing is deleted until you confirm.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private var adminWarningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.2.badge.gearshape")
                .foregroundStyle(.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("These files belong to another user account")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text("Removing them needs your admin password. \"Move to Trash\" here moves each item into that account's own Trash (they can still recover it); \"Delete Permanently\" removes it immediately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
    }

    private var personalWarningBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(personalItemsIncluded.count) item(s) look personal")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text("These were flagged as photos, videos, or documents that may not exist anywhere else — they're included in your selection below. Double-check them before confirming.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
    }

    private var itemList: some View {
        List {
            ForEach(manifest.groupedByCategory, id: \.category) { group in
                Section {
                    ForEach(group.items) { item in
                        itemRow(item)
                    }
                } header: {
                    SectionHeaderBar(title: group.category.rawValue, symbolName: group.category.symbolName, tint: group.category.tint, items: group.items)
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func itemRow(_ item: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { !excludedIDs.contains(item.id) },
                    set: { include in
                        if include { excludedIDs.remove(item.id) } else { excludedIDs.insert(item.id) }
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(item.displayName).lineLimit(1).font(.system(.body, design: .rounded))
                        SafetyBadge(level: item.safety.level)
                    }
                    Text(item.path.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button {
                    if AIAssistService.isAvailable {
                        Task { await explain(item) }
                    } else {
                        showingKeySetupFor = item
                    }
                } label: {
                    if aiLoadingID == item.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(aiLoadingID == item.id)
                .help("Ask AI what this is")

                SizeBadge(bytes: item.sizeBytes, tint: item.category.tint)
            }

            SafetyReasonLabel(assessment: item.safety)
                .padding(.leading, 32)

            if let explanation = aiExplanation[item.id] {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(Color.gray.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.leading, 32)
            }
        }
        .opacity(excludedIDs.contains(item.id) ? 0.5 : 1)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()

            if !personalItemsIncluded.isEmpty {
                Toggle(isOn: $acknowledgedPersonal) {
                    Text("I've reviewed the personal item(s) above and still want to remove them.")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("HOW SHOULD THIS BE REMOVED?")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Picker("", selection: $permanentDelete) {
                    Label("Move to Trash", systemImage: "trash").tag(false)
                    Label("Delete Permanently", systemImage: "trash.slash").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
            }

            if permanentDelete {
                Label("Permanently deleted files cannot be recovered — they won't go through the Trash.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            } else {
                Label("Moved to the Trash — you can still recover these until you empty it.", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("\(itemsToDelete.count) items · \(totalBytes.formattedBytes) will be freed")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(permanentDelete ? "Delete Permanently" : "Move to Trash") {
                    Task { await performDelete() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.gradient(permanentDelete ? Design.dangerGradient : Design.brandGradient))
                .controlSize(.large)
                .disabled(itemsToDelete.isEmpty || isDeleting || needsAcknowledgment)
            }
        }
        .padding()
    }

    private func resultSummary(_ result: DeleteResult) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)
            Text("\(result.freedBytes.formattedBytes) freed")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("\(result.succeeded) items removed" + (result.failed.isEmpty ? "" : ", \(result.failed.count) skipped"))
                .foregroundStyle(.secondary)

            if !result.failed.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(result.failed, id: \.item.id) { failure in
                            Text("\(failure.item.displayName): \(failure.error)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }

            Button("Done") { dismiss() }
                .buttonStyle(.gradient)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func performDelete() async {
        isDeleting = true
        defer { isDeleting = false }
        let mode: DeleteMode = permanentDelete ? .permanent : .trash
        let outcome = manifest.requiresAdmin
            ? await AdminDeleteService.delete(itemsToDelete, mode: mode)
            : await SafeDeleteService.delete(itemsToDelete, mode: mode)
        result = outcome
        DeletionHistoryStore.shared.record(operationTitle: manifest.title, mode: mode, result: outcome)
        if !outcome.successes.isEmpty {
            manifest.onDeleted?(outcome.successes.map(\.item))
        }
    }

    private func explain(_ item: ScanItem) async {
        aiLoadingID = item.id
        defer { aiLoadingID = nil }
        do {
            aiExplanation[item.id] = try await AIAssistService.explain(item: item)
        } catch {
            aiExplanation[item.id] = error.localizedDescription
        }
    }
}
