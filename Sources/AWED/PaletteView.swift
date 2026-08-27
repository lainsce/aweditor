import SwiftUI
import AWEDCore

struct PaletteView: View {
    @Bindable var model: EditorModel
    let atlas: SpriteAtlas

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            NativeSegmentedPicker(
                selection: $model.selectedTab,
                options: PaletteCatalog.tabs(for: model.map.tileset)
            ) { tab in
                Text(tab.displayName)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .padding(.top, 52)

            if model.selectedTab == .unit {
                ArmyColorTabs(selection: model.selectedArmy, tileset: model.map.tileset) { army in
                    model.selectArmy(army)
                }
            }

            ScrollView {
                Group {
                    if model.selectedTab == .mapArt {
                        MapVisualVariantGrid(
                            selection: model.visualVariant,
                            atlas: atlas,
                            onSelect: model.setVisualVariant
                        )
                    } else if model.selectedTab == .terrain {
                        VStack(spacing: 4) {
                            paletteGrid(
                                items: PaletteCatalog.items(for: .terrain, tileset: model.map.tileset).filter { !$0.element.isBuilding },
                                columns: fixedColumns(count: 6, spacing: 4)
                            )
                            paletteGrid(
                                items: PaletteCatalog.items(for: .terrain, tileset: model.map.tileset).filter { $0.element.isBuilding },
                                columns: fixedColumns(count: buildingColumnCount(for: model.map.tileset), spacing: 4)
                            )
                        }
                    } else {
                        paletteGrid(
                            items: PaletteCatalog.items(for: model.selectedTab, tileset: model.map.tileset),
                            columns: [GridItem(.adaptive(minimum: 32, maximum: 54), spacing: 8)]
                        )
                    }
                }
                .padding(8)
            }
            .scrollContentBackground(.hidden)

            if model.selectedTab != .mapArt {
                SelectedElementFooter(
                    element: model.selectedElement,
                    atlas: atlas,
                    palette: model.renderPalette,
                    tileset: model.map.tileset
                )
                .padding(12)
            }
        }
        .frame(minWidth: 310, idealWidth: 310, maxWidth: 310)
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
                        palette: model.renderPalette
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

    private func buildingColumnCount(for tileset: Tileset) -> Int {
        switch tileset {
        case .famicomWars: 5
        case .superFamicomWars: 7
        case .gbWars, .gbWars2, .gbWars3: 5
        default: 7
        }
    }
}

private struct MapVisualVariantGrid: View {
    let selection: MapVisualVariant
    let atlas: SpriteAtlas
    let onSelect: (MapVisualVariant) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 14) {
            ForEach(MapVisualVariant.groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.headline)
                        .padding(.horizontal, 2)

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 120), spacing: 8),
                            GridItem(.flexible(minimum: 120), spacing: 8)
                        ],
                        spacing: 8
                    ) {
                        ForEach(group.variants) { variant in
                            MapVisualVariantCard(
                                variant: variant,
                                isSelected: variant == selection,
                                atlas: atlas,
                                action: { onSelect(variant) }
                            )
                        }
                    }
                }
            }
        }
        .padding(8)
    }
}

private struct MapVisualVariantCard: View {
    let variant: MapVisualVariant
    let isSelected: Bool
    let atlas: SpriteAtlas
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.06))
                    if let image = atlas.image(for: .terrainPlain, palette: variant.palette) {
                        image
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .padding(3)
                    }
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 3) {
                    Text(variant.shortName)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 5) {
                        ForEach(variant.effects) { effect in
                            Label(effect.value, systemImage: effect.systemImage)
                            .font(.caption)
                            .foregroundStyle(effect.tint.color)
                            .tint(effect.tint.color)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(effect.tint.color.opacity(0.18), in: Capsule())
                            .help("\(effect.accessibilityLabel) (\(effect.value))")
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 62, maxHeight: 70, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.05))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
        }
        .help("\(variant.displayName): \(variant.effectAccessibilityLabel)")
        .accessibilityLabel("\(variant.displayName). \(variant.effectAccessibilityLabel)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ArmyColorTabs: View {
    let selection: Int
    let tileset: Tileset
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PaletteCatalog.visibleArmies(for: tileset), id: \.self) { army in
                let isSelected = selection == army
                Button {
                    onSelect(army)
                } label: {
                    VStack(spacing: 3) {
                        Circle()
                            .fill(color(for: army))
                            .frame(width: 10, height: 10)
                            Text(PaletteCatalog.armyAbbreviation(army, tileset: tileset))
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
                .help(PaletteCatalog.armyName(army, tileset: tileset))
                .accessibilityLabel(PaletteCatalog.armyName(army, tileset: tileset))
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
        if tileset == .daysOfRuin, army == AWConstants.armyBlackHole {
            return Color(white: 0.12)
        }

        if tileset == .famicomWars {
            switch army {
            case AWConstants.armyOrangeStar: return FamicomPPUPalette.red
            case AWConstants.armyBlueMoon: return FamicomPPUPalette.blue
            case AWConstants.armyGreenEarth: return FamicomPPUPalette.green
            case AWConstants.armyYellowComet: return FamicomPPUPalette.yellow
            case AWConstants.armyBlackHole: return FamicomPPUPalette.purple
            default: return FamicomPPUPalette.gray
            }
        }

        if tileset.isGameBoyWarsFamily {
            switch army {
            case AWConstants.armyOrangeStar: return Color(red: 0.78, green: 0.12, blue: 0.12)
            case AWConstants.armyBlueMoon: return Color(white: 0.82)
            default: break
            }
        }
        switch army {
        case AWConstants.armyOrangeStar: return Color(red: 0.94, green: 0.40, blue: 0.12)
        case AWConstants.armyBlueMoon: return Color(red: 0.18, green: 0.47, blue: 0.86)
        case AWConstants.armyGreenEarth: return Color(red: 0.22, green: 0.62, blue: 0.27)
        case AWConstants.armyYellowComet: return Color(red: 0.92, green: 0.70, blue: 0.08)
        case AWConstants.armyBlackHole: return Color(red: 0.48, green: 0.30, blue: 0.72)
        default: return .secondary
        }
    }
}

struct PaletteTileButton: View {
    let item: PaletteItem
    let element: Element
    let isSelected: Bool
    let atlas: SpriteAtlas
    let palette: SpritePalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.05))
                if let image = atlas.image(for: element, palette: palette) {
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
                maxHeight: palette.doubleHeight(for: element) ? 64 : 32
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
    let palette: SpritePalette
    let tileset: Tileset

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.05))
                if let image = atlas.image(for: element, palette: palette) {
                    image.resizable().interpolation(.none).scaledToFit().padding(3)
                }
            }
            .frame(
                minWidth: 32,
                maxWidth: 32,
                minHeight: 32,
                maxHeight: palette.doubleHeight(for: element) ? 64 : 32
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(PaletteCatalog.label(for: element, tileset: tileset))
                    .font(.headline)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected tile, \(PaletteCatalog.label(for: element, tileset: tileset))")
    }
}
