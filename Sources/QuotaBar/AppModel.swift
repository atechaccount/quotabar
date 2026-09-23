import AppKit
import Combine
import Foundation
import QuotaBarCore
import SwiftUI

/// Which page the popover is showing. Overview is the default and the only page
/// that is not a provider.
enum MenuPage: Hashable {
    case overview
    case provider(String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var lastSuccessAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    /// The page being looked at. This is *not* the menu bar focus: moving back to
    /// Overview leaves the menu bar where it was.
    @Published private(set) var page: MenuPage = .overview

    let preferences: AppPreferences

    private var wakeObserver: NSObjectProtocol?
    private var intervalObservation: AnyCancellable?
    private var activity: NSObjectProtocol?

    private lazy var coordinator: RefreshCoordinator = {
        let runner = HybridQuotaSource()
        return RefreshCoordinator(
            runner: { readOnly in
                try await runner.run(readOnly: readOnly, timeout: 20)
            },
            eventHandler: { [weak self] event in
                await self?.handle(event)
            })
    }()

    private lazy var scheduler = MonotonicRefreshScheduler(
        intervalSeconds: preferences.refreshInterval,
        tick: { [weak self] reason in
            await self?.request(reason)
        })

    /// `startRefreshing: false` builds a model that drives no schedule and runs no
    /// subprocess. The verification hook uses it so it cannot disturb the real
    /// app, and tests use it with a canned snapshot and their own defaults.
    init(
        startRefreshing: Bool = true,
        preferences injectedPreferences: AppPreferences? = nil,
        snapshot: QuotaSnapshot? = nil,
        lastKnownSnapshot: QuotaSnapshot? = nil,
        lastSuccessAt: Date? = nil)
    {
        preferences = injectedPreferences ?? AppPreferences()
        self.snapshot = snapshot?.retainingLastKnownUsage(from: lastKnownSnapshot)
        self.lastSuccessAt = lastSuccessAt
        guard startRefreshing else { return }

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Keep the quota refresh schedule responsive")

        intervalObservation = preferences.$refreshInterval
            .dropFirst()
            .sink { [weak self] interval in
                guard let self else { return }
                Task { await self.scheduler.setInterval(seconds: interval) }
            }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main)
        { [weak self] _ in
            guard let self else { return }
            Task { await self.scheduler.wake() }
        }

        Task {
            print("QuotaBar scheduler started interval=\(Int(preferences.refreshInterval))s")
            await scheduler.start()
            await request(.startup)
        }
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
    }

    // MARK: - Provider lists

    private var visibleProviders: [QuotaProvider] {
        (snapshot?.providers ?? []).filter { preferences.isVisible($0.provider) }
    }

    /// The tab strip, in a stable order. Measurable providers first, in the order
    /// they are actually used, then anything the user chose to show anyway.
    /// Deliberately not focus-first: the strip must not reshuffle under the
    /// pointer when the menu bar focus moves.
    var tabProviders: [QuotaProvider] {
        visibleProviders.sorted { first, second in
            let firstMeasurable = first.availability.isMeasurable
            let secondMeasurable = second.availability.isMeasurable
            if firstMeasurable != secondMeasurable { return firstMeasurable }

            let firstRank = Self.usageRank(first.provider)
            let secondRank = Self.usageRank(second.provider)
            if firstRank != secondRank { return firstRank < secondRank }

            return first.displayName.localizedCaseInsensitiveCompare(second.displayName)
                == .orderedAscending
        }
    }

    /// Fresh and stale readings both belong in the Overview. Unknown providers
    /// remain available on their own enabled page without inventing a row value.
    var overviewProviders: [QuotaProvider] {
        tabProviders.filter { $0.availability.isMeasurable }
    }

    /// Everything quota-axi reported that the Overview is not showing. The
    /// Overview names the count and points at Preferences rather than listing
    /// eight rows nobody can act on.
    var providersNotShown: [QuotaProvider] {
        let shown = Set(overviewProviders.map(\.provider))
        return allProviders.filter { !shown.contains($0.provider) }
    }

    private static func usageRank(_ provider: String) -> Int {
        MenuBarReadoutResolver.preferredFocusOrder.firstIndex(of: provider)
            ?? MenuBarReadoutResolver.preferredFocusOrder.count
    }

    var allProviders: [QuotaProvider] {
        (snapshot?.providers ?? []).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    func provider(_ key: String) -> QuotaProvider? {
        snapshot?.providers.first { $0.provider == key }
    }

    // MARK: - Pages and menu bar focus

    /// The page actually renderable right now. A remembered provider page whose
    /// tab has gone falls back to Overview without touching the menu bar focus.
    var resolvedPage: MenuPage {
        guard case let .provider(key) = page else { return .overview }
        return tabProviders.contains(where: { $0.provider == key }) ? page : .overview
    }

    /// Selecting a provider tab opens its page *and* points the menu bar at it.
    /// Selecting Overview only changes the page.
    func select(_ page: MenuPage) {
        self.page = page
        if case let .provider(key) = page {
            preferences.focus(on: key)
        }
    }

    var menuBarReadout: MenuBarReadout {
        MenuBarReadoutResolver.resolve(
            snapshot: snapshot,
            mode: preferences.focusMode,
            focusedProvider: preferences.focusedProvider,
            isVisible: { [preferences] in preferences.isVisible($0) })
    }

    var focusedProviderName: String? {
        snapshot?.providers.first { $0.provider == preferences.focusedProvider }?.displayName
    }

    func focus(on provider: String) {
        preferences.focus(on: provider)
    }

    // MARK: - Actions

    /// Built lazily so the window only exists once the captain asks for it.
    private lazy var settingsPresenter = SettingsWindowPresenter(
        hooks: .live(content: { @MainActor [weak self] in
            guard let self else { return AnyView(EmptyView()) }
            return AnyView(PreferencesView(model: self))
        }))

    func showPreferences() {
        settingsPresenter.show()
    }

    func refreshNow() {
        Task { await request(.manual) }
    }

    func menuOpened() {
        Task { await request(.menuOpened) }
    }

    func statusItemAppeared() {
        print("QuotaBar menu bar status item state=active activationPolicy=\(NSApp.activationPolicy().rawValue)")
    }

    private func request(_ reason: RefreshReason) async {
        await coordinator.request(reason: reason, readOnly: preferences.readOnlyRefresh)
    }

    private func handle(_ event: RefreshEvent) {
        switch event {
        case .started:
            isRefreshing = true
        case let .finished(reason, result):
            isRefreshing = false
            switch result {
            case let .success(snapshot):
                let presentation = snapshot.retainingLastKnownUsage(from: self.snapshot)
                self.snapshot = presentation
                preferences.seedVisibilityIfNeeded(from: presentation)
                preferences.seedFocusIfNeeded(from: presentation)
                lastSuccessAt = Date()
                lastError = nil
                print("QuotaBar refresh succeeded reason=\(reason.rawValue) providers=\(snapshot.providers.count) at=\(ISO8601DateFormatter().string(from: Date()))")
            case let .failure(error):
                lastError = error.message
                print("QuotaBar refresh failed reason=\(reason.rawValue) error=\(error.message)")
            }
        }
    }
}
