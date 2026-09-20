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

    /// The plate that covers the mark and the number together, or `nil` for
    /// every other backing scope.
    ///
    /// It is the status item button's own layer background, not a sublayer and
    /// not an image. A sublayer would draw on top of the title AppKit renders
    /// into the layer's contents, and no image can reach behind text the button
    /// lays out itself; a layer background is the one plate that lands
    /// underneath both.
    static func wholeItemPlate(
        appearance: MenuBarAppearance, dark: Bool) -> (color: NSColor, cornerRadius: CGFloat)?
    {
        guard let backing = appearance.wholeItemBacking(dark: dark) else { return nil }
        return (
            NSColor(backing.color).withAlphaComponent(backing.opacity),
            ProviderMarkImage.menuBarSide * ProviderMarkImage.backingCornerFraction)
    }

    /// The mark and its number as one attributed string, with the gap between
    /// them set explicitly rather than left to AppKit.
    static func statusTitle(
        mark: NSImage,
        percent: String,
        appearance: MenuBarAppearance = .default) -> NSAttributedString
    {
        let titleFont = font(for: appearance.font)
        let attachment = NSTextAttachment()
        attachment.image = mark
        let side = ProviderMarkImage.menuBarSide
        // Centred on the text's own cap height, so the mark sits on the same
        // optical line as the digits rather than on the text baseline.
        attachment.bounds = NSRect(
            x: 0,
            y: (titleFont.capHeight - side) / 2,
            width: side,
            height: side)

        let title = NSMutableAttributedString(attachment: attachment)
        guard !percent.isEmpty else { return title }

        // The mark image carries its backing inset of transparent padding on its
        // trailing edge, which is part of what the eye reads as the gap, so the
        // kern only has to make up the difference. That inset scales with the
        // mark, so the kern is derived from it rather than written down: the
        // whole gap works out to `menuBarGap` at any size.
        let kern = ProviderMarkImage.menuBarGap - ProviderMarkImage.menuBarBackingInset
        title.addAttribute(
            .kern, value: kern, range: NSRange(location: title.length - 1, length: 1))
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
        return title
    }

    /// FIGURE SPACE is exactly one digit wide in most faces, which is the whole
    /// reason `reservedPercent` pads with it - but "most" is not "every". The
    /// serif face draws it narrower than a digit, so a 9% item came out narrower
    /// than a 100% one and the menu bar moved as the quota fell. Measuring the
    /// two in the chosen face and kerning away the difference makes the reserved
    /// column hold in any face.
    private static func correctReservedPadding(
        in title: NSMutableAttributedString, from start: Int, font: NSFont)
    {
        let padding = "\u{2007}"
        let text = title.string as NSString
        let range = NSRange(location: start, length: title.length - start)
        let first = text.range(of: padding, options: [], range: range)
        guard first.location != NSNotFound else { return }
        let padded = NSRange(location: first.location, length: title.length - first.location)

        func width(_ string: String) -> CGFloat {
            (string as NSString).size(withAttributes: [.font: font]).width
        }
        let shortfall = width("0") - width(padding)
        guard abs(shortfall) > 0.01 else { return }
        title.addAttribute(.kern, value: shortfall, range: padded)
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
            mark: image, percent: title, appearance: appearance)
        applyWholeItemPlate(to: button, appearance: appearance, dark: dark)
        button.toolTip = readout.accessibilityDescription
        button.setAccessibilityLabel(readout.accessibilityDescription)

        rendered = RenderedStatusItem(
            provider: readout.provider,
            title: title,
            hasImage: Self.markImage(in: button.attributedTitle) != nil,
            imageIsTemplate: Self.markImage(in: button.attributedTitle)?.isTemplate ?? false,
            imageSize: Self.markImage(in: button.attributedTitle)?.size ?? .zero,
            usedVendorMark: readout.provider.map { ProviderMarkImage.hasVendorMark(for: $0) } ?? false)
    }

    private func applyWholeItemPlate(
        to button: NSStatusBarButton, appearance: MenuBarAppearance, dark: Bool)
    {
        button.wantsLayer = true
        guard let plate = Self.wholeItemPlate(appearance: appearance, dark: dark) else {
            button.layer?.backgroundColor = NSColor.clear.cgColor
            button.layer?.cornerRadius = 0
            return
        }
        button.layer?.backgroundColor = plate.color.cgColor
        button.layer?.cornerRadius = plate.cornerRadius
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Tabular figures stop a 1 being narrower than a 4, but they do not stop
    /// 9% being narrower than 100%. The number is padded to three digit widths
    /// with FIGURE SPACE, which in a tabular font is exactly one digit wide, so
    /// the item keeps one width from 0% to 100% and nothing in the menu bar
    /// shuffles as the quota falls.
    ///
    /// The padding is trailing, not leading: on the leading edge it opened a gap
    /// between the mark and its number for every one and two digit value, which
    /// is the whole reason the spacing read as too wide.
    static func reservedPercent(_ value: Double) -> String {
        let text = QuotaFormatting.percent(value)
        let digits = text.filter(\.isNumber).count
        return text + String(repeating: "\u{2007}", count: max(0, 3 - digits))
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
    }

    func closePopover() {
        popover.performClose(nil)
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
