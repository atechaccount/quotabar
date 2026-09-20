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
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        popover.behavior = .transient
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
        let image = ProviderMarkImage.image(
            provider: readout.provider,
            dark: dark,
            side: ProviderMarkImage.menuBarSide)

        let title = readout.percentRemaining.map { " " + QuotaFormatting.percent($0) } ?? ""

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
            format: "shown=%@ contentSize=%.0fx%.0f fitting=%.0fx%.0f subviews=%d",
            popover.isShown ? "yes" : "NO",
            view.frame.width, view.frame.height,
            fitting.width, fitting.height,
            view.subviews.count)
    }
}
