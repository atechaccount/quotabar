import QuotaBarCore
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var preferences: AppPreferences
    @StateObject private var launchAtLogin: LaunchAtLoginController

    /// `launchAtLoginOperations` is injectable so the in-app verification hook can
    /// open this window without reading the real login-item status, which is a
    /// system call the captain has asked never to be made unprompted.
    init(
        model: AppModel,
        launchAtLoginOperations: LaunchAtLoginOperations = .live,
        scrolls: Bool = true)
    {
        self.model = model
        self.scrolls = scrolls
        preferences = model.preferences
        _launchAtLogin = StateObject(
            wrappedValue: LaunchAtLoginController(operations: launchAtLoginOperations))
    }

    /// Turned off by the offscreen render check, which cannot draw a ScrollView.
    var scrolls = true

    var body: some View {
        content
            .frame(width: 510, height: scrolls ? 640 : nil)
            // Tabular figures here too: the provider states carry counts and the
            // refresh interval carries numbers, and this window is a separate
            // view hierarchy that the popover's own setting never reached.
            .monospacedDigit()
            .onAppear { launchAtLogin.loadStatusIfNeeded() }
    }

    @ViewBuilder
    private var content: some View {
        if scrolls {
            ScrollView { pane }
        } else {
            pane
        }
    }

    private var pane: some View {
            VStack(alignment: .leading, spacing: 0) {
                SectionTitle("Refresh", isFirst: true)
                Card {
                    PreferenceRow(
                        title: "Refresh interval",
                        note: "How often QuotaBar asks quota-axi for a new snapshot.")
                    {
                        Picker("", selection: $preferences.refreshInterval) {
                            ForEach(AppPreferences.refreshIntervals, id: \.seconds) { option in
                                Text(option.label).tag(option.seconds)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Divider()
                    PreferenceRow(
                        title: "Read-only refresh",
                        note: "Adds --no-credential-refresh, so QuotaBar never renews credentials. "
                            + "Quota data may become stale.")
                    {
                        Toggle("", isOn: $preferences.readOnlyRefresh)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                }

                SectionTitle("Menu bar")
                Card {
                    PreferenceRow(
                        title: "Shows",
                        note: "Keeps the number in the menu bar attributed to one provider.")
                    {
                        Picker("", selection: $preferences.focusMode) {
                            ForEach(MenuBarFocusMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }

                    if preferences.focusMode == .focusedProvider {
                        Divider()
                        PreferenceRow(
                            title: "Focused provider",
                            note: "Stays selected across pages and relaunches. Before the first "
                                + "choice QuotaBar uses the first fresh provider - Claude, then "
                                + "Codex - and otherwise shows its own glyph.")
                        {
                            Picker("", selection: Binding(
                                get: { preferences.focusedProvider },
                                set: { model.focus(on: $0) }))
                            {
                                Text("Choose a provider").tag("")
                                ForEach(model.allProviders) { provider in
                                    Text(provider.displayName).tag(provider.provider)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                    }

                    Divider()
                    PreferenceRow(
                        title: "Launch at login",
                        note: "Off until explicitly enabled. QuotaBar never registers itself "
                            + "without being asked.")
                    {
                        launchAtLoginControl
                    }
                }

                SectionTitle("Menu bar appearance")
                appearanceCard

                SectionTitle("Providers shown in the top switcher and Overview")
                providerCard
                Text("On first launch QuotaBar shows a provider only when quota-axi reports "
                    + "fresh, measurable quota for it. These switches stay under your control "
                    + "afterwards: a later snapshot never turns one back on or off.")
                    .font(Typography.font(10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 7)
                    .padding(.top, 7)

                legend
            }
            .padding(18)
    }

    /// Everything about how the item is drawn, in the order the eye reads it:
    /// the mark, then what sits behind it, then the number.
    private var appearanceCard: some View {
        Card {
            PreferenceRow(
                title: "Icon",
                note: "The provider mark in its brand colour, or filled solid in one ink.")
            {
                Picker("", selection: $preferences.menuBarAppearance.markStyle) {
                    ForEach(MenuBarMarkStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            Divider()
            PreferenceRow(
                title: "Backing",
                note: "A faint plate keeps the item legible when a bright wallpaper shows "
                    + "through the menu bar. Choose what it covers.")
            {
                Picker("", selection: $preferences.menuBarAppearance.backingScope) {
                    ForEach(MenuBarBackingScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if preferences.menuBarAppearance.backingScope != .none {
                Divider()
                PreferenceRow(
                    title: "Backing colour",
                    note: "Matching the menu bar means a touch of white on a dark menu bar and "
                        + "a touch of black on a light one.")
                {
                    Picker("", selection: $preferences.menuBarAppearance.backingColorStyle) {
                        ForEach(MenuBarBackingColorStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                if preferences.menuBarAppearance.backingColorStyle == .custom {
                    Divider()
                    PreferenceRow(
                        title: "Backing colour and strength",
                        note: "Anything much stronger than a tenth reads as a badge in the "
                            + "menu bar rather than as a backing.")
                    {
                        HStack(spacing: 10) {
                            ColorPicker(
                                "",
                                selection: hexBinding(
                                    \.backingColorHex,
                                    fallback: MenuBarAppearance.defaultCustomBackingHex),
                                supportsOpacity: false)
                                .labelsHidden()
                            Slider(
                                value: $preferences.menuBarAppearance.backingOpacity,
                                in: MenuBarAppearance.opacityRange)
                                .frame(width: 110)
                            Text(strengthLabel)
                                .font(Typography.font(10))
                                .foregroundStyle(.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }

            Divider()
            PreferenceRow(
                title: "Number colour",
                note: "Matching the menu bar follows the system label colour as the "
                    + "appearance changes.")
            {
                Picker("", selection: $preferences.menuBarAppearance.textColorStyle) {
                    ForEach(MenuBarTextColorStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            if preferences.menuBarAppearance.textColorStyle == .custom {
                Divider()
                PreferenceRow(
                    title: "Custom number colour",
                    note: "Used in both appearances, so pick one that reads on each.")
                {
                    ColorPicker(
                        "",
                        selection: hexBinding(
                            \.textColorHex, fallback: MenuBarAppearance.defaultCustomTextHex),
                        supportsOpacity: false)
                        .labelsHidden()
                }
            }

            Divider()
            PreferenceRow(
                title: "Readout font",
                note: "Every face keeps tabular figures, so the item never changes width as "
                    + "the number changes.")
            {
                Picker("", selection: $preferences.menuBarAppearance.font) {
                    ForEach(MenuBarFontChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }

            Divider()
            PreferenceRow(
                title: "Icon size",
                note: "Keeps the mark within the menu bar's reserved vertical space.")
            {
                Slider(
                    value: $preferences.menuBarAppearance.markSize,
                    in: MenuBarMetrics.markSizeRange.doubleRange)
                    .frame(width: 110)
            }

        }
    }

    private var strengthLabel: String {
        String(format: "%.0f%%", preferences.menuBarAppearance.backingOpacity * 100)
    }

    /// The colour wells work in `Color`; the settings store hex, which is the
    /// form every other colour in QuotaBar is written in.
    private func hexBinding(
        _ path: WritableKeyPath<MenuBarAppearance, String>,
        fallback: String) -> Binding<Color>
    {
        Binding(
            get: { Color(brandHex: preferences.menuBarAppearance[keyPath: path]) },
            set: { newValue in
                let hex = BrandColors.hex(from: newValue.brandRGB)
                preferences.menuBarAppearance[keyPath: path] = hex.isEmpty ? fallback : hex
            })
    }

    @ViewBuilder
    private var launchAtLoginControl: some View {
        if launchAtLogin.state == .notDetermined {
            Text(launchAtLogin.errorMessage == nil ? "Not checked" : "Unavailable")
                .font(Typography.font(11))
                .foregroundStyle(.secondary)
        } else {
            Toggle("", isOn: Binding(
                get: { launchAtLogin.state == .enabled },
                set: { launchAtLogin.setEnabled($0) }))
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }

    @ViewBuilder
    private var providerCard: some View {
        if model.allProviders.isEmpty {
            Card {
                PreferenceRow(
                    title: "Waiting for the first refresh",
                    note: "Provider visibility appears once quota-axi has reported.")
                { EmptyView() }
            }
        } else {
            Card {
                ForEach(Array(model.allProviders.enumerated()), id: \.element.id) { index, provider in
                    if index > 0 { Divider() }
                    ProviderVisibilityRow(
                        provider: provider,
                        isVisible: preferences.isVisible(provider.provider),
                        setVisible: { preferences.setVisible($0, provider: provider.provider) })
                }
            }
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider().padding(.bottom, 4)
            legendLine("Connected", tone: .good, meaning: "account and fresh quota found")
            legendLine("Measurable", tone: .good, meaning: "fresh quota found without account identity")
            legendLine("Sign-in required", tone: .neutral, meaning: "no usable credentials found")
            legendLine("CLI unavailable", tone: .warning, meaning: "the provider's source program is missing")
            legendLine("Unresolved windows", tone: .critical, meaning: "expected limits cannot be measured yet")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.top, 10)
    }

    private func legendLine(
        _ term: String,
        tone: ProviderAvailability.Tone,
        meaning: String) -> some View
    {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            StatusText(text: term, tone: tone, weight: .semibold)
            Text("- \(meaning)")
                .foregroundStyle(.secondary)
        }
        .font(Typography.font(10))
    }
}

private extension ClosedRange where Bound == CGFloat {
    var doubleRange: ClosedRange<Double> { Double(lowerBound)...Double(upperBound) }
}

/// One provider switch, with the state quota-axi actually reports next to it, so
/// the reason a provider is off is visible without opening anything else.
struct ProviderVisibilityRow: View {
    let provider: QuotaProvider
    let isVisible: Bool
    let setVisible: (Bool) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProviderMark(provider: provider.provider, size: 15)
            Text(provider.displayName)
                .font(Typography.font(12))
                .lineLimit(1)
            Spacer(minLength: 12)
            StatusText(
                text: provider.availability.label,
                tone: provider.availability.tone,
                weight: .regular)
                .font(Typography.font(10))
            Toggle("", isOn: Binding(get: { isVisible }, set: setVisible))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(minHeight: 39)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(provider.displayName), \(provider.availability.label)")
    }
}

struct StatusText: View {
    let text: String
    let tone: ProviderAvailability.Tone
    var weight: Font.Weight = .regular
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .fontWeight(weight)
            .foregroundStyle(color)
    }

    private var color: Color {
        switch tone {
        case .good: colorScheme == .dark ? Color(brandHex: "#69D78A") : Color(brandHex: "#2F7451")
        case .neutral: .secondary
        case .warning: colorScheme == .dark ? Color(brandHex: "#FFAD52") : Color(brandHex: "#9B4D1F")
        case .critical: colorScheme == .dark ? Color(brandHex: "#FF8978") : Color(brandHex: "#C94D3A")
        }
    }
}

// MARK: - Preferences chrome

struct SectionTitle: View {
    let text: String
    var isFirst = false

    init(_ text: String, isFirst: Bool = false) {
        self.text = text
        self.isFirst = isFirst
    }

    var body: some View {
        Text(text)
            .font(Typography.font(11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.top, isFirst ? 0 : 15)
            .padding(.bottom, 6)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.1)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Explanation under the label, control on the right edge. Every control in the
/// window lines up on that edge, so the eye reads one column of settings.
struct PreferenceRow<Control: View>: View {
    let title: String
    let note: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Typography.font(12))
                Text(note)
                    .font(Typography.font(9.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: 42)
    }
}
