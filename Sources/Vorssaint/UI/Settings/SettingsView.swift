// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// System-Settings-style window: a sidebar of pages on the left, the selected
/// page on the right. Scales cleanly as features are added, and gives each
/// feature a page of its own with room for examples and advanced options.
struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var router = SettingsRouter.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var searchQuery = ""
    @State private var activeSearchIndex: Int?
    @FocusState private var sidebarSearchFocused: Bool

    private struct SearchResultsSnapshot: Equatable {
        let query: String
        let groups: [SettingsSearchGroup]

        var isBlank: Bool {
            query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var items: [SettingsSearchSuggestion] {
            groups.flatMap { group in
                (group.parentMatches ? [group.parentSuggestion] : []) + group.suggestions
            }
        }

        var ids: [SettingsSearchSuggestion.ID] { items.map(\.id) }

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.query == rhs.query && lhs.ids == rhs.ids
        }
    }

    /// The one map of pages, shared with the command bar (SettingsDirectory).
    private var sidebarSections: [(title: String, items: [SettingsDirectoryItem])] {
        SettingsDirectory.sections(l10n.s, language: l10n.language)
    }

    var body: some View {
        let searchResults = SearchResultsSnapshot(
            query: searchQuery,
            groups: SettingsSearchSupport.groupedMatchingItems(
                query: searchQuery,
                items: SettingsDirectory.searchItems(l10n.s, language: l10n.language),
                isAvailable: { features.isAvailable($0) })
        )

        NavigationSplitView {
            sidebar(searchResults: searchResults)
                .navigationSplitViewColumnWidth(min: 198, ideal: 210, max: 240)
        } detail: {
            // NavigationSplitView's detail slot sometimes queries its content
            // for an unconstrained ideal size (settling the divider, or on a
            // page switch). `List` answers that with its full content height
            // rather than a viewport size the way `ScrollView` does, and
            // `.frame(maxHeight: .infinity)` only bounds a size it is given,
            // not one it is asked to report - so a few hundred rows (Kill
            // Process) grew the whole window. `GeometryReader` reports the
            // real space it was actually given for normal layout, and ~zero
            // when asked for an unconstrained ideal size, breaking the chain.
            GeometryReader { geometry in
                detail
                    .settingsSectionFocus(for: router.page)
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 772, maxWidth: .infinity, minHeight: 528, maxHeight: .infinity)
        .onAppear { ensureVisiblePage() }
        .onChange(of: features.revision) { _, _ in ensureVisiblePage() }
        .onChange(of: searchResults, initial: true) { previous, current in
            updateSearchSelection(previous: previous, current: current)
        }
        .onChange(of: router.requestID) { _, _ in
            searchQuery = ""
            activeSearchIndex = nil
            ensureVisiblePage()
        }
    }

    /// macOS 27 backs the pinned sidebar search field with a hard top scroll
    /// edge, so rows fade out cleanly under it. On macOS 26 that effect does
    /// not render inside split-view sidebars and the pinned field has no
    /// backing of its own, so rows slid legibly across the placeholder
    /// (issues #183, #254); there the field lives on a fixed header above the
    /// list, where rows can never reach it. Earlier systems keep the classic
    /// opaque sidebar chrome.
    @ViewBuilder
    private func sidebar(searchResults: SearchResultsSnapshot) -> some View {
#if compiler(>=6.2)
        if #available(macOS 27, *) {
            sidebarList(searchResults: searchResults)
                .searchable(text: $searchQuery,
                            placement: .sidebar,
                            prompt: l10n.s.settingsSearchPlaceholder)
                .scrollEdgeEffectStyle(.hard, for: .top)
        } else if #available(macOS 26, *) {
            VStack(spacing: 0) {
                SidebarSearchField(query: $searchQuery, isFocused: $sidebarSearchFocused)
                sidebarList(searchResults: searchResults)
            }
        } else {
            sidebarList(searchResults: searchResults)
                .searchable(text: $searchQuery,
                            placement: .sidebar,
                            prompt: l10n.s.settingsSearchPlaceholder)
        }
#else
        sidebarList(searchResults: searchResults)
            .searchable(text: $searchQuery,
                        placement: .sidebar,
                        prompt: l10n.s.settingsSearchPlaceholder)
