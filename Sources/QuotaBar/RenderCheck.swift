import AppKit
import QuotaBarCore
import SwiftUI

/// Renders the real views offscreen to PNGs so the layout can actually be looked
/// at. Launch the bundle with `QUOTABAR_RENDER=<directory>`.
///
/// This draws the views into a bitmap with `ImageRenderer`; it never captures the
/// screen, so it asks for no screen-recording permission. It is evidence about
/// layout only - the status item's own drawing is checked in `SelfTest`, because
/// an offscreen render of a view is exactly the check that missed the missing
/// menu bar mark.
@MainActor
enum RenderCheck {
    /// The captured sample the approved mockups were designed against, so a
    /// render can be held next to them.
    private static func iso(_ hours: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date().addingTimeInterval(hours * 3_600))
    }

    private static var sample: String { """
    {"generatedAt":"2026-09-20T15:24:02.920Z","providers":[
      {"provider":"claude","label":"Claude","source":"oauth","plan":"pro",
       "account":{"email":"service.5k7fv@simplelogin.com"},
       "state":{"status":"fresh"},
       "windows":[
         {"id":"five_hour","label":"session","kind":"session","percentRemaining":100,
          "windowSeconds":18000,"resetsAt":"\(iso(4.9))"},
         {"id":"seven_day","label":"week","kind":"weekly","percentRemaining":46,
          "windowSeconds":604800,"resetsAt":"\(iso(83))"}]},
      {"provider":"codex","label":"Codex","source":"oauth","plan":"plus",
       "account":{"email":"buy@durellgill.com"},
       "state":{"status":"fresh"},
       "credits":{"remaining":0,"unlimited":false,"unit":"credits"},
       "windows":[
         {"id":"five_hour","label":"session","kind":"session","percentRemaining":91,
          "windowSeconds":18000,"resetsAt":"\(iso(4.9))"},
         {"id":"weekly","label":"week","kind":"weekly","percentRemaining":88,
          "windowSeconds":604800,"resetsAt":"\(iso(161))"}]},
      {"provider":"agy","label":"Antigravity","source":"cli","state":{"status":"fresh"},
       "windows":[
         {"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1,
          "resetsAt":"\(iso(124))"},
         {"id":"claude_gpt_weekly","label":"Claude/GPT weekly","kind":"weekly",
          "percentRemaining":100,"resetsAt":"\(iso(167))"}]},
      {"provider":"cursor","label":"Cursor","source":"unavailable",
       "state":{"status":"auth_required","error":"Cursor sign-in required",
                "sourcesTried":["state-vscdb","cli-keychain"]},
       "attempts":[{"source":"state-vscdb","status":"skipped","error":"credentials_missing"},
                   {"source":"cli-keychain","status":"skipped","error":"credentials_missing"}]},
      {"provider":"copilot","label":"GitHub Copilot","source":"unavailable",
       "state":{"status":"auth_required","sourcesTried":["apps-json","gh:hosts.yml"]}},
      {"provider":"grok","label":"Grok","source":"unavailable",
       "state":{"status":"auth_required","sourcesTried":["auth-json","pi:xai"]}},
      {"provider":"kimi","label":"Kimi","source":"unavailable",
       "state":{"status":"auth_required","sourcesTried":["pi:kimi-coding","kimi-code-cli"]}},
      {"provider":"zai","label":"Z.AI","source":"unavailable",
       "state":{"status":"auth_required","sourcesTried":["pi:zai","opencode:auth.json"]}},
      {"provider":"alibaba","label":"Alibaba Coding Plan","source":"unavailable",
       "state":{"status":"unavailable","error":"bl_cli_unavailable","sourcesTried":["bl-cli"]}},
      {"provider":"opencode-go","label":"OpenCode Go","source":"api",
       "state":{"status":"auth_required","sourcesTried":["opencode:auth.json"]},
       "quotaSemantics":{"status":"partial",
         "unresolvedWindowIds":["rolling","weekly","monthly"]}},
      {"provider":"commandcode","label":"Command Code","source":"unavailable",
       "state":{"status":"auth_required","sourcesTried":["pi:commandcode","commandcode-cli"]}}]}
    """ }

    static func run(into directory: String) {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        guard let snapshot = try? QuotaParser.decode(sample) else {
            print("RENDER sample snapshot failed to decode")
            return
        }

        for dark in [false, true] {
            let suffix = dark ? "-dark" : "-light"

            write(page("overview", snapshot: snapshot, focus: "claude", dark: dark),
                  to: root.appendingPathComponent("overview\(suffix).png"))

            write(page("codex", snapshot: snapshot, focus: "codex", dark: dark),
                  to: root.appendingPathComponent("provider-signed-in\(suffix).png"))

            write(page("cursor", snapshot: snapshot, focus: "cursor", dark: dark, show: ["cursor"]),
                  to: root.appendingPathComponent("provider-unavailable\(suffix).png"))

            write(preferences(snapshot: snapshot, focus: "claude", dark: dark),
                  to: root.appendingPathComponent("preferences\(suffix).png"))
        }
    }

    private static func model(
        snapshot: QuotaSnapshot,
        focus: String,
        show extra: [String]) -> AppModel
    {
        let preferences = AppPreferences(defaults: InMemoryPreferenceStore())
        preferences.seedVisibilityIfNeeded(from: snapshot)
        for provider in extra { preferences.setVisible(true, provider: provider) }
        preferences.focus(on: focus)
        return AppModel(
            startRefreshing: false,
            preferences: preferences,
            snapshot: snapshot,
            lastSuccessAt: Date())
    }

    private static func page(
        _ page: String,
        snapshot: QuotaSnapshot,
        focus: String,
        dark: Bool,
        show extra: [String] = []) -> NSImage?
    {
        let subject = model(snapshot: snapshot, focus: focus, show: extra)
        subject.select(page == "overview" ? .overview : .provider(page))
        return render(QuotaMenuView(model: subject, scrolls: false), dark: dark)
    }

    private static func preferences(
        snapshot: QuotaSnapshot,
        focus: String,
        dark: Bool) -> NSImage?
    {
        let subject = model(snapshot: snapshot, focus: focus, show: [])
        // Never the live login-item status: reading it is a system call the
        // captain has asked QuotaBar not to make unprompted.
        return render(
            PreferencesView(
                model: subject,
                launchAtLoginOperations: LaunchAtLoginOperations(
                    status: { .disabled }, register: {}, unregister: {}),
                scrolls: false),
            dark: dark)
    }

    private static func render(_ view: some View, dark: Bool) -> NSImage? {
        let renderer = ImageRenderer(
            content: view
                .environment(\.colorScheme, dark ? .dark : .light)
                .background(dark
                    ? Color(nsColor: NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1))
                    : Color(nsColor: NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))))
        renderer.scale = 2
        return renderer.nsImage
    }

    private static func write(_ image: NSImage?, to url: URL) {
        guard let image,
              let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data),
              let png = bitmap.representation(using: .png, properties: [:])
        else {
            print("RENDER failed \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
        print("RENDER wrote \(url.lastPathComponent) \(bitmap.pixelsWide)x\(bitmap.pixelsHigh)")
    }
}
