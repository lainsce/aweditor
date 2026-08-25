import SwiftUI
import AWEDCore

struct PlaytestHeader: View {
    static let height: CGFloat = 60

    let session: PlaytestSession
    let restartAction: () -> Void
    let endTurnAction: () -> Void
    let exitAction: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var session = session
        let frameTheme = PlaytestFrameTheme.playtest(for: session.map.tileset)
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
                    .foregroundStyle(.secondary)
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

                    Text("Fog")
                        .font(.caption.weight(.semibold))
                }
            }

            Spacer(minLength: 14)

            Button("Exit", systemImage: "xmark.rectangle", action: exitAction)
                .buttonStyle(.bordered)
            Button("Restart", systemImage: "arrow.counterclockwise", action: restartAction)
                .buttonStyle(.bordered)
            Button("End Turn", systemImage: "forward.fill", action: endTurnAction)
                .buttonStyle(.borderedProminent)
                .disabled(session.isGameOver || session.activeArmyIsCPU)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background {
            ZStack {
                if reduceTransparency {
                    Rectangle()
                        .fill(frameTheme.headerTint.opacity(0.94))
                } else {
                    Rectangle()
                        .fill(.thinMaterial)
                    Rectangle()
                        .fill(frameTheme.headerTint.opacity(frameTheme.headerOpacity))
                }
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(frameTheme.headerTint.opacity(reduceTransparency ? 0.70 : 0.48))
                .frame(height: 1)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(frameTheme.headerBorder.opacity(reduceTransparency ? 0.55 : 0.34))
                .frame(height: 1)
        }
        .shadow(
            color: frameTheme.headerShadow.opacity(reduceTransparency ? 0.08 : 0.16),
            radius: 7,
            y: 2
        )
    }
}
