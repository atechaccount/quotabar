import AppKit
import QuotaBarCore
import SwiftUI

/// One place for the popover geometry, so labels stay on the left edge and every
/// comparable number lands on the same right edge down the whole page.
enum Layout {
    static let popoverWidth: CGFloat = 430
    static let contentPadding: CGFloat = 18
    static let tabStripPadding: CGFloat = 7
    static let tabSpacing: CGFloat = 4
    /// Past this the strip scrolls instead of squeezing every tab thinner.
    static let maxTabsAcross = 5

    /// The page area sizes to its page, capped so a long one scrolls instead of
    /// turning the popover into a column. A fixed height was tried and rejected:
    /// it makes every short provider page as tall as the longest page in the set.
    ///
    /// This is not the layout-stability rule relaxing. That rule is about
    /// content moving *within* a page as values change width, and it still
    /// holds - tabular figures and reserved columns, both unchanged.
    static let maxContentHeight: CGFloat = 520

    /// And a floor under it, so a provider with one window does not snap the
    /// panel shorter than the provider beside it. 256pt is measured, not
    /// chosen: it is the page area of the ordinary two-window provider page -
    /// a session and a week, which is Claude, Codex and Antigravity - so that
    /// page is untouched and the shorter ones rise to meet it. The panel is
    /// 468pt at the floor; `QUOTABAR_SELFTEST` prints it for every page.
    ///
    /// This is not the fixed height coming back. Nothing is padded to the
    /// longest page: Overview and the unavailable pages are still taller and
    /// still size to themselves. The floor only stops a page collapsing below
    /// the common one.
    static let minContentHeight: CGFloat = 256

    /// Right-hand number columns. Fixed widths are what make the numbers line up
    /// with each other rather than with whatever label happens to precede them,
    /// and they are what stops a 9%, a 91% and a 100% laying out differently.
    static let headlineColumn: CGFloat = 96
    static let laneLabelColumn: CGFloat = 116
    static let laneValueColumn: CGFloat = 38
    /// Wide enough for the longest reset string, which now sits under the value.
    static let windowValueColumn: CGFloat = 116
    /// The freshness and source block on a provider page.
    static let metaColumn: CGFloat = 104

    /// A subtle tint behind the tab strip. Off by default; the render check
    /// draws both so the choice can be made by eye rather than by argument.
    static let tabStripTintOpacity: Double = 0

    static func tabWidth(count: Int) -> CGFloat {
        let across = CGFloat(max(1, min(count, maxTabsAcross)))
        let available = popoverWidth - tabStripPadding * 2 - tabSpacing * (across - 1)
        return available / across
    }
}

/// One type scale for the whole interface.
///
/// Sizes are written as the base size they were designed at and passed through
/// a single factor, so the interface gets smaller or larger as one system
/// rather than label by label. The floor keeps the fine print readable: the
/// three smallest bases in use - 9.5, 10 and 10.5 - land on it and collapse
/// together, which is intended.
///
/// 0.85 against a 9.0 floor is as far down as this pair goes while the
/// hierarchy survives. Base 11 is the secondary body size, on the plan line,
/// the account identity, the freshness sentence, the credits line and every
/// reset time; at 0.85 it computes to 9.35 and the old 9.5 floor would have
/// clamped it into the fine print with the three sizes below it. Dropping the
/// floor to 9.0 - AppKit's own mini control size - lets 11 through at 9.5 and
/// keeps the collapsed group exactly the same three bases it was before. Any
/// scale below 0.85 needs a floor under 9.0, which is too small to read here.
enum Typography {
    static let scale: CGFloat = 0.85
    static let minimumSize: CGFloat = 9.0

    static func size(_ base: CGFloat) -> CGFloat {
        max(minimumSize, (base * scale * 2).rounded() / 2)
    }

    static func font(_ base: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size(base), weight: weight)
    }
}

// MARK: - Popover shell

struct QuotaMenuView: View {
    @ObservedObject var model: AppModel
    var dismiss: () -> Void = {}
    /// The offscreen render check turns scrolling off: `ImageRenderer` draws a
    /// `ScrollView` as an empty box, so a scrolling shell would make the layout
    /// evidence a picture of nothing.
    var scrolls = true
    var tabStripTintOpacity = Layout.tabStripTintOpacity

    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            TabStrip(model: model, scrolls: scrolls, tintOpacity: tabStripTintOpacity)
            Divider()

