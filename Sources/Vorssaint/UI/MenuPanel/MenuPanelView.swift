// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let menuPanelWillShow = Notification.Name("ChikitMenuPanelWillShow")
}

struct MenuPanelFocusRequest: Equatable {
    let target: MenuPanelFocusTarget
    let serial: Int
}

enum MenuPanelFocusTarget: Equatable {
    case normal
    case section(PanelSectionID)
    case metric(MetricDetailKind)
}

final class MenuPanelFocus: ObservableObject {
    static let shared = MenuPanelFocus()

    @Published private(set) var request: MenuPanelFocusRequest?
    @Published private(set) var activeMetric: MetricDetailKind?
    @Published private(set) var isSwitchingMetricAnchor = false
    private var serial = 0

    private init() {}

    func showNormalPanel() {
        serial += 1
        activeMetric = nil
        request = MenuPanelFocusRequest(target: .normal, serial: serial)
    }

    func focus(_ section: PanelSectionID) {
        serial += 1
        activeMetric = nil
        request = MenuPanelFocusRequest(target: .section(section), serial: serial)
    }

    func focus(_ metric: MetricDetailKind) {
        serial += 1
        activeMetric = metric
        request = MenuPanelFocusRequest(target: .metric(metric), serial: serial)
    }

    func clearMetricFocus() {
        activeMetric = nil
    }

    func setSwitchingMetricAnchor(_ switching: Bool) {
        isSwitchingMetricAnchor = switching
    }
}

