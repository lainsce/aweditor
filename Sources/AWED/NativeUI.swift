import SwiftUI

struct NativeToolbarIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.primary)
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
    }
}

/// Native control helpers for the editor. They preserve the existing layout
/// contracts while letting SwiftUI/AppKit supply the control chrome.
struct NativeToolbarControlGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .frame(minHeight: 38, maxHeight: 38)
        .buttonStyle(.borderless)
    }
}

struct NativeToolbarMenuButton<MenuContent: View>: View {
    let title: LocalizedStringKey
    let systemImage: String
    private let menuContent: () -> MenuContent

    init(
        _ title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.title = title
        self.systemImage = systemImage
        self.menuContent = menuContent
    }

    init(
        title: LocalizedStringKey,
        systemImage: String,
        @ViewBuilder menuContent: @escaping () -> MenuContent
    ) {
        self.init(title, systemImage: systemImage, menuContent: menuContent)
    }

    var body: some View {
        Menu {
            menuContent()
        } label: {
            NativeToolbarIcon(systemImage: systemImage)
                .frame(width: 38, height: 38)
        }
        .menuStyle(.borderlessButton)
        .help(Text(title))
        .accessibilityLabel(Text(title))
    }
}

struct NativeFormRow<Control: View>: View {
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
            control
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NativeSliderField: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double
    let tint: Color
    let onEditingChanged: (Bool) -> Void

    init(
        value: Binding<Double>,
        in bounds: ClosedRange<Double>,
        step: Double,
        tint: Color = Color("AccentColor"),
        onEditingChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self._value = value
        self.bounds = bounds
        self.step = step
        self.tint = tint
        self.onEditingChanged = onEditingChanged
    }

    var body: some View {
        Slider(value: $value, in: bounds, step: step, onEditingChanged: onEditingChanged)
            .tint(tint)
            .controlSize(.small)
            .frame(minHeight: 36)
    }
}

struct NativePullDownMenu<Selection: Hashable, ItemLabel: View>: View {
    private let title: LocalizedStringKey
    @Binding private var selection: Selection
    private let options: [Selection]
    private let label: (Selection) -> ItemLabel
    private let showsTitle: Bool

    init(
        _ title: LocalizedStringKey,
        selection: Binding<Selection>,
        options: [Selection],
        showsTitle: Bool = true,
        label: @escaping (Selection) -> ItemLabel
    ) {
        self.title = title
        self._selection = selection
        self.options = options
        self.showsTitle = showsTitle
        self.label = label
    }

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                Button {
                    selection = option
                } label: {
                    label(option)
                }
                .accessibilityAddTraits(option == selection ? .isSelected : [])
            }
        } label: {
            HStack(spacing: 8) {
                if showsTitle {
                    Text(title)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                }
                label(selection)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 36, alignment: .leading)
        }
        .menuStyle(.button)
        .accessibilityLabel(Text(title))
        .fixedSize(horizontal: true, vertical: false)
    }
}

struct NativeSegmentedPicker<Selection: Hashable, ItemLabel: View>: View {
    @Binding private var selection: Selection
    private let options: [Selection]
    private let label: (Selection) -> ItemLabel

    init(
        selection: Binding<Selection>,
        options: [Selection],
        label: @escaping (Selection) -> ItemLabel
    ) {
        self._selection = selection
        self.options = options
        self.label = label
    }

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(options.indices, id: \.self) { index in
                label(options[index])
                    .tag(options[index])
            }
        }
        .labelsHidden()
        .pickerStyle(.tabs)
    }
}

@MainActor
extension Binding where Value: LosslessStringConvertible {
    var nativeStringValue: Binding<String> {
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

struct NativeTextFieldStepper<Value>: View
where Value: Strideable & LosslessStringConvertible {
    @Binding var value: Value
    let range: ClosedRange<Value>
    let step: Value.Stride

    init(value: Binding<Value>, in range: ClosedRange<Value>, step: Value.Stride) {
        self._value = value
        self.range = range
        self.step = step
    }

    var body: some View {
        HStack(spacing: 4) {
            TextField(" ", text: $value.nativeStringValue)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 50)

            NativeToolbarControlGroup {
                Stepper("Adjust value", value: $value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(height: 34)
            }
        }
    }
}