            // `maxHeight: .infinity` inside the minimum is what lets a short
            // page spend the slack itself: each page ends in a footer pushed
            // down by a `Spacer`, so the space a missing window would have
            // taken opens above that footer instead of below it.
            let body = page(now: now)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, Layout.contentPadding)
                .padding(.top, Layout.contentPadding)
                .padding(.bottom, 12)
                .frame(minHeight: Layout.minContentHeight)

            if scrolls {
                ScrollView {
                    body
                }
                .frame(maxHeight: Layout.maxContentHeight)
                .scrollBounceBehavior(.basedOnSize)
            } else {
                body
            }

            ActionRows(model: model, dismiss: dismiss)
        }
        .frame(width: Layout.popoverWidth)
        // Every number in the popover is tabular, so a value changing from 9%
        // to 100% cannot change the width of anything around it.
        .monospacedDigit()
        .onReceive(clock) { now = $0 }
    }

    @ViewBuilder
    private func page(now: Date) -> some View {
        switch model.resolvedPage {
        case .overview:
            OverviewPage(model: model, now: now)
        case let .provider(key):
            if let provider = model.provider(key) {
                if provider.availability.isMeasurable {
                    SignedInProviderPage(provider: provider, model: model, now: now)
                } else {
                    UnavailableProviderPage(provider: provider, model: model)
                }
            } else {
                Text("That provider is no longer in the snapshot.")
                    .font(Typography.font(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Tabs

/// Overview first, then one tab per provider the user has chosen to show. The
/// filled tab is the page being looked at; the outlined tab with the dot is the
/// provider driving the menu bar. They are different things and the strip says so.
struct TabStrip: View {
    @ObservedObject var model: AppModel
    var scrolls = true
    var tintOpacity = Layout.tabStripTintOpacity
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let providers = model.tabProviders
        let width = Layout.tabWidth(count: providers.count + 1)

        Group {
            if scrolls {
                ScrollView(.horizontal) {
                    strip(providers: providers, width: width)
                }
                .scrollIndicators(.never)
            } else {
                strip(providers: providers, width: width)
            }
        }
        .background(Color.primary.opacity(tintOpacity))
    }

    @ViewBuilder
    private func strip(providers: [QuotaProvider], width: CGFloat) -> some View {
        HStack(spacing: Layout.tabSpacing) {
            TabButton(
                title: "Overview",
                width: width,
                isSelected: model.resolvedPage == .overview,
                isMenuBarFocus: false,
                accent: .accentColor,
                action: { model.select(.overview) })
            {
                OverviewTabGlyph()
            }

            ForEach(providers) { provider in
                TabButton(
                    title: provider.displayName,
                    width: width,
                    isSelected: model.resolvedPage == .provider(provider.provider),
                    isMenuBarFocus: model.preferences.focusedProvider == provider.provider,
                    accent: .brand(provider.provider, dark: colorScheme == .dark),
                    action: { model.select(.provider(provider.provider)) })
                {
                    ProviderMark(provider: provider.provider, size: 17)
                }
            }
        }
        .padding(.horizontal, Layout.tabStripPadding)
        .padding(.top, 8)
        .padding(.bottom, 7)
    }
}

struct TabButton<Glyph: View>: View {
    let title: String
    let width: CGFloat
    let isSelected: Bool
    let isMenuBarFocus: Bool
    let accent: Color
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                glyph
                    .frame(height: 17)
                Text(title)
                    .font(Typography.font(10.5, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            }
            .padding(.top, 7)
            .padding(.bottom, 9)
            .frame(width: width)
            .background(alignment: .bottom) {
                // The brand underline identifies the provider even when the tab
                // is neither selected nor the menu bar focus.
                Capsule()
                    .fill(accent.opacity(0.72))
                    .frame(width: width * 0.64, height: 2)
                    .padding(.bottom, 3)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? accent.opacity(0.16) : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isMenuBarFocus ? accent : .clear, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if isMenuBarFocus {
                    Circle()
                        .fill(accent)
                        .frame(width: 4, height: 4)
                        .padding(.top, 5)
                        .padding(.trailing, 7)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(isMenuBarFocus
            ? "\(title) is shown in the menu bar"
            : "Open \(title) and show it in the menu bar")
        .accessibilityLabel(isMenuBarFocus ? "\(title), shown in the menu bar" : title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The Overview tab's own navigation glyph - QuotaBar's, not any vendor's.
struct OverviewTabGlyph: View {
    var body: some View {
        Canvas { context, size in
            let width = max(2, size.width / 5)
            let gap = (size.width - width * 3) / 2
            let heights = [size.height * 0.45, size.height * 0.72, size.height]
            for index in 0..<3 {
                let rect = CGRect(
                    x: CGFloat(index) * (width + gap),
                    y: size.height - heights[index],
                    width: width,
                    height: heights[index])
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .foreground)
            }
        }
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }
}

// MARK: - Overview

struct OverviewPage: View {
    @ObservedObject var model: AppModel
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.top, 13)

            if model.snapshot == nil {
                Text("Loading provider quotas…")
                    .font(Typography.font(11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else if model.overviewProviders.isEmpty {
                emptyOverview
            } else {
                ForEach(model.overviewProviders) { provider in
                    OverviewProviderRow(provider: provider, now: now)
                    Divider()
                }
            }

            Spacer(minLength: 0)
            hiddenProvidersRow
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overview")
                    .font(Typography.font(19, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(freshness)
                    Text(focusSentence)
                }
                .font(Typography.font(11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                if let error = model.lastError {
                    Text(error)
                        .font(Typography.font(11))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                StatusPill(
                    text: "\(model.overviewProviders.count) shown",
                    tone: model.overviewProviders.isEmpty ? .neutral : .good)
            }
        }
    }

    private var freshness: String {
        guard let last = model.lastSuccessAt else { return "Waiting for the first refresh" }
        let stale = model.lastError == nil ? "" : " · stale"
        return "Updated \(QuotaFormatting.age(since: last, now: now)) · All figures are remaining\(stale)"
    }

    private var focusSentence: String {
        guard let name = model.focusedProviderName else {
            return "No provider chosen for the menu bar yet"
        }
        return "Menu bar stays on \(name) across pages and relaunches"
    }

    private var emptyOverview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No provider is reporting measurable quota")
                .font(Typography.font(12, weight: .medium))
            Text("Sign in to a provider, or turn one on in Preferences to see its page anyway.")
                .font(Typography.font(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 20)
    }

    /// The single quiet path to everything the Overview is not showing, in place
    /// of eight rows nobody can act on.
    @ViewBuilder
    private var hiddenProvidersRow: some View {
        let count = model.providersNotShown.count
        if count > 0 {
            Button {
                model.showPreferences()
            } label: {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(count == 1 ? "1 more provider" : "\(count) more providers")
                            .font(Typography.font(11, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Hidden until configured or measurable")
                            .font(Typography.font(11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("Preferences ›")
                        .font(Typography.font(11))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 12)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Preferences to choose which providers appear here")
        }
    }
}

struct OverviewProviderRow: View {
    let provider: QuotaProvider
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { .brand(provider.provider, dark: colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // No mark here: the tab strip already carries provider identity, and
            // repeating it pushes the name away from the left edge.
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(Typography.font(13, weight: .semibold))
                        .lineLimit(1)
                    Text(provider.overviewContext)
                        .font(Typography.font(10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 0) {
                    Text(provider.headline.map { QuotaFormatting.percent($0.percentRemaining) } ?? "Unknown")
                        .font(Typography.font(14, weight: .medium))
                        .monospacedDigit()
                    Text(provider.headline.map { "\($0.windowLabel) left" }
                        ?? (provider.usageState == .stale ? "last known - stale" : "usage unknown"))
                        .font(Typography.font(10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: Layout.headlineColumn, alignment: .trailing)
            }

            // A Grid, so the label column is as wide as this provider's longest
            // window name and the meters and values still line up down the rows.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 7) {
                ForEach(provider.allWindows) { window in
                    OverviewLane(window: window, accent: accent)
                }
            }
        }
        .padding(.top, 15)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
    }
}

/// Label on the left, solid meter in the middle, percentage on a clean right edge.
struct OverviewLane: View {
    let window: QuotaWindow
    let accent: Color

    private var isCritical: Bool { (window.percentRemaining ?? 100) <= 10 }

    var body: some View {
        GridRow {
            Text(window.titleLabel)
                .font(Typography.font(10, weight: .medium))
                .lineLimit(1)
                .frame(maxWidth: Layout.laneLabelColumn, alignment: .leading)
                .gridColumnAlignment(.leading)

            Meter(
                value: window.percentRemaining,
                tint: isCritical ? Color(brandHex: "#E36F5C") : accent,
                height: 6)

            Text(window.percentRemaining.map { QuotaFormatting.percent($0) } ?? "Unknown")
                .font(Typography.font(10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(isCritical ? Color(brandHex: "#C94D3A") : Color.primary)
                .frame(width: Layout.laneValueColumn, alignment: .trailing)
                .gridColumnAlignment(.trailing)
        }
    }
}

/// A plain solid bar. Deliberately not `ProgressView`, whose indeterminate and
/// gradient treatments read as activity rather than as a level.
struct Meter: View {
    let value: Double?
    let tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.primary.opacity(0.12))
                if let value {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(tint)
                        .frame(width: geometry.size.width * min(max(value, 0), 100) / 100)
                } else {
                    RoundedRectangle(cornerRadius: height / 2)
                        .stroke(Color.secondary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Signed-in provider page

struct SignedInProviderPage: View {
    let provider: QuotaProvider
    @ObservedObject var model: AppModel
    let now: Date
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { .brand(provider.provider, dark: colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.top, 14)

            ForEach(provider.allWindows) { window in
                WindowSection(window: window, accent: accent, now: now)
            }

            if let credits = creditsLine {
                HStack(spacing: 8) {
                    Text("Credits")
                        .font(Typography.font(11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(credits)
                        .font(Typography.font(11, weight: .medium))
                        .monospacedDigit()
                }
                .padding(.top, 14)
            }

            // The footer, pushed to the bottom of the page area. On a page that
            // fills its space this is nothing; on a short one it puts the slack
            // where a missing window would have been.
            Spacer(minLength: 0)
            boundaryNote
        }
    }

    /// No provider mark here. The tab above already says which provider this
    /// page is, and repeating it pushed the name off the left edge.
    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(Typography.font(19, weight: .semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.accountIdentity)
                        .font(Typography.font(11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    // Always drawn, so a provider without a plan does not make
                    // this page a line shorter than the one beside it.
                    Text(provider.planDescription ?? " ")
                        .font(Typography.font(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 1) {
                Text(model.lastSuccessAt.map { "Updated \(QuotaFormatting.age(since: $0, now: now))" }
                    ?? "Not yet refreshed")
                    .lineLimit(1)
                Text(provider.usageState == .stale
                    ? "Stale - \(ProviderPresentation.humanizeSource(provider.source))"
                    : ProviderPresentation.humanizeSource(provider.source))
                    .lineLimit(1)
            }
            .font(Typography.font(10))
            .foregroundStyle(.secondary)
            // Fixed, so "Updated just now" and "Updated 12m ago" do not move the
            // name beside them.
            .frame(width: Layout.metaColumn, alignment: .trailing)
        }
    }

    /// Only a balance worth acting on. quota-axi reports a spending-credit
    /// balance, never the limit-reset credits the CodexBar reference shows, so
    /// nothing here promises that number.
    private var creditsLine: String? {
        guard let credits = provider.credits,
              credits.unlimited != true,
              let remaining = credits.remaining,
              remaining > 0
        else { return nil }
        return "\(Int(remaining)) \(credits.unit ?? "credits") remaining"
    }

    private var boundaryNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(Typography.font(11))
                .foregroundStyle(accent)
            Text("QuotaBar displays the current quota-axi snapshot. It does not contact "
                + "\(provider.brand.vendor) or manage this account.")
                .font(Typography.font(10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 14)
    }
}

/// One window: its name on the left, its remaining percentage and its reset on
/// their own right edges, and a solid meter underneath.
struct WindowSection: View {
    let window: QuotaWindow
    let accent: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(window.titleLabel)
                    .font(Typography.font(16, weight: .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                // The value sits above its reset rather than beside it, so the
                // eye reads one right-hand column instead of two.
                VStack(alignment: .trailing, spacing: 2) {
                    Text(window.percentRemaining.map { "\(QuotaFormatting.percent($0)) left" }
                        ?? "Unknown")
                        .font(Typography.font(16, weight: .semibold))
                        .lineLimit(1)
                    Text(resetText)
                        .font(Typography.font(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(width: Layout.windowValueColumn, alignment: .trailing)
            }

            Meter(value: window.percentRemaining, tint: accent, height: 9)
        }
        .padding(.top, 17)
        .accessibilityElement(children: .combine)
    }

    private var resetText: String {
        guard let reset = QuotaFormatting.date(from: window.resetsAt) else { return "No reset time" }
        return QuotaFormatting.resetDescription(reset, now: now).capitalizedFirst
    }
}

// MARK: - Unavailable provider page

struct UnavailableProviderPage: View {
    let provider: QuotaProvider
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color { .brand(provider.provider, dark: colorScheme == .dark) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.top, 14)
            empty
            visibilityNote
            diagnostics
            Spacer(minLength: 0)
            Text("QuotaBar only displays quota-axi output. It does not open provider login "
                + "flows or read credentials itself.")
                .font(Typography.font(10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }
    }

    /// No provider mark beside the name, for the same reason as the signed-in
    /// page: the tab above already identifies the provider.
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(provider.displayName)
                    .font(Typography.font(19, weight: .semibold))
                Text(provider.account?.email ?? "No account detected")
                    .font(Typography.font(11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            StatusPill(text: provider.availability.label, tone: provider.availability.tone)
        }
    }

    /// Never a zero. A quota QuotaBar cannot read is stated, not invented.
    private var empty: some View {
        VStack(spacing: 13) {
            ProviderMark(provider: provider.provider, size: 28)
                .frame(width: 54, height: 54)
                .background(RoundedRectangle(cornerRadius: 16).fill(accent.opacity(0.1)))

            Text(provider.unavailableHeadline)
                .font(Typography.font(16, weight: .semibold))
            Text(provider.unavailableGuidance)
                .font(Typography.font(11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 24)
    }

    @ViewBuilder
    private var visibilityNote: some View {
        if model.preferences.focusedProvider == provider.provider {
            (Text("\(provider.displayName) remains the menu bar focus, so its mark stays "
                + "while the percentage disappears.")
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                + Text(" Pick another provider to change the menu bar; turn "
                    + "\(provider.displayName) off in Preferences to remove this tab."))
                .font(Typography.font(10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(accent.opacity(0.09)))
                .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var diagnostics: some View {
        let rows = provider.sourceDiagnostics
        if !rows.isEmpty {
            VStack(spacing: 0) {
                Text("SOURCES CHECKED")
                    .font(Typography.font(10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .kerning(0.4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.04))

                ForEach(rows) { row in
                    Divider()
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(Typography.font(11))
                            Text(row.sourceID)
                                .font(Typography.font(9.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Text(row.outcome)
                            .font(Typography.font(10))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                }
            }
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 9))
        }
    }
}

// MARK: - Shared pieces

struct StatusPill: View {
    let text: String
    let tone: ProviderAvailability.Tone
    @Environment(\.colorScheme) private var colorScheme

    private var color: Color {
        switch tone {
        case .good: colorScheme == .dark ? Color(brandHex: "#69D78A") : Color(brandHex: "#2F7451")
        case .neutral: .secondary
        case .warning: colorScheme == .dark ? Color(brandHex: "#FFAD52") : Color(brandHex: "#9B4D1F")
        case .critical: colorScheme == .dark ? Color(brandHex: "#FF8978") : Color(brandHex: "#C94D3A")
        }
    }

    var body: some View {
        Text(text)
            .font(Typography.font(10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.14)))
            .fixedSize()
    }
}

/// Stable action rows at the bottom of every page: label on the left, keyboard
/// shortcut on a clean right edge.
struct ActionRows: View {
    @ObservedObject var model: AppModel
    var dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            row("Refresh", shortcut: "⌘R", key: "r") {
                model.refreshNow()
            }
            Divider()
            row(preferencesTitle, shortcut: "⌘,", key: ",") {
                dismiss()
                model.showPreferences()
            }
            Divider()
            // Present on every page, including Overview. The mockups show it only
            // on the provider pages, but a page-dependent row count changes the
            // height of the whole panel when tabs are switched.
            row("About QuotaBar", shortcut: nil, key: nil) {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                NSApp.orderFrontStandardAboutPanel(nil)
            }
            Divider()
            row("Quit QuotaBar", shortcut: "⌘Q", key: "q") {
                NSApp.terminate(nil)
            }
        }
    }

    /// On an unreadable provider's page, the useful thing Preferences offers is
    /// turning that provider off - so the row says so.
    private var preferencesTitle: String {
        guard case let .provider(key) = model.resolvedPage,
              let provider = model.provider(key),
              !provider.availability.isMeasurable
        else { return "Preferences…" }
        return "Hide \(provider.displayName) in Preferences…"
    }

    @ViewBuilder
    private func row(
        _ title: String,
        shortcut: String?,
        key: Character?,
        action: @escaping () -> Void) -> some View
    {
        let button = Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(Typography.font(12))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(shortcut ?? "")
                    .font(Typography.font(12))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Layout.contentPadding)
            .padding(.vertical, 9)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)

        if let key {
            button.keyboardShortcut(KeyEquivalent(key), modifiers: .command)
        } else {
            button
        }
    }
}

private extension String {
    /// "resets in 4h 54m" reads as a sentence on its own line in the window rows.
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
