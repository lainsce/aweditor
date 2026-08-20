import SwiftUI

struct GLWNTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 36, alignment: .leading)
            .modifier(GLWNInsetFieldChrome())
    }
}