/// Content of the menu bar popover: keep-awake controls, the volume mixer and
/// the system monitor.
struct MenuPanelView: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var panelFocus = MenuPanelFocus.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(DefaultsKey.monitorShowMixer) private var showMixer = true
    @AppStorage(DefaultsKey.monitorShowSystem) private var showSystem = true
    @AppStorage(DefaultsKey.monitorShowNetwork) private var showNetwork = true
    @AppStorage(DefaultsKey.monitorShowDisk) private var showDisk = true
    @AppStorage(DefaultsKey.monitorShowPower) private var showPower = true
    @AppStorage(DefaultsKey.panelShowFanControl) private var showFanControl = true
    @AppStorage(DefaultsKey.panelShowKeepAwake) private var showKeepAwake = true
    @AppStorage(DefaultsKey.panelShowUtilities) private var showUtilities = true
    @AppStorage(DefaultsKey.panelShowControls) private var showControls = true
    @AppStorage(DefaultsKey.panelSectionOrder) private var sectionOrderRaw = ""
    @State private var navigableContentHeight: CGFloat = 0
    @State private var metricContentHeight: CGFloat = 0
    @State private var selectedSection: PanelSectionID = PanelLayout.order.first ?? .keepAwake
    @State private var selectedMetric: MetricDetailKind?
    @FocusState private var focusedSection: PanelSectionID?

    /// Cap the panel to the usable screen height so it never overflows the menu
    /// bar; taller content scrolls inside. Measured against the display the
    /// menu bar icon is on, which is not always the one holding the key window.
    private var maxHeight: CGFloat {
        let anchored = PanelInteractionState.shared.anchorScreen
            .flatMap { anchor in anchor.isStillAttached ? anchor : nil }
        return max(360, ((anchored ?? NSScreen.withMenuBar)?.visibleFrame.height ?? 760) - 24)
    }

    var body: some View {
        Group {
            if selectedMetric != nil {
                metricPanel
            } else {
                navigablePanel
            }
        }
        .onAppear {
            applyFocus(panelFocus.request)
            KeepAwakeManager.shared.refreshPasswordlessStatus()
            syncMonitorSampling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuPanelWillShow)) { _ in
            syncMonitorSampling()
        }
        .onDisappear {
            if !panelFocus.isSwitchingMetricAnchor {
                SystemMonitor.shared.setMenuPanelNeeds(.none)
            }
        }
        .onChange(of: monitorNeeds) { _, _ in
            syncMonitorSampling()
        }
        .onChange(of: panelFocus.request) { _, request in
            applyFocus(request)
        }
        .onChange(of: focusedSection) { _, section in
            if let section { selectedSection = section }
        }
    }

    private var monitorNeeds: SystemMonitorPanelNeeds {
        if let selectedMetric {
            return selectedMetric.monitorNeeds
        }
        switch activeSection {
        case .system: return SystemMonitorPanelNeeds(system: true)
        case .network: return SystemMonitorPanelNeeds(network: true)
        case .disk: return SystemMonitorPanelNeeds(disk: true)
        case .power: return SystemMonitorPanelNeeds(power: true)
        default: return .none
        }
    }

    private func syncMonitorSampling() {
        SystemMonitor.shared.setMenuPanelNeeds(monitorNeeds)
    }

    private func applyFocus(_ request: MenuPanelFocusRequest?) {
        guard let request else { return }
        switch request.target {
        case .normal:
            selectedMetric = nil
        case .section(let section):
            guard isSectionVisible(section) else { return }
            selectedMetric = nil
            selectedSection = section
            focusedSection = section
        case .metric(let metric):
            focusedSection = nil
            selectedMetric = metric
            selectedSection = metric.panelSection
        }
    }

    private var navigablePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            sectionNavigation

            OverlayScrollView(measuredHeight: $navigableContentHeight) {
                VStack(alignment: .leading, spacing: 12) {
                    section(for: activeSection, collapsible: false)
                }
                .frame(width: 308)
            }
            .frame(width: 308, height: navigableScrollHeight)

            footer
        }
        .padding(12)
        .frame(width: 332, height: navigablePanelHeight)
        .panelGlassSurface()
    }

    private var metricPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let selectedMetric {
                metricNavigationHeader(selectedMetric)
                OverlayScrollView(measuredHeight: $metricContentHeight) {
                    MetricDetailView(kind: selectedMetric)
                        .frame(width: 308)
                }
                .frame(width: 308, height: metricScrollHeight)
            }

            footer
        }
        .padding(12)
        .frame(width: 332, height: metricPanelHeight)
        .panelGlassSurface()
    }

    /// The major sections in the user's saved order. Reading `sectionOrderRaw`
    /// (the @AppStorage backing) establishes the dependency so reordering in
    /// Settings refreshes the live panel; PanelLayout fills in any sections the
    /// saved order omits.
    private var orderedSections: [PanelSectionID] {
        _ = sectionOrderRaw
        return PanelLayout.order
    }

    private var visibleSections: [PanelSectionID] {
        orderedSections.filter(isSectionVisible)
    }

    private var activeSection: PanelSectionID {
        visibleSections.contains(selectedSection) ? selectedSection : (visibleSections.first ?? .keepAwake)
    }

    private var navigableScrollHeight: CGFloat {
        let measured = navigableContentHeight == 0 ? estimatedNavigableContentHeight : navigableContentHeight
        return min(measured, max(80, maxHeight - navigableChromeHeight))
    }

    private var navigablePanelHeight: CGFloat {
        min(maxHeight, max(220, navigableScrollHeight + navigableChromeHeight))
    }

    private var metricScrollHeight: CGFloat {
        let measured = metricContentHeight == 0 ? estimatedMetricContentHeight : metricContentHeight
        return min(measured, max(80, maxHeight - navigableChromeHeight))
    }

    private var metricPanelHeight: CGFloat {
        min(maxHeight, max(220, metricScrollHeight + navigableChromeHeight))
    }

    private var navigableChromeHeight: CGFloat {
        180
    }

    private var estimatedNavigableContentHeight: CGFloat {
        switch activeSection {
        case .keepAwake: return 250
        case .mixer: return 250
        case .system: return 460
        case .network: return 190
        case .disk: return 360
        case .power: return 170
        case .fanControl: return 220
        case .utilities: return 500
        case .controls: return 360
        }
    }

    private var estimatedMetricContentHeight: CGFloat {
        guard let selectedMetric else { return 320 }
        switch selectedMetric {
        case .cpu, .gpu, .memory: return 430
        case .network: return 330
        case .disk: return 360
        case .battery, .power: return 360
        case .fan: return 240
        }
    }

    /// Renders the section for an id, honoring its "show in panel" toggle. Each
    /// section self-hides when it has nothing to show, so the order is stable
    /// whether or not a section is currently populated.
    @ViewBuilder
    private func section(for id: PanelSectionID, collapsible: Bool = true) -> some View {
        switch id {
        case .keepAwake: KeepAwakeCard(collapsible: collapsible)
        case .mixer: if showMixer { MixerSection(collapsible: collapsible) }
        case .system: if showSystem { SystemSection(collapsible: collapsible) }
        case .network: if showNetwork { NetworkSection(collapsible: collapsible) }
        case .disk: if showDisk { DiskSection(collapsible: collapsible) }
        case .power: if showPower { PowerSection(collapsible: collapsible) }
        case .fanControl: if showFanControl { FanControlSection(collapsible: collapsible) }
        case .utilities: UtilitiesSection(collapsible: collapsible)
        case .controls: QuickControlsSection(collapsible: collapsible)
        }
    }

    private func isSectionVisible(_ id: PanelSectionID) -> Bool {
        guard id.isAvailable else { return false }
        switch id {
        case .keepAwake: return showKeepAwake
        case .mixer: return showMixer
        case .system: return showSystem
        case .network: return showNetwork
        case .disk: return showDisk
        case .power: return showPower
        case .fanControl: return showFanControl
        case .utilities: return showUtilities
        case .controls: return showControls
        }
    }

    private var sectionNavigation: some View {
        HStack(spacing: 2) {
            ForEach(visibleSections) { id in
                let isActive = activeSection == id
                Button {
                    selectedSection = id
                    focusedSection = id
                } label: {
                    Image(systemName: id.symbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .focused($focusedSection, equals: id)
                .foregroundStyle(isActive ? Color.chikitAccent : Color.secondary.opacity(0.86))
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isActive ? navigationActiveFill : Color.clear)
                )
                .help(id.title(l10n.s))
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(PanelSurface.cardFill(for: colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
        )
    }

    private var navigationActiveFill: Color {
        colorScheme == .light ? Color.chikitAccent.opacity(0.13) : Color.chikitAccent.opacity(0.20)
    }

    private func metricNavigationHeader(_ kind: MetricDetailKind) -> some View {
        HStack(spacing: 8) {
            Button {
                selectedMetric = nil
                selectedSection = kind.panelSection
                MenuPanelFocus.shared.clearMetricFocus()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(PanelSurface.cardFill(for: colorScheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.7)
            )

            Label(kind.title(l10n.s), systemImage: kind.symbolName)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        MenuPanelHeader()
    }

    private var footer: some View {
        HStack(spacing: 8) {
            footerButton(l10n.s.panelSettings,
                         systemImage: "gearshape",
                         horizontalPadding: 7) {
                // The hosted utility's own page, or the general one from the
                // panel's lists: the router is sticky, so it is set every time.
                SettingsRouter.shared.page = PanelInteractionState.shared.hostedSettingsPage ?? .general
                appDelegate()?.openSettingsWindow()
            }

            footerButton(l10n.s.panelQuit,
                         systemImage: "power",
                         horizontalPadding: 7) {
                NSApp.terminate(nil)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .padding(.top, 4)
    }

    private func footerButton(_ title: String, systemImage: String,
                              horizontalPadding: CGFloat = 8,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, horizontalPadding)
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PanelSurface.cardFill(for: colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(PanelSurface.border(for: colorScheme), lineWidth: 0.8)
                )
                .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
    }
}

private struct MenuPanelHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        ZStack {
            BrandMark(width: 48, tint: markTint)
                .frame(height: 28)
                .accessibilityHidden(true)
        }
        .frame(height: 28)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
    }

    private var markTint: Color {
        colorScheme == .light ? Color(white: 0.03) : .white
    }
}

private enum UtilityPanelItem: String, PanelOrderItem, Identifiable {
    // Case order IS the default panel order (PanelLayout.itemOrder falls back
    // to allCases).
    case cleaner, clipboard, windowLayout, uninstaller, screenRecorder, converter

    var id: String { rawValue }

    /// The hub feature behind the tile; off in the hub removes it everywhere,
    /// including the edit and hidden lists.
    var feature: AppFeature {
        switch self {
        case .cleaner: return .cleaner
        case .clipboard: return .clipboardHistory
        case .windowLayout: return .windowLayout
        case .uninstaller: return .uninstaller
        case .screenRecorder: return .screenRecorder
        case .converter: return .fileConverter
        }
    }
}

struct UtilitiesSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @ObservedObject private var features = FeatureRuntime.shared
    @State private var showUninstaller = false
    @State private var showConverter = false
    @AppStorage(DefaultsKey.panelUtilityConverter) private var showConverterAction = true
    @State private var showCleanerPanel = false
    @State private var showClipboardPanel = false
    @State private var showRecentCapturesPanel = false
    @State private var showWindowLayoutPanel = false
    @AppStorage(DefaultsKey.panelUtilityUninstaller) private var showUninstallerAction = true
    @AppStorage(DefaultsKey.panelUtilityCleaner) private var showCleanerAction = true
    @AppStorage(DefaultsKey.panelUtilityClipboard) private var showClipboard = true
    @AppStorage(DefaultsKey.panelUtilityWindowLayout) private var showWindowLayout = true
    @AppStorage(DefaultsKey.panelUtilityScreenRecorder) private var showScreenRecorder = true
    @ObservedObject private var recorder = ScreenRecorderService.shared
    @AppStorage(DefaultsKey.clipboardHistoryEnabled) private var clipboardEnabled = false
    @AppStorage(DefaultsKey.panelUtilityOrder) private var utilityOrderRaw = ""
    @State private var draggingItem: UtilityPanelItem?
    var collapsible = true

    var body: some View {
        PanelSection(.utilities, title: l10n.s.utilitiesSection, collapsible: collapsible,
                     supportsEditing: true,
                     editButtonVisible: !isHostingUtility,
                     resetAction: resetPanelDefaults) { editing in
            if showUninstaller {
                PanelUninstallerView {
                    showUninstaller = false
                }
            } else if showConverter {
                PanelConverterView {
                    showConverter = false
                }
            } else if showCleanerPanel {
                PanelCleanerView {
                    showCleanerPanel = false
                }
            } else if showClipboardPanel {
                PanelClipboardView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showClipboardPanel = false
                }
            } else if showRecentCapturesPanel {
                PanelRecentCapturesView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showRecentCapturesPanel = false
                }
            } else if showWindowLayoutPanel {
                PanelWindowLayoutView {
                    PanelInteractionState.shared.viewKeepsPopoverOpen = false
                    showWindowLayoutPanel = false
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(items(editing: editing)) { item in
                        PanelReorderableItem(item: item,
                                             isEnabled: editing,
                                             order: itemOrderBinding,
                                             dragging: $draggingItem) {
                            itemView(item, editing: editing)
                        }
                    }
                }
            }
        }
        .onChange(of: hostedUtilityKeepsPopoverOpen) { _, keepsOpen in
            PanelInteractionState.shared.viewKeepsPopoverOpen = keepsOpen
        }
        .onChange(of: hostedSettingsPage) { _, page in
            PanelInteractionState.shared.hostedSettingsPage = page
        }
        .onDisappear {
            // Another section, or a metric, replacing this one takes the
            // tool off screen with it; a closed panel does not, and keeps it.
            PanelInteractionState.shared.viewKeepsPopoverOpen = false
            PanelInteractionState.shared.hostedSettingsPage = nil
        }
    }

    /// The Settings page that belongs to whichever tool the section is
    /// showing, derived from the same state as `isHostingUtility` so every
    /// hosted tool is covered by the one list. Mirrored by the `onChange`
    /// beside it, and cleared only where this section leaves the screen.
    private var hostedSettingsPage: SettingsPage? {
        if showUninstaller { return .uninstaller }
        if showCleanerPanel { return .cleaner }
        if showClipboardPanel { return .clipboard }
        if showRecentCapturesPanel { return .screenRecorder }
        if showWindowLayoutPanel { return .windowLayout }
        return nil
    }

    /// True while the section is showing one of the tools instead of its own
    /// list. A hosted tool turns the panel into a work surface, so clicks
    /// elsewhere in the app must not dismiss it.
    private var isHostingUtility: Bool {
        showUninstaller || showConverter || showCleanerPanel || showClipboardPanel
            || showRecentCapturesPanel || showWindowLayoutPanel
    }

    private var hostedUtilityKeepsPopoverOpen: Bool {
        isHostingUtility
    }

    private var orderedItems: [UtilityPanelItem] {
        _ = utilityOrderRaw
        return PanelLayout.itemOrder(UtilityPanelItem.self, key: DefaultsKey.panelUtilityOrder)
    }

    private var itemOrderBinding: Binding<[UtilityPanelItem]> {
        Binding {
            orderedItems
        } set: { newValue in
            PanelLayout.setItemOrder(newValue, key: DefaultsKey.panelUtilityOrder)
        }
    }

    private func items(editing: Bool) -> [UtilityPanelItem] {
        orderedItems.filter { $0.feature.isAvailable && (editing || isVisible($0)) }
    }

    private func isVisible(_ item: UtilityPanelItem) -> Bool {
        switch item {
        case .clipboard: return showClipboard
        case .windowLayout: return showWindowLayout
        case .uninstaller: return showUninstallerAction
        case .cleaner: return showCleanerAction
        case .screenRecorder: return showScreenRecorder
        case .converter: return showConverterAction
        }
    }

    @ViewBuilder
    private func itemView(_ item: UtilityPanelItem, editing: Bool) -> some View {
        switch item {
        case .clipboard:
            UtilityActionButton(title: FeatureStrings.clipboard(l10n.language).title,
                                caption: clipboardEnabled
                                    ? FeatureStrings.clipboard(l10n.language).caption
                                    : FeatureStrings.clipboard(l10n.language).disabled,
                                systemImage: "doc.on.clipboard",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showClipboard,
                                shortcutHint: shortcutHint(.clipboard),
                                action: {
                                    showClipboardPanel = true
                                })
        case .windowLayout:
            UtilityActionButton(title: FeatureStrings.windowLayout(l10n.language).title,
                                caption: FeatureStrings.windowLayout(l10n.language).caption,
                                systemImage: "rectangle.3.group",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showWindowLayout,
                                action: {
                                    showWindowLayoutPanel = true
                                })
        case .uninstaller:
            UtilityActionButton(title: l10n.s.uninstallerName,
                                caption: l10n.s.uninstallerEnableCaption,
                                systemImage: "trash",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showUninstallerAction,
                                action: {
                                    showUninstaller = true
                                })
        case .converter:
            UtilityActionButton(title: "Convert",
                                caption: "Audio, video, images, docs, PDF, Excel",
                                systemImage: "arrow.triangle.2.circlepath",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showConverterAction,
                                action: {
                                    showConverter = true
                                })
        case .cleaner:
            UtilityActionButton(title: l10n.s.cleanerName,
                                caption: l10n.s.cleanerPanelCaption,
                                systemImage: "sparkle",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showCleanerAction,
                                action: {
                                    showCleanerPanel = true
                                })
        case .screenRecorder:
            UtilityActionButton(title: screenRecorderTitle,
                                caption: screenRecorderCaption,
                                systemImage: recorder.isRecording ? "stop.circle" : "record.circle",
                                isEditing: editing,
                                showsDragHandle: true,
                                visibility: $showScreenRecorder,
                                needsAttention: !permissions.screenRecording,
                                permissionButtonTitle: l10n.s.permissionRequest,
                                permissionAction: permissions.screenRecording ? nil : grantScreenRecordingPermission,
                                shortcutHint: shortcutHint(.screenRecorder),
                                accessoryTitle: recorder.isRecording
                                    ? nil
                                    : FeatureStrings.recentCaptures(l10n.language).title,
                                accessorySystemImage: "clock.arrow.circlepath",
                                accessoryAction: recorder.isRecording ? nil : showRecentCaptures,
                                action: {
                                    appDelegate()?.closePopover()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        ScreenRecorderService.shared.toggle()
                                    }
                                })
        }
    }

    /// The row's key hint: only when the shortcut is actually REGISTERED,
    /// using the same gates the services use (the clipboard needs both the
    /// feature and its shortcut toggle), so the badge never advertises a
    /// combo that does nothing.
    private func shortcutHint(_ role: GlobalShortcutRole) -> String? {
        guard role.isAvailable(using: { $0.isAvailable }),
              role.requiredEnableKeys.allSatisfy({ UserDefaults.standard.bool(forKey: $0) })
        else { return nil }
        return role.savedShortcut.displayString
    }

    /// While a recording runs the tile becomes the way to end it, so the
    /// panel never shows an action the person cannot take.
    private var screenRecorderTitle: String {
        let strings = FeatureStrings.recorder(l10n.language)
        return recorder.isRecording ? strings.stopButton : strings.pageTitle
    }

    private var screenRecorderCaption: String {
        guard permissions.screenRecording else {
            return "\(l10n.s.permissionRequired): \(l10n.s.permissionScreenRecording)"
        }
        let strings = FeatureStrings.recorder(l10n.language)
        return recorder.isRecording
            ? RecorderSupport.elapsedLabel(seconds: recorder.elapsedSeconds)
            : strings.panelCaption
    }

    private func grantScreenRecordingPermission() {
        Permissions.shared.requestScreenRecording()
    }

    private func showRecentCaptures() {
        showRecentCapturesPanel = true
    }

    private func resetPanelDefaults() {
        PanelLayout.resetItemOrder(key: DefaultsKey.panelUtilityOrder)
        utilityOrderRaw = ""
        showClipboard = true
        showWindowLayout = true
        showUninstallerAction = true
        showConverterAction = true
        showCleanerAction = true
        showScreenRecorder = true
    }
}

