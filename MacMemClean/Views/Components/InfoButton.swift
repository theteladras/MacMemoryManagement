import SwiftUI

/// A small "what is this" affordance for section/card headers — tap to reveal a short explanation
/// in a popover instead of assuming every icon and label is self-explanatory.
struct InfoButton: View {
    let text: String
    var tint: Color = .secondary
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.callout)
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowing, arrowEdge: .top) {
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(14)
        }
        .help(text)
    }
}
