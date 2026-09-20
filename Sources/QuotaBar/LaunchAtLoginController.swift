import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case notDetermined
    case enabled
    case disabled
}

struct LaunchAtLoginOperations {
    let status: () -> LaunchAtLoginState
    let register: () throws -> Void
    let unregister: () throws -> Void

    static let live = LaunchAtLoginOperations(
        status: {
            switch SMAppService.mainApp.status {
            case .enabled:
                return .enabled
            case .notRegistered:
                return .disabled
            case .requiresApproval, .notFound:
                return .notDetermined
            @unknown default:
                return .notDetermined
            }
        },
        register: { try SMAppService.mainApp.register() },
        unregister: { try SMAppService.mainApp.unregister() })
}

@MainActor
final class LaunchAtLoginController: ObservableObject {
    @Published private(set) var state = LaunchAtLoginState.notDetermined
    @Published private(set) var errorMessage: String?
    private let operations: LaunchAtLoginOperations
    private var didQueryStatus = false

    /// Construction is intentionally side-effect free. Preferences calls
    /// `loadStatusIfNeeded()` only after its user-visible surface appears.
    init(operations: LaunchAtLoginOperations = .live) {
        self.operations = operations
    }

    func loadStatusIfNeeded() {
        guard !didQueryStatus else { return }
        didQueryStatus = true
        state = operations.status()
        errorMessage = state == .notDetermined ? "Login item status is unavailable." : nil
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try operations.register()
            } else {
                try operations.unregister()
            }
            errorMessage = nil
            state = enabled ? .enabled : .disabled
        } catch {
            errorMessage = error.localizedDescription
            state = .notDetermined
        }
    }
}
