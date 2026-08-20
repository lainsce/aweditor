import SwiftUI

struct StatusBarView: View {
    let name: String
    let author: String
    let coordinates: String
    let isDirty: Bool

    var body: some View {
        HStack(spacing: 12) {
            Label {
                Text("\(name) (by \(author))")
                    .lineLimit(1)
            } icon: {
                Image(systemName: "map")
            }
            if isDirty {
                Text("Edited")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Unsaved changes")
            }
            Spacer(minLength: 8)
            Text(coordinates)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Map coordinates \(coordinates)")
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(minWidth: 285, idealWidth: 310, maxWidth: 360)
    }
}
