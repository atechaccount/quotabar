import AppKit
import Combine
import Foundation
import QuotaBarCore
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: QuotaSnapshot?
    @Published private(set) var lastSuccessAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isRefreshing = false

    let preferences = AppPreferences()

    private var wakeObserver: NSObjectProtocol?
    private var intervalObservation: AnyCancellable?
    private var activity: NSObjectProtocol?

    private lazy var coordinator: RefreshCoordinator = {
        let runner = QuotaAXIRunner()
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

    init() {
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

    /// Signed-in providers the captain has chosen to show, focus first so the
    /// provider driving the menu bar is always the first thing in the overview.
    var activeProviders: [QuotaProvider] {
        visibleProviders
            .filter(\.isFresh)
            .sorted { first, second in
                let firstFocused = first.provider == preferences.focusedProvider
                let secondFocused = second.provider == preferences.focusedProvider
                if firstFocused != secondFocused { return firstFocused }

                // Then the providers in day-to-day use, so the overview opens on
                // what matters rather than on whatever sorts first alphabetically.
                let firstRank = Self.usageRank(first.provider)
                let secondRank = Self.usageRank(second.provider)
                if firstRank != secondRank { return firstRank < secondRank }

                return first.displayName.localizedCaseInsensitiveCompare(second.displayName)
                    == .orderedAscending
            }
    }

    private static func usageRank(_ provider: String) -> Int {
        MenuBarReadoutResolver.preferredFocusOrder.firstIndex(of: provider)
            ?? MenuBarReadoutResolver.preferredFocusOrder.count
    }

    /// Everything quota-axi reported that is not currently readable. These still
    /// appear, dimmed and in their own section - never as a fake zero.
    var inactiveProviders: [QuotaProvider] {
        visibleProviders
            .filter { !$0.isFresh }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var visibleProviders: [QuotaProvider] {
        (snapshot?.providers ?? []).filter { preferences.isVisible($0.provider) }
    }

    var allProviders: [QuotaProvider] {
        (snapshot?.providers ?? []).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Providers worth offering as a focus target in the one-click switcher.
    var focusCandidates: [QuotaProvider] {
        activeProviders
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
                self.snapshot = snapshot
                preferences.seedFocusIfNeeded(from: snapshot)
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
