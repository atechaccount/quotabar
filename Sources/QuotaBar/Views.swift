import AppKit
import QuotaBarCore
import SwiftUI

/// One place for the column geometry, so the mark, label, percentage and bar line
/// up down the whole list instead of drifting per row.
enum Layout {
    static let menuWidth: CGFloat = 320
    static let markColumn: CGFloat = 16
    static let percentColumn: CGFloat = 46
    static let gutter: CGFloat = 9
    static let horizontalPadding: CGFloat = 12
    /// Indent that lines a window row's text up with the provider label above it.
    static var textInset: CGFloat { markColumn + gutter }
}

// MARK: - Menu bar item

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let readout = model.menuBarReadout
        return HStack(spacing: 3) {
            if let provider = readout.provider {
                ProviderMark(provider: provider, size: 13)
            } else {
                QuotaGlyph()
            }
            if let remaining = readout.percentRemaining {
                Text(QuotaFormatting.percent(remaining))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(readout.accessibilityDescription)
        .onAppear { model.statusItemAppeared() }
    }
}

/// The app's own mark, used only when no provider is being shown.
struct QuotaGlyph: View {
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
        .frame(width: 13, height: 13)
        .accessibilityHidden(true)
    }
}

// MARK: - Dropdown

struct QuotaMenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header(now: context.date)
                Divider()
                FocusSwitcher(model: model)
                Divider()
                overview(now: context.date)
                Divider()
                actions
            }
            .frame(width: Layout.menuWidth)
        }
        .onAppear { model.menuOpened() }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("QuotaBar")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if model.isRefreshing {
                    ProgressView().controlSize(.small)
                }
                if model.lastError != nil, model.lastSuccessAt != nil {
                    Text("STALE")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.orange.opacity(0.18), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            Text(model.lastSuccessAt.map {
                "Updated \(QuotaFormatting.age(since: $0, now: now)) · all figures are remaining"
            } ?? "Waiting for first refresh")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let error = model.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func overview(now: Date) -> some View {
        if model.snapshot == nil {
            Text("Loading provider quotas…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.activeProviders) { provider in
                        ProviderCard(
                            provider: provider,
                            now: now,
                            isFocused: provider.provider == model.preferences.focusedProvider,
                            onFocus: { model.focus(on: provider.provider) })
                        Divider().padding(.leading, Layout.horizontalPadding + Layout.textInset)
                    }

                    if !model.inactiveProviders.isEmpty {
                        Text("NOT SIGNED IN")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, Layout.horizontalPadding)
                            .padding(.top, 9)
                            .padding(.bottom, 3)

                        ForEach(model.inactiveProviders) { provider in
                            InactiveProviderRow(provider: provider)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 430)
        }
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.refreshNow()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }

            Spacer()

            Button("Preferences…") { model.showPreferences() }
                .font(.caption)
            Button("Quit") { NSApp.terminate(nil) }
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 8)
    }
}

/// Changing what the menu bar reads is one click from the dropdown, never buried
/// behind a preferences window.
struct FocusSwitcher: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Menu bar")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { model.preferences.focusMode },
                set: { model.preferences.focusMode = $0 }))
            {
                ForEach(MenuBarFocusMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()

            if model.preferences.focusMode == .focusedProvider {
                Picker("", selection: Binding(
                    get: { model.preferences.focusedProvider },
                    set: { model.focus(on: $0) }))
                {
                    if model.focusCandidates.isEmpty {
                        Text("None").tag(model.preferences.focusedProvider)
                    }
                    ForEach(model.focusCandidates) { provider in
                        Text(provider.displayName).tag(provider.provider)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .fixedSize()
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 6)
    }
}

// MARK: - Provider rows

struct ProviderCard: View {
    let provider: QuotaProvider
    let now: Date
    let isFocused: Bool
    let onFocus: () -> Void

    private var brandColor: Color {
        Color(brandHex: BrandColors.hex(for: provider.provider))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: Layout.gutter) {
                ProviderMark(provider: provider.provider, size: Layout.markColumn)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }

                VStack(alignment: .leading, spacing: 1) {
                    Text(provider.displayName)
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    if let plan = provider.plan, !plan.isEmpty {
                        Text(plan)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer(minLength: 6)

                if let headline = provider.headline {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(QuotaFormatting.percent(headline.percentRemaining))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("\(headline.windowLabel) left")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: Layout.percentColumn + 24, alignment: .trailing)
                }
            }

            ForEach(provider.allWindows) { window in
                WindowRow(window: window, tint: brandColor, now: now)
            }

            if let credits = provider.credits, credits.unlimited != true,
               let remaining = credits.remaining
            {
                Text("\(Int(remaining)) \(credits.unit ?? "credits") remaining")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, Layout.textInset)
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 9)
        .background(isFocused ? brandColor.opacity(0.08) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocus)
        .help(isFocused ? "Shown in the menu bar" : "Click to show \(provider.displayName) in the menu bar")
        .accessibilityElement(children: .combine)
    }
}

