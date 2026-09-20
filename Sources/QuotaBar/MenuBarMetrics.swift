import AppKit

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

    /// The whole gap between the mark and the number beside it.
    ///
    /// Not scaled. This is an optical minimum rather than a dimension of the
    /// item: it is already as small as it can be while keeping the glyphs from
    /// running into each other at every digit count, and shrinking it with
    /// everything else would spend the only margin there is. The self-test's
    /// `menubargap` sweep is what holds it above zero.
    static let gap: CGFloat = 1.5
}
