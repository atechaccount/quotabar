import CoreGraphics
import QuotaBarCore
import SwiftUI
import Testing
@testable import QuotaBar

/// The marks have to read at menu bar size, so each one must actually draw
/// something, fill a fair share of its box, and stay inside it.
struct ProviderMarkTests {
    private let box = CGRect(x: 0, y: 0, width: 32, height: 32)

    @Test(arguments: BrandMark.allCases)
    func everyMarkDrawsInsideItsBox(_ mark: BrandMark) {
        let path = ProviderMarkShape(mark: mark).path(in: box)

        #expect(!path.isEmpty, "\(mark) drew nothing")

        let bounds = path.boundingRect
        #expect(bounds.width > box.width * 0.3, "\(mark) is too narrow to recognize")
        #expect(bounds.height > box.height * 0.3, "\(mark) is too short to recognize")
        #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(bounds), "\(mark) draws outside its box")
    }

    /// Samples the filled area on a grid so two marks are compared by the shape
    /// they actually cover, not just by their bounding boxes.
    private func signature(_ mark: BrandMark) -> String {
        let path = ProviderMarkShape(mark: mark).path(in: box)
        var bits = ""
        for row in 0..<12 {
            for column in 0..<12 {
                let point = CGPoint(
                    x: box.minX + (CGFloat(column) + 0.5) / 12 * box.width,
                    y: box.minY + (CGFloat(row) + 0.5) / 12 * box.height)
                bits += path.contains(point) ? "1" : "0"
            }
        }
        return bits
    }

    @Test
    func everyMarkCoversAUsableShareOfItsBox() {
        for mark in BrandMark.allCases {
            let filled = signature(mark).filter { $0 == "1" }.count
            let coverage = Double(filled) / 144 * 100
            #expect(coverage > 12, "\(mark) covers only \(coverage)% and will look faint")
            #expect(coverage < 92, "\(mark) is nearly a solid block and reads as a blob")
        }
    }

    @Test
    func noTwoMarksDrawTheSameShape() {
        var seen: [String: BrandMark] = [:]
        for mark in BrandMark.allCases {
            let signature = signature(mark)
            if let clash = seen[signature] {
                Issue.record("\(mark) draws the same shape as \(clash)")
            }
            seen[signature] = mark
        }
    }

    /// The crescent and ring are cut out of a larger shape; a filling mistake
    /// there leaves a stray sliver outside the disc or fills the hole in.
    @Test
    func subtractedMarksActuallyHaveTheirHoleRemoved() {
        let ring = ProviderMarkShape(mark: .ring).path(in: box)
        #expect(!ring.contains(CGPoint(x: box.midX, y: box.midY)), "the ring's hole is filled in")
        #expect(ring.contains(CGPoint(x: box.midX, y: box.minY + 2)), "the ring's band is missing")

        let crescent = ProviderMarkShape(mark: .crescent).path(in: box)
        #expect(!crescent.contains(CGPoint(x: box.maxX - 3, y: box.midY)), "the crescent's bite is filled in")
        #expect(crescent.contains(CGPoint(x: box.minX + 2, y: box.midY)), "the crescent's body is missing")
    }
}
