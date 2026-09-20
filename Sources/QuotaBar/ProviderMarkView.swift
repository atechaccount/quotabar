import QuotaBarCore
import SwiftUI

/// Draws each provider's mark as plain vector geometry. These are original simple
/// shapes chosen to be distinguishable at menu bar size - never vendor logo artwork.
private extension Path {
    /// Adds a closed polygon from points expressed in a 0...1 unit square.
    mutating func addLines(normalized points: [(CGFloat, CGFloat)], in box: CGRect) {
        for (index, point) in points.enumerated() {
            let resolved = CGPoint(
                x: box.minX + point.0 * box.width,
                y: box.minY + point.1 * box.height)
            index == 0 ? move(to: resolved) : addLine(to: resolved)
        }
        closeSubpath()
    }
}

struct ProviderMarkShape: Shape {
    let mark: BrandMark

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let box = CGRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side)
        var path = Path()

        switch mark {
        case .starburst:
            let center = CGPoint(x: box.midX, y: box.midY)
            let spoke = side * 0.10
            for index in 0..<8 {
                let angle = Double(index) * .pi / 4
                var ray = Path(roundedRect: CGRect(
                    x: center.x - spoke / 2,
                    y: box.minY,
                    width: spoke,
                    height: side * 0.5), cornerRadius: spoke / 2)
                ray = ray.applying(
                    CGAffineTransform(translationX: -center.x, y: -center.y)
                        .concatenating(CGAffineTransform(rotationAngle: angle))
                        .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
                path.addPath(ray)
            }

        case .ring:
            var outer = Path()
            outer.addEllipse(in: box)
            var hole = Path()
            hole.addEllipse(in: box.insetBy(dx: side * 0.28, dy: side * 0.28))
            path.addPath(outer.subtracting(hole))

        case .pointer:
            path.move(to: CGPoint(x: box.minX + side * 0.08, y: box.minY))
            path.addLine(to: CGPoint(x: box.maxX - side * 0.08, y: box.midY + side * 0.14))
            path.addLine(to: CGPoint(x: box.midX - side * 0.04, y: box.midY + side * 0.16))
            path.addLine(to: CGPoint(x: box.minX + side * 0.34, y: box.maxY))
            path.closeSubpath()

        case .lobes:
            let radius = side * 0.3
            path.addEllipse(in: CGRect(
                x: box.minX, y: box.midY - radius, width: radius * 2, height: radius * 2))
            path.addEllipse(in: CGRect(
                x: box.maxX - radius * 2, y: box.midY - radius, width: radius * 2, height: radius * 2))

        case .bolt:
            path.addLines(normalized: [
                (0.66, 0.00), (0.08, 0.57), (0.44, 0.57),
                (0.32, 1.00), (0.92, 0.41), (0.56, 0.41),
            ], in: box)

        case .crescent:
            // Subtracting keeps the result a true lune. Even-odd would also fill
            // the part of the cutting circle that falls outside the disc.
            var disc = Path()
            disc.addEllipse(in: box)
            var cut = Path()
            cut.addEllipse(in: CGRect(
                x: box.minX + side * 0.28,
                y: box.minY - side * 0.04,
                width: side,
                height: side))
            path.addPath(disc.subtracting(cut))

        case .zigzag:
            let bar = side * 0.16
            path.addRect(CGRect(x: box.minX, y: box.minY, width: side, height: bar))
            path.addRect(CGRect(x: box.minX, y: box.maxY - bar, width: side, height: bar))
            var diagonal = Path(CGRect(
                x: box.midX - bar / 2,
                y: box.minY + bar * 0.5,
                width: bar,
                height: side - bar))
            diagonal = diagonal.applying(
                CGAffineTransform(translationX: -box.midX, y: -box.midY)
                    .concatenating(CGAffineTransform(rotationAngle: .pi / 5))
                    .concatenating(CGAffineTransform(translationX: box.midX, y: box.midY)))
            path.addPath(diagonal)

        case .chevron:
            for step in 0..<2 {
                let offset = CGFloat(step) * 0.44
                path.addLines(normalized: [
                    (0.00, 1.00 - offset), (0.50, 0.62 - offset), (1.00, 1.00 - offset),
                    (1.00, 0.82 - offset), (0.50, 0.44 - offset), (0.00, 0.82 - offset),
                ], in: box)
            }

        case .hexagon:
            for index in 0..<6 {
                let angle = Double(index) * .pi / 3 - .pi / 2
                let point = CGPoint(
                    x: box.midX + cos(angle) * side / 2,
                    y: box.midY + sin(angle) * side / 2)
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()

        case .brackets:
            let bar = side * 0.15
            for leading in [true, false] {
                let x = leading ? box.minX : box.maxX - side * 0.34
                path.addRect(CGRect(x: x, y: box.minY, width: side * 0.34, height: bar))
                path.addRect(CGRect(x: x, y: box.maxY - bar, width: side * 0.34, height: bar))
                path.addRect(CGRect(
                    x: leading ? box.minX : box.maxX - bar,
                    y: box.minY,
                    width: bar,
                    height: side))
            }

        case .quatrefoil:
            let radius = side * 0.29
            for angle in stride(from: 0.0, to: 2 * .pi, by: .pi / 2) {
                path.addEllipse(in: CGRect(
                    x: box.midX + cos(angle) * side * 0.21 - radius,
                    y: box.midY + sin(angle) * side * 0.21 - radius,
                    width: radius * 2,
                    height: radius * 2))
            }

        case .dot:
            path.addEllipse(in: box.insetBy(dx: side * 0.18, dy: side * 0.18))
        }

        return path
    }
}

struct ProviderMark: View {
    let provider: String
    var size: CGFloat = 13
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ProviderMarkShape(mark: BrandColors.brand(for: provider).mark)
            .fill(
                Color(readable: BrandColors.readableColor(
                    for: provider,
                    darkAppearance: colorScheme == .dark)),
                style: FillStyle())
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Color {
    init(readable rgb: BrandRGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    init(brandHex hex: String) {
        self.init(readable: BrandColors.rgb(fromHex: hex))
    }
}