struct QuickControlsSection: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.autoQuitEnabled) private var autoQuitEnabled = false
    var collapsible = true

    var body: some View {
        PanelSection(.controls, title: l10n.s.quickControlsSection, collapsible: collapsible) {
            PanelToggleRow(title: l10n.s.autoQuitName,
                           caption: caption,
                           systemImage: "xmark.rectangle",
                           isOn: $autoQuitEnabled,
                           needsAttention: autoQuitEnabled && !permissions.accessibility,
                           permissionButtonTitle: l10n.s.permissionRequest,
                           permissionAction: autoQuitEnabled && !permissions.accessibility
                               ? grantAccessibility : nil)
                .onChange(of: autoQuitEnabled) { _, _ in
                    AutoQuitService.shared.syncWithPreferences()
                }
        }
    }

    private var caption: String {
        guard autoQuitEnabled, !permissions.accessibility else { return l10n.s.autoQuitEnableCaption }
        return "\(l10n.s.permissionRequired): \(l10n.s.permissionAccessibility)"
    }

    private func grantAccessibility() {
        Permissions.shared.requestAccessibility()
        Permissions.shared.openAccessibilitySettings()
    }
}

// Internal (not private): the quick toggles tab builds its rows from the same
// component, so every action row in the panel looks and behaves the same.
struct UtilityActionButton: View {
    let title: String
    let caption: String
    let systemImage: String
    var badge: String? = nil
    var isEditing = false
    var showsDragHandle = false
    var visibility: Binding<Bool>? = nil
    var needsAttention = false
    var permissionButtonTitle: String? = nil
    var permissionAction: (() -> Void)? = nil
    /// The feature's enabled global shortcut, shown as a quiet key hint so
    /// the panel row doubles as a reminder that the keyboard path exists.
    var shortcutHint: String? = nil
    var accessoryTitle: String? = nil
    var accessorySystemImage: String? = nil
    var accessoryAction: (() -> Void)? = nil
    let action: () -> Void

