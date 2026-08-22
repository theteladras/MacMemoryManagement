import SwiftUI

/// A single selectable scan result row, reused across the junk/large-files/duplicates views.
struct ScanItemRow: View {
    let item: ScanItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                .toggleStyle(.checkbox)

            IconChip(symbolName: item.category.symbolName, tint: item.category.tint, size: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .font(.system(.body, design: .rounded).weight(.medium))
                        .lineLimit(1)
                    SafetyBadge(level: item.safety.level)
                }
                Text(item.path.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(item.reason)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .frame(maxWidth: 140, alignment: .trailing)

            SizeBadge(bytes: item.sizeBytes, tint: item.category.tint)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .help(item.safety.reason)
    }
}
