// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// Every feature the Features hub can switch off entirely. The raw value is
/// the stable identity persisted inside the availability key, so cases can be
/// added but never renamed.
///
/// Availability is a layer ABOVE each feature's own enable key: an unavailable
/// feature disappears from Settings, the menu panel and the menu bar, and its
/// service tears down (and never instantiates on the next launch). Turning a
/// feature back on restores whatever enabled state it had, because the enable
/// keys are never touched.
enum AppFeature: String, CaseIterable {
    // Windows
    case windowLayout, autoQuit
    // Clipboard and files
    case clipboardHistory, finderRename
    // Sound
    case mixer, soundOutputSwitcher
    // Energy
    case keepAwake
    // Tools
    case cleaner, uninstaller, screenRecorder, notchMediaControls, fileConverter
    // System monitor, one entry per metric family (temperatures live with
    // their parent metric: CPU temp with CPU, battery temp with power).
    case monitorCPU, monitorGPU, monitorMemory, monitorNetwork, monitorDisk, monitorPower, fanControl
}

/// Hub sections, in display order.
enum FeatureGroup: String, CaseIterable {
    case windowsDock, clipboardFiles, sound, energyDisplay, tools, monitor
}

/// System permissions surfaced by the hub's transparency portal.
enum AppPermission: String, CaseIterable {
    case accessibility, screenRecording, fullDiskAccess, notifications,
         automationFinder, audioCapture, microphone
}

enum PermissionPollingSupport {
    static func interval(visibleSurfaceCount: Int,
                         accessibilityIsNeeded: Bool,
                         screenRecordingIsNeeded: Bool,
                         accessibilityIsGranted: Bool,
                         screenRecordingIsGranted: Bool) -> TimeInterval? {
        guard visibleSurfaceCount > 0 || accessibilityIsNeeded || screenRecordingIsNeeded else {
            return nil
        }
        if visibleSurfaceCount > 0
            || (accessibilityIsNeeded && !accessibilityIsGranted)
            || (screenRecordingIsNeeded && !screenRecordingIsGranted) {
            return 2.5
        }
        return 60
    }
}

extension AppFeature {
    /// Whether an engaged feature needs permission changes while it sits in
    /// the background. One-shot tools ask and refresh at the moment they run;
    /// polling for those just because their tile is installed wastes wakeups.
    func monitorsPermissionChanges(boolFor: (String) -> Bool) -> Bool {
        switch self {
        case .windowLayout:
            return boolFor(DefaultsKey.windowLayoutShortcutsEnabled)
                || boolFor(DefaultsKey.windowGestureEnabled)
                || boolFor(DefaultsKey.windowEdgeSnapEnabled)
        case .screenRecorder:
            return false
        default:
            return true
        }
    }

    var monitorsPermissionChanges: Bool {
        monitorsPermissionChanges(boolFor: UserDefaults.standard.bool(forKey:))
    }

    var group: FeatureGroup {
        switch self {
        case .windowLayout, .autoQuit:
            return .windowsDock
        case .clipboardHistory, .finderRename:
            return .clipboardFiles
        case .mixer, .soundOutputSwitcher:
            return .sound
        case .keepAwake:
            return .energyDisplay
        case .cleaner, .uninstaller, .screenRecorder, .notchMediaControls, .fileConverter:
            return .tools
        case .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .fanControl:
            return .monitor
        }
    }

    var symbolName: String {
        switch self {
        case .windowLayout: return "rectangle.3.group"
        case .autoQuit: return "xmark.rectangle"
        case .clipboardHistory: return "doc.on.clipboard"
        case .finderRename: return "pencil"
        case .mixer: return "slider.horizontal.3"
        case .soundOutputSwitcher: return "hifispeaker"
        case .keepAwake: return "moon.zzz.fill"
        case .cleaner: return "sparkles"
        case .uninstaller: return "trash"
        case .screenRecorder: return "record.circle"
        case .notchMediaControls: return "rectangle.topthird.inset.filled"
        case .fileConverter: return "arrow.triangle.2.circlepath"
        case .monitorCPU: return "cpu"
        case .monitorGPU: return "rectangle.connected.to.line.below"
        case .monitorMemory: return "memorychip"
        case .monitorNetwork: return "network"
        case .monitorDisk: return "internaldrive"
        case .monitorPower: return "bolt.fill"
        case .fanControl: return "fanblades.fill"
        }
    }

    var availabilityKey: String { DefaultsKey.featureAvailable(rawValue) }

    var isBeta: Bool { self == .fanControl }

    /// Availability read straight from defaults. Existing features stay
    /// available on update; explicit beta opt-ins may start unavailable.
    var isAvailable: Bool {
        UserDefaults.standard.bool(forKey: availabilityKey)
    }

    /// The feature's own enable keys; any one being true means the feature is
    /// engaged. Empty means the feature works on demand (a panel tile, a
    /// context-menu action), so being available already counts as engaged for
    /// the permissions portal.
    var enabledKeys: [String] {
        switch self {
        case .autoQuit: return [DefaultsKey.autoQuitEnabled]
        case .notchMediaControls: return [DefaultsKey.notchMediaControlsEnabled]
        case .clipboardHistory: return [DefaultsKey.clipboardHistoryEnabled]
        case .finderRename: return [DefaultsKey.finderRenameEnabled]
        case .soundOutputSwitcher: return [DefaultsKey.soundOutputSwitcherEnabled]
        case .windowLayout, .mixer, .keepAwake,
             .cleaner, .uninstaller, .screenRecorder, .fileConverter,
             .monitorCPU, .monitorGPU, .monitorMemory, .monitorNetwork, .monitorDisk, .monitorPower,
             .fanControl:
            return []
        }
    }

