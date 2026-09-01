import AppKit
import SwiftUI
import AWEDCore


struct PlaytestLegacyCommandRail: View {
    /// Reserve the largest of the per-cartridge rails plus its 16 px outer
    /// breathing room. The rail overlays the map, so this never changes the
    /// map's centering math.
    static let width: CGFloat = 284

    let session: PlaytestSession
    /// The rail overlays the map, so this is only used to cap a compact menu
    /// on short playtest windows; it never participates in map centering.
    let availableHeight: CGFloat
    @Binding var mode: PlaytestLegacyMenuMode
    @Binding var selection: Int
    @Binding var buildSelection: Int
    let onAction: (PlaytestLegacyAction) -> Void
    let onBuild: (Int) -> Void

    private var theme: PlaytestStatusTheme {
        PlaytestStatusTheme(tileset: session.map.tileset)
    }

    private var menuTheme: PlaytestLegacyMenuTheme {
        theme.legacyMenu
    }

    private var actions: [PlaytestLegacyAction] {
        PlaytestLegacyActionCatalog.actions(for: session)
    }

    private var commandMenuWidth: CGFloat {
        let fallbackFont = NSFont.systemFont(ofSize: theme.legacyMenuFontPointSize)
        let font = NSFont(
            name: theme.legacyMenuFontFamily,
            size: theme.legacyMenuFontPointSize
        ) ?? fallbackFont
        let labels = actions.map {
            PlaytestLegacyActionCatalog.title(for: $0, session: session)
        } + [menuTheme.title]
        let longestText = labels.map { width(of: $0, font: font) }.max() ?? 0
        let twoSpaces = width(of: "  ", font: font)
        let markerColumn: CGFloat = 10 + (menuTheme.showsActionIcons ? 21 : 0)
        let columnGaps: CGFloat = menuTheme.showsActionIcons ? 12 : 6
        let buttonPadding: CGFloat = 14
        let framePadding: CGFloat = 16

        // The two spaces are the only text-derived breathing room. Marker,
        // icon, button, and frame columns are added separately so the
        // longest label remains fully visible without a fixed wide rail.
        let textWidth = longestText + twoSpaces
        let structuralWidth = markerColumn + columnGaps + buttonPadding + framePadding
        let totalWidth = textWidth + structuralWidth
        return ceil(totalWidth)
    }

    private func width(of text: String, font: NSFont) -> CGFloat {
        NSString(string: text).size(withAttributes: [.font: font]).width
    }

    private var commandRowsHeight: CGFloat {
        guard !actions.isEmpty else { return menuTheme.rowHeight }
        return CGFloat(actions.count) * menuTheme.rowHeight
            + CGFloat(max(0, actions.count - 1)) * menuTheme.rowSpacing
    }

    /// The title row, divider, row spacing, and the menu frame's vertical
    /// padding. Command mode intentionally has no footer, so this is the only
    /// chrome added to the command rows.
    private var commandMenuChromeHeight: CGFloat {
        menuTheme.contentPadding * 2 + 26 + 1 + 16
    }

    private var commandMenuHeight: CGFloat {
        let desired = commandMenuChromeHeight + commandRowsHeight
        let maximum = max(commandMenuChromeHeight, availableHeight - 32)
        return min(desired, maximum)
    }

    private var commandScrollHeight: CGFloat {
        max(menuTheme.rowHeight, commandMenuHeight - commandMenuChromeHeight)
    }