#endif
    }

    private var hasSearchQuery: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func sidebarList(searchResults: SearchResultsSnapshot) -> some View {
        if hasSearchQuery {
            searchResultsList(searchResults)
        } else {
            normalSidebarList
        }
    }

    private var normalSidebarList: some View {
        List(selection: $router.page) {
            ForEach(sidebarSections, id: \.title) { section in
                let items = section.items.filter {
                    FeatureVisibilitySupport.isPageVisible($0.page) { $0.isAvailable }
                        && SettingsSearchSupport.matches(query: searchQuery, title: $0.title,
                                                         keywords: $0.keywords)
                }
                if !items.isEmpty {
                    Section(section.title) {
                        ForEach(items) { item in
                            Label(item.title, systemImage: item.icon).tag(item.page)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private func searchResultsList(_ searchResults: SearchResultsSnapshot) -> some View {
        ScrollViewReader { proxy in
            List {
                ForEach(searchResults.groups) { group in
                    searchPageRow(group, searchResults: searchResults)
                    ForEach(group.suggestions) { suggestion in
                        searchSuggestionRow(suggestion, searchResults: searchResults)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: activeSearchIndex) { _, index in
                guard let index, searchResults.items.indices.contains(index) else { return }
                let id = searchResults.items[index].id
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    proxy.scrollTo(id)
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
            .background {
                SearchKeyMonitor(customSearchFocused: sidebarSearchFocused) { keyCode in
                    handleSearchKey(keyCode, searchResults: searchResults.items)
                }
            }
        }
    }

    private func searchPageRow(_ group: SettingsSearchGroup,
                               searchResults: SearchResultsSnapshot) -> some View {
        let suggestion = group.parentSuggestion
        let selectionIndex = searchResults.items.firstIndex { $0.id == suggestion.id }
        let isSelected = selectionIndex == activeSearchIndex
        return Button {
            requestSearchItem(suggestion)
        } label: {
            Label(group.pageItem.title, systemImage: group.pageItem.icon)
                .fontWeight(.semibold)
                .searchResultRowStyle(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(suggestion.id)
    }

    private func searchSuggestionRow(_ suggestion: SettingsSearchSuggestion,
                                     searchResults: SearchResultsSnapshot) -> some View {
        let selectionIndex = searchResults.items.firstIndex { $0.id == suggestion.id }
        let isSelected = selectionIndex == activeSearchIndex
        return Button {
            requestSearchItem(suggestion)
        } label: {
            Label(suggestion.title, systemImage: suggestion.icon)
                .searchResultRowStyle(isSelected: isSelected)
                .padding(.leading, 18)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .id(suggestion.id)
    }

    private func handleSearchKey(_ keyCode: UInt16,
                                  searchResults: [SettingsSearchSuggestion]) -> Bool {
        switch keyCode {
        case 126: // Up
            guard !searchResults.isEmpty else { return false }
            activeSearchIndex = SettingsSearchSupport.moveSelection(
                index: activeSearchIndex, delta: -1, count: searchResults.count)
            return true
        case 125: // Down
            guard !searchResults.isEmpty else { return false }
            activeSearchIndex = SettingsSearchSupport.moveSelection(
                index: activeSearchIndex, delta: 1, count: searchResults.count)
            return true
        case 36, 76: // Return / Keypad Enter
            guard let index = activeSearchIndex,
                  searchResults.indices.contains(index) else { return false }
            requestSearchItem(searchResults[index])
            return true
        default:
            return false
        }
    }

    private func updateSearchSelection(previous: SearchResultsSnapshot,
                                       current: SearchResultsSnapshot) {
        guard !current.isBlank, !current.items.isEmpty else {
            activeSearchIndex = nil
            return
        }
        if previous.query != current.query {
            activeSearchIndex = 0
        } else if previous.ids != current.ids {
            activeSearchIndex = SettingsSearchSupport.reconciledSelection(
                index: activeSearchIndex,
                previousIDs: previous.ids,
                resultIDs: current.ids)
        }
    }

    private struct SearchKeyMonitor: NSViewRepresentable {
        var customSearchFocused: Bool
        var handleKey: (UInt16) -> Bool

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.install(for: view)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            context.coordinator.customSearchFocused = customSearchFocused
            context.coordinator.handleKey = handleKey
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(customSearchFocused: customSearchFocused, handleKey: handleKey)
        }

        static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
            coordinator.removeMonitor()
        }

        final class Coordinator: NSObject {
            var customSearchFocused: Bool
            var handleKey: (UInt16) -> Bool
            private var monitor: Any?

            init(customSearchFocused: Bool, handleKey: @escaping (UInt16) -> Bool) {
                self.customSearchFocused = customSearchFocused
                self.handleKey = handleKey
            }

            func install(for view: NSView) {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                    [weak self, weak view] event in
                    guard let self, let view, let window = view.window,
                          event.window === window,
                          Self.isNavigationKey(event),
                          let editor = window.firstResponder as? NSTextView,
                          editor.isFieldEditor,
                          (customSearchFocused || Self.isSidebarSearchEditor(editor, near: view)),
                          !editor.hasMarkedText() else { return event }
                    return handleKey(event.keyCode) ? nil : event
                }
            }

            func removeMonitor() {
                guard let monitor else { return }
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }

            private static func isNavigationKey(_ event: NSEvent) -> Bool {
                let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
                guard event.modifierFlags.intersection(blockedModifiers).isEmpty else { return false }
                return [UInt16(126), 125, 36, 76].contains(event.keyCode)
            }

            private static func isSidebarSearchEditor(_ editor: NSTextView,
                                                      near monitorView: NSView) -> Bool {
                guard let searchField = editor.delegate as? NSSearchField else { return false }
                let searchMidX = searchField.convert(searchField.bounds, to: nil).midX
                let sidebarFrame = monitorView.convert(monitorView.bounds, to: nil)
                return sidebarFrame.minX...sidebarFrame.maxX ~= searchMidX
            }
        }
    }

    private func requestSearchItem(_ suggestion: SettingsSearchSuggestion) {
        activeSearchIndex = nil
        let routed = SettingsSearchSupport.route(for: suggestion)
        router.request(routed.destination, targetFeature: routed.targetFeature)
    }

    /// The selected page can leave the sidebar when its last feature is
    /// switched off in the hub; fall back to the hub itself, where the
    /// feature can be brought back.
    private func ensureVisiblePage() {
        if !FeatureVisibilitySupport.isPageVisible(router.page, isAvailable: { $0.isAvailable }) {
            router.page = .features
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch router.page {
        case .general: GeneralSettings()
        case .features: FeatureHubSettings()
        case .energy: EnergySettings()
        case .monitor: MonitorSettings()
        case .finderRename: FinderRenameSettings()
        case .autoQuit: AutoQuitSettings()
        case .uninstaller: UninstallerView()
        case .cleaner: CleanerSettings()
        case .clipboard: ClipboardSettings()
        case .screenRecorder: ScreenRecordingCaptureSettings()
        case .notchMedia: NotchMediaSettings()
        case .windowLayout: WindowLayoutSettings()
        case .shortcuts: ShortcutsSettings()
        case .advanced: AdvancedSettings()
        case .about: AboutSettings()
        }
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var appearance = AppAppearanceController.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var hotkeys = HotkeyManager.shared
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?
    @AppStorage(DefaultsKey.hotkeyEnabled) private var hotkeyEnabled = true

    private var appearanceStrings: AppearanceStrings { FeatureStrings.appearance(l10n.language) }

    var body: some View {
        Form {
            Section {
                Toggle(l10n.s.launchAtLogin, isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.setEnabled(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                    .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
                if let loginError {
                    Text(loginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Picker(l10n.s.languageLabel, selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                Picker(appearanceStrings.label, selection: $appearance.appearance) {
                    ForEach(AppAppearance.allCases) { option in
                        Text(option.title(appearanceStrings)).tag(option)
                    }
                }
                .pickerStyle(.segmented)
#if compiler(>=6.2)
                if #available(macOS 26.0, *) {
                    Toggle(appearanceStrings.liquidGlass, isOn: $appearance.liquidGlassEnabled)
                }
#endif
            }
            Section(l10n.s.menuBarSection) {
                Button(l10n.s.showMenuBarIcon) {
                    appDelegate()?.reshowStatusItem()
                }
                Text(l10n.s.showMenuBarIconCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // The panel hosts more than monitoring, so its layout editor lives
            // here with the app-wide options rather than on the Monitor page
            // (which the hub can hide entirely).
            Section(l10n.s.monitorOrderSection) {
                PanelOrderEditor()
                Text(l10n.s.monitorOrderHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingsSectionAnchor(.panelConfiguration)
            if AppFeature.keepAwake.isAvailable {
                Section(l10n.s.globalHotkeySection) {
                    Toggle(l10n.s.hotkeyToggle, isOn: $hotkeyEnabled)
                        .onChange(of: hotkeyEnabled) { _, enabled in
                            HotkeyManager.shared.setEnabled(enabled)
                        }
                    ShortcutPreferenceRow(role: .keepAwake, isEnabled: hotkeyEnabled) {
                        HotkeyManager.shared.syncWithPreferences()
                    }
                    if hotkeyEnabled, hotkeys.registrationFailed {
                        Text(l10n.s.shortcutUnavailable)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text(l10n.s.hotkeyCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Energy

struct EnergySettings: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration = 0
    @AppStorage(DefaultsKey.batteryLimit) private var batteryLimit = 10
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var keepAwakeAutoStart = false
    @AppStorage(DefaultsKey.keepAwakeRightClickToggle) private var keepAwakeRightClickToggle = false
    @AppStorage(DefaultsKey.keepAwakeAllowDisplaySleep) private var keepAwakeAllowDisplaySleep = false
    @AppStorage(DefaultsKey.showCountdown) private var showCountdown = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeActiveIcon) private var keepAwakeActiveIcon = KeepAwakeActiveIcon.chikit.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5

    var body: some View {
        Form {
            if AppFeature.keepAwake.isAvailable {
                Section(l10n.s.sessionSection) {
                    Picker(l10n.s.defaultDurationLabel, selection: $defaultDuration) {
                        Text(l10n.s.minutes15).tag(15)
                        Text(l10n.s.minutes30).tag(30)
                        Text(l10n.s.hour1).tag(60)
                        Text(l10n.s.hours2).tag(120)
                        Text(l10n.s.hours4).tag(240)
                        Text(l10n.s.hours8).tag(480)
                        Text(l10n.s.indefinite).tag(0)
                    }
                    SettingsToggleWithCaption(title: l10n.s.keepAwakeAutoStart,
                                              caption: l10n.s.keepAwakeAutoStartCaption,
                                              isOn: $keepAwakeAutoStart)
                    SettingsToggleWithCaption(title: l10n.s.keepAwakeRightClickToggle,
                                              caption: l10n.s.keepAwakeRightClickToggleCaption,
                                              isOn: $keepAwakeRightClickToggle)
                    // The countdown is a Keep Awake session readout, so it sits
                    // with the session options. Under the General page's menu
                    // bar section the label gave no clue which time it meant.
                    Toggle(l10n.s.showCountdown, isOn: $showCountdown)
                    SettingsToggleWithCaption(title: displaySleepStrings.allowDisplaySleep,
                                              caption: displaySleepStrings.allowDisplaySleepCaption,
                                              isOn: $keepAwakeAllowDisplaySleep)
                }
                .settingsSectionAnchor(.keepAwake)
                Section(automationStrings.automationSection) {
                    SettingsCaptionText(automationStrings.automationCaption)
                    KeepAwakeAutomationEditor()
                }
                if PowerSampler.hasInternalBattery {
                    Section(l10n.s.batteryProtectionSection) {
                        Picker(l10n.s.batteryDisableBelow, selection: $batteryLimit) {
                            Text(l10n.s.batteryNever).tag(0)
                            Text("5%").tag(5)
                            Text("10%").tag(10)
                            Text("15%").tag(15)
                            Text("20%").tag(20)
                        }
                        SettingsCaptionText(l10n.s.batteryProtectionCaption)
                    }
                }
                Section(l10n.s.keepAwakeTitle) {
                    KeepAwakeIconPicker(iconValue: $keepAwakeActiveIcon,
                                        tintValue: $keepAwakeIconTint)
                    SettingsToggleWithCaption(title: l10n.s.keepAwakeMouseJiggle,
                                              caption: l10n.s.keepAwakeMouseJiggleCaption,
                                              isOn: $keepAwakeMouseJiggle)
                    if keepAwakeMouseJiggle {
                        Picker(l10n.s.keepAwakeMouseJiggleInterval, selection: $keepAwakeMouseJiggleInterval) {
                            ForEach(Defaults.allowedKeepAwakeMouseJiggleIntervals, id: \.self) { minutes in
                                Text(KeepAwakeMouseJiggleIntervalPicker.label(for: minutes)).tag(minutes)
                            }
                        }
                        if !permissions.accessibility {
                            PermissionRow(kind: .accessibility)
                        }
                    }
                }
                Section(l10n.s.clamshellSection) {
                    Toggle(l10n.s.clamshellTitle, isOn: $awake.clamshellPreferred)
                        .disabled(awake.clamshellSetupInProgress)
                    if awake.clamshellSetupInProgress {
                        Text(l10n.s.configuring)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if awake.clamshellSetupFailed {
                        Text(l10n.s.sudoersFailed)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    SettingsCaptionText(l10n.s.clamshellExplanation)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            batteryLimit = Defaults.sanitizedBatteryLimit(batteryLimit)
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            keepAwakeActiveIcon = Defaults.sanitizedKeepAwakeActiveIcon(keepAwakeActiveIcon).rawValue
            keepAwakeMouseJiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(keepAwakeMouseJiggleInterval)
            awake.refreshPasswordlessStatus()
        }
    }

    private var automationStrings: KeepAwakeAutomationStrings {
        FeatureStrings.keepAwakeAutomation(l10n.language)
    }

    private var displaySleepStrings: KeepAwakeDisplaySleepStrings {
        FeatureStrings.keepAwakeDisplaySleep(l10n.language)
    }
}

// MARK: - About

struct AboutSettings: View {
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Form {
            Section {
                aboutContent
            }
        }
        .formStyle(.grouped)
    }

    private var aboutContent: some View {
        VStack(spacing: 14) {
            BrandBadge(size: 76)
            VStack(spacing: 3) {
                Text(AppInfo.name)
                    .font(.title2.bold())
                HStack(spacing: 6) {
                    Text("\(l10n.s.versionPrefix) \(AppInfo.version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if AppInfo.isDeveloperBuild, let commit = AppInfo.buildCommit {
                    // Dev-only: which source commit this build came from. Never shipped.
                    Text(commit)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            Text(l10n.s.aboutDescription)
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(l10n.s.reviewIntro) {
                    appDelegate()?.showOnboarding()
                }
                Link(l10n.s.viewOnGitHub, destination: AppInfo.repositoryURL)
            }
            Text(AppInfo.copyright)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Shared settings rows

private struct SettingsCaptionText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsToggleWithCaption: View {
    let title: String
    let caption: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                SettingsCaptionText(caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Shared permission row

enum PermissionKind {
    case accessibility
    case screenRecording
    case microphone
}

/// Status + actions for one TCC permission; shared by Settings and onboarding.
struct PermissionRow: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @State private var pollingDemandID = UUID()
    let kind: PermissionKind

    private var granted: Bool {
        switch kind {
        case .accessibility: return permissions.accessibility
        case .screenRecording: return permissions.screenRecording
        case .microphone: return permissions.microphone == .granted
        }
    }

    private var monitorsActivePermission: Bool {
        switch kind {
        case .accessibility, .screenRecording: return true
        case .microphone: return false
        }
    }

    private var name: String {
        switch kind {
        case .accessibility: return l10n.s.permissionAccessibility
        case .screenRecording: return l10n.s.permissionScreenRecording
        case .microphone:
            return FeatureStrings.recorder(l10n.language).microphonePermissionName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? .green : .orange)
                Text(name)
                Spacer()
                Text(granted ? l10n.s.permissionGranted : l10n.s.permissionMissing)
                    .font(.caption)
                    .foregroundStyle(granted ? .green : .orange)
            }
            if !granted {
                HStack(spacing: 8) {
                    Button(l10n.s.permissionRequest) {
                        switch kind {
                        case .accessibility:
                            permissions.requestAccessibility()
                        case .screenRecording:
                            permissions.requestScreenRecording()
                        case .microphone:
                            permissions.requestMicrophone()
                        }
                    }
                    Button(l10n.s.permissionOpenSettings) {
                        switch kind {
                        case .accessibility:
                            permissions.openAccessibilitySettings()
                        case .screenRecording:
                            permissions.openScreenRecordingSettings()
                        case .microphone:
                            permissions.openMicrophoneSettings()
                        }
                    }
                }
                .controlSize(.small)
            }
        }
        .onAppear {
            if monitorsActivePermission {
                permissions.setActivePermissionSurface(pollingDemandID, visible: true)
            }
        }
        .onDisappear {
            permissions.setActivePermissionSurface(pollingDemandID, visible: false)
        }
    }
}

/// Search field for the macOS 26 sidebar, styled after the system pill.
/// It sits on a fixed header outside the List, so scrolling rows can never
/// cross it (issues #183, #254). Esc and the clear button empty the query,
/// matching the system field.
private struct SidebarSearchField: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var query: String
    var isFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(l10n.s.settingsSearchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .onExitCommand { query = "" }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.s.urlCleanerClearButton)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 7)
        .background(.quaternary.opacity(0.5), in: Capsule())
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

private extension View {
    func searchResultRowStyle(isSelected: Bool) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected ? Color.chikitAccent : Color.primary)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.chikitAccent.opacity(0.18) : .clear)
            }
    }
}
