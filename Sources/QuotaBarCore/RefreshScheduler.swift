import Foundation

public struct SchedulerClock: Sendable {
    public let now: @Sendable () async -> Duration
    public let sleepUntil: @Sendable (Duration) async throws -> Void

    public init(
        now: @escaping @Sendable () async -> Duration,
        sleepUntil: @escaping @Sendable (Duration) async throws -> Void)
    {
        self.now = now
        self.sleepUntil = sleepUntil
    }

    public static func continuous() -> SchedulerClock {
        let clock = ContinuousClock()
        let origin = clock.now
        return SchedulerClock(
            now: { origin.duration(to: clock.now) },
            sleepUntil: { deadline in
                try await clock.sleep(until: origin.advanced(by: deadline), tolerance: .milliseconds(100))
            })
    }
}

public enum RefreshReason: String, Equatable, Sendable {
    case startup
    case scheduled
    case wake
    case menuOpened
    case manual
}

public actor MonotonicRefreshScheduler {
    public typealias Tick = @Sendable (RefreshReason) async -> Void

    private let clock: SchedulerClock
    private let tick: Tick
    private var interval: Duration
    private var task: Task<Void, Never>?

    public init(intervalSeconds: TimeInterval, clock: SchedulerClock = .continuous(), tick: @escaping Tick) {
        interval = .seconds(intervalSeconds)
        self.clock = clock
        self.tick = tick
    }

    public func start() {
        restart()
    }

    public func setInterval(seconds: TimeInterval) {
        interval = .seconds(seconds)
        restart()
    }

    public func wake() async {
        restart()
        await tick(.wake)
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func restart() {
        task?.cancel()
        let interval = interval
        let clock = clock
        let tick = tick
        task = Task.detached(priority: .utility) {
            var next = await clock.now() + interval
            while !Task.isCancelled {
                do {
                    try await clock.sleepUntil(next)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await tick(.scheduled)
                let current = await clock.now()
                repeat {
                    next += interval
                } while next <= current
            }
        }
    }
}
