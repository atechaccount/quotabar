import Testing
@testable import QuotaBar

@MainActor
struct LaunchAtLoginControllerTests {
    @Test
    func constructionDoesNotQueryServiceManagement() {
        var statusCalls = 0
        let controller = LaunchAtLoginController(operations: LaunchAtLoginOperations(
            status: {
                statusCalls += 1
                return .disabled
            },
            register: {},
            unregister: {}))

        #expect(controller.state == .notDetermined)
        #expect(statusCalls == 0)
    }

    @Test
    func preferencesAppearanceQueriesStatusOnlyOnce() {
        var statusCalls = 0
        let controller = LaunchAtLoginController(operations: LaunchAtLoginOperations(
            status: {
                statusCalls += 1
                return .enabled
            },
            register: {},
            unregister: {}))

        controller.loadStatusIfNeeded()
        controller.loadStatusIfNeeded()

        #expect(controller.state == .enabled)
        #expect(statusCalls == 1)
    }

    @Test
    func userToggleDoesNotCauseAnotherStatusQuery() {
        var statusCalls = 0
        var registerCalls = 0
        let controller = LaunchAtLoginController(operations: LaunchAtLoginOperations(
            status: {
                statusCalls += 1
                return .disabled
            },
            register: { registerCalls += 1 },
            unregister: {}))

        controller.loadStatusIfNeeded()
        controller.setEnabled(true)

        #expect(controller.state == .enabled)
        #expect(statusCalls == 1)
        #expect(registerCalls == 1)
    }
}
