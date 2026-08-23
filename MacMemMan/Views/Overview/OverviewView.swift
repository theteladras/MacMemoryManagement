import Charts
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var viewModel = OverviewViewModel.shared
    @ObservedObject private var historyStore = StorageHistoryStore.shared
    @ObservedObject private var deletionHistory = DeletionHistoryStore.shared
    // Observed purely so `recentlyAddedItems` recomputes when any of these finish a background
    // rescan — each already tracks its own scan results in memory, this just reads their most
    // recent items for the "last 24 hours" card instead of doing any scanning of its own.
    @ObservedObject private var junkVM = JunkScanViewModel.shared
    @ObservedObject private var largeOldVM = LargeOldFilesViewModel.shared
    @ObservedObject private var duplicatesVM = DuplicatesViewModel.shared
    @State private var expandedActivityKind: ActivityKind?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroCard
                activityCard

                if let autoManifest = appState.pendingAutoCleanupManifest {
                    autoCleanupBanner(autoManifest)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                trendCard
                byTypeCard
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
        .animation(.easeInOut(duration: 0.3), value: appState.pendingAutoCleanupManifest?.title)
        .task {
            await viewModel.loadSummary()
        }
    }

    // MARK: - Automatic Cleanup approval banner

    private func autoCleanupBanner(_ manifest: ReviewManifest) -> some View {
        HStack {
            IconChip(symbolName: "sparkles", tint: .teal, size: 34, useBrandGradient: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Automatic scan found \(manifest.totalBytes.formattedBytes) you could free up")
                    .font(.system(.callout, design: .rounded).weight(.semibold))
                Text("\(manifest.count) item(s) found by the background scan — nothing has been touched. Review before anything is removed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") { appState.pendingAutoCleanupManifest = nil }
            Button("Review…") {
                appState.requestReview(manifest)
                appState.pendingAutoCleanupManifest = nil
            }
            .buttonStyle(.gradient)
        }
        .cardStyle(padding: 14)
    }

    // MARK: - Storage hero (segmented capacity bar, macOS "About This Mac" style)

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    IconChip(symbolName: "internaldrive.fill", tint: .indigo, size: 26, useBrandGradient: true)
                    Text("Storage")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    InfoButton(text: "How full your disk is and what's using it, sized from Applications, Documents, Desktop, Downloads, Photos/Movies/Music, and System & Library. \"Other\" covers used space outside those folders (hidden system files, other users, etc).")
                }
                Spacer()
                if let staleness = stalenessLabel {
                    Text(staleness)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(viewModel.isLoadingSummary ? .orange : .secondary)
                }
                Button {
                    Task { await viewModel.loadSummary(force: true) }
                } label: {
                    if viewModel.isLoadingSummary {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(viewModel.isLoadingSummary)

                // The full Smart Scan card further down can end up below the fold once the
                // capacity legend (and any drill-down panel) grows tall, so the primary "go clean
                // something" action also lives right here at the very top of the page, always
                // visible without scrolling.
                Button {
                    Task { await runQuickClean() }
                } label: {
                    Label(viewModel.isSmartScanning ? "Cleaning…" : "Quick Clean", systemImage: "bolt.fill")
                }
                .buttonStyle(.gradient)
                .disabled(viewModel.isSmartScanning)
            }

            quickCleanStatus

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(freeHeadline)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .contentTransition(.numericText())
                Text("free")
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if viewModel.summary.totalBytes > 0 {
                    Text("of \(viewModel.summary.totalBytes.formattedBytes)")
                        .font(.system(.callout, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            SegmentedCapacityBar(segments: capacitySegments) { name in
                Task { await viewModel.toggleDrillDown(name) }
            }
            .frame(height: 22)

            if viewModel.isLoadingSummary && viewModel.summary.totalBytes == 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Calculating…").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], spacing: 8) {
                    ForEach(viewModel.summary.breakdown) { category in
                        CapacityLegendRow(
                            color: category.tint,
                            label: category.name,
                            bytes: category.bytes,
                            isSelected: viewModel.drillDownCategory == category.name
                        ) {
                            Task { await viewModel.toggleDrillDown(category.name) }
                        }
                    }
                    if viewModel.summary.otherBytes > 0 {
                        CapacityLegendRow(
                            color: .gray,
                            label: "Other",
                            bytes: viewModel.summary.otherBytes,
                            isSelected: viewModel.drillDownCategory == "Other"
                        ) {
                            Task { await viewModel.toggleDrillDown("Other") }
                        }
                    }
                    CapacityLegendRow(color: .secondary.opacity(0.35), label: "Free", bytes: viewModel.summary.freeBytes)
                }
            }

            if let drillDownCategory = viewModel.drillDownCategory {
                drillDownPanel(drillDownCategory)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoadingSummary)
        .animation(.easeInOut(duration: 0.3), value: viewModel.summary.breakdown.map(\.id))
        .animation(.easeInOut(duration: 0.25), value: viewModel.drillDownCategory)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isSmartScanning)
        .animation(.easeInOut(duration: 0.25), value: viewModel.smartScanItems.count)
    }

    private func drillDownPanel(_ category: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()

            HStack {
                Text("Inside \(category)")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                Spacer()
                Button {
                    Task { await viewModel.toggleDrillDown(category) }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if viewModel.isLoadingDrillDown {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Measuring…").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else if viewModel.drillDownSegments.isEmpty {
                Text("No further breakdown available for \(category).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let total = max(viewModel.drillDownSegments.reduce(0) { $0 + $1.bytes }, 1)
                SegmentedCapacityBar(segments: viewModel.drillDownSegments.map {
                    SegmentedCapacityBar.Segment(id: $0.name, fraction: Double($0.bytes) / Double(total), color: $0.tint)
                }, height: 14)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 10)], spacing: 6) {
                    ForEach(viewModel.drillDownSegments) { item in
                        CapacityLegendRow(color: item.tint, label: item.name, bytes: item.bytes)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// Scans AND lands straight in the Review screen, ready to confirm, in one click — shared by
    /// both the compact button at the top of the page and the full Smart Scan card further down.
    private func runQuickClean() async {
        await viewModel.runSmartScan()
        if !viewModel.smartScanItems.isEmpty {
            // Quick Clean hands over everything it found, unfiltered — so unlike a manifest built
            // from a scan view (where the user already hand-picked what's checked), anything not
            // rated "Safe" must start unchecked here, or a personal photo/video that happened to be
            // a large old Downloads file would be pre-selected for deletion.
            let riskyIDs = Set(viewModel.smartScanItems.filter { $0.safety.level != .safe }.map(\.id))
            appState.requestReview(ReviewManifest(title: "Smart Scan Results", items: viewModel.smartScanItems, preExcludedIDs: riskyIDs, onDeleted: { viewModel.removeFromSmartScanResults($0) }))
        }
    }

    private var freeHeadline: String {
        (viewModel.isLoadingSummary && viewModel.summary.totalBytes == 0) ? "—" : viewModel.summary.freeBytes.formattedBytes
    }

    /// Shown next to the refresh button so old numbers are never mistaken for current ones: while
    /// a refresh is in flight but we still have a previous result on screen, it's explicitly
    /// labeled stale rather than silently showing outdated data as if it were fresh.
    private var stalenessLabel: String? {
        if viewModel.isLoadingSummary && viewModel.summary.totalBytes > 0 {
            return "Stale — updating…"
        }
        guard let lastUpdated = viewModel.lastUpdated else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated " + formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }

    private var capacitySegments: [SegmentedCapacityBar.Segment] {
        let total = max(viewModel.summary.totalBytes, 1)
        var segments = viewModel.summary.breakdown.map {
            SegmentedCapacityBar.Segment(id: $0.name, fraction: Double($0.bytes) / Double(total), color: $0.tint)
        }
        if viewModel.summary.otherBytes > 0 {
            segments.append(SegmentedCapacityBar.Segment(id: "Other", fraction: Double(viewModel.summary.otherBytes) / Double(total), color: .gray))
        }
        return segments
    }

    // MARK: - Activity in the last 24 hours

    private enum ActivityKind: Equatable { case added, removed }
    private static let recentActivityWindow: TimeInterval = 24 * 60 * 60

    /// Reuses whatever's already sitting in memory from sections you've scanned before (Caches &
    /// Junk, Large & Old Files, Duplicates) — never walks the disk on its own to watch for new
    /// files, so this costs nothing extra to compute but can under-count if you haven't opened a
    /// given section recently. Deduplicated by id since the same file can legitimately show up in
    /// more than one of those scans.
    private var recentlyAddedItems: [ScanItem] {
        let cutoff = Date().addingTimeInterval(-Self.recentActivityWindow)
        var seen = Set<String>()
        var result: [ScanItem] = []
        for item in junkVM.items + largeOldVM.allItems + duplicatesVM.groups.flatMap(\.items) {
            guard let modifiedAt = item.modifiedAt, modifiedAt >= cutoff else { continue }
            if seen.insert(item.id).inserted { result.append(item) }
        }
        return result.sorted { ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
    }

    /// Actual deletions recorded through the app in the last 24 hours — a real, complete count
    /// (unlike "New" above, nothing here is approximate).
    private var recentlyRemovedEntries: [DeletionLogEntry] {
        let cutoff = Date().addingTimeInterval(-Self.recentActivityWindow)
        return deletionHistory.entries.filter { $0.date >= cutoff && $0.outcome == .deleted }
    }

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                IconChip(symbolName: "arrow.left.arrow.right.circle.fill", tint: .teal, size: 24)
                Text("Last 24 Hours")
                    .font(.system(.headline, design: .rounded))
                InfoButton(text: "Files with a modification date in the last 24 hours, from sections you've scanned before (Caches & Junk, Large & Old Files, Duplicates), plus everything actually deleted through the app in that same window. This isn't a full-disk watch — \"New\" can under-count if you haven't opened a given section recently; \"Removed\" is always a complete count. Tap either to see which files.")
                Spacer()
            }

            HStack(spacing: 16) {
                activityStat(kind: .added, symbol: "arrow.down.circle.fill", tint: .green, label: "New", count: recentlyAddedItems.count, bytes: recentlyAddedItems.reduce(0) { $0 + $1.sizeBytes })
                Divider().frame(height: 40)
                activityStat(kind: .removed, symbol: "arrow.up.circle.fill", tint: .orange, label: "Removed", count: recentlyRemovedEntries.count, bytes: recentlyRemovedEntries.reduce(Int64(0)) { $0 + $1.sizeBytes })
            }

            if let expandedActivityKind {
                Divider()
                activityFileList(for: expandedActivityKind)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.2), value: expandedActivityKind)
    }

    private func activityStat(kind: ActivityKind, symbol: String, tint: Color, label: String, count: Int, bytes: Int64) -> some View {
        Button {
            expandedActivityKind = (expandedActivityKind == kind) ? nil : kind
        } label: {
            HStack(spacing: 10) {
                IconChip(symbolName: symbol, tint: tint, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text("\(count) \(label)")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                        if count > 0 {
                            Image(systemName: expandedActivityKind == kind ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(bytes > 0 ? bytes.formattedBytes : "—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }

    /// Kept collapsed by default so this card stays small — only appears once you tap a stat above,
    /// and is capped in height so a busy day scrolls in place rather than pushing the rest of the
    /// page down.
    @ViewBuilder
    private func activityFileList(for kind: ActivityKind) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                switch kind {
                case .added:
                    ForEach(recentlyAddedItems) { item in
                        activityFileRow(name: item.displayName, detail: item.category.rawValue, bytes: item.sizeBytes)
                    }
                case .removed:
                    ForEach(recentlyRemovedEntries) { entry in
                        activityFileRow(name: entry.displayName, detail: entry.category.rawValue, bytes: entry.sizeBytes)
                    }
                }
            }
        }
        .frame(maxHeight: 160)
    }

    private func activityFileRow(name: String, detail: String, bytes: Int64) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(bytes.formattedBytes)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Storage over time

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                IconChip(symbolName: "chart.xyaxis.line", tint: .teal, size: 24)
                Text("Storage Over Time")
                    .font(.system(.headline, design: .rounded))
                InfoButton(text: "A snapshot of used space is recorded (at most once an hour) every time Overview loads. Keep using MacMemMan over days and weeks and a real trend will build up here.")
                Spacer()
            }

            if chartableSnapshots.count < 2 {
                Text("Not enough history yet — check back after a few more days of use.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            } else {
                Chart(trendPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Bytes", point.bytes)
                    )
                    .foregroundStyle(by: .value("Series", point.series))
                    .lineStyle(StrokeStyle(lineWidth: point.series == Self.totalSeriesName ? 3 : 1.5, lineCap: .round))
                    // `.linear`, not `.catmullRom` — Charts' spline interpolation has a known
                    // crash on sparse/uneven series (e.g. a series with very few points, or a
                    // sharp value jump right after Full Disk Access newly unlocks a much more
                    // accurate size for a category), which is exactly the shape of data this
                    // chart produces since not every snapshot has every category.
                    .interpolationMethod(.linear)
                }
                .chartForegroundStyleScale(domain: Self.seriesOrder, range: Self.seriesTints)
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let bytes = value.as(Int64.self) {
                                Text(bytes.formattedBytes)
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .cardStyle()
    }

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let series: String
        let bytes: Int64
    }

    private static let totalSeriesName = "Total Used"
    /// Fixed order (rather than derived from a Dictionary) so it lines up 1:1 with `seriesTints` —
    /// matches the same location categories/colors as the capacity bar on this page.
    private static let seriesOrder: [String] = [totalSeriesName, "Applications", "Documents & Desktop", "Downloads", "Photos, Movies & Music", "System & Library", "Other"]
    private static let seriesTints: [Color] = [.primary, .purple, .indigo, .teal, .pink, .orange, .gray]

    /// Snapshots recorded before per-location breakdowns existed have an empty `breakdown`.
    /// Charting them anyway would draw the white "Total Used" line across the full width while
    /// every colored line simply doesn't exist yet for that stretch — which reads as "these don't
    /// add up" even though the underlying numbers are fine. Simplest fix: only chart snapshots
    /// that actually have a breakdown, so every visible line starts at the same point.
    private var chartableSnapshots: [StorageSnapshot] {
        historyStore.snapshots.filter { !$0.breakdown.isEmpty }
    }

    private var trendPoints: [TrendPoint] {
        chartableSnapshots.flatMap { snapshot -> [TrendPoint] in
            var points = [TrendPoint(date: snapshot.date, series: Self.totalSeriesName, bytes: snapshot.usedBytes)]
            points += snapshot.breakdown.map { TrendPoint(date: snapshot.date, series: $0.name, bytes: $0.bytes) }
            return points
        }
    }

    // MARK: - By File Type

    private var byTypeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                IconChip(symbolName: "chart.pie.fill", tint: .blue, size: 24)
                Text("By File Type")
                    .font(.system(.headline, design: .rounded))
                InfoButton(text: "Scans Documents, Desktop, Downloads, Pictures, Movies, Music & Public and groups every file by what it actually is — a photo in Downloads still counts as a photo, not just \"Downloads\". This is a separate on-demand scan, not automatic.")
                Spacer()
                Button {
                    Task { await viewModel.analyzeByType() }
                } label: {
                    Label(viewModel.isAnalyzingTypes ? "Analyzing…" : (viewModel.hasAnalyzedTypes ? "Rescan" : "Analyze"), systemImage: "chart.pie.fill")
                }
                .disabled(viewModel.isAnalyzingTypes)
            }
            Text("So a photo in Downloads still counts as a photo, not just \"Downloads\".")
                .font(.caption)
                .foregroundStyle(.secondary)

            if viewModel.isAnalyzingTypes {
                HStack {
                    ProgressView()
                    Text("Reading files…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 40)
            } else if viewModel.typeBreakdown.isEmpty {
                Text(viewModel.hasAnalyzedTypes ? "No files found in those folders." : "Tap Analyze to break down your content by type.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 28) {
                        donut
                        legend
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Spacer()
                            donut
                            Spacer()
                        }
                        legend
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .cardStyle()
        .animation(.easeInOut(duration: 0.3), value: viewModel.isAnalyzingTypes)
        .animation(.easeInOut(duration: 0.3), value: viewModel.typeBreakdown.map(\.id))
    }

    private var donut: some View {
        DonutChart(segments: viewModel.typeBreakdown.map {
            DonutChart.Segment(id: $0.id, value: Double($0.bytes), color: $0.category.tint)
        })
        .frame(width: 130, height: 130)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(viewModel.typeBreakdown) { usage in
                HStack(spacing: 8) {
                    IconChip(symbolName: usage.category.symbolName, tint: usage.category.tint, size: 20)
                    Text(usage.category.rawValue)
                        .font(.system(.callout, design: .rounded))
                        .lineLimit(1)
                    Text("(\(usage.count))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(usage.bytes.formattedBytes)
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                }
            }
        }
    }

    // MARK: - Quick Clean status (feedback for the button up in the Storage header)

    /// What "Quick Clean" actually runs: the Caches & Junk scan plus a large/old-files pass over
    /// Downloads, combined into one Review — this row is just live feedback for that action, not a
    /// second, differently-named feature. There is exactly one button for it, in the header above.
    @ViewBuilder
    private var quickCleanStatus: some View {
        if viewModel.isSmartScanning {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(viewModel.smartScanStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if !viewModel.smartScanItems.isEmpty {
            let total = viewModel.smartScanItems.reduce(0) { $0 + $1.sizeBytes }
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal).font(.caption)
                Text("Quick Clean found \(viewModel.smartScanItems.count) items — \(total.formattedBytes) reclaimable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Review Again") {
                    let riskyIDs = Set(viewModel.smartScanItems.filter { $0.safety.level != .safe }.map(\.id))
                    appState.requestReview(ReviewManifest(title: "Smart Scan Results", items: viewModel.smartScanItems, preExcludedIDs: riskyIDs, onDeleted: { viewModel.removeFromSmartScanResults($0) }))
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            }
            .transition(.opacity)
        }
    }
}
