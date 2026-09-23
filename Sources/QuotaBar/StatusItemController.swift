import AppKit
import Combine
import QuotaBarCore
import SwiftUI

/// Owns the real menu bar item.
///
/// QuotaBar used to hand SwiftUI's `MenuBarExtra` a label containing a custom
/// `Shape`. The status item host keeps the `Text` from such a label and drops the
/// shape, which is why the captain saw a bare percentage with no mark while the
/// offscreen renderer insisted every mark drew fine. An `NSStatusItem` takes an
/// `NSImage` and a title, so that is what QuotaBar gives it now.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []
    private var appearanceObservation: NSKeyValueObservation?

    /// The plate under the whole item. It is a sibling layer behind the
    /// button's own, not the button layer's background.
    ///
    /// The background was what it used to be, and it could only ever fill the
    /// button's bounds - AppKit's padding included - so the plate could not be
    /// brought in to hug the readout. A sublayer of the *button* is no good
    /// either: the button draws its title into its layer's contents and
    /// sublayers composite above that, so the plate would cover the number.
    /// The button's superview is layer-backed and draws nothing of its own, so
    /// a layer inserted below the button's layer there lands underneath both
    /// the mark and the digits and can be any size it likes.
    private let plateLayer = CALayer()

    /// Whether the panel is up. The item says so, because macOS does not: the
    /// system's own highlight is drawn while the mouse is down and is gone by
    /// the time the panel is on screen.
    private var isPanelOpen = false

    /// What was last pushed into the button. The self-test reads this to compare
    /// the model's intent against what the status item actually received.
    private(set) var rendered = RenderedStatusItem.empty

    struct RenderedStatusItem: Equatable {
        var provider: String?
        var title: String
        var hasImage: Bool
        var imageIsTemplate: Bool
        var imageSize: NSSize
        var usedVendorMark: Bool

        static let empty = RenderedStatusItem(
            provider: nil, title: "", hasImage: false, imageIsTemplate: false,
            imageSize: .zero, usedVendorMark: false)
    }

    /// The default face, at the size `MenuBarMetrics` sets. Every choice is
    /// derived from it, so every readout keeps the tabular figures the menu bar
    /// needs - AppKit draws this title and the popover's own `.monospacedDigit()`
    /// never reaches it.
    static let titleFont = font(for: .system)

    /// The captain's chosen face, still with tabular figures. The design is
    /// applied to the monospaced-digit system font and the figure-spacing
    /// feature is re-stated on the result, because a design substitution can
    /// otherwise drop it and let a 1 come out narrower than a 4.
    static func font(for choice: MenuBarFontChoice) -> NSFont {
        let base = NSFont.monospacedDigitSystemFont(
            ofSize: MenuBarMetrics.titleSize, weight: MenuBarMetrics.titleWeight)
        let tabular: [[NSFontDescriptor.FeatureKey: Int]] = [[
            .typeIdentifier: kNumberSpacingType,
            .selectorIdentifier: kMonospacedNumbersSelector,
        ]]

        var descriptor = base.fontDescriptor
        if let design = choice.systemDesign, let designed = descriptor.withDesign(design) {
            descriptor = designed
        }
        descriptor = descriptor.addingAttributes([.featureSettings: tabular])
        return NSFont(descriptor: descriptor, size: MenuBarMetrics.titleSize) ?? base
    }

    /// The one plate drawn under the whole item: the backing that covers mark
    /// and number together, the indication that the panel is open, or the two
    /// composited. `nil` means no plate at all.
    ///
    /// The colour decision is `MenuBarAppearance.itemPlate`; this only turns it
    /// into AppKit's types and adds the shared corner radius.
    static func wholeItemPlate(
        appearance: MenuBarAppearance,
        dark: Bool,
        open: Bool = false) -> (color: NSColor, cornerRadius: CGFloat)?
    {
        guard let plate = appearance.itemPlate(dark: dark, open: open) else { return nil }
        return (
            NSColor(plate.color).withAlphaComponent(plate.opacity),
            ProviderMarkImage.menuBarSide(for: appearance) * ProviderMarkImage.backingCornerFraction)
    }

    /// Where that plate goes inside the button: hard against the title, with
    /// `MenuBarMetrics.plateHugFraction` of the mark's side either side of it.
    ///
    /// Not the button's bounds. A variable-length status item is about 10pt
    /// wider than its own title on each side - AppKit's padding, not ours - and
    /// a plate filling the bounds framed the readout instead of backing it.
    /// What it hugs is the title's measured width, which is the reserved
    /// three-digit column and therefore the same at 4% as at 100%, so the plate
    /// keeps one width as the quota falls.
    /// Takes an `NSButton` rather than the status one so the tests can measure
    /// it without a menu bar.
    static func wholeItemPlateFrame(
        in button: NSButton,
        appearance: MenuBarAppearance = .default) -> NSRect
    {
        let bounds = button.bounds
        let side = ProviderMarkImage.menuBarSide(for: appearance)
        let hug = side * MenuBarMetrics.plateHugFraction
        let titleWidth = button.attributedTitle.size().width
        guard titleWidth > 0, titleWidth + hug * 2 < bounds.width else { return bounds }
        return NSRect(
            x: ((bounds.width - titleWidth) / 2 - hug).rounded(),
            y: bounds.minY,
            width: (titleWidth + hug * 2).rounded(),
            height: bounds.height)
    }

    /// The mark and its number as one attributed string, with the gap between
    /// them set explicitly rather than left to AppKit.
    static func statusTitle(
        mark: NSImage,
        percent: String,
        extraUsage: String? = nil,
        appearance: MenuBarAppearance = .default) -> NSAttributedString
    {
        let titleFont = font(for: appearance.font)
        let attachment = NSTextAttachment()
        attachment.image = mark
        // The attachment reserves exactly the image, never a box of its own.
        //
        // This is the whole mechanism behind the mark-to-number gap, and it is
        // the second thing tried. The first set the gap as `.kern` on this
        // attachment character, and TextKit ignores kerning on an attachment
        // glyph - measured across the setting's entire range, every value laid
        // the item out to the same width, to three decimal places. An
        // attachment advances by its bounds and by nothing else, and bounds
        // that differ from the image stretch the artwork, so the only honest
        // place for the gap is the image itself. `ProviderMarkImage` crops it
        // there; this reserves what it produced.
        //
        // Centred on the text's own cap height, so the mark sits on the same
        // optical line as the digits rather than on the text baseline.
        attachment.bounds = NSRect(
            x: 0,
            y: (titleFont.capHeight - mark.size.height) / 2,
            width: mark.size.width,
            height: mark.size.height)

        let title = NSMutableAttributedString(attachment: attachment)
        guard !percent.isEmpty else { return title }

        let numberStart = title.length
        title.append(NSAttributedString(string: percent, attributes: [
            .font: titleFont,
            .foregroundColor: appearance.textColor().map { NSColor($0) } ?? NSColor.labelColor,
        ]))
        if percent == reservedUnknown() {
            let knownWidth = ("100%" as NSString).size(withAttributes: [.font: titleFont]).width
            let unknownWidth = (percent as NSString).size(withAttributes: [.font: titleFont]).width
            // NSTextAttachment's layout applies this attribute across all four
            // character slots in the appended title.
            let gaps = max(percent.count, 1)
            title.addAttribute(
                .kern, value: (knownWidth - unknownWidth) / CGFloat(gaps),
                range: NSRange(location: numberStart, length: percent.count))
        }
        correctReservedPadding(in: title, from: numberStart, font: titleFont)
        if let extraUsage {
            title.append(NSAttributedString(string: "  \(extraUsage)", attributes: [
                .font: titleFont,
                .foregroundColor: appearance.textColor().map { NSColor($0) } ?? NSColor.labelColor,
            ]))
        }
        return title
    }

    /// FIGURE SPACE is exactly one digit wide in most faces, which is the whole
    /// reason `reservedPercent` pads with it - but "most" is not "every". The
    /// serif face draws it narrower than a digit, so a 9% item came out narrower
    /// than a 100% one and the menu bar moved as the quota fell. Measuring the
    /// two in the chosen face and kerning away the difference makes the reserved
    /// column hold in any face.
    ///
    /// The kern goes on the pad run itself, not on everything from the first pad
    /// to the end of the string. `.kern` adds its value after every character in
    /// its range, so a range that reached over the digits would widen the number
    /// as well and move the percent sign that the column exists to hold still.
    private static func correctReservedPadding(
        in title: NSMutableAttributedString, from start: Int, font: NSFont)
    {
        let text = title.string as NSString
        let pad = Character(reservedPad)
        var length = 0
        while start + length < title.length,
              Character(text.substring(with: NSRange(location: start + length, length: 1))) == pad
        {
            length += 1
        }
        guard length > 0 else { return }

        func width(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: [.font: font]).width
        }
        let shortfall = width("0") - width(reservedPad)
        guard abs(shortfall) > 0.01 else { return }
        title.addAttribute(
            .kern, value: shortfall, range: NSRange(location: start, length: length))
    }

    /// Where the percent sign starts, measured from the leading edge of the
    /// title. The reserved column exists so this number does not change as the
    /// quota falls, and it is the number the evidence hooks report.
    static func percentSignOffset(in title: NSAttributedString) -> CGFloat? {
        let text = title.string as NSString
        let mark = text.range(of: "%")
        guard mark.location != NSNotFound else { return nil }
        return title
            .attributedSubstring(from: NSRange(location: 0, length: mark.location))
            .size()
            .width
    }

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.behavior = [.terminationOnRemoval]
        if let button = statusItem.button {
            // The mark travels inside the attributed title as a text attachment
            // rather than in `button.image`.
            //
            // This is not decoration. `button.image` plus `button.title` puts a
            // fixed ~15pt of AppKit spacing between the two, and none of
            // `imagePosition` or `imageHugsTitle` moves it - all four
            // combinations were measured at exactly 15.0pt. Carrying the mark as
            // an attachment makes the gap a typographic one, which is ours to
            // set, and `ProviderMarkImage.menuBarGap` sets it.
            button.imagePosition = .noImage
            // Tabular figures in the menu bar too. The title is drawn by AppKit,
            // not SwiftUI, so the popover's `.monospacedDigit()` never reached
            // it: a 1 was narrower than a 4 and the item breathed as the number
            // changed.
            button.font = Self.titleFont
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        // Never animated. The dropdown should appear, not unfold.
        //
        // `animates` also governs the size transition between pages, so turning
        // it back on once the popover is up was tried - and measured. The
        // resize lands instantly either way, because the height comes from the
        // hosting controller's `preferredContentSize` and NSPopover does not
        // animate that. All `animates = true` would buy is an animated close
        // when the popover is dismissed by clicking away, which is the slow
        // unfold that was asked for removal. `resizeAnimationReport()` prints
        // the evidence from the running app.
        popover.animates = false
        popover.delegate = self
        let host = NSHostingController(
            rootView: QuotaMenuView(model: model, dismiss: { [weak self] in self?.closePopover() }))
        // The popover is built before the first snapshot arrives, so without this
        // it keeps the height of the empty "loading" state and clips the real
        // content once the quota lands.
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host

        observeModel()
        observeAppearance()
        refresh()
    }

    deinit {
        appearanceObservation?.invalidate()
    }

    // MARK: - Rendering

    /// Rebuilt whenever the focused provider, the quota numbers, or the effective
    /// appearance changes - the three things that can make the drawn mark wrong.
    func refresh() {
        guard let button = statusItem.button else { return }

        let readout = model.menuBarReadout
        let appearance = model.preferences.menuBarAppearance
        let dark = Self.isDark(button.effectiveAppearance)
        let image = ProviderMarkImage.menuBarImage(
            provider: readout.provider, dark: dark, appearance: appearance)

        let title = readout.percentRemaining.map { Self.reservedPercent($0) }
            ?? (readout.provider == nil ? "" : Self.reservedUnknown())

        button.image = nil
        button.imagePosition = .noImage
        button.font = Self.font(for: appearance.font)
        button.attributedTitle = Self.statusTitle(
            mark: image, percent: title, extraUsage: readout.extraUsageSpent,
            appearance: appearance)
        button.layoutSubtreeIfNeeded()
        applyWholeItemPlate(to: button, appearance: appearance, dark: dark)
        button.toolTip = readout.accessibilityDescription
        button.setAccessibilityLabel(readout.accessibilityDescription)

        rendered = RenderedStatusItem(
            provider: readout.provider,
            title: title + (readout.extraUsageSpent.map { "  \($0)" } ?? ""),
            hasImage: Self.markImage(in: button.attributedTitle) != nil,
            imageIsTemplate: Self.markImage(in: button.attributedTitle)?.isTemplate ?? false,
            imageSize: Self.markImage(in: button.attributedTitle)?.size ?? .zero,
            usedVendorMark: readout.provider.map { ProviderMarkImage.hasVendorMark(for: $0) } ?? false)
    }

    private func applyWholeItemPlate(
        to button: NSStatusBarButton, appearance: MenuBarAppearance, dark: Bool)
    {
        // Left over from when the plate was the button's own background. It has
        // to be cleared, not just ignored, or an install that ran the old build
        // keeps a full-width plate behind the hugging one.
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.layer?.cornerRadius = 0

        guard let host = button.superview, let hostLayer = host.layer else { return }
        if plateLayer.superlayer !== hostLayer {
            hostLayer.insertSublayer(plateLayer, at: 0)
        }

        guard let plate = Self.wholeItemPlate(
            appearance: appearance, dark: dark, open: isPanelOpen)
        else {
            plateLayer.isHidden = true
            return
        }

        // The plate follows the button's frame and must not animate: an implicit
        // fade or slide as the number changes is exactly the movement the rest
        // of this file exists to prevent.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plateLayer.isHidden = false
        plateLayer.frame = host.convert(
            Self.wholeItemPlateFrame(in: button, appearance: appearance), from: button)
        plateLayer.backgroundColor = plate.color.cgColor
        plateLayer.cornerRadius = plate.cornerRadius
        plateLayer.cornerCurve = .continuous
        CATransaction.commit()
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The padding character: FIGURE SPACE, which in a tabular face is exactly
    /// one digit wide. `correctReservedPadding` makes up the difference in the
    /// faces where it is not.
    static let reservedPad = "\u{2007}"

    /// Tabular figures stop a 1 being narrower than a 4, but they do not stop
    /// 9% being narrower than 100%. The number is padded to three digit widths
    /// with FIGURE SPACE, so the item keeps one width from 0% to 100% and
    /// nothing in the menu bar shuffles as the quota falls.
    ///
    /// The padding is **leading**, so the digits are right-aligned in a
    /// three-digit column and the percent sign lands in the same place at 4%,
    /// 44% and 100%. Trailing padding also held the item's width, but it let the
    /// number slide left inside that width as the quota fell, which is a moving
    /// readout wearing a fixed frame.
    ///
    /// Leading padding was tried once before and rejected, and it is worth
    /// saying why it comes back. At the time the mark and the number were
    /// separated by AppKit's own ~15pt, so the column opened on top of a gap
    /// that was already far too wide and the whole readout drifted away from its
    /// mark. That gap is now `MenuBarMetrics.markTrailingMargin`, cropped into
    /// the mark's own image rather than spent on spacing - so the column starts
    /// hard against the mark at every value, and what sits between them is the
    /// reserved room for the hundreds digit rather than spacing.
    static func reservedPercent(_ value: Double) -> String {
        let text = QuotaFormatting.percent(value)
        let digits = text.filter(\.isNumber).count
        return String(repeating: reservedPad, count: max(0, 3 - digits)) + text
    }

    /// An explicit unknown percentage with the same four glyph slots as 100%.
    static func reservedUnknown() -> String { "???%" }

    private func observeModel() {
        // `objectWillChange` fires before the value lands, so read on the next
        // turn of the run loop rather than re-deriving the old readout.
        for publisher in [model.objectWillChange, model.preferences.objectWillChange] {
            publisher
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.refresh() }
                .store(in: &cancellables)
        }
    }

    private func observeAppearance() {
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.refresh() }
        }
        // The menu bar can flip independently of the app's own appearance, so
        // listen for the system-wide switch too. Reading this notification asks
        // for no permission and shows no dialog.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main)
        { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        popover.isShown ? closePopover() : showPopover()
    }

    func showPopover() {
        guard let button = statusItem.button else { return }
        model.menuOpened()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        setPanelOpen(true)
    }

    func closePopover() {
        popover.performClose(nil)
    }

    /// `NSPopoverDelegate`. The transient popover also closes by clicking away,
    /// pressing Escape or opening another menu, and none of those come back
    /// through `closePopover`, so the open state is taken from the popover
    /// itself rather than from whoever asked it to shut.
    func popoverDidClose(_ notification: Notification) {
        setPanelOpen(false)
    }

    /// Puts the item into, or out of, its open state.
    ///
    /// Two things happen. QuotaBar's own plate comes up, which is the
    /// indication that lasts. And the system's momentary highlight is cleared
    /// if it is still set: AppKit draws that one while the mouse is down, in a
    /// near-full-width pill whose colour, shape and inset no API exposes, and
    /// leaving it to linger over a plate that hugs the readout is the mismatch
    /// this avoids. Clearing it is the whole of the control there is - the
    /// highlight is not drawn by anything in this process, which is why
    /// `cacheDisplay` on the button cannot see it.
    private func setPanelOpen(_ open: Bool) {
        guard isPanelOpen != open else { return }
        isPanelOpen = open
        statusItem.button?.highlight(false)
        refresh()
    }

    // MARK: - Evidence hooks

    var button: NSStatusBarButton? { statusItem.button }

    /// The mark the status item is actually carrying. This is the guard against
    /// the original bug: a menu bar with a percentage and no icon.
    static func markImage(in title: NSAttributedString) -> NSImage? {
        var found: NSImage?
        title.enumerateAttribute(
            .attachment, in: NSRange(location: 0, length: title.length))
        { value, _, stop in
            if let image = (value as? NSTextAttachment)?.image {
                found = image
                stop.pointee = true
            }
        }
        return found
    }

    /// The plate as it actually landed, or `nil` when none is drawn. The
    /// evidence hooks read this: the plate is a layer of its own now, so the
    /// button's layer background - which used to be the plate - says nothing
    /// about it.
    var drawnPlate: (alpha: Double, cornerRadius: CGFloat, frame: NSRect)? {
        guard !plateLayer.isHidden, let alpha = plateLayer.backgroundColor?.alpha, alpha > 0
        else { return nil }
        return (Double(alpha), plateLayer.cornerRadius, plateLayer.frame)
    }

    /// What the item is actually wearing while the panel is open, and what
    /// macOS contributes to the picture.
    ///
    /// This is the hook that settles the question rather than assuming it. Two
    /// facts it reports, both established by measurement:
    ///
    /// - The system's pressed highlight is not drawn by anything in this
    ///   process. `highlight(true)` leaves a `cacheDisplay` of the button
    ///   byte-identical while changing the pixels on screen, so no colour,
    ///   shape or inset of it is QuotaBar's to set; the single bit
    ///   `NSStatusBarButton.highlight(_:)` is the whole of the control.
    /// - AppKit does not keep that highlight on for the life of an `NSPopover`.
    ///   With the panel up, the cell reports itself unhighlighted, which is why
    ///   the item needs an indication of its own.
    ///
    /// `cachedDelta` is the first of those, measured live: the mean channel
    /// difference between the button's own drawing highlighted and not. Zero
    /// means the highlight is entirely the system's.
    func openStateReport() async -> String {
        guard let button = statusItem.button else { return "button=MISSING" }

        func plate() -> String {
            let drawn = drawnPlate
            return String(
                format: "alpha=%.3f w=%.0f", drawn?.alpha ?? 0, drawn?.frame.width ?? 0)
        }

        // An earlier hook may still have a popover on the way out, and
        // `performClose` does not land the delegate callback before this runs,
        // so take the shut state from a settled item rather than a closing one.
        closePopover()
        try? await Task.sleep(nanoseconds: 300_000_000)
        refresh()
        let closed = plate()

        let unhighlighted = buttonMean(button)
        button.highlight(true)
        button.display()
        let highlighted = buttonMean(button)
        button.highlight(false)
        button.display()

        showPopover()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let open = plate()
        let cellWhileOpen = button.cell?.isHighlighted ?? false
        closePopover()
        try? await Task.sleep(nanoseconds: 300_000_000)
        let reclosed = plate()

        return String(
            format: "closed[%@] open[%@] reclosed[%@] restored=%@ "
                + "systemHighlightInAppDrawing=%.4f cellHighlightedWhilePanelOpen=%@",
            closed, open, reclosed,
            closed == reclosed ? "yes" : "NO",
            abs(highlighted - unhighlighted),
            cellWhileOpen ? "yes" : "no")
    }

    /// The mean channel value of the button's own drawing. Used only to show
    /// that the system highlight never appears in it.
    private func buttonMean(_ button: NSStatusBarButton) -> Double {
        let bounds = button.bounds
        guard bounds.width > 1, bounds.height > 1,
              let bitmap = button.bitmapImageRepForCachingDisplay(in: bounds)
        else { return 0 }
        button.cacheDisplay(in: bounds, to: bitmap)
        var total = 0.0
        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let alpha = color.alphaComponent
                total += (color.redComponent + color.greenComponent + color.blueComponent)
                    / 3 * alpha
                count += 1
            }
        }
        return count > 0 ? total / Double(count) : 0
    }

    /// Opens the popover, measures what SwiftUI actually laid out inside it, and
    /// closes it again. `ImageRenderer` cannot draw a `ScrollView`, so the
    /// offscreen layout renders use a non-scrolling variant of the same views -
    /// this is what proves the scrolling one really hosts and sizes.
    func popoverReport() async -> String {
        showPopover()
        defer { closePopover() }

        guard let view = popover.contentViewController?.view else {
            return "shown=\(popover.isShown) content=MISSING"
        }
        // Let AppKit settle the popover onto the hosting controller's preferred
        // size before measuring, or the report describes the frame it opened at.
        try? await Task.sleep(nanoseconds: 400_000_000)
        view.layoutSubtreeIfNeeded()
        let fitting = view.fittingSize
        return String(
            format: "shown=%@ animates=%@ contentSize=%.0fx%.0f fitting=%.0fx%.0f subviews=%d",
            popover.isShown ? "yes" : "NO",
            popover.animates ? "yes" : "no",
            view.frame.width, view.frame.height,
            fitting.width, fitting.height,
            view.subviews.count)
    }

    /// Walks every page with the popover open and reports the panel size each
    /// one settles at. The captain's complaint is that switching providers moves
    /// things, so the evidence is a list of sizes that had better all be equal.
    /// The page and the menu bar focus are put back exactly as they were.
    func pageSizeReport() async -> [String] {
        let originalPage = model.resolvedPage
        let originalFocus = model.preferences.focusedProvider
        defer {
            model.select(originalPage)
            if !originalFocus.isEmpty { model.preferences.focus(on: originalFocus) }
            refresh()
        }

        showPopover()
        defer { closePopover() }

        var lines: [String] = []
        // Claude and Codex twice, because switching back and forth is how he
        // actually noticed it.
        let pages: [MenuPage] = [.overview]
            + model.tabProviders.map { .provider($0.provider) }
            + model.tabProviders.prefix(2).map { .provider($0.provider) }

        for page in pages {
            model.select(page)
            guard let view = popover.contentViewController?.view else { continue }
            try? await Task.sleep(nanoseconds: 300_000_000)
            view.layoutSubtreeIfNeeded()
            let name: String
            switch page {
            case .overview: name = "overview"
            case let .provider(key): name = key
            }
            lines.append(String(
                format: "%@=%.0fx%.0f", name, view.frame.width, view.frame.height))
        }
        return lines
    }

    /// Establishes whether the popover's size transition is actually animated on
    /// this surface, rather than assuming it either way. Selects a page, samples
    /// the frame immediately, then samples again after the animation would have
    /// finished. A height that is mid-flight on the first sample and settled on
    /// the second is a real animation; two identical samples mean the resize
    /// landed instantly whatever `animates` says.
    func resizeAnimationReport() async -> String {
        let originalPage = model.resolvedPage
        let originalFocus = model.preferences.focusedProvider
        defer {
            model.select(originalPage)
            if !originalFocus.isEmpty { model.preferences.focus(on: originalFocus) }
            refresh()
        }

        showPopover()
        defer { closePopover() }

        guard let view = popover.contentViewController?.view,
              let provider = model.tabProviders.first
        else { return "inconclusive=no-provider-page animates=\(popover.animates)" }

        func settle() async {
            try? await Task.sleep(nanoseconds: 450_000_000)
            view.layoutSubtreeIfNeeded()
        }

        // Overview against a provider page: the largest height difference the
        // app actually has, so an animation has something to animate.
        let wasAnimating = popover.animates
        popover.animates = true
        defer { popover.animates = wasAnimating }

        model.select(.overview)
        await settle()
        let from = view.frame.height

        model.select(.provider(provider.provider))
        try? await Task.sleep(nanoseconds: 40_000_000)
        view.layoutSubtreeIfNeeded()
        let immediate = view.frame.height
        await settle()
        let settled = view.frame.height

        let animated = abs(immediate - settled) > 1
        return String(
            format: "animates=%@ from=%.0f immediate=%.0f settled=%.0f transition=%@ "
                + "sizesDiffer=%@",
            popover.animates ? "yes" : "no",
            from, immediate, settled,
            animated ? "animated" : "instant",
            abs(from - settled) > 1 ? "yes" : "no")
    }
}

extension MenuBarFontChoice {
    /// The system font design behind each choice. `nil` is the system face
    /// itself, which needs no substitution.
    var systemDesign: NSFontDescriptor.SystemDesign? {
        switch self {
        case .system: nil
        case .rounded: .rounded
        case .monospaced: .monospaced
        case .serif: .serif
        }
    }
}
