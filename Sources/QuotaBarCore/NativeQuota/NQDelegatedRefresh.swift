import Foundation

/// Ports `providers/delegated-refresh.js`: the only place any of the three
/// native readers spawns a vendor CLI to change what a credential store holds.
/// Claude is the sole user (`claude doctor`, see `NQClaudeReader`); Codex and
/// Cursor never delegate a refresh at all - see their own files for why.
///
/// Every rule here is load-bearing for not signing the operator out of a live
/// Claude Code session:
/// - stdin is closed and stdout/stderr are discarded, so a command that would
///   prompt exits instead of hanging or leaking output;
/// - the environment forces `NO_COLOR`/`TERM=dumb`/`NO_BROWSER`/
///   `NO_OPEN_BROWSER`, the vendor's own non-interactive/no-browser opt-outs;
/// - on timeout, **no signal is ever sent**. The delegate may be mid a
///   single-use refresh-token exchange; quota-axi (and this port) simply stops
///   waiting and lets the process that owns the store finish on its own,
///   because killing it mid-exchange is the one outcome that could leave the
///   store rewritten halfway.
enum NQDelegatedRefresh {
    struct Delegate {
        let source: String
        let command: String
        let args: [String]
        let waitBudgetMs: Int
    }

    static let commandNotFound = "refresh_command_not_found"
    static let spawnFailed = "refresh_spawn_failed"
    static let timedOut = "refresh_timed_out"
    static let exitStatusError = "refresh_exit_status"
    /// A live vendor process already owns refreshing its own credential store.
    static let liveVendorProcess = "refresh_live_vendor_process"
    /// quota-axi could not tell whether the vendor is already running.
    static let vendorUnknown = "refresh_vendor_processes_unknown"

    enum RunOutcome {
        case unavailable(error: String)
        case failed(error: String)
        case unconfirmed(error: String)
        case ran(exitCode: Int32)
    }

    static func run(_ delegate: Delegate) async -> RunOutcome {
        guard let executable = NQProcess.findCommandPath(delegate.command) else {
            return .unavailable(error: commandNotFound)
        }
        var environment = ProcessInfo.processInfo.environment
        environment["NO_COLOR"] = "1"
        environment["TERM"] = "dumb"
        environment["NO_BROWSER"] = "1"
        environment["NO_OPEN_BROWSER"] = "1"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = delegate.args
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return .failed(error: spawnFailed)
        }

        let deadline = DispatchTime.now() + .milliseconds(delegate.waitBudgetMs)
        while process.isRunning && DispatchTime.now() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        if process.isRunning {
            return .unconfirmed(error: timedOut)
        }
        return .ran(exitCode: process.terminationStatus)
    }

    static func attempt(_ delegate: Delegate, outcome: RunOutcome) -> NQAttempt {
        switch outcome {
        case let .unavailable(error):
            return NQAttempt(source: delegate.source, status: "skipped", error: error)
        case let .failed(error):
            return NQAttempt(source: delegate.source, status: "failed", error: error, degraded: false)
        case let .unconfirmed(error):
            return NQAttempt(source: delegate.source, status: "failed", error: error, degraded: false)
        case let .ran(exitCode):
            if exitCode == 0 { return NQAttempt(source: delegate.source, status: "success") }
            return NQAttempt(source: delegate.source, status: "failed", error: exitStatusError, degraded: false)
        }
    }
}

/// Ports `liveClaudeRefreshBlocker`/`isLiveClaudeCodeProcess` in
/// `providers/claude.js`: a best-effort check that no other live Claude Code
/// process already owns the session before delegating a refresh to it. "Cannot
/// tell" is treated the same as "yes, one is running" - never guessed safe.
enum NQClaudeProcessGuard {
    static func liveRefreshBlocker() async -> String? {
        let listing = await NQRunningProcesses.list()
        switch listing {
        case .unavailable:
            return NQDelegatedRefresh.vendorUnknown
        case let .listed(entries):
            let myPid = ProcessInfo.processInfo.processIdentifier
            let hasLive = entries.contains { $0.pid != myPid && isLiveClaudeCodeProcess($0.commandLine) }
            return hasLive ? NQDelegatedRefresh.liveVendorProcess : nil
        }
    }

    static func isLiveClaudeCodeProcess(_ commandLine: String) -> Bool {
        let tokens = commandLine.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        for (index, token) in tokens.enumerated() {
            let basename = token.split(separator: "/").last.map(String.init) ?? token
            if basename == "claude" && (index == 0 || token.contains("/")) { return true }
        }
        return commandLine.contains("@anthropic-ai/claude-code/")
    }
}
