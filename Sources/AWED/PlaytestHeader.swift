import SwiftUI
import AWEDCore

struct PlaytestHeader: View {
    static let height: CGFloat = 55

    let session: PlaytestSession
    let restartAction: () -> Void
    let endTurnAction: () -> Void
    let exitAction: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var session = session
        let frameTheme = PlaytestFrameTheme.playtest(for: session.map.tileset)
        let secondaryLabelColor = session.map.tileset == .famicomWars
            ? FamicomPPUPalette.gray
            : Color.secondary
        let exitButtonTint = session.map.tileset == .famicomWars
            ? FamicomPPUPalette.darkBrown
            : Color.accentColor
        let headerFillOpacity = reduceTransparency ? 1 : frameTheme.headerOpacity
        HStack(spacing: 12) {
            Label("Playtest", systemImage: "gamecontroller.fill")
                .font(.headline)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.gameDisplayName)
                    .font(.subheadline.weight(.semibold))
                Text(session.usesCompatibilityRules
                    ? "Compatibility rules: \(session.ruleset.shortName)"
                    : "Current Ruleset")
                    .font(.caption)
                    .foregroundStyle(secondaryLabelColor)
            }

            if PlaytestRulebook.supportsWeatherControl(session.ruleset) {
                NativePullDownMenu(
                    "Weather",
                    selection: Binding(
                        get: { session.weatherMode },
                        set: { session.setWeatherMode($0) }
                    ),
                    options: PlaytestRulebook.weatherOptions(for: session.ruleset),
                    showsTitle: false
                ) { weather in
                    Text(weather.displayName)
                }
                .frame(minWidth: 78)
                .help(session.weatherMode == .random
                    ? "Weather changes randomly at the start of each day. Current: \(session.weather.displayName)."
                    : "Choose the weather used for movement, vision, and combat.")

            }

            if PlaytestRulebook.supportsFogOfWar(session.ruleset) {
                HStack(spacing: 6) {
                    Toggle("Fog", isOn: $session.fogOfWarEnabled)
                        .toggleStyle(.switch)
                        .disabled(session.isFogForcedByWeather)
                        .help(session.isFogForcedByWeather
                            ? "Rain forces Fog of War in this ruleset"
                            : "Hide enemy units outside friendly vision")
                }
            }

            Spacer(minLength: 14)

            if !session.ruleset.usesLegacyKeyboardControls {
                Button(action: restartAction) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Restart playtest")
                .accessibilityLabel("Restart playtest")

                Button(action: endTurnAction) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 14))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                        .glassEffect(.regular.interactive(), in: Circle())
                }
                .buttonStyle(.plain)
                .help("End turn")
                .accessibilityLabel("End turn")
                    .disabled(session.isGameOver || session.activeArmyIsCPU)
            }

            Button(action: exitAction) {
                Image(systemName: "xmark")
                    .font(.system(size: 14))
                    .frame(width: 38, height: 38)
                    .contentShape(Circle())
                    .glassEffect(.regular.tint(exitButtonTint).interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Exit playtest")
            .accessibilityLabel("Exit playtest")
        }
        .padding(.horizontal, 8)
        .padding(.leading, 16)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background {
            Rectangle()
                .fill(frameTheme.headerTint.opacity(headerFillOpacity))
        }
        .foregroundStyle(frameTheme.headerFGTint)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(frameTheme.headerTint.opacity(reduceTransparency ? 1 : 0.48))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(frameTheme.headerBorder.opacity(reduceTransparency ? 0.5 : 0.34))
                .frame(height: 1)
        }
        .shadow(
            color: frameTheme.headerShadow.opacity(reduceTransparency ? 0.16 : 0.08),
            radius: 4,
            y: 1
        )
        // Keep native labels and bordered controls in the frame's light
        // appearance instead of allowing app-wide dark mode to override the
        // era-specific header palette.
        .environment(\.colorScheme, .light)
    }
}
