import Darwin
import Testing
@testable import QuotaBarCore

struct QuotaAXIRunnerTests {
    @Test
    func testRunsPNPMShimWithNVMNodeOutsideBarePath() async throws {
        let root = testRoot("runs")
        defer { removeTestRoot(root) }

        try writeExecutable("#!/bin/sh\nexec node \"$@\"\n", at: root + "/Library/pnpm/bin/quota-axi")
        try writeExecutable("#!/bin/sh\nprintf '%s\\n' '{\"providers\":[]}'\n", at: root + "/.nvm/versions/node/v26.7.0/bin/node")

        let runner = QuotaAXIRunner(environment: ["HOME": root, "PATH": "/quota-bar-bare-path"])
        let snapshot = try await runner.run(readOnly: true)

        #expect(snapshot.providers.isEmpty)
    }

    @Test
    func testMissingNodeNamesSearchLocations() {
        let root = testRoot("missing-node")
        let error = QuotaAXIError.nodeNotFound(locations: [root + "/.nvm/versions/node/*/bin"])

        #expect(error.errorDescription?.contains("node not found") == true)
        #expect(error.errorDescription?.contains(root + "/.nvm/versions/node/*/bin") == true)
    }

    private func testRoot(_ name: String) -> String {
        let directory = "/" + #filePath.split(separator: "/").dropLast().joined(separator: "/")
        return directory + "/.quota-axi-runner-\(name)-\(getpid())"
    }

    private func writeExecutable(_ contents: String, at path: String) throws {
        try makeDirectories(for: path)
        let descriptor = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o755)
        guard descriptor >= 0 else { throw POSIXError(errno) }
        defer { close(descriptor) }

        let bytes = Array(contents.utf8)
        let written = bytes.withUnsafeBytes { write(descriptor, $0.baseAddress, bytes.count) }
        guard written == bytes.count else { throw POSIXError(errno) }
    }

    private func makeDirectories(for path: String) throws {
        var current = ""
        for component in path.split(separator: "/").dropLast() {
            current += "/\(component)"
            if mkdir(current, 0o755) != 0 && errno != EEXIST { throw POSIXError(errno) }
        }
    }

    private func removeTestRoot(_ root: String) {
        let files = [
            root + "/Library/pnpm/bin/quota-axi",
            root + "/.nvm/versions/node/v26.7.0/bin/node",
        ]
        for path in files { unlink(path) }
        let directories = [
            root + "/Library/pnpm/bin", root + "/Library/pnpm", root + "/Library",
            root + "/.nvm/versions/node/v26.7.0/bin", root + "/.nvm/versions/node/v26.7.0",
            root + "/.nvm/versions/node", root + "/.nvm/versions", root + "/.nvm", root,
        ]
        for path in directories { rmdir(path) }
    }
}

private struct POSIXError: Error {
    let code: Int32

    init(_ code: Int32) {
        self.code = code
    }
}
