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

    init(model: AppModel) {
        self.model = model
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.behavior = [.terminationOnRemoval]
        if let button = statusItem.button {
            button.imagePosition = .imageLeft
            // Tabular figures in the menu bar too. The title is drawn by AppKit,
            // not SwiftUI, so the popover's `.monospacedDigit()` never reached
            // it: a 1 was narrower than a 4 and the item breathed as the number
            // changed.
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize, weight: .regular)
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
        // The dropdown should appear, not unfold. This is behavior rather than a
        // preference because nobody wants a slow menu.
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
        let dark = Self.isDark(button.effectiveAppearance)
        let image = ProviderMarkImage.menuBarImage(provider: readout.provider, dark: dark)

        let title = readout.percentRemaining.map { " " + Self.reservedPercent($0) } ?? ""

        button.image = image
        button.title = title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.toolTip = readout.accessibilityDescription
        button.setAccessibilityLabel(readout.accessibilityDescription)

        rendered = RenderedStatusItem(
            provider: readout.provider,
            title: title,
            hasImage: button.image != nil,
            imageIsTemplate: button.image?.isTemplate ?? false,
            imageSize: button.image?.size ?? .zero,
            usedVendorMark: readout.provider.map { ProviderMarkImage.hasVendorMark(for: $0) } ?? false)
    }

    static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// Tabular figures stop a 1 being narrower than a 4, but they do not stop
    /// 9% being narrower than 100%. The number is padded to three digit widths
    /// with FIGURE SPACE, which in a tabular font is exactly one digit wide, so
    /// the item keeps one width from 0% to 100% and nothing in the menu bar
    /// shuffles as the quota falls.
    static func reservedPercent(_ value: Double) -> String {
        let text = QuotaFormatting.percent(value)
        let digits = text.filter(\.isNumber).count
        return String(repeating: "\u{2007}", count: max(0, 3 - digits)) + text
    }

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
            try? await Task.sleep(nanoseconds: 120_000_000)
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
}
