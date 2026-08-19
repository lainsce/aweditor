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
            .padding(.vertical, 10)

            if model.selectedTab == .unit {
                ArmyColorTabs(selection: model.selectedArmy) { army in
                    model.selectArmy(army)
                }
            }

            Divider()

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 42, maximum: 54), spacing: 9)], spacing: 9) {
                    ForEach(PaletteCatalog.items(for: model.selectedTab)) { item in
                        PaletteTileButton(item: item, isSelected: model.isPaletteItemSelected(item), atlas: atlas, tileset: model.map.tileset) {
                            model.select(item)
                        }
                    }
                }
                .padding(12)
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
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 1)
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
    let isSelected: Bool
    let atlas: SpriteAtlas
    let tileset: Tileset
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.055))
                if let image = atlas.image(for: item.element, tileset: tileset) {
                    image
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .padding(3)
                } else {
                    Image(systemName: "square.dashed")
                        .foregroundStyle(.secondary)
                }
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            }
            .frame(minWidth: 42, minHeight: 42)
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
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.primary.opacity(0.06))
                if let image = atlas.image(for: element, tileset: tileset) {
                    image.resizable().interpolation(.none).scaledToFit().padding(3)
                }
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(elementName(element))
                    .font(.headline)
                Text("Tile \(element.value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected tile, \(elementName(element))")
    }

    private func elementName(_ element: Element) -> String {
        if element == .unitEmpty { return "Empty Unit" }
        if element == .unitDelete { return "Delete Unit" }
        if element.isBuilding { return "Building" }
        if element.isUnit { return "Unit" }
        if element.isExtra { return "Extra" }
        if element.isTerrain { return "Terrain" }
        return "Tile"
    }
}