    var body: some View {
        menuFrame
        .frame(width: mode == .build ? menuTheme.railWidth : commandMenuWidth)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var menuFrame: some View {
        PlaytestLegacyMenuFrame(theme: menuTheme, panelTheme: theme) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(mode == .build ? "PRODUCTION" : menuTheme.title)
                        .font(menuTheme.titleFont)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                    Spacer(minLength: 4)
                }

                Rectangle()
                    .fill(menuTheme.secondaryBorder)
                    .frame(height: 1)
                    .opacity(0.86)

                if mode == .build {
                    ScrollView(.vertical, showsIndicators: false) {
                        buildMenu
                    }
                    .frame(maxHeight: .infinity, alignment: .top)

                    Rectangle()
                        .fill(menuTheme.secondaryBorder)
                        .frame(height: 1)
                        .opacity(0.84)

                    Text("Z BUILD   X BACK")
                        .font(menuTheme.detailFont)
                        .foregroundStyle(menuTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.58)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        commandMenu
                    }
                    .frame(height: commandScrollHeight, alignment: .top)
                }
            }
        }
        .modifier(LegacyMenuHeight(mode: mode, commandMenuHeight: commandMenuHeight))
    }

    private var commandMenu: some View {
        VStack(alignment: .leading, spacing: menuTheme.rowSpacing) {
            ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                Button {
                    selection = index
                    onAction(action)
                } label: {
                    HStack(spacing: 6) {
                        Text(mode == .commands && selection == index ? menuTheme.selectionMarker : " ")
                            .font(menuTheme.detailFont)
                            .frame(width: 10, alignment: .center)
                        if menuTheme.showsActionIcons {
                            PlaytestLegacyMenuIcon(action: action, theme: menuTheme)
                        }
                        Text(PlaytestLegacyActionCatalog.title(for: action, session: session))
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(
                    PlaytestLegacyMenuButtonStyle(
                        theme: menuTheme,
                        isSelected: mode == .commands && selection == index
                    )
                )
                .disabled(!PlaytestLegacyActionCatalog.isEnabled(action, session: session))
                .accessibilityValue(PlaytestLegacyActionCatalog.isEnabled(action, session: session) ? "Available" : "Unavailable")
            }
        }
    }

    private var buildMenu: some View {
        VStack(alignment: .leading, spacing: menuTheme.rowSpacing) {
            Button {
                mode = .commands
                selection = 0
            } label: {
                HStack(spacing: 6) {
                    Text(" ")
                        .frame(width: 10)
                    if menuTheme.showsActionIcons {
                        PlaytestLegacyMenuIcon(action: nil, theme: menuTheme)
                    }
                    Text("BACK")
                }
            }
            .buttonStyle(
                PlaytestLegacyMenuButtonStyle(
                    theme: menuTheme,
                    isSelected: false
                )
            )

            if session.productionOptions.isEmpty {
                Text("SELECT AN OWNED PRODUCTION PROPERTY")
                    .font(menuTheme.detailFont)
                    .foregroundStyle(menuTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 5)
            } else {
                ForEach(Array(session.productionOptions.enumerated()), id: \.offset) { index, option in
                    Button {
                        buildSelection = index
                        onBuild(index)
                    } label: {
                        HStack(spacing: 6) {
                            Text(buildSelection == index ? menuTheme.selectionMarker : " ")
                                .font(menuTheme.detailFont)
                                .frame(width: 10, alignment: .center)
                            if menuTheme.showsActionIcons {
                                PlaytestLegacyMenuIcon(action: .build, theme: menuTheme)
                            }
                            Text(option.label.uppercased())
                                .lineLimit(1)
                                .minimumScaleFactor(0.54)
                            Spacer(minLength: 2)
                            Text(PlaytestRulebook.formatFunds(option.cost))
                                .font(menuTheme.detailFont)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(
                        PlaytestLegacyMenuButtonStyle(
                            theme: menuTheme,
                            isSelected: buildSelection == index
                        )
                    )
                    .disabled(!session.canBuild(option))
                }
            }
        }
    }
}
private struct LegacyMenuHeight: ViewModifier {
    let mode: PlaytestLegacyMenuMode
    let commandMenuHeight: CGFloat

    func body(content: Content) -> some View {
        if mode == .build {
            content.frame(maxHeight: .infinity, alignment: .top)
        } else {
            content.frame(height: commandMenuHeight, alignment: .top)
        }
    }
}
