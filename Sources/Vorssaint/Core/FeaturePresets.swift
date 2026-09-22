// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One-click starting points for the Features hub. A preset is a shape, not a
/// prison: applying one installs and engages its features and uninstalls the
/// rest, but nothing is deleted — every feature keeps its settings and comes
/// back with one click, exactly like any hub install.
enum FeaturePreset: String, CaseIterable, Identifiable {
    case essential, battery

    var id: String { rawValue }

    /// A clean install starts from the small Essential set before any feature
    /// binding runs. Updates keep every existing availability choice, and an
    /// interrupted setup keeps the selection already applied on its purpose
    /// step.
    static func prepareFirstRunAvailability(in defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: DefaultsKey.hasOnboarded),
              defaults.integer(forKey: DefaultsKey.onboardingStep) == 0
        else { return }
        let selected = FeaturePreset.essential.features
        for feature in AppFeature.allCases {
            defaults.set(selected.contains(feature), forKey: feature.availabilityKey)
        }
    }

    /// The features the preset keeps installed.
    var features: Set<AppFeature> {
        switch self {
        case .essential:
            // Fan control is deliberately excluded: it is a hardware-gated
            // beta (see `isHardwareSupported`), and this first-run seed
            // writes availability directly, bypassing the `mayFlip` hardware
            // check that every other install surface goes through. Putting
            // it here would silently force-install it on Macs whose fans
            // aren't controllable. It stays one click away in the hub, where
            // the gate applies normally.
            return [.windowLayout, .cleaner, .uninstaller, .notchMediaControls,
                    .autoQuit, .clipboardHistory, .finderRename,
                    .mixer, .soundOutputSwitcher, .screenRecorder,
                    .monitorCPU, .monitorGPU, .monitorMemory,
                    .monitorNetwork, .monitorDisk, .monitorPower]
        case .battery:
            // The lean monitor: battery, memory pressure and the processor,
            // with nothing that listens to input events.
            return [.monitorCPU, .monitorMemory, .monitorPower]
        }
    }

    /// Enable keys switched on along with the install, so the preset's
    /// features actually work instead of arriving as more toggles to find.
    /// Presets whose features are on-demand need none.
    var enableKeys: [String] {
        switch self {
        case .essential:
            return [DefaultsKey.autoQuitEnabled,
                    DefaultsKey.clipboardHistoryEnabled,
                    DefaultsKey.finderRenameEnabled,
                    DefaultsKey.soundOutputSwitcherEnabled]
        case .battery:
            return []
        }
    }

    var symbolName: String {
        switch self {
        case .essential: return "star.fill"
        case .battery: return "battery.75percent"
        }
    }
}

/// The honest, curated cost label each feature earns in the hub: what the
/// feature keeps alive WHILE IT IS ON. Uninstalled features load nothing at
/// all, which is the hub's own promise. Static by design — pretending to
/// measure per-feature cost live would be theater.
enum FeatureEnergyProfile: String {
    /// Nothing at rest: on-demand tools, shortcut-driven actions and
    /// system-notification listeners.
    case idle
    /// A pointer gesture that works with either a trackpad or mouse.
    case pointer
    /// A keyboard event tap.
    case keyboard
    /// Both input taps.
    case inputs
    /// Samples or polls on an interval while active or visible.
    case periodic
}

extension AppFeature {
    var energyProfile: FeatureEnergyProfile {
        switch self {
        case .finderRename:
            return .keyboard
        case .autoQuit:
            return .inputs
        case .windowLayout:
            return UserDefaults.standard.bool(forKey: DefaultsKey.windowGestureEnabled)
                || UserDefaults.standard.bool(forKey: DefaultsKey.windowEdgeSnapEnabled)
                ? .pointer : .idle
        case .clipboardHistory,
             .monitorCPU, .monitorGPU, .monitorMemory,
             .monitorNetwork, .monitorDisk, .monitorPower, .notchMediaControls:
            return .periodic
        case .mixer:
            return UserDefaults.standard.bool(forKey: DefaultsKey.preciseVolumeRollerEnabled)
                ? .keyboard : .idle
        case .soundOutputSwitcher, .cleaner, .uninstaller, .screenRecorder, .fanControl:
            return .idle
        }
    }
}
