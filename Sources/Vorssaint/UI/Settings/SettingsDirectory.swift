// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// One Settings page as the sidebar and the command bar present it.
struct SettingsDirectoryItem: Identifiable {
    let page: SettingsPage
    let title: String
    let icon: String
    /// Labels of options living inside the page, so a search finds a page by
    /// what it contains, in the user's language.
    var keywords: [String] = []
    /// Feature ownership for keyword rows on shared pages. `nil` means the
    /// setting belongs to the page itself and remains searchable whenever the
    /// page is visible.
    var keywordFeatures: [AppFeature?] = []
    var id: SettingsPage { page }

    init(page: SettingsPage, title: String, icon: String,
         keywords: [String] = [],
         featureKeywords: [(feature: AppFeature, titles: [String])] = []) {
        self.page = page
        self.title = title
        self.icon = icon
        self.keywords = keywords + featureKeywords.flatMap(\.titles)
        keywordFeatures = Array(repeating: nil, count: keywords.count)
            + featureKeywords.flatMap { entry in
                Array(repeating: Optional(entry.feature), count: entry.titles.count)
            }
    }
}

/// The single map of the Settings window: sections, pages, icons and search
/// keywords. The sidebar renders it; the command bar searches it. One list,
/// so a page added here is findable everywhere at once.
enum SettingsDirectory {
    /// Destination-aware rows for focused Settings search. The regular
    /// directory remains page-based so blank-query sidebar identity and
    /// command-bar behavior do not change.
    static func searchItems(_ s: Strings,
                            language: AppLanguage) -> [SettingsSearchItem] {
        let pageItems = sections(s, language: language).flatMap(\.items).map { item in
            SettingsSearchItem(id: .page(item.page),
                               destination: FeatureSettingsDestination(item.page),
                               title: item.title,
                               icon: item.icon,
                               keywords: item.keywords,
                               keywordFeatures: item.keywordFeatures)
        }
        let hub = FeatureStrings.hub(language)
        let featureItems = SettingsSearchSupport.featureItems(language: language) { feature in
            feature.hubTitle(s, hub: hub)
        }
        return SettingsSearchSupport.combinedItems(pageItems: pageItems,
                                                   featureItems: featureItems)
    }

    static func sections(_ s: Strings,
                         language: AppLanguage)
        -> [(title: String, items: [SettingsDirectoryItem])] {
        let categories = FeatureStrings.settingsCategories(language)
        return [
            (categories.essentials, [
                SettingsDirectoryItem(page: .general, title: s.tabGeneral, icon: "gearshape",
                                       keywords: [s.launchAtLogin, s.languageLabel, s.showMenuBarIcon,
                                                  FeatureStrings.appearance(language).label,
                                                  FeatureStrings.appearance(language).dark]),
                // Searching any feature name lands here even when the feature
                // is hidden, so the hub is always the way back.
                SettingsDirectoryItem(page: .features, title: FeatureStrings.hub(language).pageTitle,
                                       icon: "square.grid.2x2",
                                       featureKeywords: AppFeature.allCases.map {
                                        ($0, [$0.hubTitle(s, hub: FeatureStrings.hub(language))])
                                       }),
                SettingsDirectoryItem(page: .energy, title: s.tabEnergy, icon: "bolt.fill",
                                       featureKeywords: [
                                        (.keepAwake, [s.keepAwakeTitle, s.clamshellTitle,
                                                      s.defaultDurationLabel, s.showCountdown,
                                                      s.keepAwakeActiveIconLabel,
                                                      s.keepAwakeActiveIconCoffee,
                                                      s.keepAwakeActiveIconEye,
                                                      FeatureStrings.keepAwakeAutomation(language)
                                                        .externalDisplayToggle,
                                                      FeatureStrings.keepAwakeAutomation(language)
                                                        .powerToggle,
                                                      FeatureStrings.keepAwakeDisplaySleep(language)
                                                        .allowDisplaySleep]),
                                       ]),
                SettingsDirectoryItem(page: .monitor, title: s.tabMonitor, icon: "chart.line.uptrend.xyaxis",
                                       keywords: [s.menuBarSpacingLabel, s.menuBarHideIconToggle],
                                       featureKeywords: [
                                        (.monitorMemory, [s.monitorMemoryPressureDot]),
                                        (.fanControl, [FeatureStrings.fanControl(language).menuBarTitle]),
                                       ]),
            ]),
            (categories.windowsControls, [
                SettingsDirectoryItem(page: .windowLayout,
                                      title: FeatureStrings.windowLayout(language).title,
                                      icon: "rectangle.3.group",
                                      keywords: [FeatureStrings.windowLayout(language).edgeSnapEnable,
                                                 FeatureStrings.windowLayout(language).gestureEnable,
                                                 FeatureStrings.windowLayout(language).gestureResize]),
                SettingsDirectoryItem(page: .autoQuit, title: s.autoQuitName, icon: "xmark.rectangle",
                                      keywords: [s.autoQuitEnable]),
            ]),
            (categories.files, [
                SettingsDirectoryItem(page: .clipboard, title: FeatureStrings.clipboard(language).title,
                                       icon: "doc.on.clipboard",
                                       featureKeywords: [
                                        (.clipboardHistory, [FeatureStrings.clipboard(language).limit,
                                                             FeatureStrings.clipboard(language).skipSensitive,
                                                             FeatureStrings.clipboard(language).autoClearEnable,
                                                             FeatureStrings.clipboard(language).autoClearOnSleep,
                                                             FeatureStrings.clipboard(language)
                                                                .autoClearOnDisplaySleep,
                                                             FeatureStrings.clipboard(language)
                                                                .autoClearOnScreenLock,
                                                             FeatureStrings.clipboardIgnoredApps(language)
                                                                .listTitle]),
                                       ]),
                SettingsDirectoryItem(page: .finderRename,
                                       title: FeatureStrings.finderRename(language).pageTitle,
                                       icon: "pencil",
                                       keywords: [FeatureStrings.finderRename(language).enableLabel]),
            ]),
            // Everything about the apps installed on the Mac lives together:
            // what is out of date, what is junk and what should go.
            (categories.appManagement, [
                SettingsDirectoryItem(page: .cleaner, title: s.cleanerName, icon: "sparkles",
                                      keywords: [s.cleanerScheduleTitle]),
                SettingsDirectoryItem(page: .uninstaller, title: s.uninstallerName, icon: "trash"),
            ]),
            (categories.utilities, [
                SettingsDirectoryItem(page: .screenRecorder,
                                       title: FeatureStrings.recorder(language).pageTitle,
                                       icon: "record.circle",
                                       keywords: [FeatureStrings.recorder(language).startButton,
                                                  FeatureStrings.recorder(language).folderLabel]),
                SettingsDirectoryItem(page: .notchMedia,
                                       title: FeatureStrings.notchMedia(language).pageTitle,
                                       icon: "rectangle.topthird.inset.filled",
                                       keywords: [FeatureStrings.notchMedia(language).toggleLabel]),
            ]),
            (categories.app, [
                SettingsDirectoryItem(page: .shortcuts, title: s.shortcutsPageTitle, icon: "command"),
                SettingsDirectoryItem(page: .advanced, title: s.tabAdvanced, icon: "wrench.and.screwdriver"),
                SettingsDirectoryItem(page: .about, title: s.tabAbout, icon: "info.circle",
                                      keywords: [s.reviewIntro]),
            ]),
        ]
    }
}