    /// Which permissions the feature can use at all. Whether it is using them
    /// RIGHT NOW is answered by `activeFeatures(using:)`, which also applies
    /// the dynamic rules (the monitor only notifies when an alert is on, and
    /// so on).
    var permissions: [AppPermission] {
        switch self {
        case .windowLayout, .autoQuit:
            return [.accessibility]
        case .finderRename: return [.accessibility]
        case .keepAwake: return [.accessibility]
        case .screenRecorder: return [.screenRecording, .accessibility, .microphone]
        case .cleaner: return [.fullDiskAccess, .notifications]
        case .uninstaller: return [.fullDiskAccess, .automationFinder]
        case .mixer: return [.audioCapture, .accessibility]
        case .monitorCPU, .monitorMemory, .monitorDisk, .monitorPower: return [.notifications]
        case .clipboardHistory, .soundOutputSwitcher, .monitorGPU, .monitorNetwork, .fanControl,
             .notchMediaControls, .fileConverter:
            // Reads Now Playing info and sends playback commands through the
            // same MediaRemote technique the notch card already uses (see
            // NotchMediaService); macOS asks for no TCC permission for either,
            // so this stays permission-free.
            return []
        }
    }

    /// Broad grants worth explaining during first run. Permissions used only
    /// by an optional sub-feature stay contextual, at the moment that control
    /// is actually used.
    var onboardingPermissions: [AppPermission] {
        switch self {
        case .keepAwake, .cleaner, .uninstaller, .mixer:
            return []
        default:
            return permissions.filter { $0 == .accessibility || $0 == .screenRecording }
        }
    }

    static func features(in group: FeatureGroup) -> [AppFeature] {
        allCases.filter { $0.group == group }
    }

    /// Registered defaults preserve existing features on update. New opt-in
    /// features and explicit betas ship uninstalled.
    static var availabilityDefaults: [String: Any] {
        Dictionary(uniqueKeysWithValues: allCases.map {
            ($0.availabilityKey, $0 != .fanControl)
        })
    }

    /// Features that are available, engaged and using `permission` right now.
    /// Readers are injectable so the logic stays testable without touching
    /// real UserDefaults.
    static func activeFeatures(using permission: AppPermission,
                               isAvailable: (AppFeature) -> Bool,
                               boolFor: (String) -> Bool,
                               stringFor: (String) -> String?,
                               dataFor: (String) -> Data? = { _ in nil }) -> [AppFeature] {
        allCases.filter { feature in
            guard feature.permissions.contains(permission), isAvailable(feature) else { return false }
            let keys = feature.enabledKeys
            guard keys.isEmpty || keys.contains(where: boolFor) else { return false }
            switch (feature, permission) {
            case (.keepAwake, .accessibility):
                return boolFor(DefaultsKey.keepAwakeMouseJiggleEnabled)
            case (.mixer, .accessibility):
                return boolFor(DefaultsKey.preciseVolumeRollerEnabled)
            case (.monitorCPU, .notifications):
                return boolFor(DefaultsKey.monitorAlertCPU) || boolFor(DefaultsKey.monitorAlertCPUTemperature)
            case (.monitorMemory, .notifications):
                return boolFor(DefaultsKey.monitorAlertMemory)
            case (.monitorDisk, .notifications):
                return boolFor(DefaultsKey.monitorAlertDisk)
            case (.monitorPower, .notifications):
                return boolFor(DefaultsKey.monitorAlertBattery)
                    || boolFor(DefaultsKey.monitorAlertBatteryTemperature)
            case (.cleaner, .notifications):
                return (stringFor(DefaultsKey.cleanerScheduleFrequency) ?? "off") != "off"
                    && boolFor(DefaultsKey.cleanerScheduleNotify)
            case (.screenRecorder, .microphone):
                return boolFor(DefaultsKey.recorderMicrophone)
            default:
                return true
            }
        }
    }

    /// Monitor alert keys and the metric feature each one belongs to. An
    /// alert only counts while its metric is available in the hub.
    static let monitorAlertPairs: [(key: String, feature: AppFeature)] = [
        (DefaultsKey.monitorAlertCPU, .monitorCPU),
        (DefaultsKey.monitorAlertCPUTemperature, .monitorCPU),
        (DefaultsKey.monitorAlertBatteryTemperature, .monitorPower),
        (DefaultsKey.monitorAlertMemory, .monitorMemory),
        (DefaultsKey.monitorAlertDisk, .monitorDisk),
        (DefaultsKey.monitorAlertBattery, .monitorPower),
    ]

    static func anyMonitorAlertEnabled(isAvailable: (AppFeature) -> Bool,
                                       boolFor: (String) -> Bool) -> Bool {
        monitorAlertPairs.contains { boolFor($0.key) && isAvailable($0.feature) }
    }

    /// Runtime convenience over the injectable core.
    static func activeFeatures(using permission: AppPermission,
                               defaults: UserDefaults = .standard) -> [AppFeature] {
        activeFeatures(using: permission,
                       isAvailable: { defaults.bool(forKey: $0.availabilityKey) },
                       boolFor: { defaults.bool(forKey: $0) },
                       stringFor: { defaults.string(forKey: $0) },
                       dataFor: { defaults.data(forKey: $0) })
    }
}

extension AppPermission {
    var symbolName: String {
        switch self {
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .fullDiskAccess: return "externaldrive.badge.person.crop"
        case .notifications: return "bell.badge"
        case .automationFinder: return "gearshape.2"
        case .audioCapture: return "waveform"
        case .microphone: return "mic"
        }
    }
}
