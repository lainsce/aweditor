import SwiftUI
import AWEDCore

struct PaletteView: View {
    @Bindable var model: EditorModel
    let atlas: SpriteAtlas

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            Divider()
                .padding(.top, 50)

            Picker("", selection: $model.selectedTab) {
                ForEach(PaletteTab.allCases) { tab in
                    Text(tab.displayName).tag(tab)
                }
            }
            .pickerStyle(.tabs)
            .padding(.vertical, 12)

            if model.selectedTab == .unit {
                ArmyColorTabs(selection: model.selectedArmy) { army in
                    model.selectArmy(army)
                }
            }

            Divider()

            ScrollView {
                Group {
                    if model.selectedTab == .terrain {
                        VStack(spacing: 4) {
                            paletteGrid(
                                items: PaletteCatalog.items(for: .terrain).filter { !$0.element.isBuilding },
                                columns: fixedColumns(count: 6, spacing: 4)
                            )
                            paletteGrid(
                                items: PaletteCatalog.items(for: .terrain).filter { $0.element.isBuilding },
                                columns: fixedColumns(count: 7, spacing: 4)
                            )
                        }
                    } else {
                        paletteGrid(
                            items: PaletteCatalog.items(for: model.selectedTab),
                            columns: [GridItem(.adaptive(minimum: 32, maximum: 54), spacing: 8)]
                        )
                    }
                }
                .padding(8)
            }
            .scrollContentBackground(.hidden)

            Divider()

            SelectedElementFooter(element: model.selectedElement, atlas: atlas, tileset: model.map.tileset)
                .padding(12)

            Divider()
        }
        .frame(minWidth: 285, idealWidth: 310, maxWidth: 360)
        .background(.regularMaterial)
        .ignoresSafeArea(.container)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tile Palette")
    }

    @ViewBuilder
    private func paletteGrid(items: [PaletteItem], columns: [GridItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(items) { item in
                ZStack(alignment: .bottom) {
                    PaletteTileButton(
                        item: item,
                        element: model.paletteElement(for: item),
                        isSelected: model.isPaletteItemSelected(item),
                        atlas: atlas,
                        tileset: model.map.tileset
                    ) {
                        model.select(item)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
    }

    private func fixedColumns(count: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 32, maximum: 54), spacing: spacing), count: count)
    }
}

private struct ArmyColorTabs: View {
    let selection: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<AWConstants.playableArmies, id: \.self) { army in
                let isSelected = selection == army
                Button {
                    onSelect(army)
                } label: {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(color(for: army))
                            .frame(width: 10, height: 10)
                        Text(PaletteCatalog.armyAbbreviation(army))
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 1 : 1)
                }
                .help(PaletteCatalog.armyName(army))
                .accessibilityLabel(PaletteCatalog.armyName(army))
                .accessibilityValue(isSelected ? "Selected" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Army Color")
    }

    private func color(for army: Int) -> Color {
        switch army {
        case AWConstants.armyOrangeStar: Color(red: 0.94, green: 0.40, blue: 0.12)
        case AWConstants.armyBlueMoon: Color(red: 0.18, green: 0.47, blue: 0.86)
        case AWConstants.armyGreenEarth: Color(red: 0.22, green: 0.62, blue: 0.27)
        case AWConstants.armyYellowComet: Color(red: 0.92, green: 0.70, blue: 0.08)
        case AWConstants.armyBlackHole: Color(red: 0.48, green: 0.30, blue: 0.72)
        default: .secondary
        }
    }
}

struct PaletteTileButton: View {
    let item: PaletteItem
    let element: Element
    let isSelected: Bool
    let atlas: SpriteAtlas
    let tileset: Tileset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.05))
                if let image = atlas.image(for: element, tileset: tileset) {
                    image
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(2)
                        .frame(
                            alignment: .init(
                                horizontal: .center,
                                vertical: .bottom
                            )
                        )
                } else {
                    Image(systemName: "square.dashed")
                        .foregroundStyle(.secondary)
                }
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
            .frame(
                minWidth: 32,
                minHeight: 32,
                maxHeight: item.element.doubleHeight ? 64 : 32
            )
        }
        .buttonStyle(.plain)
        .help(item.label)
        .accessibilityLabel(item.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SelectedElementFooter: View {
    let element: Element
    let atlas: SpriteAtlas
    let tileset: Tileset

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                if let image = atlas.image(for: element, tileset: tileset) {
                    image.resizable().interpolation(.none).scaledToFit().padding(3)
                }
            }
            .frame(
                minWidth: 32,
                maxWidth: 32,
                minHeight: 32,
                maxHeight: element.doubleHeight ? 64 : 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(PaletteCatalog.label(for: element))
                    .font(.headline)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected tile, \(PaletteCatalog.label(for: element))")
    }
}
