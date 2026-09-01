import SwiftUI
struct NativeToggleStyle: ToggleStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        Button {
            if reduceMotion {
                configuration.isOn.toggle()
            } else {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.86, blendDuration: 0.05)) {
                    configuration.isOn.toggle()
                }
            }
        } label: {
            HStack(spacing: 8) {
                configuration.label
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(
                            configuration.isOn
                                ? Color("AccentColor")
                                : Color.primary.opacity(0.045)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(.white)
                        .overlay {
                            RoundedRectangle(cornerRadius: 999, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        }
                        .frame(width: 24, height: 24)
                        .padding(4)
                }
                .frame(width: 48, height: 32)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.86, blendDuration: 0.05),
                    value: configuration.isOn
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityRemoveTraits(.isButton)
        .accessibilityAddTraits(.isToggle)
    }
}
struct NativeToolbarIcon: View {
    let systemImage: String
    let foregroundColor: Color
    init(systemImage: String, foregroundColor: Color = .primary) {
        self.systemImage = systemImage
        self.foregroundColor = foregroundColor
    }
    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(foregroundColor)
            .frame(width: 38, height: 38)
            .accessibilityHidden(true)
            .awedWindowActivityAppearance()
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
        HStack(alignment: .center, spacing: 0) {
            content
        }
        .frame(minHeight: 38, maxHeight: 38, alignment: .center)
        .buttonStyle(.borderless)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(.windowBackground)
        }
        .awedWindowActivityAppearance()
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
        }
        .menuStyle(.borderlessButton)
        .frame(width: 38, height: 38)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(.windowBackground)
        }
        .help(Text(title))
        .accessibilityLabel(Text(title))
        .awedWindowActivityAppearance()
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
        HStack(alignment: .center, spacing: 14) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .topTrailing)
            control
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}
struct NativeSliderField: View {
    @Binding var value: Double
    let bounds: ClosedRange<Double>
    let step: Double
    let tint: Color
    let onEditingChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var dragProgress: CGFloat?
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
        // Keep AppKit's slider continuous and snap the binding ourselves.
        // Passing a fine-grained step to the native control makes its
        // tick marks collapse together instead of forming a readable
        // scale, while this preserves the requested editing increment.
        GeometryReader { proxy in
            let horizontalInset: CGFloat = 8
            let usableWidth = max(proxy.size.width - (horizontalInset * 2), 1)
            let trackY = proxy.size.height / 2
            let displayedProgress = dragProgress ?? progress(for: value)
            ZStack(alignment: .topLeading) {
                // Keep the native control in the accessibility tree and use it
                // as the semantic value source. Its AppKit chrome is fully
                // transparent; the custom gesture below owns pointer input so
                // AppKit cannot reveal a second track while dragging.
                Slider(value: snappedValue, in: bounds, onEditingChanged: onEditingChanged)
                    .controlSize(.small)
                    .opacity(0)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(isEnabled ? 0.12 : 0.06))
                    .frame(width: usableWidth, height: 5)
                    .offset(x: horizontalInset, y: trackY - 2.5)
                    .allowsHitTesting(false)
                if displayedProgress > 0 {
                    Capsule(style: .continuous)
                        .fill(tint.opacity(isEnabled ? 1 : 0.33))
                        .frame(width: max(usableWidth * displayedProgress, 1), height: 5)
                        .offset(x: horizontalInset, y: trackY - 2.5)
                        .allowsHitTesting(false)
                }
                NativeSliderStepLine(
                    bounds: bounds,
                    step: step,
                    width: proxy.size.width,
                    height: proxy.size.height,
                    lineY: trackY + 8
                )
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.white.opacity(isEnabled ? 1 : 0.33))
                    .overlay {
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .strokeBorder(Color.primary.opacity(isEnabled ? 0.12 : 0.06), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(isEnabled ? 0.12 : 0.06), radius: 2, y: 1)
                    .frame(width: 24, height: 24)
                    .position(
                        x: horizontalInset + usableWidth * displayedProgress,
                        y: trackY
                    )
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let nextProgress = progress(for: gesture.location.x, width: proxy.size.width)
                        if dragProgress == nil {
                            onEditingChanged(true)
                        }
                        dragProgress = nextProgress
                        value = snappedValue(for: nextProgress)
                    }
                    .onEnded { _ in
                        dragProgress = nil
                        onEditingChanged(false)
                    }
            )
        }
        .frame(maxWidth: .infinity, minHeight: 36)
    }
    private func progress(for value: Double) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        return min(max(CGFloat((value - bounds.lowerBound) / span), 0), 1)
    }
    private func progress(for locationX: CGFloat, width: CGFloat) -> CGFloat {
        let horizontalInset: CGFloat = 8
        let usableWidth = max(width - (horizontalInset * 2), 1)
        return min(max((locationX - horizontalInset) / usableWidth, 0), 1)
    }
    private func snappedValue(for progress: CGFloat) -> Double {
        let proposedValue = bounds.lowerBound + Double(progress) * (bounds.upperBound - bounds.lowerBound)
        let clampedValue = min(max(proposedValue, bounds.lowerBound), bounds.upperBound)
        guard step > 0 else { return clampedValue }
        let stepIndex = ((clampedValue - bounds.lowerBound) / step).rounded()
        let snapped = bounds.lowerBound + stepIndex * step
        return min(max(snapped, bounds.lowerBound), bounds.upperBound)
    }
    private var snappedValue: Binding<Double> {
        Binding(
            get: { value },
            set: { proposedValue in
                let clampedValue = min(max(proposedValue, bounds.lowerBound), bounds.upperBound)
                guard step > 0 else {
                    value = clampedValue
                    return
                }
                let stepIndex = ((clampedValue - bounds.lowerBound) / step).rounded()
                let snapped = bounds.lowerBound + stepIndex * step
                value = min(max(snapped, bounds.lowerBound), bounds.upperBound)
            }
        )
    }
}
private struct NativeSliderStepLine: View {
    let bounds: ClosedRange<Double>
    let step: Double
    let width: CGFloat
    let height: CGFloat
    let lineY: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let horizontalInset: CGFloat = 8
        let usableWidth = max(width - (horizontalInset * 2), 1)
        let ticks = displayedTicks
        ZStack(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.26 : 0.18))
                .frame(width: usableWidth, height: 1)
                .offset(x: horizontalInset, y: lineY)
            ForEach(Array(ticks.enumerated()), id: \.offset) { index, tick in
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.38 : 0.28))
                    .frame(
                        width: 1,
                        height: isMajorTick(index: index, count: ticks.count) ? 8 : 4
                    )
                    .position(
                        x: horizontalInset + usableWidth * progress(for: tick),
                        y: lineY
                    )
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
    /// Keep the visual scale compact even when the editing step is small.
    /// Every requested increment remains available through the binding above.
    private var displayedTicks: [Double] {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return [bounds.lowerBound] }
        let targetTickCount = 9.0
        let rawInterval = span / (targetTickCount - 1)
        let stepSize = max(step, 0.000001)
        let stepCount = max(1, Int(ceil(rawInterval / stepSize)))
        let interval = Double(stepCount) * stepSize
        var ticks = [bounds.lowerBound]
        var cursor = bounds.lowerBound + interval
        while cursor < bounds.upperBound - (interval * 0.25) {
            ticks.append(cursor)
            cursor += interval
        }
        if ticks.last != bounds.upperBound {
            ticks.append(bounds.upperBound)
        }
        return ticks
    }
    private func progress(for value: Double) -> CGFloat {
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        return CGFloat((value - bounds.lowerBound) / span)
    }
    private func isMajorTick(index: Int, count: Int) -> Bool {
        index == 0 || index == count - 1 || index.isMultiple(of: 2)
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
        .pickerStyle(.segmented)
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
        HStack(alignment: .center, spacing: 0) {
            TextField(" ", text: $value.nativeStringValue)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .frame(width: 50, height: 34, alignment: .center)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Stepper("Adjust value", value: $value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(x: -8, y: 12)
                Spacer(minLength: 0)
            }
            .frame(width: 38, height: 34, alignment: .center)
        }
        .frame(height: 38, alignment: .center)
        .offset(x: 8, y: -12)
    }
}
/// Removes chroma from a window while it is inactive, preserving its layout and controls.
struct AWEDWindowActivityAppearance: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .saturation(appearsActive ? 1 : 0)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.18),
                value: appearsActive
            )
    }
}
extension View {
    func awedWindowActivityAppearance() -> some View {
        modifier(AWEDWindowActivityAppearance())
    }
}