/// One window - its own label, its own remaining percent, its own reset.
struct WindowRow: View {
    let window: QuotaWindow
    let tint: Color
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.displayLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let cadence = QuotaFormatting.cadence(windowSeconds: window.windowSeconds) {
                    Text(cadence)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if let reset = QuotaFormatting.date(from: window.resetsAt) {
                    Text(QuotaFormatting.resetDescription(reset, now: now))
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let remaining = window.percentRemaining {
                    Text(QuotaFormatting.percent(remaining))
                        .font(.system(size: 10.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)
                }
            }

            if let remaining = window.percentRemaining {
                ProgressView(value: min(max(remaining, 0), 100), total: 100)
                    .tint(tint)
                    .controlSize(.small)
                    .frame(height: 3)
            }
        }
        .padding(.leading, Layout.textInset)
    }
}

struct InactiveProviderRow: View {
    let provider: QuotaProvider

    var body: some View {
        HStack(spacing: Layout.gutter) {
            ProviderMark(provider: provider.provider, size: Layout.markColumn)
            Text(provider.displayName)
                .font(.system(size: 11.5))
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(provider.unavailableDescription)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 3)
        .opacity(0.5)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preferences

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var preferences: AppPreferences
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    init(model: AppModel) {
        self.model = model
        preferences = model.preferences
    }

    var body: some View {
        Form {
            Picker("Refresh interval", selection: $preferences.refreshInterval) {
                ForEach(AppPreferences.refreshIntervals, id: \.seconds) { option in
                    Text(option.label).tag(option.seconds)
                }
            }

            Picker("Menu bar shows", selection: $preferences.focusMode) {
                ForEach(MenuBarFocusMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            if preferences.focusMode == .focusedProvider {
                Picker("Focused provider", selection: Binding(
                    get: { preferences.focusedProvider },
                    set: { model.focus(on: $0) }))
                {
                    Text("Choose a provider").tag("")
                    ForEach(model.allProviders) { provider in
                        Text(provider.displayName).tag(provider.provider)
                    }
                }
            }

            Toggle("Read-only refresh", isOn: $preferences.readOnlyRefresh)
            Text("Adds --no-credential-refresh. This avoids credential renewal, but quota may become stale.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if launchAtLogin.state == .notDetermined {
                LabeledContent("Launch at login") {
                    Text(launchAtLogin.errorMessage == nil ? "Not checked" : "Unavailable")
                        .foregroundStyle(.secondary)
                }
            } else {
                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin.state == .enabled },
                    set: { launchAtLogin.setEnabled($0) }))
            }
            if let error = launchAtLogin.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Providers") {
                if model.allProviders.isEmpty {
                    Text("Provider visibility is available after the first refresh.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.allProviders) { provider in
                        Toggle(isOn: Binding(
                            get: { preferences.isVisible(provider.provider) },
                            set: { preferences.setVisible($0, provider: provider.provider) }))
                        {
                            HStack(spacing: 7) {
                                ProviderMark(provider: provider.provider, size: 13)
                                Text(provider.displayName)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
        .onAppear { launchAtLogin.loadStatusIfNeeded() }
    }
}
