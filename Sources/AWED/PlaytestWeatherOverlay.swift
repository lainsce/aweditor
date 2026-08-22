import SwiftUI

/// A small, render-only weather pass for playtest maps. It deliberately uses
/// a fixed number of Canvas primitives rather than one view per particle, so
/// large maps do not turn weather into a per-tile rendering cost.
struct PlaytestWeatherOverlay: View {
    let weather: PlaytestWeather
    let mapSize: CGSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? 1 : 0.12,
                paused: reduceMotion
            )
        ) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                drawWeather(
                    weather,
                    time: time,
                    size: size,
                    context: &context
                )
            }
        }
        .frame(width: mapSize.width, height: mapSize.height)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawWeather(
        _ weather: PlaytestWeather,
        time: TimeInterval,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        switch weather {
        case .rain:
            drawRain(time: time, size: size, context: &context)
        case .snow:
            drawSnow(time: time, size: size, context: &context)
        case .sandstorm:
            drawSandstorm(time: time, size: size, context: &context)
        case .clear, .random:
            drawClouds(time: time, size: size, context: &context)
        }
    }

    private func drawRain(
        time: TimeInterval,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        let count = min(72, max(28, Int(size.width / 18)))
        let opacity = reduceTransparency ? 0.18 : 0.28

        for index in 0..<count {
            let xBase = randomUnit(index, salt: 0.17)
            let yBase = randomUnit(index, salt: 0.31)
            let phase = randomUnit(index, salt: 0.83)
            let fallCycle = 1.9 + (randomUnit(index, salt: 1.47) * 1.8)
            let fall = unitFraction(time / fallCycle + phase)
            let slant = 0.04 + (randomUnit(index, salt: 2.11) * 0.08)
            let x = (xBase + (fall * slant)) * size.width
            let y = unitFraction(yBase + fall) * size.height
            let length = 8 + (randomUnit(index, salt: 2.79) * min(11, size.height * 0.022))
            let start = CGPoint(x: x, y: y)
            let end = CGPoint(
                x: x - (2.5 + randomUnit(index, salt: 3.41) * 4.5),
                y: y + length
            )
            var streak = Path()
            streak.move(to: start)
            streak.addLine(to: end)
            context.stroke(
                streak,
                with: .color(
                    Color(red: 0.72, green: 0.88, blue: 1).opacity(
                        opacity * (0.72 + randomUnit(index, salt: 4.03) * 0.48)
                    )
                ),
                style: StrokeStyle(
                    lineWidth: 0.7 + (randomUnit(index, salt: 4.67) * 0.6),
                    lineCap: .round
                )
            )
        }
    }

    private func drawSnow(
        time: TimeInterval,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        let count = min(56, max(22, Int(size.width / 24)))
        let opacity = reduceTransparency ? 0.32 : 0.52

        for index in 0..<count {
            let xBase = randomUnit(index, salt: 0.09)
            let yBase = randomUnit(index, salt: 0.43)
            let phase = randomUnit(index, salt: 0.71) * 6.28318530718
            let fallCycle = 4.6 + (randomUnit(index, salt: 1.33) * 4.2)
            let fall = unitFraction(time / fallCycle + randomUnit(index, salt: 1.91))
            let driftRate = 0.25 + (randomUnit(index, salt: 2.37) * 0.75)
            let driftAmplitude = 3 + (randomUnit(index, salt: 2.89) * 11)
            let drift = sin(time * driftRate + phase) * driftAmplitude
            let x = (xBase * size.width) + drift
            let y = unitFraction(yBase + fall) * size.height
            let radius = 0.75 + (randomUnit(index, salt: 3.23) * 1.8)
            let flake = CGRect(
                x: x - radius,
                y: y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.fill(
                Path(ellipseIn: flake),
                with: .color(
                    Color.white.opacity(
                        opacity * (0.70 + randomUnit(index, salt: 3.79) * 0.55)
                    )
                )
            )
        }
    }

    private func drawSandstorm(
        time: TimeInterval,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        let count = min(64, max(24, Int(size.width / 20)))
        let opacity = reduceTransparency ? 0.13 : 0.22

        for index in 0..<count {
            let xBase = randomUnit(index, salt: 0.22)
            let yBase = randomUnit(index, salt: 0.07)
            let travelCycle = 1.4 + (randomUnit(index, salt: 0.59) * 2.4)
            let travel = unitFraction(time / travelCycle + randomUnit(index, salt: 1.07))
            let x = unitFraction(xBase + travel) * size.width
            let yDrift = 2 + (randomUnit(index, salt: 1.61) * 7)
            let y = yBase * size.height + sin(time * (0.35 + randomUnit(index, salt: 2.03)) + Double(index)) * yDrift
            let length = 8 + (randomUnit(index, salt: 2.67) * 28)
            let angle = -1.0 + (randomUnit(index, salt: 3.19) * 3.0)
            var grain = Path()
            grain.move(to: CGPoint(x: x, y: y))
            grain.addLine(to: CGPoint(x: x + length, y: y + angle))
            context.stroke(
                grain,
                with: .color(
                    Color(red: 0.96, green: 0.73, blue: 0.36).opacity(
                        opacity * (0.65 + randomUnit(index, salt: 3.83) * 0.60)
                    )
                ),
                style: StrokeStyle(
                    lineWidth: 0.7 + (randomUnit(index, salt: 4.41) * 0.75),
                    lineCap: .round
                )
            )
        }
    }

    private func drawClouds(
        time: TimeInterval,
        size: CGSize,
        context: inout GraphicsContext
    ) {
        let cloudCount = min(3, max(1, Int(size.width / 360)))
        let opacity = reduceTransparency ? 0.06 : 0.13

        for index in 0..<cloudCount {
            let cycle = 13.0 + (randomUnit(index, salt: 0.47) * 7.0)
            let progress = unitFraction(
                time / cycle + randomUnit(index, salt: 0.91)
            )
            let envelope = cloudEnvelope(progress)
            guard envelope > 0.01 else { continue }

            let scale = 0.62 + (randomUnit(index, salt: 1.43) * 0.60)
            let cloudWidth = 94 * scale
            let cloudHeight = 28 * scale
            let x = (progress * (size.width + cloudWidth * 2)) - cloudWidth
            let y = (0.08 + randomUnit(index, salt: 2.07) * 0.28) * size.height
            drawCloud(
                at: CGPoint(x: x, y: y),
                width: cloudWidth,
                height: cloudHeight,
                opacity: opacity * envelope,
                context: &context
            )
        }
    }

    private func drawCloud(
        at origin: CGPoint,
        width: CGFloat,
        height: CGFloat,
        opacity: Double,
        context: inout GraphicsContext
    ) {
        let color = Color.white.opacity(opacity)
        let base = CGRect(
            x: origin.x,
            y: origin.y + height * 0.28,
            width: width,
            height: height * 0.54
        )
        let left = CGRect(
            x: origin.x + width * 0.10,
            y: origin.y + height * 0.18,
            width: width * 0.40,
            height: height * 0.62
        )
        let center = CGRect(
            x: origin.x + width * 0.34,
            y: origin.y,
            width: width * 0.40,
            height: height * 0.78
        )
        let right = CGRect(
            x: origin.x + width * 0.60,
            y: origin.y + height * 0.24,
            width: width * 0.28,
            height: height * 0.52
        )
        context.fill(Path(ellipseIn: base), with: .color(color))
        context.fill(Path(ellipseIn: left), with: .color(color))
        context.fill(Path(ellipseIn: center), with: .color(color))
        context.fill(Path(ellipseIn: right), with: .color(color))
    }

    private func cloudEnvelope(_ progress: Double) -> Double {
        let fadeIn = min(1, progress / 0.14)
        let fadeOut = min(1, (1 - progress) / 0.18)
        return max(0, min(fadeIn, fadeOut))
    }

    private func unitFraction(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }

    /// Stable pseudo-randomness keeps each particle's personality consistent
    /// between Canvas redraws while avoiding the regular low-discrepancy
    /// spacing that made the first pass look patterned. It is intentionally
    /// not `Double.random`, which would make particles shimmer every frame.
    private func randomUnit(_ index: Int, salt: Double) -> Double {
        let source = (Double(index) + 1) * 12.9898 + salt * 78.233
        return unitFraction(sin(source) * 43_758.5453)
    }
}
