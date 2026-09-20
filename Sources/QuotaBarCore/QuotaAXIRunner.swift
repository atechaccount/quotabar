import Darwin
import Foundation

public enum QuotaAXIError: Error, Equatable, LocalizedError, Sendable {
    case notFound
    case launch(String)
    case timedOut(seconds: TimeInterval)
    case failed(status: Int32, message: String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "quota-axi not found. Install it or add it to PATH."
        case let .launch(message):
            return "Could not start quota-axi: \(message)"
        case let .timedOut(seconds):
            return "quota-axi timed out after \(Int(seconds)) seconds."
        case let .failed(status, message):
            let detail = message.isEmpty ? "No error output." : message
            return "quota-axi exited with status \(status): \(detail)"
        case let .invalidJSON(message):
            return "quota-axi returned invalid JSON: \(message)"
        }
    }
}

public struct QuotaAXIRunner: Sendable {
    public static let fallbackExecutable = "/Users/durell/Library/pnpm/bin/quota-axi"

    public init() {}

    public func run(readOnly: Bool, timeout: TimeInterval = 20) async throws -> QuotaSnapshot {
        let data = try await Self.runProcess(readOnly: readOnly, timeout: timeout)
        do {
            return try QuotaParser.decode(data)
        } catch {
            throw QuotaAXIError.invalidJSON(error.localizedDescription)
        }
    }

    public static func resolveExecutable(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let fileManager = FileManager.default
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = String(directory) + "/quota-axi"
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return fileManager.isExecutableFile(atPath: fallbackExecutable) ? fallbackExecutable : nil
    }

    private static func runProcess(readOnly: Bool, timeout: TimeInterval) async throws -> Data {
        guard let executable = resolveExecutable() else {
            throw QuotaAXIError.notFound
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try runBlocking(
                        executable: executable,
                        readOnly: readOnly,
                        timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        executable: String,
        readOnly: Bool,
        timeout: TimeInterval) throws -> Data
    {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--json", "--full"] + (readOnly ? ["--no-credential-refresh"] : [])
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw QuotaAXIError.launch(error.localizedDescription)
        }

        let output = DataBox()
        let errorOutput = DataBox()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            output.value = standardOutput.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .utility).async {
            errorOutput.value = standardError.fileHandleForReading.readDataToEndOfFile()
            readers.leave()
        }

        let deadline = DispatchTime.now() + timeout
        while process.isRunning && DispatchTime.now() < deadline {
            usleep(20_000)
        }

        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            let terminateDeadline = DispatchTime.now() + .milliseconds(250)
            while process.isRunning && DispatchTime.now() < terminateDeadline {
                usleep(10_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()
        readers.wait()

        if timedOut {
            throw QuotaAXIError.timedOut(seconds: timeout)
        }
        guard process.terminationStatus == 0 else {
            let message = String(data: errorOutput.value, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw QuotaAXIError.failed(status: process.terminationStatus, message: message)
        }
        return output.value
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    var value: Data {
        get { lock.withLock { data } }
        set { lock.withLock { data = newValue } }
    }
}
