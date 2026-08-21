import SwiftUI

@MainActor
extension Binding where Value: LosslessStringConvertible {
    var glwnStringValue: Binding<String> {
        Binding<String>(
            get: {
                let description = "\(wrappedValue)"
                return description.hasSuffix(".0")
                    ? String(description.dropLast(2))
                    : description
            },
            set: { newValue in
                wrappedValue = Value(newValue) ?? wrappedValue
            }
        )
    }
}

/// The Glasswing numeric control used wherever a value can be stepped.
/// Keep the text entry and the native increment/decrement affordance together
/// so keyboard editing and precise mouse adjustments share one control.
struct GLWNTextFieldStepper<Value>: View
where Value: Strideable & LosslessStringConvertible {
    @Binding var value: Value

    let range: ClosedRange<Value>
    let step: Value.Stride

    init(
        value: Binding<Value>,
        in range: ClosedRange<Value>,
        step: Value.Stride
    ) {
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(" ", text: $value.glwnStringValue)
                .textFieldStyle(GLWNTextFieldStyle())
                .monospacedDigit()
                .frame(width: 50)

            GLWNToolbarControlGroup {
                Stepper(
                    "Adjust value",
                    value: $value,
                    in: range,
                    step: step
                )
                .labelsHidden()
                .controlSize(.small)
                .frame(height: 34)
            }
        }
    }
}

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
