import SwiftUI

/// Lets an admin free up space sitting in other local accounts' Caches/Logs/Trash — never
/// Documents/Desktop/Pictures or anything else that might hold someone else's irreplaceable
/// files. Every scan and every deletion here costs a real macOS admin-password prompt
/// (`AdminShellService`); nothing about this screen runs silently in the background.
struct MultiUserView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var viewModel = MultiUserViewModel.shared

    var body: some View {
        HSplitView {
            accountListColumn
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            detailColumn
                .frame(minWidth: 380, maxWidth: .infinity)
        }
        .navigationTitle("Other Users")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                InfoButton(text: "Shows other local accounts on this Mac and lets you clean up their Caches, Logs, and Trash — never Documents, Desktop, Photos, or anything else that could hold someone's irreplaceable files. Every scan and cleanup here requires an admin password, since this app can't otherwise read into another account's home folder.")
            }
        }
        .task {
            if !viewModel.hasLoadedAccounts { viewModel.loadAccounts() }
        }
    }

    private var accountListColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.accounts.count) other account(s)")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task { await viewModel.loadSizes() }
                } label: {
                    if viewModel.isLoadingSizes {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Check Sizes", systemImage: "internaldrive")
                    }
                }
                .disabled(viewModel.accounts.isEmpty || viewModel.isLoadingSizes)
            }
            .padding()

            if viewModel.accounts.isEmpty {
                EmptyStateView(symbolName: "person.2", title: "No Other Accounts", message: "This Mac only has your account on it.")
            } else {
                List(viewModel.accounts, selection: Binding(
                    get: { viewModel.selectedAccount?.id },
                    set: { id in
                        if let account = viewModel.accounts.first(where: { $0.id == id }) {
                            Task { await viewModel.scanJunk(for: account) }
                        }
                    }
                )) { account in
                    HStack(spacing: 10) {
                        IconChip(symbolName: "person.crop.circle.fill", tint: .red, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.fullName).font(.system(.body, design: .rounded)).lineLimit(1)
                            Text(account.homeDirectory.path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        if let size = viewModel.accountSizes[account.username] {
                            Text(size.formattedBytes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                    .tag(account.id)
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }

            if let error = viewModel.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let account = viewModel.selectedAccount {
            if viewModel.isScanning {
                ProgressView("Scanning \(account.fullName)'s Caches, Logs & Trash…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                EmptyStateView(symbolName: "checkmark.circle", title: "Nothing Found", message: "No cache, log, or trash items found for \(account.fullName).")
            } else {
                junkList(for: account)
            }
        } else {
            EmptyStateView(
                symbolName: "person.2.badge.gearshape",
                title: "Clean Up Other Accounts",
                message: "Select an account on the left to scan its Caches, Logs, and Trash. Requires an admin password — this app can't otherwise read into another account's home folder."
            )
        }
    }

    private func junkList(for account: OtherUserAccount) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(viewModel.items.count) items · \(viewModel.items.reduce(Int64(0)) { $0 + $1.sizeBytes }.formattedBytes)")
                    .font(.system(.callout, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Select All") { viewModel.selectAll() }
                Button("Select None") { viewModel.selectNone() }
                Button {
                    Task { await viewModel.scanJunk(for: account) }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
            }
            .padding()

            if let change = viewModel.lastChange {
                ScanChangeBanner(change: change) { viewModel.lastChange = nil }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            List {
                ForEach(viewModel.items) { item in
                    ScanItemRow(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                        viewModel.toggle(item)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(viewModel.selectedItems.count) selected")
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                    Text(viewModel.selectedBytes.formattedBytes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review & Clean…") {
                    appState.requestReview(ReviewManifest(title: "Clean \(account.fullName)'s Files", items: viewModel.selectedItems, requiresAdmin: true, onDeleted: { viewModel.removeFromResults($0) }))
                }
                .buttonStyle(.gradient(Design.dangerGradient))
                .controlSize(.large)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding()
        }
    }
}
