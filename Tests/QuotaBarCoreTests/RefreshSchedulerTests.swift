import Testing
@testable import QuotaBarCore

struct RefreshSchedulerTests {
    @Test
    func testTicksContinueAfterFailureAndTimeout() async throws {
        let clock = ManualClock()
        let runner = SequencedRunner(results: [
            .failure(RefreshFailure("failed")),
            .failure(RefreshFailure("quota-axi timed out")),
            .success(try snapshot()),
        ])
        let events = EventRecorder()
        let coordinator = RefreshCoordinator(
            runner: { _ in try await runner.run() },
            eventHandler: { await events.record($0) })
        let scheduler = MonotonicRefreshScheduler(
            intervalSeconds: 10,
            clock: clock.schedulerClock,
            tick: { reason in await coordinator.request(reason: reason, readOnly: false) })

        await scheduler.start()
        let firstSleep = await waitUntil { await clock.waiterCount == 1 }
        #expect(firstSleep)
        await clock.advance(by: .seconds(10))
        let sawFirst = await waitUntil { await runner.callCount == 1 }
        #expect(sawFirst)
        let secondSleep = await waitUntil { await clock.waiterCount == 1 }
        #expect(secondSleep)
        await clock.advance(by: .seconds(10))
        let sawSecond = await waitUntil { await runner.callCount == 2 }
        #expect(sawSecond)
        let thirdSleep = await waitUntil { await clock.waiterCount == 1 }
        #expect(thirdSleep)
        await clock.advance(by: .seconds(10))
        let sawThird = await waitUntil { await runner.callCount == 3 }
        #expect(sawThird)
        let finished = await waitUntil { await events.finishedCount == 3 }
        #expect(finished)

        await scheduler.stop()
        let failures = await events.failureCount
        let successes = await events.successCount
        #expect(failures == 2)
        #expect(successes == 1)
    }

    @Test
    func testWakeFiresImmediatelyAndReanchorsSchedule() async {
        let clock = ManualClock()
        let ticks = TickRecorder()
        let scheduler = MonotonicRefreshScheduler(
            intervalSeconds: 10,
            clock: clock.schedulerClock,
            tick: { reason in await ticks.record(reason) })

        await scheduler.start()
        await settle()
        await clock.advance(by: .seconds(4))
        await scheduler.wake()
        let wakeCount = await ticks.count
        let wakeReasons = await ticks.reasons
        #expect(wakeCount == 1)
        #expect(wakeReasons == [.wake])

        let reanchoredSleep = await waitUntil { await clock.nextDeadline == .seconds(14) }
        #expect(reanchoredSleep)
        await clock.advance(by: .seconds(9))
        let beforeDeadline = await ticks.count
        #expect(beforeDeadline == 1)
        await clock.advance(by: .seconds(1))
        let scheduled = await waitUntil { await ticks.count == 2 }
        #expect(scheduled)
        let finalReasons = await ticks.reasons
        #expect(finalReasons == [.wake, .scheduled])
        await scheduler.stop()
    }

    @Test
    func testOverlappingTicksCoalesceIntoOneFollowUpRun() async throws {
        let clock = ManualClock()
        let runner = GatedRunner(snapshot: try snapshot())
        let events = EventRecorder()
        let ticks = TickRecorder()
        let coordinator = RefreshCoordinator(
            runner: { _ in try await runner.run() },
            eventHandler: { await events.record($0) })
        let scheduler = MonotonicRefreshScheduler(
            intervalSeconds: 1,
            clock: clock.schedulerClock,
            tick: { reason in
                await ticks.record(reason)
                await coordinator.request(reason: reason, readOnly: false)
            })

        await scheduler.start()
        let firstSleep = await waitUntil { await clock.waiterCount == 1 }
        #expect(firstSleep)
        await clock.advance(by: .seconds(1))
        let started = await waitUntil { await runner.callCount == 1 }
        #expect(started)

        for _ in 0..<3 {
            let nextSleep = await waitUntil { await clock.waiterCount == 1 }
            #expect(nextSleep)
            await clock.advance(by: .seconds(1))
        }
        let callsWhileBlocked = await runner.callCount
        #expect(callsWhileBlocked == 1)

        await runner.releaseFirstRun()
        // The coordinator has already recorded the coalesced request. Wait for its
        // causal effects instead of letting suite load expire a wall-clock poll.
        await runner.waitForFollowUpRun()
        await events.waitForSecondFinishedEvent()
        let coalescedRunCount = await runner.callCount
        let finishedCount = await events.finishedCount
        let reasons = await ticks.reasons
        #expect(coalescedRunCount == 2)
        #expect(finishedCount == 2)
        #expect(reasons == [.scheduled, .scheduled, .scheduled, .scheduled])
        let maximumConcurrentRuns = await runner.maximumConcurrentRuns
        #expect(maximumConcurrentRuns == 1)
        await scheduler.stop()
    }

