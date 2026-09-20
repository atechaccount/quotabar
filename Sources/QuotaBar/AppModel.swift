import AppKit
import Combine
import Foundation
import QuotaBarCore

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

    var providers: [QuotaProvider] {
        (snapshot?.providers ?? [])
            .filter { preferences.isVisible($0.provider) }
            .sorted {
                if $0.isFresh != $1.isFresh { return $0.isFresh }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    var allProviders: [QuotaProvider] {
        (snapshot?.providers ?? []).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    var menuBarPercent: String? {
        guard preferences.displayStyle != .iconOnly else { return nil }
        let provider: QuotaProvider?
        if preferences.displayStyle == .pinned {
            provider = snapshot?.providers.first { $0.provider == preferences.pinnedProvider && $0.isFresh }
        } else {
            provider = providers.filter(\.isFresh).min {
                ($0.headlineRemaining ?? 101) < ($1.headlineRemaining ?? 101)
            }
        }
        guard let value = provider?.headlineRemaining else { return nil }
        return QuotaFormatting.percent(value)
    }

    func refreshNow() {
        Task { await request(.manual) }
    }

    func menuOpened() {
        Task { await request(.menuOpened) }
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
