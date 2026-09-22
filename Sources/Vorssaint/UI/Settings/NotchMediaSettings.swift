// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

struct NotchMediaSettings: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(DefaultsKey.notchMediaControlsEnabled) private var notchMediaControlsEnabled = false
    @AppStorage(DefaultsKey.notchMediaControlsShowIdlePill) private var notchMediaControlsShowIdlePill = true

    var body: some View {
        Form {
            Section {
                Toggle(FeatureStrings.notchMedia(l10n.language).toggleLabel,
                       isOn: $notchMediaControlsEnabled)
                    .onChange(of: notchMediaControlsEnabled) { _, _ in
                        NotchMediaService.shared.syncWithPreferences()
                    }
                Text(FeatureStrings.notchMedia(l10n.language).panelCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if notchMediaControlsEnabled {
                    Toggle(FeatureStrings.notchMedia(l10n.language).idlePillToggleLabel,
                           isOn: $notchMediaControlsShowIdlePill)
                    Text(FeatureStrings.notchMedia(l10n.language).idlePillCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(FeatureStrings.notchMedia(l10n.language).pageTitle)
            }
            .settingsSectionAnchor(.notchMediaControls)
        }
        .formStyle(.grouped)
    }
}