    private func snapshot() throws -> QuotaSnapshot {
        try QuotaParser.decode(#"{"providers":[]}"#)
    }

    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private func waitUntil(_ condition: @escaping () async -> Bool) async -> Bool {
        for _ in 0..<1_000 {
            if await condition() { return true }
            try? await Task.sleep(nanoseconds: 100_000)
        }
        return false
    }
}

private actor ManualClock {
    struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var instant = Duration.zero
    private var nextID = 0
    private var waiters: [Int: Waiter] = [:]

    nonisolated var schedulerClock: SchedulerClock {
        SchedulerClock(
            now: { await self.now() },
            sleepUntil: { try await self.sleep(until: $0) })
    }

    func now() -> Duration { instant }
    var waiterCount: Int { waiters.count }
    var nextDeadline: Duration? { waiters.values.map(\.deadline).min() }

    func sleep(until deadline: Duration) async throws {
        if deadline <= instant { return }
        let id = nextID
        nextID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters[id] = Waiter(deadline: deadline, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func advance(by duration: Duration) {
        instant += duration
        let ready = waiters.filter { $0.value.deadline <= instant }
        for (id, waiter) in ready {
            waiters.removeValue(forKey: id)
            waiter.continuation.resume()
        }
    }

    private func cancel(_ id: Int) {
        waiters.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError())
    }
}

private actor SequencedRunner {
    private var results: [Result<QuotaSnapshot, RefreshFailure>]
    private(set) var callCount = 0

    init(results: [Result<QuotaSnapshot, RefreshFailure>]) {
        self.results = results
    }

    func run() throws -> QuotaSnapshot {
        let result = results[min(callCount, results.count - 1)]
        callCount += 1
        return try result.get()
    }
}

private actor GatedRunner {
    private let snapshot: QuotaSnapshot
    private var gate: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0
    private(set) var maximumConcurrentRuns = 0
    private var activeRuns = 0
    private var followUpRunContinuation: CheckedContinuation<Void, Never>?

    init(snapshot: QuotaSnapshot) {
        self.snapshot = snapshot
    }

    func run() async throws -> QuotaSnapshot {
        callCount += 1
        if callCount == 2 {
            followUpRunContinuation?.resume()
            followUpRunContinuation = nil
        }
        activeRuns += 1
        maximumConcurrentRuns = max(maximumConcurrentRuns, activeRuns)
        if callCount == 1 {
            await withCheckedContinuation { gate = $0 }
        }
        activeRuns -= 1
        return snapshot
    }

    func releaseFirstRun() {
        gate?.resume()
        gate = nil
    }

    func waitForFollowUpRun() async {
        guard callCount < 2 else { return }
        await withCheckedContinuation { followUpRunContinuation = $0 }
    }
}

private actor EventRecorder {
    private(set) var finishedCount = 0
    private(set) var failureCount = 0
    private(set) var successCount = 0
    private var secondFinishedEventContinuation: CheckedContinuation<Void, Never>?

    func record(_ event: RefreshEvent) {
        guard case let .finished(_, result) = event else { return }
        finishedCount += 1
        switch result {
        case .success: successCount += 1
        case .failure: failureCount += 1
        }
        if finishedCount == 2 {
            secondFinishedEventContinuation?.resume()
            secondFinishedEventContinuation = nil
        }
    }

    func waitForSecondFinishedEvent() async {
        guard finishedCount < 2 else { return }
        await withCheckedContinuation { secondFinishedEventContinuation = $0 }
    }
}

private actor TickRecorder {
    private(set) var reasons: [RefreshReason] = []
    var count: Int { reasons.count }

    func record(_ reason: RefreshReason) {
        reasons.append(reason)
    }
}
