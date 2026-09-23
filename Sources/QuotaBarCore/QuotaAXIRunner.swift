import Darwin
import Foundation

public enum QuotaAXIError: Error, Equatable, LocalizedError, Sendable {
    case executableNotFound(locations: [String])
    case nodeNotFound(locations: [String])
    case launch(String)
    case timedOut(seconds: TimeInterval)
    case failed(status: Int32, message: String)
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(locations):
            return "quota-axi not found. Looked in: \(locations.joined(separator: ", ")). Install quota-axi or add it to PATH."
        case let .nodeNotFound(locations):
            return "node not found. quota-axi needs Node. Looked in: \(locations.joined(separator: ", ")). Install Node or add it to PATH."
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
    private let environment: [String: String]
    private let bundledExecutablePath: String?

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledExecutablePath: String? = Bundle.main.executableURL?
            .deletingLastPathComponent().appendingPathComponent("quota-axi").path
    ) {
        self.environment = environment
        self.bundledExecutablePath = bundledExecutablePath
    }

    /// `providers`, when given, adds `--provider a,b,c` so a fallback run can
    /// be scoped to exactly the providers the caller still needs.
    public func run(readOnly: Bool, timeout: TimeInterval = 20, providers: [String]? = nil) async throws -> QuotaSnapshot {
        let data = try await runProcess(readOnly: readOnly, timeout: timeout, providers: providers)
        do {
            return try QuotaParser.decode(data)
        } catch {
            throw QuotaAXIError.invalidJSON(error.localizedDescription)
        }
    }

    public static func resolveExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundledExecutablePath: String? = Bundle.main.executableURL?
            .deletingLastPathComponent().appendingPathComponent("quota-axi").path
    ) -> String? {
        if let bundledExecutablePath, FileManager.default.isExecutableFile(atPath: bundledExecutablePath) {
            return bundledExecutablePath
        }
        return firstExecutable(named: "quota-axi", in: quotaAXIDirectories(environment: environment))
    }

    private func runProcess(readOnly: Bool, timeout: TimeInterval, providers: [String]?) async throws -> Data {
        let quotaDirectories = Self.quotaAXIDirectories(environment: environment)
        guard let executable = Self.resolveExecutable(
            environment: environment,
            bundledExecutablePath: bundledExecutablePath) else {
            throw QuotaAXIError.executableNotFound(locations: quotaDirectories)
        }

        var childEnvironment = environment
        if executable != bundledExecutablePath {
            let nodeDirectories = Self.nodeDirectories(environment: environment)
            guard let node = Self.firstExecutable(named: "node", in: nodeDirectories) else {
                throw QuotaAXIError.nodeNotFound(locations: nodeDirectories)
            }
            childEnvironment["PATH"] = Self.path(
                including: [
                    URL(fileURLWithPath: node).deletingLastPathComponent().path,
                    URL(fileURLWithPath: executable).deletingLastPathComponent().path,
                ],
                then: environment["PATH"])
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(returning: try Self.runBlocking(
                        executable: executable,
                        environment: childEnvironment,
                        readOnly: readOnly,
                        timeout: timeout,
                        providers: providers))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runBlocking(
        executable: String,
        environment: [String: String],
        readOnly: Bool,
        timeout: TimeInterval,
        providers: [String]? = nil) throws -> Data
    {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["--json", "--full"] + (readOnly ? ["--no-credential-refresh"] : [])
            + (providers.map { ["--provider", $0.joined(separator: ",")] } ?? [])
        process.environment = environment
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

    private static func quotaAXIDirectories(environment: [String: String]) -> [String] {
        let home = homeDirectory(environment: environment)
        return unique([
            paths(in: environment["PATH"]),
            environment["PNPM_HOME"].map { [$0] } ?? [],
            [
                home.appendingPathComponent("Library/pnpm/bin").path,
                home.appendingPathComponent(".local/share/pnpm").path,
                home.appendingPathComponent(".local/bin").path,
                "/opt/homebrew/bin",
                "/usr/local/bin",
            ],
        ].flatMap { $0 })
    }

    private static func nodeDirectories(environment: [String: String]) -> [String] {
        let home = homeDirectory(environment: environment)
        let nvm = URL(fileURLWithPath: environment["NVM_DIR"] ?? home.appendingPathComponent(".nvm").path)
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: nvm.appendingPathComponent("versions/node"),
            includingPropertiesForKeys: [.isDirectoryKey]))?
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
            .map { $0.appendingPathComponent("bin").path } ?? []
        let nvmDirectories = versions.isEmpty
            ? [nvm.appendingPathComponent("versions/node/*/bin").path]
            : versions

        return unique([
            paths(in: environment["PATH"]),
            environment["PNPM_HOME"].map { [$0] } ?? [],
            nvmDirectories,
            [
                home.appendingPathComponent(".volta/bin").path,
                "/opt/homebrew/bin",
                "/usr/local/bin",
            ],
        ].flatMap { $0 })
    }

    private static func homeDirectory(environment: [String: String]) -> URL {
        URL(fileURLWithPath: environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path)
    }

    private static func paths(in path: String?) -> [String] {
        (path ?? "").split(separator: ":").map(String.init)
    }

    private static func firstExecutable(named name: String, in directories: [String]) -> String? {
        directories.map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func path(including directories: [String], then inheritedPath: String?) -> String {
        unique(directories + paths(in: inheritedPath)).joined(separator: ":")
    }

    private static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { !$0.isEmpty && seen.insert($0).inserted }
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
