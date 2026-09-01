import SwiftUI
import AWEDCore


struct MapInspectorBorder: View {
    let theme: PlaytestStatusTheme

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let pixel = 1 / max(displayScale, 1)
        let shape = PlaytestPanelShape(cornerRadius: theme.cornerRadius)

        ZStack {
            if theme.outerBorderPixels > 0 {
                shape.strokeBorder(
                    theme.outerBorder,
                    style: StrokeStyle(lineWidth: theme.outerBorderPixels * pixel),
                    antialiased: false
                )
            }
            if theme.innerBorderPixels > 0 {
                shape
                    .inset(by: theme.innerBorderInsetPixels * pixel)
                    .strokeBorder(
                        theme.innerBorder,
                        style: StrokeStyle(lineWidth: theme.innerBorderPixels * pixel),
                        antialiased: false
                    )
            }
            if theme == .famicomWars {
                shape
                    .inset(by: 4 * pixel)
                    .strokeBorder(
                        theme.outerBorder,
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
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MapCanvasTallSpriteOverflow: View {
    let model: EditorModel
    let atlas: SpriteAtlas
    let tileSize: CGFloat
    let mapOverride: MapState?

    private var renderMap: MapState { mapOverride ?? model.map }

    var body: some View {
        let map = renderMap
        let staggered = MapCanvasMetrics.isStaggeredGB(map: map, palette: model.renderPalette)
        let mapSize = MapCanvasMetrics.mapPixelSize(
            width: map.width,
            height: map.height,
            tileSize: tileSize,
            staggered: staggered
        )
        Canvas { context, _ in
            for x in 0..<map.width {
                let origin = MapCanvasMetrics.tileOrigin(x: x, y: 0, tileSize: tileSize, staggered: staggered)
                let rect = CGRect(origin: origin, size: CGSize(width: tileSize, height: tileSize))
                drawSprite(map.backgroundDrawElement(atX: x, y: 0), at: rect, context: &context)
                drawSprite(map.foregroundElement(atX: x, y: 0), at: rect, context: &context)
            }
        }
        .frame(
            width: mapSize.width,
            height: tileSize * 2,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func drawSprite(_ element: Element, at rect: CGRect, context: inout GraphicsContext) {
        guard model.renderPalette.doubleHeight(for: element),
              element.isBuilding || element.isExtra || element.simplified == .terrainMountain,
              let image = atlas.image(for: element, palette: model.renderPalette) else { return }
        context.draw(
            context.resolve(image),
            in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height * 2)
        )
    }
}

struct MapWoodBorderOverlay: View {
    let theme: PlaytestFrameTheme

    var body: some View {
        MapWoodSurface(theme: theme)
            .mask {
                MapWoodBorderShape()
                    .fill(.white, style: FillStyle(eoFill: true))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct MapWoodBorderShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(
            rect.insetBy(
                dx: MapCanvasMetrics.woodPadding,
                dy: MapCanvasMetrics.woodPadding
            )
        )
        return path
    }
}

struct MapWoodDepthOverlay: View {
    let theme: PlaytestFrameTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let highlightOpacity = reduceTransparency ? 0.30 : 0.56
        let shadowOpacity = reduceTransparency ? 0.36 : 0.66

        ZStack {
            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            theme.woodHighlight.opacity(highlightOpacity),
                            theme.woodDeep.opacity(0.78),
                            theme.woodDeep.opacity(shadowOpacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 3
                )

            Rectangle()
                .strokeBorder(theme.woodDeep.opacity(shadowOpacity), lineWidth: 2)
                .padding(MapCanvasMetrics.woodPadding - 2)
                .shadow(color: theme.headerShadow.opacity(reduceTransparency ? 0.16 : 0.34), radius: 4, y: 2)

            Rectangle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            theme.woodHighlight.opacity(highlightOpacity),
                            .clear,
                            theme.woodDeep.opacity(shadowOpacity)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 2
                )
                .padding(MapCanvasMetrics.woodPadding - 5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MapWoodLowerWall: View {
    let theme: PlaytestFrameTheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Canvas { context, size in
            let bevelHeight = min(CGFloat(6), size.height * 0.35)
            let sideSlope = min(CGFloat(12), size.width * 0.08)
            let lowerInset = min(CGFloat(20), sideSlope * 1.6)
            let base = theme.woodLowerBase ?? theme.woodGradient.first ?? theme.woodDeep
            let deep = theme.woodDeep
            let highlight = theme.woodHighlight
            let opacity = reduceTransparency ? 0.72 : 1

            var frontFace = Path()
            frontFace.move(to: CGPoint(x: sideSlope, y: bevelHeight))
            frontFace.addLine(to: CGPoint(x: size.width - sideSlope, y: bevelHeight))
            frontFace.addLine(to: CGPoint(x: size.width - lowerInset, y: size.height))
            frontFace.addLine(to: CGPoint(x: lowerInset, y: size.height))
            frontFace.closeSubpath()
            context.fill(
                frontFace,
                with: .linearGradient(
                    Gradient(colors: [
                        base.opacity(opacity),
                        deep.opacity(opacity)
                    ]),
                    startPoint: CGPoint(x: 0, y: bevelHeight),
                    endPoint: CGPoint(x: 0, y: size.height)
                )
            )

            var angledTop = Path()
            angledTop.move(to: CGPoint(x: 0, y: 0))
            angledTop.addLine(to: CGPoint(x: size.width, y: 0))
            angledTop.addLine(to: CGPoint(x: size.width - sideSlope, y: bevelHeight))
            angledTop.addLine(to: CGPoint(x: sideSlope, y: bevelHeight))
            angledTop.closeSubpath()
            context.fill(
                angledTop,
                with: .linearGradient(
                    Gradient(colors: [
                        highlight.opacity(reduceTransparency ? 0.44 : 0.80),
                        base.opacity(opacity)
                    ]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: bevelHeight)
                )
            )

            var topEdge = Path()
            topEdge.move(to: CGPoint(x: 0, y: 0.5))
            topEdge.addLine(to: CGPoint(x: size.width, y: 0.5))
            context.stroke(
                topEdge,
                with: .color(highlight.opacity(reduceTransparency ? 0.34 : 0.62)),
                style: StrokeStyle(lineWidth: 1)
            )

            var frontEdge = Path()
            frontEdge.move(to: CGPoint(x: sideSlope, y: bevelHeight))
            frontEdge.addLine(to: CGPoint(x: size.width - sideSlope, y: bevelHeight))
            context.stroke(
                frontEdge,
                with: .color(deep.opacity(reduceTransparency ? 0.48 : 0.78)),
                style: StrokeStyle(lineWidth: 1.4)
            )

            for y in stride(from: bevelHeight + 5, through: size.height - 2, by: CGFloat(8)) {
                let progress = (y - bevelHeight) / max(size.height - bevelHeight, 1)
                let inset = sideSlope + ((lowerInset - sideSlope) * progress)
                var grain = Path()
                grain.move(to: CGPoint(x: inset + 3, y: y))
                grain.addCurve(
                    to: CGPoint(x: size.width - inset - 3, y: y + 0.8),
                    control1: CGPoint(x: size.width * 0.32, y: y - 1.5),
                    control2: CGPoint(x: size.width * 0.67, y: y + 2)
                )
                context.stroke(
                    grain,
                    with: .color(deep.opacity(reduceTransparency ? 0.10 : 0.18)),
                    style: StrokeStyle(lineWidth: 0.7)
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct MapParchmentSurface: View {
    let tileSize: CGFloat
    let mapSize: CGSize
    let gridOrigin: CGPoint?
    let theme: PlaytestFrameTheme

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        tileSize: CGFloat,
        mapSize: CGSize,
        gridOrigin: CGPoint? = nil,
        theme: PlaytestFrameTheme = .editor
    ) {
        self.tileSize = tileSize
        self.mapSize = mapSize
        self.gridOrigin = gridOrigin
        self.theme = theme
    }

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let bounds = CGRect(origin: .zero, size: size)
                if theme.usesFlatParchment {
                    context.fill(
                        Path(bounds),
                        with: .color(theme.parchmentGradient[0])
                    )
                } else {
                    context.fill(
                        Path(bounds),
                        with: .linearGradient(
                            Gradient(colors: [
                                theme.parchmentGradient[0],
                                theme.parchmentGradient[1],
                                theme.parchmentGradient[2]
                            ]),
                            startPoint: CGPoint(x: 0, y: 0),
                            endPoint: CGPoint(x: size.width, y: size.height)
                        )
                    )
                }

                drawPaperGrid(context: &context, size: size)
            }
            .overlay {
                if !theme.usesFlatParchment {
                    LinearGradient(
                        colors: [
                            theme.parchmentHighlight.opacity(reduceTransparency ? 0.16 : 0.27),
                            .clear,
                            theme.parchmentShadow.opacity(reduceTransparency ? 0.07 : 0.13)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
            .accessibilityHidden(true)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func drawPaperGrid(context: inout GraphicsContext, size: CGSize) {
        let gridColor = theme.gridColor
        let regularOpacity = reduceTransparency
            ? min(theme.gridRegularOpacity * 1.65, 0.20)
            : theme.gridRegularOpacity
        let majorOpacity = reduceTransparency
            ? min(theme.gridMajorOpacity * 1.65, 0.24)
            : theme.gridMajorOpacity
        let mapOrigin = gridOrigin ?? CGPoint(
            x: (size.width - mapSize.width) / 2,
            y: (size.height - mapSize.height) / 2
        )

        drawGridLines(
            context: &context,
            size: size,
            origin: mapOrigin.x,
            length: size.height,
            isMajor: { index in index.isMultiple(of: 4) },
            makePath: { position in
                var path = Path()
                path.move(to: CGPoint(x: position, y: 0))
                path.addLine(to: CGPoint(x: position, y: size.height))
                return path
            },
            color: gridColor,
            regularOpacity: regularOpacity,
            majorOpacity: majorOpacity
        )

        drawGridLines(
            context: &context,
            size: size,
            origin: mapOrigin.y,
            length: size.width,
            isMajor: { index in index.isMultiple(of: 4) },
            makePath: { position in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: position))
                path.addLine(to: CGPoint(x: size.width, y: position))
                return path
            },
            color: gridColor,
            regularOpacity: regularOpacity,
            majorOpacity: majorOpacity
        )
    }

    private func drawGridLines(
        context: inout GraphicsContext,
        size: CGSize,
        origin: CGFloat,
        length: CGFloat,
        isMajor: (Int) -> Bool,
        makePath: (CGFloat) -> Path,
        color: Color,
        regularOpacity: Double,
        majorOpacity: Double
    ) {
        var position = origin
        var index = 0
        while position <= length {
            if position >= 0 {
                let major = isMajor(index)
                context.stroke(
                    makePath(position),
                    with: .color(color.opacity(major ? majorOpacity : regularOpacity)),
                    style: StrokeStyle(lineWidth: major ? 0.9 : 0.6)
                )
            }
            position += tileSize
            index += 1
        }

        position = origin - tileSize
        index = 1
        while position >= 0 {
            let major = isMajor(index)
            context.stroke(
                makePath(position),
                with: .color(color.opacity(major ? majorOpacity : regularOpacity)),
                style: StrokeStyle(lineWidth: major ? 0.9 : 0.6)
            )
            position -= tileSize
            index += 1
        }
    }
}

struct MapWoodSurface: View {
    let theme: PlaytestFrameTheme

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: theme.woodGradient,
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                MapWoodGrain(theme: theme)
            }
    }
}

private struct MapWoodGrain: View {
    let theme: PlaytestFrameTheme

    var body: some View {
        Canvas { context, size in
            let dark = theme.woodGrainDark
            let light = theme.woodGrainLight

            for y in stride(from: CGFloat(7), through: size.height, by: CGFloat(18)) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addCurve(
                    to: CGPoint(x: size.width, y: y + 1.5),
                    control1: CGPoint(x: size.width * 0.30, y: y - 3),
                    control2: CGPoint(x: size.width * 0.68, y: y + 4)
                )
                context.stroke(path, with: .color(dark.opacity(0.15)), style: StrokeStyle(lineWidth: 0.8))
            }

            for x in stride(from: CGFloat(10), through: size.width, by: CGFloat(28)) {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addCurve(
                    to: CGPoint(x: x + 2, y: size.height),
                    control1: CGPoint(x: x - 4, y: size.height * 0.30),
                    control2: CGPoint(x: x + 5, y: size.height * 0.72)
                )
                context.stroke(path, with: .color(light.opacity(0.13)), style: StrokeStyle(lineWidth: 0.7))
            }

            let knotCenters = [
                CGPoint(x: size.width * 0.16, y: size.height * 0.32),
                CGPoint(x: size.width * 0.82, y: size.height * 0.68)
            ]
            for center in knotCenters {
                let knot = CGRect(x: center.x - 8, y: center.y - 3, width: 16, height: 6)
                context.stroke(Path(ellipseIn: knot), with: .color(dark.opacity(0.16)), style: StrokeStyle(lineWidth: 1))
                context.stroke(Path(ellipseIn: knot.insetBy(dx: 3, dy: 1)), with: .color(light.opacity(0.16)), style: StrokeStyle(lineWidth: 0.8))
            }
        }
        .allowsHitTesting(false)
    }
}
