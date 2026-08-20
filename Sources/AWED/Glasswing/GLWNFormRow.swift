import SwiftUI

struct GLWNFormRow<Control: View>: View {
    private let title: LocalizedStringKey
    private let control: Control

    init(_ title: LocalizedStringKey, @ViewBuilder control: () -> Control) {
        self.title = title
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .trailing)
                .padding(.top, 8)
            control.frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

