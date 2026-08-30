import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Your data stays local", systemImage: "hand.raised.fill")
                        .font(.title2.bold())
                    Text("AW Map Editor is designed to work locally on your Mac. This policy explains what happens when you use the app.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()

                VStack(alignment: .leading, spacing: 18) {
                    PrivacyPolicySection(
                        title: "Data stored on this Mac",
                        systemImage: "internaldrive",
                        text: "Maps and editor preferences are stored locally on this Mac. AW Map Editor does not require an account or cloud sync."
                    )
                    PrivacyPolicySection(
                        title: "Files you choose",
                        systemImage: "doc",
                        text: "The app reads and writes map files only when you choose a location through the standard macOS file panels."
                    )
                    PrivacyPolicySection(
                        title: "No tracking or advertising",
                        systemImage: "eye.slash",
                        text: "AW Map Editor includes no analytics, advertising, or third-party account services."
                    )
                    PrivacyPolicySection(
                        title: "Optional links",
                        systemImage: "safari",
                        text: "The Original Editor link opens your default browser only when you select it; the browser's own privacy practices then apply."
                    )
                }

                Text("Last updated: August 20, 2026")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer()
                    Button("Close") { dismiss() }
                        .buttonStyle(.bordered)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(28)
            .frame(maxWidth: 680, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 440)
    }
}

private struct PrivacyPolicySection: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)
        }
        .labelStyle(.titleAndIcon)
    }
}