    var body: some View {
        Group {
            if isEditing {
                rowContent(showChevron: false)
                    .panelCard()
            } else if permissionAction != nil || accessoryAction != nil {
                VStack(alignment: .leading, spacing: 7) {
                    if permissionAction != nil {
                        rowContent(showChevron: false)
                        permissionButton
                    } else {
                        mainButton
                    }
                    accessoryButton
                }
                .panelCard()
            } else {
                Button(action: action) {
                    rowContent(showChevron: true)
                        .panelCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var mainButton: some View {
        Button(action: action) {
            rowContent(showChevron: true)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var accessoryButton: some View {
        if let accessoryTitle, let accessoryAction {
            Button(action: accessoryAction) {
                Label(accessoryTitle, systemImage: accessorySystemImage ?? "clock")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .padding(.leading, 31)
        }
    }

    private func rowContent(showChevron: Bool) -> some View {
        HStack(spacing: 9) {
            if isEditing && showsDragHandle {
                PanelDragHandle()
            }
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHiddenInEditor ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge {
                        PanelBetaBadge(text: badge)
                    }
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(captionColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if isEditing, let visibility {
                if !visibility.wrappedValue {
                    PanelHiddenBadge()
                }
                PanelInlineHideButton(isVisible: visibility)
            } else {
                if let shortcutHint {
                    Text(shortcutHint)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var permissionButton: some View {
        Button {
            permissionAction?()
        } label: {
            Label(permissionButtonTitle ?? "", systemImage: "hand.raised.fill")
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
    }

    private var iconColor: Color {
        if isHiddenInEditor { return .secondary }
        return needsAttention ? .orange : .chikitAccent
    }

    private var captionColor: Color {
        if isHiddenInEditor { return Color.secondary.opacity(0.55) }
        return needsAttention ? .orange : .secondary
    }

    private var isHiddenInEditor: Bool {
        isEditing && visibility?.wrappedValue == false
    }
}


/// Shared switch row used by Quick Controls and Quick toggles.
struct PanelToggleRow: View {
    let title: String
    let caption: String
    let systemImage: String
    @Binding var isOn: Bool
    var badge: String? = nil
    var isEditing = false
    var showsDragHandle = false
    var visibility: Binding<Bool>? = nil
    var isActive = false
    var activeText: String? = nil
    var needsAttention = false
    var permissionButtonTitle: String? = nil
    var permissionAction: (() -> Void)? = nil
    /// Optional inline action under the caption (e.g. "Open the shelf (3)"),
    /// shown only outside edit mode.
    var accessoryTitle: String? = nil
    var accessoryAction: (() -> Void)? = nil

    var body: some View {
        rowContent
            .panelCard()
    }

    private var rowContent: some View {
        HStack(spacing: 9) {
            if isEditing && showsDragHandle {
                PanelDragHandle()
            }
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isHiddenInEditor ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let badge {
                        PanelBetaBadge(text: badge)
                    }
                }
                Text(caption)
                    .font(.system(size: 10))
                    .foregroundStyle(captionColor)
                    .fixedSize(horizontal: false, vertical: true)
                if isActive, let activeText {
                    Label(activeText, systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.green)
                        .lineLimit(1)
                }
                if needsAttention, let permissionAction {
                    Button {
                        permissionAction()
                    } label: {
                        Label(permissionButtonTitle ?? "", systemImage: "hand.raised.fill")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                if !isEditing, let accessoryTitle, let accessoryAction {
                    Button {
                        accessoryAction()
                    } label: {
                        Label(accessoryTitle, systemImage: "arrow.up.forward.square")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
            trailingControl
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isEditing, let visibility {
            if !visibility.wrappedValue {
                PanelHiddenBadge()
            }
            PanelInlineHideButton(isVisible: visibility)
        } else {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .controlSize(.small)
                .toggleStyle(.switch)
        }
    }

    private var iconColor: Color {
        if isHiddenInEditor { return .secondary }
        if needsAttention { return .orange }
        return isOn ? .chikitAccent : .secondary
    }

    private var captionColor: Color {
        if isHiddenInEditor { return Color.secondary.opacity(0.55) }
        return needsAttention ? .orange : .secondary
    }

    private var isHiddenInEditor: Bool {
        isEditing && visibility?.wrappedValue == false
    }
}

/// A small "Beta" pill, used to flag a control as still experimental.
struct PanelBetaBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 8, weight: .bold))
            .tracking(0.4)
            .foregroundStyle(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                Capsule(style: .continuous).fill(Color.orange.opacity(0.16))
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel(text)
    }
}

// MARK: - Overlay scroll container

/// A vertical scroll container that always uses an overlay scroller, so it never
/// reserves a legacy gutter on the right (which, when the system is set to always
/// show scroll bars, would push the fixed-width panel content off-center). The
/// content is pinned to the full width and reports its natural height back after
/// every layout pass, so the popover sizes itself to fit and only scrolls once the
/// content is taller than the screen.
private struct OverlayScrollView<Content: View>: NSViewRepresentable {
    @Binding var measuredHeight: CGFloat
    let content: Content

    init(measuredHeight: Binding<CGFloat>, @ViewBuilder content: () -> Content) {
        _measuredHeight = measuredHeight
        self.content = content()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder

        let host = HeightReportingHostingView(rootView: content)
        host.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = host
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            host.topAnchor.constraint(equalTo: clip.topAnchor),
            host.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            host.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])
        context.coordinator.host = host
        installReporter(on: host)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.scrollerStyle = .overlay
        guard let host = context.coordinator.host else { return }
        host.rootView = content
        installReporter(on: host)               // re-bind to the latest measuredHeight
        let h = host.fittingSize.height          // catch content changes with no new layout pass
        if h > 1, abs(h - measuredHeight) > 0.5 {
            DispatchQueue.main.async { measuredHeight = h }
        }
    }

    /// Wire the hosting view to report its natural height into `measuredHeight`
    /// after every AppKit layout pass — including the frames of a collapse/expand
    /// animation — so the popover tracks the real content height instead of a
    /// single stale reading taken when SwiftUI happened to re-run updateNSView.
    /// The 0.5pt guard also breaks the measure → resize → measure feedback loop.
    private func installReporter(on host: HeightReportingHostingView<Content>) {
        let binding = $measuredHeight
        host.onLayout = { [weak host] in
            guard let host else { return }
            let h = host.fittingSize.height
            guard h > 1, abs(h - binding.wrappedValue) > 0.5 else { return }
            DispatchQueue.main.async { binding.wrappedValue = h }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var host: HeightReportingHostingView<Content>? }
}

/// An `NSHostingView` that fires `onLayout` after each AppKit layout pass. The
/// menu panel uses it because collapsing or expanding a section flips state inside
/// this view's own SwiftUI graph and never re-runs the surrounding `updateNSView`
/// — so the height has to be read from here, where the change actually lands.
private final class HeightReportingHostingView<Content: View>: NSHostingView<Content> {
    var onLayout: (() -> Void)?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        onLayout?()
    }
}

// MARK: - Keep awake

struct KeepAwakeCard: View {
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var awake = KeepAwakeManager.shared
    @ObservedObject private var permissions = Permissions.shared
    @AppStorage(DefaultsKey.defaultDuration) private var defaultDuration: Int = 0
    @AppStorage(DefaultsKey.keepAwakeAutoStart) private var keepAwakeAutoStart = false
    @AppStorage(DefaultsKey.keepAwakeAllowDisplaySleep) private var keepAwakeAllowDisplaySleep = false
    @AppStorage(DefaultsKey.keepAwakeExternalDisplay) private var keepAwakeExternalDisplay = false
    @AppStorage(DefaultsKey.keepAwakeConnectedToPower) private var keepAwakeConnectedToPower = false
    @AppStorage(DefaultsKey.keepAwakeIconTint) private var keepAwakeIconTint = KeepAwakeIconTint.orange.rawValue
    @AppStorage(DefaultsKey.keepAwakeActiveIcon) private var keepAwakeActiveIcon = KeepAwakeActiveIcon.chikit.rawValue
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleEnabled) private var keepAwakeMouseJiggle = false
    @AppStorage(DefaultsKey.keepAwakeMouseJiggleInterval) private var keepAwakeMouseJiggleInterval = 5
    @State private var optionsExpanded = false
    @State private var automationExpanded = false
    var collapsible = true

    var body: some View {
        // The collapsible header supplies the "Keep awake" title, so the card's
        // first row is just the live status and the on/off switch.
        PanelSection(.keepAwake, title: l10n.s.keepAwakeTitle, collapsible: collapsible) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    statusLine
                    Spacer()
                    Toggle("", isOn: activeBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                if awake.isActive, awake.endDate != nil {
                    HStack(spacing: 6) {
                        extendButton(15)
                        extendButton(30)
                        extendButton(60)
                        Spacer()
                    }
                }

                if !awake.isActive {
                    HStack {
                        Text(l10n.s.durationLabel)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Spacer()
                        DurationPicker(selection: $defaultDuration)
                    }
                }

                optionsDisclosure

                Divider()

                optionRow(title: l10n.s.clamshellTitle,
                          caption: clamshellCaption,
                          isOn: $awake.clamshellPreferred,
                          disabled: awake.clamshellSetupInProgress,
                          captionIsError: awake.clamshellSetupFailed)
            }
            .panelCard()
        }
        .onAppear {
            defaultDuration = Defaults.sanitizedDefaultDuration(defaultDuration)
            keepAwakeIconTint = Defaults.sanitizedKeepAwakeIconTint(keepAwakeIconTint).rawValue
            keepAwakeActiveIcon = Defaults.sanitizedKeepAwakeActiveIcon(keepAwakeActiveIcon).rawValue
            keepAwakeMouseJiggleInterval = Defaults.sanitizedKeepAwakeMouseJiggleInterval(keepAwakeMouseJiggleInterval)
        }
    }

    private var optionsDisclosure: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                optionsExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: optionsExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    Text(l10n.s.keepAwakeOptions)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if optionsExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    KeepAwakeIconPicker(iconValue: $keepAwakeActiveIcon,
                                        tintValue: $keepAwakeIconTint,
                                        compact: true)
                    compactOptionToggle(
                        icon: "display",
                        title: displaySleepStrings.allowDisplaySleep,
                        isOn: $keepAwakeAllowDisplaySleep
                    )
                    compactOptionToggle(
                        icon: "play.circle",
                        title: l10n.s.keepAwakeAutoStart,
                        isOn: $keepAwakeAutoStart
                    )
                    automationDisclosure
                    compactOptionToggle(
                        icon: "cursorarrow.motionlines",
                        title: l10n.s.keepAwakeMouseJiggle,
                        isOn: $keepAwakeMouseJiggle,
                        errorText: mouseJiggleNeedsAccessibility ? mouseJiggleCaption : nil
                    )
                    if keepAwakeMouseJiggle {
                        mouseJiggleIntervalRow
                        if mouseJiggleNeedsAccessibility {
                            Button(l10n.s.permissionRequest) {
                                grantAccessibility()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.leading, 19)
            }
        }
    }

    private var automationDisclosure: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                automationExpanded.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 15)
                    Text(automationStrings.automationSection)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    automationSummaryBadges
                    Image(systemName: automationExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if automationExpanded {
                KeepAwakeAutomationEditor(compact: true)
                    .padding(.leading, 22)
            }
        }
    }

    @ViewBuilder
    private var automationSummaryBadges: some View {
        if !keepAwakeExternalDisplay,
           !keepAwakeConnectedToPower {
            Text(automationStrings.automationOff)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 4) {
                if keepAwakeExternalDisplay {
                    automationSystemBadge("display")
                }
                if keepAwakeConnectedToPower {
                    automationSystemBadge("powerplug.fill")
                }
            }
        }
    }

    private func automationSystemBadge(_ icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Color.chikitAccent)
            .frame(width: 17, height: 17)
            .background(Circle().fill(Color.chikitAccent.opacity(0.12)))
    }

    private func compactOptionToggle(icon: String,
                                     title: String,
                                     isOn: Binding<Bool>,
                                     errorText: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 15)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.red)
                    .padding(.leading, 22)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var mouseJiggleIntervalRow: some View {
        HStack(spacing: 8) {
            Text(l10n.s.keepAwakeMouseJiggleInterval)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            KeepAwakeMouseJiggleIntervalPicker(selection: $keepAwakeMouseJiggleInterval)
        }
    }

    private var mouseJiggleNeedsAccessibility: Bool {
        keepAwakeMouseJiggle && !permissions.accessibility
    }

    private var mouseJiggleCaption: String {
        mouseJiggleNeedsAccessibility
            ? "\(l10n.s.permissionRequired): \(l10n.s.permissionAccessibility)"
            : l10n.s.keepAwakeMouseJiggleCaption
    }

    private var statusLine: some View {
        Group {
            if awake.isActive {
                if awake.sessionTrigger == .automation {
                    Text(automationStrings.activeStatus(for: awake.activeAutomationConditions))
                } else if let end = awake.endDate {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(l10n.s.keepAwakeEndsIn) \(Self.remainingText(until: end))")
                    }
                } else {
                    Text(l10n.s.keepAwakeUntilDisabled)
                }
            } else {
                Text(l10n.s.keepAwakeNormalRules)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }

    private var automationStrings: KeepAwakeAutomationStrings {
        FeatureStrings.keepAwakeAutomation(l10n.language)
    }

    private var displaySleepStrings: KeepAwakeDisplaySleepStrings {
        FeatureStrings.keepAwakeDisplaySleep(l10n.language)
    }

    private var clamshellCaption: String {
        if awake.clamshellSetupInProgress {
            return l10n.s.configuring
        }
        if awake.clamshellSetupFailed {
            return l10n.s.sudoersFailed
        }
        if awake.clamshellActive {
            return l10n.s.clamshellOnCaption
        }
        if awake.clamshellPreferred {
            return l10n.s.clamshellNeedsSession
        }
        return awake.passwordlessClamshell ? l10n.s.clamshellReady : l10n.s.clamshellNeedsPassword
    }

    private var activeBinding: Binding<Bool> {
        Binding(
            get: { awake.isActive },
            set: { on in
                if on {
                    awake.activate(minutes: defaultDuration)
                } else if awake.isActive {
                    awake.toggle()
                }
            }
        )
    }

    private func grantAccessibility() {
        Permissions.shared.requestAccessibility()
        Permissions.shared.openAccessibilitySettings()
    }

    private func optionRow(title: String,
                           caption: String?,
                           isOn: Binding<Bool>,
                           disabled: Bool,
                           captionIsError: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12))
                if let caption {
                    Text(caption)
                        .font(.system(size: 10))
                        .foregroundStyle(captionIsError ? Color.red : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(disabled)
        }
    }

    private func extendButton(_ minutes: Int) -> some View {
        Button("+\(minutes) min") {
            awake.extend(minutes: minutes)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .font(.system(size: 10))
    }

    private static func remainingText(until end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSinceNow))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return String(format: "%d h %02d min", hours, minutes) }
        if minutes > 0 { return String(format: "%d min %02d s", minutes, seconds) }
        return "\(seconds) s"
    }
}

/// Session duration picker shared by the panel and Settings.
struct DurationPicker: View {
    @ObservedObject private var l10n = L10n.shared
    @Binding var selection: Int

    var body: some View {
        Picker("", selection: $selection) {
            Text(l10n.s.minutes15).tag(15)
            Text(l10n.s.minutes30).tag(30)
            Text(l10n.s.hour1).tag(60)
            Text(l10n.s.hours2).tag(120)
            Text(l10n.s.hours4).tag(240)
            Text(l10n.s.hours8).tag(480)
            Text(l10n.s.indefinite).tag(0)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }
}

struct KeepAwakeMouseJiggleIntervalPicker: View {
    @Binding var selection: Int

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(Defaults.allowedKeepAwakeMouseJiggleIntervals, id: \.self) { minutes in
                Text(Self.label(for: minutes)).tag(minutes)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .controlSize(.small)
        .fixedSize()
    }

    static func label(for minutes: Int) -> String {
        "\(minutes) min"
    }
}
