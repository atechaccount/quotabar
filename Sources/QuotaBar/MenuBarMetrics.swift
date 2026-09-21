import AppKit
import QuotaBarCore

/// The size of the menu bar item itself, in one place.
///
/// The mark and the number beside it are read as one object, so they are sized
/// as one: the design sizes below are the item as it was first built, and
/// `scale` is the single factor that shrinks the pair. Changing the factor moves
/// the mark and the digits together and cannot put them out of proportion with
/// each other, which is the same arrangement `Typography` uses for the popover.
///
/// This is deliberately separate from `Typography`. That factor scales the
/// dropdown, which is QuotaBar's own surface; this one scales an item sitting in
/// the system menu bar next to everybody else's, and the two were asked to be
/// different sizes.
///
/// It is also deliberately not a setting. `MenuBarAppearance` carries what the
/// captain chooses about the item - its plate, its colours, its face - and every
/// one of those is a matter of taste with no better answer. The size is not: it
/// was simply too big, and one right size beats a control nobody should have to
/// find. Adding it there later is a small change if that turns out to be wrong.
enum MenuBarMetrics {
    /// The captain read the original item - a 20pt mark against the 13pt system
    /// font - as too large for the menu bar. This is that item, smaller.
    static let scale: CGFloat = 0.85

    /// Design sizes, before the factor.
    private static let designSide: CGFloat = 20
    private static let designTitleSize: CGFloat = NSFont.systemFontSize

    /// Rounded to a half point: AppKit will happily lay out at 11.05pt, but a
    /// size that lands on the pixel grid keeps the small digits crisp.
    private static func rounded(_ value: CGFloat) -> CGFloat {
        (value * 2).rounded() / 2
    }

    /// The whole menu bar image, backing plate included.
    static let side = rounded(designSide * scale)

    /// The menu bar has a fixed vertical lane. Keep two points clear above and
    /// below the backing plate, and reserve the attachment at this exact size.
    static let markSizeRange: ClosedRange<CGFloat> = (side * 0.75)...min(
        designSide, NSStatusBar.system.thickness - 4)

    static func markSide(for appearance: MenuBarAppearance) -> CGFloat {
        min(max(CGFloat(appearance.markSize), markSizeRange.lowerBound), markSizeRange.upperBound)
    }

    /// The number's point size.
    static let titleSize = rounded(designTitleSize * scale)

    /// Smaller text on a translucent menu bar is the one thing this change risks,
    /// so the weight goes up by one step as the size comes down. Medium holds its
    /// stroke against a bright wallpaper showing through where regular at this
    /// size starts to thin out; it is still lighter than the system menu titles
    /// beside it.
    static let titleWeight: NSFont.Weight = .medium

    /// How far the mark is inset inside its backing plate. A fraction of the
    /// side rather than a fixed number, so the plate keeps the same visual
    /// margin at any scale.
    static let backingInsetFraction: CGFloat = 0.1

    /// How far the plate that covers the mark and the number together sits
    /// outside them, on each side.
    ///
    /// The item is wider than its own content: AppKit gives a variable-length
    /// status item about 10pt of its own padding on each side, and a plate
    /// filling the button's bounds inherited all of it, which read as a frame
    /// around the readout rather than a backing behind it. The plate is now
    /// placed against the title and given this much room.
    ///
    /// A fraction of the side, like every other margin here, so it holds its
    /// proportion at whatever scale the item is drawn at. What it hugs is the
    /// reserved three-digit column, not the ink: the column is the same width
    /// at 4% as at 100%, and a plate that tracked the ink would breathe as the
    /// quota fell.
    static let plateHugFraction: CGFloat = 0.12

    /// The clear space left after the mark's own box, before the readout starts.
    ///
    /// This is the whole of QuotaBar's contribution to the mark-to-number gap,
    /// and it is the only part of it the app controls. What the eye reads as the
    /// gap is this margin, plus whatever transparent padding the vendor drew
    /// into its own artwork, plus the left side bearing of the readout's first
    /// glyph - and the last of those is the font's, not ours.
    ///
    /// It used to be a setting. It never worked: the spacing was applied as
    /// `.kern` on the mark's text attachment and TextKit ignores kerning on an
    /// attachment glyph, so the slider's whole range laid out identically.
    /// Spacing a text attachment is geometry, not typography - the attachment
    /// advances by its image's width and by nothing else - so the margin is part
    /// of the image now and `markTrailingTrim` is what crops it to this size.
    ///
    /// Not scaled, and a hard floor rather than a starting point. It is measured
    /// against the tightest case the settings can produce - the app's own glyph,
    /// whose ink fills its box, in front of the `?` of an unknown readout, whose
    /// left bearing is the smallest of any leading glyph - and at 0.7pt that
    /// case still renders about a point of clear space, two device pixels on a
    /// Retina display. Below this the two run together into one smudge. The
    /// self-test's `menubargap` sweep is what holds it there.
    static let markTrailingMargin: CGFloat = 0.7

    /// How much of the mark image's trailing edge is cropped away, which is the
    /// same thing as how far the readout moves in towards the mark.
    ///
    /// The mark is drawn inset inside its plate, so the image already carried a
    /// full inset of transparent padding after the ink; all but
    /// `markTrailingMargin` of that is spare room, and this spends it. Never
    /// more than the inset, or the crop would reach the ink itself.
    static func markTrailingTrim(for side: CGFloat) -> CGFloat {
        max(0, side * backingInsetFraction - markTrailingMargin)
    }

    /// The mark image's width: its square box, less the trailing crop. The
    /// height stays the full box, because that is the item's vertical lane.
    static func markImageWidth(for side: CGFloat) -> CGFloat {
        side - markTrailingTrim(for: side)
    }
}
