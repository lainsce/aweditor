import AppKit
import SwiftUI
import AWEDCore


struct PlaytestLegacyMenuFrame<Content: View>: View {
    let theme: PlaytestLegacyMenuTheme
    let panelTheme: PlaytestStatusTheme
    @ViewBuilder let content: Content

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixel = 1 / max(displayScale, 1)
        let shape = PlaytestPanelShape(cornerRadius: panelTheme.cornerRadius)
        let shadow = panelTheme.shadow

        content
            .padding(theme.contentPadding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(theme.surface)
            .clipShape(shape)
            .overlay {
                frameOverlay(shape: shape, pixel: pixel)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: shadow.color,
                radius: shadow.radius,
                x: shadow.xPixels * pixel,
                y: shadow.yPixels * pixel
            )
            .environment(\.colorScheme, panelTheme.preferredColorScheme)
    }

    @ViewBuilder
    private func frameOverlay(
        shape: PlaytestPanelShape,
        pixel: CGFloat
    ) -> some View {
        ZStack {
            if panelTheme.outerBorderPixels > 0 {
                shape.strokeBorder(
                    panelTheme.outerBorder,
                    style: StrokeStyle(lineWidth: panelTheme.outerBorderPixels * pixel),
                    antialiased: false
                )
            }
            if panelTheme.innerBorderPixels > 0 {
                shape
                    .inset(by: panelTheme.innerBorderInsetPixels * pixel)
                    .strokeBorder(
                        panelTheme.innerBorder,
                        style: StrokeStyle(lineWidth: panelTheme.innerBorderPixels * pixel),
                        antialiased: false
                    )
            }
            if panelTheme == .famicomWars {
                shape
                    .inset(by: 4 * pixel)
                    .strokeBorder(
                        panelTheme.outerBorder,
                        style: StrokeStyle(lineWidth: 2 * pixel),
                        antialiased: false
                    )
                shape
                    .inset(by: 6 * pixel)
                    .strokeBorder(
                        FamicomPPUPalette.black,
                        style: StrokeStyle(lineWidth: pixel),
                        antialiased: false
                    )
            }
        }
    }
}

struct PlaytestLegacyMenuButtonStyle: ButtonStyle {
    let theme: PlaytestLegacyMenuTheme
    let isSelected: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let pixel = 1 / max(displayScale, 1)
        let shape = RoundedRectangle(cornerRadius: theme.rowCornerRadius)
        let isFamicom = switch theme.frame {
        case .famicom: true
        default: false
        }
        // Famicom Wars keeps the cursor visible even when an unavailable
        // command is selected. Its rows are otherwise flat monochrome text;
        // the olive fill is the only per-row selection treatment.
        let selected = isSelected && (isEnabled || isFamicom)

        configuration.label
            .font(theme.menuFont)
            .foregroundStyle(selected ? theme.activeText : theme.text)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: theme.rowHeight, alignment: .leading)
            .background {
                shape.fill(
                    selected
                        ? theme.activeSurface
                        : (isEnabled ? theme.rowSurface : theme.disabledSurface)
                )
            }
            .overlay(alignment: .top) {
                if !isFamicom {
                    Rectangle()
                        .fill(theme.innerBorder.opacity(selected ? 0.9 : 0.55))
                        .frame(height: pixel)
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottom) {
                if !isFamicom {
                    Rectangle()
                        .fill(theme.secondaryBorder.opacity(selected ? 0.95 : 0.72))
                        .frame(height: pixel)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                if !isFamicom {
                    shape.strokeBorder(
                        selected ? theme.innerBorder : theme.border.opacity(0.68),
                        style: StrokeStyle(lineWidth: pixel),
                        antialiased: false
                    )
                    .allowsHitTesting(false)
                }
            }
            .opacity(isEnabled ? 1 : 0.58)
            .offset(y: configuration.isPressed ? pixel : 0)
            .contentShape(shape)
    }
}

struct PlaytestLegacyMenuIcon: View {
    let action: PlaytestLegacyAction?
    let theme: PlaytestLegacyMenuTheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(theme.secondaryBorder.opacity(0.42))
            Rectangle()
                .stroke(theme.border.opacity(0.88), lineWidth: 1)
            Text(glyph)
                .font(theme.detailFont)
                .foregroundStyle(theme.text)
                .minimumScaleFactor(0.6)
        }
        .frame(width: 21, height: 21)
    }

    private var glyph: String {
        guard let action else { return "+" }
        return switch action {
        case .build: "B"
        case .stat: "I"
        case .move: "M"
        case .attack: "A"
        case .capture: "C"
        case .load: "L"
        case .unload: "U"
        case .join: "J"
        case .resupply: "S"
        case .surface: "D"
        case .stealth: "C"
        case .detonate: "X"
        case .flare: "F"
        case .silo: "T"
        case .wait: "W"
        case .endTurn: "E"
        case .surrender: "S"
        }
    }
}

/// Cartridge-era command rail. The map remains the visual focus, while the
/// left rail makes every legal action discoverable without a modern inspector
/// click target being required.
