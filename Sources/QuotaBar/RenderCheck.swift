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

    /// Antigravity's two windows, and the same provider reporting only one.
    /// The short page is its own case worth looking at: a single window is the
    /// shortest signed-in page the app draws, and it is where the panel's
    /// minimum height and the top alignment of a page with slack under it show
    /// up. The captain reported Antigravity with one window.
    private static let agyWindowsBoth = """
    {"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1,
     "resetsAt":"\(iso(124))"},
    {"id":"claude_gpt_weekly","label":"Claude/GPT weekly","kind":"weekly",
     "percentRemaining":100,"resetsAt":"\(iso(167))"}
    """

    private static let agyWindowsSingle = """
    {"id":"gemini_weekly","label":"Gemini weekly","kind":"weekly","percentRemaining":1,
     "resetsAt":"\(iso(124))"}
    """

    private static var sample: String { sample(agyWindows: agyWindowsBoth) }

    private static func sample(agyWindows: String) -> String { """
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
       "windows":[\(agyWindows)]},
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

        guard let snapshot = try? QuotaParser.decode(sample),
              let shortSnapshot = try? QuotaParser.decode(sample(agyWindows: agyWindowsSingle))
        else {
            print("RENDER sample snapshot failed to decode")
            return
        }

        for dark in [false, true] {
            let suffix = dark ? "-dark" : "-light"

            write(page("overview", snapshot: snapshot, focus: "claude", dark: dark),
                  to: root.appendingPathComponent("overview\(suffix).png"))

            write(page("codex", snapshot: snapshot, focus: "codex", dark: dark),
                  to: root.appendingPathComponent("provider-signed-in\(suffix).png"))

            // Antigravity with two windows and with one, so the tall and the
            // short signed-in page can be held side by side. The short one is
            // where the panel's minimum height shows.
            write(page("agy", snapshot: snapshot, focus: "agy", dark: dark),
                  to: root.appendingPathComponent("provider-two-windows\(suffix).png"))

            write(page("agy", snapshot: shortSnapshot, focus: "agy", dark: dark),
                  to: root.appendingPathComponent("provider-single-window\(suffix).png"))

            write(page("cursor", snapshot: snapshot, focus: "cursor", dark: dark, show: ["cursor"]),
                  to: root.appendingPathComponent("provider-unavailable\(suffix).png"))

            write(preferences(snapshot: snapshot, focus: "claude", dark: dark),
                  to: root.appendingPathComponent("preferences\(suffix).png"))

            // The tab strip tint is a question, not a decision: both are drawn
            // so it can be settled by eye.
            write(page("overview", snapshot: snapshot, focus: "claude", dark: dark, tint: 0.05),
                  to: root.appendingPathComponent("overview-tinted-tabs\(suffix).png"))
        }

        write(menuBarBackingSheet(), to: root.appendingPathComponent("menubar-backing.png"))
    }

    /// A contact sheet of the menu bar mark at four backing strengths, over the
    /// three backgrounds that matter: a light menu bar, a dark one, and a bright
    /// busy wallpaper showing through a translucent one. Shipped strength is
    /// marked. This is a swatch, not a screenshot: it asks for no permission and
    /// captures nothing.
    private static func menuBarBackingSheet() -> NSImage? {
        let swatch: CGFloat = 92
        let rowHeight: CGFloat = 46
        let strengths: [(label: String, value: Double?)] = [
            ("none", 0),
            ("shipped", nil),
            ("0.18", 0.18),
            ("0.28", 0.28),
        ]
        let backdrops: [(name: String, dark: Bool, fill: (NSRect) -> Void)] = [
            ("Light menu bar", false, { rect in
                NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1).setFill()
                rect.fill()
            }),
            ("Dark menu bar", true, { rect in
                NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1).setFill()
                rect.fill()
            }),
            ("Bright wallpaper", false, { rect in
                NSGradient(
                    colors: [
                        NSColor(srgbRed: 0.98, green: 0.80, blue: 0.35, alpha: 1),
                        NSColor(srgbRed: 0.45, green: 0.78, blue: 0.95, alpha: 1),
                        NSColor(srgbRed: 0.93, green: 0.55, blue: 0.72, alpha: 1),
                    ])?.draw(in: rect, angle: 12)
            }),
            ("Busy dark wallpaper", true, { rect in
                NSGradient(
                    colors: [
                        NSColor(srgbRed: 0.07, green: 0.10, blue: 0.24, alpha: 1),
                        NSColor(srgbRed: 0.36, green: 0.14, blue: 0.30, alpha: 1),
                        NSColor(srgbRed: 0.05, green: 0.22, blue: 0.24, alpha: 1),
                    ])?.draw(in: rect, angle: 12)
            }),
        ]

        let width = swatch * CGFloat(strengths.count) + 150
        let height = rowHeight * CGFloat(backdrops.count) + 26

        return NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
            NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
                .setFill()
            NSRect(x: 0, y: 0, width: width, height: height).fill()

            let caption: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9, weight: .semibold),
                .foregroundColor: NSColor(white: 0.82, alpha: 1),
            ]
            for (column, strength) in strengths.enumerated() {
                let x = 150 + CGFloat(column) * swatch
                (strength.label as NSString).draw(
                    at: NSPoint(x: x + swatch / 2 - 18, y: 7), withAttributes: caption)
            }

            for (row, backdrop) in backdrops.enumerated() {
                let y = 24 + CGFloat(row) * rowHeight
                (backdrop.name as NSString).draw(
                    at: NSPoint(x: 10, y: y + rowHeight / 2 - 6), withAttributes: caption)

                for (column, strength) in strengths.enumerated() {
                    let cell = NSRect(
                        x: 150 + CGFloat(column) * swatch, y: y,
                        width: swatch, height: rowHeight)
                    backdrop.fill(cell)

                    let opacity = strength.value
                        ?? ProviderMarkImage.defaultBackingOpacity(dark: backdrop.dark)
                    let mark = ProviderMarkImage.image(
                        provider: "claude",
                        dark: backdrop.dark,
                        side: ProviderMarkImage.menuBarSide,
                        backingOpacity: opacity)
                    let side = ProviderMarkImage.menuBarSide
                    mark.draw(in: NSRect(
                        x: cell.midX - side / 2 - 14,
                        y: cell.midY - side / 2,
                        width: side, height: side))

                    let number: [NSAttributedString.Key: Any] = [
                        .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                        .foregroundColor: backdrop.dark ? NSColor.white : NSColor.black,
                    ]
                    ("84%" as NSString).draw(
                        at: NSPoint(x: cell.midX + 6, y: cell.midY - 7), withAttributes: number)
                }
            }
            return true
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
        show extra: [String] = [],
        tint: Double = Layout.tabStripTintOpacity) -> NSImage?
    {
        let subject = model(snapshot: snapshot, focus: focus, show: extra)
        subject.select(page == "overview" ? .overview : .provider(page))
        return render(
            QuotaMenuView(model: subject, scrolls: false, tabStripTintOpacity: tint),
            dark: dark)
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
