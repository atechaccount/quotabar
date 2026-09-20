import AppKit
import QuotaBarCore
import SwiftUI

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 3) {
            QuotaGlyph()
            if let percent = model.menuBarPercent {
                Text(percent)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .onAppear { model.statusItemAppeared() }
    }

    private var accessibilityLabel: String {
        model.menuBarPercent.map { "QuotaBar, \($0) remaining" } ?? "QuotaBar"
    }
}

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
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
    }
}

struct QuotaMenuView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 0) {
                header(now: context.date)
                Divider()
                providerList(now: context.date)
                Divider()
                actions
            }
            .frame(width: 350)
        }
        .onAppear { model.menuOpened() }
    }

    private func header(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("QuotaBar")
                    .font(.headline)
                Spacer()
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                    Text("Refreshing")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 5) {
                if let updated = model.lastSuccessAt {
                    Text("Last updated \(QuotaFormatting.age(since: updated, now: now))")
                } else {
                    Text("Waiting for first refresh")
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
            .font(.caption)
            .foregroundStyle(.secondary)

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func providerList(now: Date) -> some View {
        if model.providers.isEmpty {
            Text(model.snapshot == nil ? "Loading provider quotas…" : "No providers are visible.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.providers) { provider in
                        ProviderRow(provider: provider, now: now)
                        if provider.id != model.providers.last?.id {
                            Divider().padding(.leading, 34)
                        }
                    }
                }
            }
            .frame(maxHeight: 520)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button {
                model.refreshNow()
            } label: {
                Label("Refresh now", systemImage: "arrow.clockwise")
            }

            Spacer()

            Button("Preferences…") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Quit") {
                NSApp.terminate(nil)
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
    }
}

struct ProviderRow: View {
    let provider: QuotaProvider
    let now: Date

    private var color: Color { Color(hex: BrandColors.hex(for: provider.provider)) }
    private var windows: [QuotaWindow] { provider.windows ?? [] }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(provider.displayName)
                            .font(.system(size: 13, weight: .semibold))
                        if let plan = provider.plan, !plan.isEmpty {
                            Text(plan)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    headline
                }

                if provider.isFresh, let remaining = provider.headlineRemaining {
                    ProgressView(value: min(max(remaining, 0), 100), total: 100)
                        .tint(color)
                        .controlSize(.small)

                    if let reset = soonestReset {
                        Text(QuotaFormatting.resetDescription(reset, now: now))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if windows.count > 1 {
                        VStack(spacing: 2) {
                            ForEach(Array(windows.enumerated()), id: \.offset) { _, window in
                                windowLine(window)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .opacity(provider.isFresh ? 1 : 0.48)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var headline: some View {
        if provider.isFresh, let remaining = provider.headlineRemaining {
            Text(QuotaFormatting.percent(remaining))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        } else {
            Text(provider.unavailableDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func windowLine(_ window: QuotaWindow) -> some View {
        HStack {
            Text(window.label ?? window.kind ?? "window")
            Spacer()
            if let remaining = window.percentRemaining {
                Text(QuotaFormatting.percent(remaining))
                    .monospacedDigit()
            }
            if let reset = QuotaFormatting.date(from: window.resetsAt) {
                Text("· \(QuotaFormatting.resetDescription(reset, now: now))")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var soonestReset: Date? {
        windows.compactMap { QuotaFormatting.date(from: $0.resetsAt) }.min()
    }
}

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

            Picker("Menu bar display", selection: $preferences.displayStyle) {
                ForEach(MenuBarDisplayStyle.allCases) { style in
                    Text(style.title).tag(style)
                }
            }

            if preferences.displayStyle == .pinned {
                Picker("Pinned provider", selection: $preferences.pinnedProvider) {
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
                        Toggle(provider.displayName, isOn: Binding(
                            get: { preferences.isVisible(provider.provider) },
                            set: { preferences.setVisible($0, provider: provider.provider) }))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 480, height: 520)
        .onAppear { launchAtLogin.loadStatusIfNeeded() }
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(), radix: 16) ?? 0x7C7C80
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1)
    }
}
