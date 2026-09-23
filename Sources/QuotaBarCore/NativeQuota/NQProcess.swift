import Darwin
import Foundation

/// Bounded child-process execution, mirroring quota-axi's `src/lib/process.js`
/// (`execFileText`, `findCommandPath`) and `src/lib/running-processes.js`
/// (`listRunningCommandLines`). macOS-only: quota-axi's Windows shim path is
/// not ported, since QuotaBar only ships for macOS.
enum NQProcess {
    struct ExecError: Error, Equatable {
        let message: String
        /// Set when the process was killed for running past its timeout, mirroring
        /// the `killed`/`signal` fields Node's `execFile` reports.
        let killed: Bool
        /// The child's exit code, when it exited on its own with a non-zero status.
        let exitStatus: Int32?
    }

    /// Runs `executable` with `arguments`, capturing stdout as UTF-8 text.
    /// Throws `ExecError` on a non-zero exit, launch failure, or timeout.
    static func execFileText(
        _ executable: String, _ arguments: [String], timeout: TimeInterval,
        environment: [String: String]? = nil, currentDirectory: String? = nil
    ) async throws -> String {
        let result = try await run(
            executable: executable, arguments: arguments, environment: environment,
            currentDirectoryPath: currentDirectory, timeout: timeout, stdin: nil)
        guard result.terminationStatus == 0 else {
            throw ExecError(
                message: String(data: result.stderrData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                killed: result.timedOut,
                exitStatus: result.timedOut ? nil : result.terminationStatus)
        }
        return String(data: result.stdoutData, encoding: .utf8) ?? ""
    }

    struct RunResult {
        let stdoutData: Data
        let stderrData: Data
        let terminationStatus: Int32
        let timedOut: Bool
    }

    static func run(
        executable: String, arguments: [String], environment: [String: String]?,
        currentDirectoryPath: String?, timeout: TimeInterval, stdin: Data?
    ) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try runBlocking(
                        executable: executable, arguments: arguments, environment: environment,
                        currentDirectoryPath: currentDirectoryPath, timeout: timeout, stdin: stdin))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        executable: String, arguments: [String], environment: [String: String]?,
        currentDirectoryPath: String?, timeout: TimeInterval, stdin: Data?
    ) throws -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectoryPath {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectoryPath)
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let stdinPipe = Pipe()
        process.standardInput = stdinPipe

        do {
            try process.run()
        } catch {
            throw ExecError(message: error.localizedDescription, killed: false, exitStatus: nil)
        }

        if let stdin {
            stdinPipe.fileHandleForWriting.write(stdin)
        }
        try? stdinPipe.fileHandleForWriting.close()

        let stdoutBox = NQDataBox()
        let stderrBox = NQDataBox()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutBox.value = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.value = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        let deadline = DispatchTime.now() + timeout
        while process.isRunning && DispatchTime.now() < deadline {
            usleep(10_000)
        }
        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let killDeadline = DispatchTime.now() + .milliseconds(250)
            while process.isRunning && DispatchTime.now() < killDeadline {
                usleep(10_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        readers.wait()

        return RunResult(
            stdoutData: stdoutBox.value, stderrData: stderrBox.value,
            terminationStatus: process.terminationStatus, timedOut: timedOut)
    }

    /// Mirrors `findCommandPath` for the macOS/POSIX branch only: an absolute or
    /// relative path with a separator is checked directly, otherwise `PATH` is
    /// searched in order.
    static func findCommandPath(_ command: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("/") {
            return isExecutableFile(trimmed) ? trimmed : nil
        }
        guard let pathValue = environment["PATH"] else { return nil }
        for entry in pathValue.split(separator: ":", omittingEmptySubsequences: false) {
            let directory = entry.isEmpty ? "." : String(entry)
            let candidate = (directory as NSString).appendingPathComponent(trimmed)
            if isExecutableFile(candidate) { return candidate }
        }
        return nil
    }

    private static func isExecutableFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue
        else { return false }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Mirrors `commandExists`.
    static func commandExists(_ command: String) -> Bool {
        findCommandPath(command) != nil
    }
}

/// Mirrors `src/lib/running-processes.js`: a read-only listing of the current
/// user's own running processes, used only to answer "is the vendor CLI
/// already running?" before delegating a credential refresh. Command lines are
/// matched in memory and never persisted.
enum NQRunningProcesses {
    struct Entry {
        let pid: Int32
        let commandLine: String
    }

    enum Listing {
        case listed([Entry])
        case unavailable
    }

    static func list(timeout: TimeInterval = 4) async -> Listing {
        let uid = getuid()
        do {
            let output = try await NQProcess.execFileText(
                "/bin/ps", ["-x", "-u", String(uid), "-o", "pid=,command="], timeout: timeout)
            let entries = output.split(separator: "\n").compactMap(parseLine)
            return .listed(entries)
        } catch {
            return .unavailable
        }
    }

    private static func parseLine(_ line: Substring) -> Entry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let spaceIndex = trimmed.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        guard let pid = Int32(trimmed[trimmed.startIndex..<spaceIndex]) else { return nil }
        let commandLine = trimmed[trimmed.index(after: spaceIndex)...]
            .trimmingCharacters(in: .whitespaces)
        return Entry(pid: pid, commandLine: commandLine)
    }
}

private final class NQDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    var value: Data {
        get { lock.withLock { data } }
        set { lock.withLock { data = newValue } }
    }
}
