import Foundation

public struct RefreshFailure: Error, Equatable, LocalizedError, Sendable {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public enum RefreshEvent: Sendable {
    case started(RefreshReason)
    case finished(RefreshReason, Result<QuotaSnapshot, RefreshFailure>)
}

public actor RefreshCoordinator {
    public typealias Runner = @Sendable (Bool) async throws -> QuotaSnapshot
    public typealias EventHandler = @Sendable (RefreshEvent) async -> Void

    private let runner: Runner
    private let eventHandler: EventHandler
    private var isRunning = false
    private var pending: (reason: RefreshReason, readOnly: Bool)?

    public init(runner: @escaping Runner, eventHandler: @escaping EventHandler) {
        self.runner = runner
        self.eventHandler = eventHandler
    }

    public func request(reason: RefreshReason, readOnly: Bool) {
        if isRunning {
            pending = (reason, readOnly)
            return
        }
        isRunning = true
        Task { await runLoop(reason: reason, readOnly: readOnly) }
    }

    private func runLoop(reason initialReason: RefreshReason, readOnly initialReadOnly: Bool) async {
        var reason = initialReason
        var readOnly = initialReadOnly
        while true {
            await eventHandler(.started(reason))
            let result: Result<QuotaSnapshot, RefreshFailure>
            do {
                result = .success(try await runner(readOnly))
            } catch {
                result = .failure(RefreshFailure(error.localizedDescription))
            }
            await eventHandler(.finished(reason, result))

            guard let next = pending else {
                isRunning = false
                return
            }
            pending = nil
            reason = next.reason
            readOnly = next.readOnly
        }
    }
}
