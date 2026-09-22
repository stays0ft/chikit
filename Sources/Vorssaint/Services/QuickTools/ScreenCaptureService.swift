// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Shared state for the chooser. Every overlay panel observes the same value,
/// so changing a mode on one display updates the controls on all displays.
final class ScreenCaptureSelectionOptions: ObservableObject {
    let availableTools: [ScreenCaptureTool]
    let recorderAudio = RecorderSelectionAudioOptions()
    @Published private(set) var selectedTool: ScreenCaptureTool
    var onSelectionChange: (() -> Void)?

    init(availableTools: [ScreenCaptureTool], selectedTool: ScreenCaptureTool) {
        precondition(availableTools.contains(selectedTool))
        self.availableTools = availableTools
        self.selectedTool = selectedTool
    }

    func select(_ tool: ScreenCaptureTool) {
        guard availableTools.contains(tool), selectedTool != tool else { return }
        selectedTool = tool
        onSelectionChange?()
    }
}

/// One entry point for the recorder's screen-region selection. It owns the
/// tool's own capture shortcut and the shared selection surface; the recorder
/// service still owns what happens after selection.
final class ScreenCaptureService: ObservableObject {
    static let shared = ScreenCaptureService()

    /// The tools whose own shortcut could not be registered, so each tool's
    /// settings can say so.
    @Published private(set) var toolShortcutRegistrationFailures: Set<ScreenCaptureTool> = []

    /// One hotkey per tool, built from the tool list so a new mode cannot be
    /// added without one. Ids continue past the hand-assigned quick tool
    /// range, which ends at 24.
    private let toolHotkeys: [ScreenCaptureTool: QuickToolHotkey] = {
        var next: UInt32 = 25
        var hotkeys: [ScreenCaptureTool: QuickToolHotkey] = [:]
        for tool in ScreenCaptureTool.allCases {
            hotkeys[tool] = QuickToolHotkey(id: next)
            next += 1
        }
        return hotkeys
    }()
    private var selection: ScreenshotSelectionController?
    private var options: ScreenCaptureSelectionOptions?

    var protectedWindowIDs: Set<CGWindowID> {
        selection?.protectedWindowIDs ?? []
    }

    private init() {
        for (tool, hotkey) in toolHotkeys {
            hotkey.onPress = { [weak self] in self?.capture(initial: tool) }
        }
    }

    func syncWithPreferences() {
        let availableTools = ScreenCaptureTool.available()
        guard !availableTools.isEmpty else {
            toolShortcutRegistrationFailures = []
            toolHotkeys.values.forEach { $0.unregister() }
            cancelSelection()
            return
        }
        if let activeTools = options?.availableTools,
           ScreenshotSupport.captureAvailabilityChanged(activeTools: activeTools,
                                                        availableTools: availableTools) {
            cancelSelection()
        }
        syncToolShortcuts(availableTools: availableTools, defaults: UserDefaults.standard)
    }

    /// A tool's own shortcut opens the same chooser already on that mode. A
    /// tool whose feature is not installed leaves its combination free for
    /// whatever else wants it.
    private func syncToolShortcuts(availableTools: [ScreenCaptureTool],
                                   defaults: UserDefaults) {
        var failures: Set<ScreenCaptureTool> = []
        for (tool, hotkey) in toolHotkeys {
            let keys = tool.dedicatedShortcut
            let enabled = availableTools.contains(tool) && defaults.bool(forKey: keys.enabledKey)
            if !hotkey.sync(enabled: enabled, shortcut: keys.role.savedShortcut) {
                failures.insert(tool)
            }
        }
        toolShortcutRegistrationFailures = failures
    }

    func suspend() {
        toolHotkeys.values.forEach { $0.unregister() }
        cancelSelection()
    }

    /// Opens the same chooser from every feature surface. A feature-specific
    /// button merely picks the initial mode; the person can switch before
    /// selecting anything.
    func capture(initial preferred: ScreenCaptureTool? = nil) {
        if AppFeature.screenRecorder.isAvailable,
           ScreenRecorderService.shared.stopOrCancelActiveCapture() {
            return
        }
        guard selection == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }

        let tools = ScreenCaptureTool.available()
        guard !tools.isEmpty else { return }
        let selected = preferred.flatMap { tools.contains($0) ? $0 : nil } ?? tools[0]

        guard Permissions.shared.screenRecording else {
            Permissions.shared.requestScreenRecording()
            return
        }
        if selected == .recording,
           !ScreenRecorderService.shared.prepareForSelection() {
            return
        }

        beginSelection(tools: tools, selected: selected)
    }

    private func beginSelection(tools: [ScreenCaptureTool], selected: ScreenCaptureTool) {
        guard selection == nil, !ScreenshotSelectionController.isSessionOnScreen else { return }
        let options = ScreenCaptureSelectionOptions(availableTools: tools,
                                                    selectedTool: selected)
        self.options = options
        startSelection(options: options)
    }

    private func startSelection(options: ScreenCaptureSelectionOptions) {
        guard selection == nil, !ScreenshotSelectionController.isSessionOnScreen,
              self.options === options else { return }
        let defaults = UserDefaults.standard
        let policy = ScreenshotSupport.unifiedCapturePolicy(
            for: options.selectedTool,
            screenshotFreeze: defaults.bool(forKey: DefaultsKey.screenshotFreeze),
            screenshotIncludePointer: defaults.bool(forKey: DefaultsKey.screenshotIncludePointer),
            screenshotHideChikitWindows: defaults.bool(
                forKey: DefaultsKey.screenshotHideChikitWindows))
        let controller = ScreenshotSelectionController(
            freeze: policy.freeze,
            includePointer: policy.includePointer,
            showLastRegion: defaults.bool(forKey: DefaultsKey.screenshotShowLastRegion),
            hideChikitWindows: policy.hideChikitWindows,
            purpose: FeatureStrings.screenshot(L10n.shared.language).screenCaptureTitle,
            mode: policy.usesGeometry ? .geometry : .image,
            screenCaptureOptions: options)
        selection = controller
        controller.begin { [weak self, weak controller, weak options] outcome in
            guard let self, let controller, let options,
                  self.selection === controller else { return }
            self.selection = nil
            self.options = nil
            self.route(outcome, selected: options.selectedTool,
                       recorderAudio: options.recorderAudio)
        }
    }

    private func route(_ outcome: ScreenshotSelectionController.Outcome,
                       selected: ScreenCaptureTool,
                       recorderAudio: RecorderSelectionAudioOptions) {
        guard ScreenshotSupport.captureRouteIsAuthorized(selected: selected) else { return }
        switch outcome {
        case .region(let region):
            ScreenRecorderService.shared.record(region, audioOptions: recorderAudio)
        case .captured, .scrollingRegion, .color:
            showFailure()
        case .cancelled:
            break
        case .failed:
            showFailure()
        }
    }

    private func showFailure() {
        let strings = FeatureStrings.recorder(L10n.shared.language)
        QuickToolHUD.show(icon: "record.circle", message: strings.recordFailed)
    }

    private func cancelSelection() {
        selection?.cancel()
        selection = nil
        options = nil
    }
}
