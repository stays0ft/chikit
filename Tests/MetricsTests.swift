// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Carbon.HIToolbox
import Combine
import CoreAudio
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import VMStatisticsCompat

// Standalone unit tests for pure helpers. Compiled without IOKit or UI by
// `./build.sh --test`, so they run fast and deterministically on any machine.
//
// A tiny @main harness instead of XCTest: the Command Line Tools cannot run
// `swift test`, and these checks need nothing more than equality assertions.
@main
struct MetricsTests {
    static func main() {
        var failures: [String] = []
        var checks = 0

        func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
            checks += 1
            if !condition { failures.append(message()) }
        }
        func expectEqual(_ actual: String, _ expected: String, _ label: String) {
            checks += 1
            if actual != expected { failures.append("\(label): got \"\(actual)\", expected \"\(expected)\"") }
        }
        func expectClose(_ actual: Double, _ expected: Double, _ label: String, tol: Double = 0.0001) {
            checks += 1
            if abs(actual - expected) > tol { failures.append("\(label): got \(actual), expected \(expected)") }
        }
        func expectFormat(_ format: String, _ expected: [String], _ label: String) {
            checks += 1
            let actual = formatSpecifiers(in: format)
            if actual != expected { failures.append("\(label): got \(actual), expected \(expected)") }
        }

        // MARK: Byte / rate formatting

        expectEqual(MetricFormat.bytes(0), "0 B", "bytes zero")
        expectEqual(MetricFormat.bytes(512), "512 B", "bytes < 1K")
        expectEqual(MetricFormat.bytes(1024), "1.0 KB", "bytes 1K")
        expectEqual(MetricFormat.bytes(1536), "1.5 KB", "bytes 1.5K")
        expectEqual(MetricFormat.bytes(10 * 1024), "10 KB", "bytes 10K drops decimal")
        expectEqual(MetricFormat.bytes(1024 * 1024), "1.0 MB", "bytes 1M")
        expectEqual(MetricFormat.bytes(3 * 1024 * 1024 * 1024), "3.0 GB", "bytes 3G")
        expectEqual(MetricFormat.diskBytes(245_107_195_904), "245 GB", "disk bytes use decimal storage units")
        expectEqual(MetricFormat.diskBytes(1_000_204_845_056), "1.0 TB", "disk bytes show decimal terabytes")
        expectEqual(MetricFormat.diskBytes(123_456_789_000), "123 GB", "disk bytes match Finder-style GB")
        expectEqual(MetricFormat.diskBytesPrecise(14_878_047_232_000), "14.88 TB",
                    "precise disk bytes keep SMART totals readable")

        expectEqual(MetricFormat.bytesPerSec(0), "0 B/s", "rate zero")
        expectEqual(MetricFormat.bytesPerSec(2 * 1024 * 1024), "2.0 MB/s", "rate 2M")
        expectEqual(MetricFormat.bytesPerSec(1500 * 1024), "1.5 MB/s", "rate 1.5M")

        expectEqual(MetricFormat.bytesPerSecCompact(0), "0B", "compact zero")
        expectEqual(MetricFormat.bytesPerSecCompact(320 * 1024), "320K", "compact 320K")
        expectEqual(MetricFormat.bytesPerSecCompact(1.2 * 1024 * 1024), "1.2M", "compact 1.2M")
        expectEqual(MetricFormat.bytesPerSecCompact(1022), "1022B", "compact 1022B remains stable")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.4), "1023B", "compact keeps sub-kilobyte values")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.6), "1.0K", "compact promotes rounded kilobyte edge")
        expectEqual(MetricFormat.bytesPerSecCompact(9.96 * 1024), "10K", "compact drops redundant decimal at 10K")
        expectEqual(MetricFormat.bytesPerSecCompact(1023.6 * 1024), "1.0M", "compact promotes rounded megabyte edge")
        expectEqual(MetricFormat.bytesPerSecCompact(9.96 * 1024 * 1024), "10M", "compact drops redundant decimal at 10M")

        // MARK: Disk helpers

        expect(DiskSupport.nvmeBytes(low: 2, high: nil) == 1_024_000,
               "NVMe data units convert to 512,000 byte units")
        expect(DiskSupport.nvmeBytes(low: 1, high: 1) == 2_199_023_256_064_000,
               "NVMe high data unit word is included")
        expectClose(DiskSupport.celsius(fromSMARTTemperature: 302) ?? -1, 28.85,
                    "SMART Kelvin temperature converts to Celsius")
        expectClose(DiskSupport.celsius(fromSMARTTemperature: 33) ?? -1, 33,
                    "SMART Celsius temperature is preserved")
        expect(DiskSupport.celsius(fromSMARTTemperature: 999) == nil,
               "SMART invalid temperature is ignored")
        expect(DiskSupport.healthPercent(fromPercentageUsed: 1) == 99,
               "SMART health subtracts percentage used")
        expect(DiskSupport.healthPercent(fromPercentageUsed: 150) == 0,
               "SMART health clamps exhausted drives")
        expect(DiskSupport.fileSystemLabel(type: "apfs") == "APFS",
               "file system label maps apfs")
        expect(DiskSupport.fileSystemLabel(type: " APFS \n") == "APFS",
               "file system label trims and ignores case")
        expect(DiskSupport.fileSystemLabel(type: "hfs", name: "Journaled HFS+") == "HFS+",
               "file system label maps journaled hfs")
        expect(DiskSupport.fileSystemLabel(type: "exfat") == "exFAT",
               "file system label keeps exFAT capitalization")
        expect(DiskSupport.fileSystemLabel(type: "ntfs") == "NTFS",
               "file system label maps ntfs")
        expect(DiskSupport.fileSystemLabel(type: "msdos", name: "Legacy FAT32") == "FAT32",
               "file system label reads FAT width from the name")
        expect(DiskSupport.fileSystemLabel(type: "msdos", name: "Legacy FAT16") == "FAT16",
               "file system label reads FAT16 from the name")
        expect(DiskSupport.fileSystemLabel(type: "msdos") == "FAT",
               "file system label falls back to plain FAT")
        expect(DiskSupport.fileSystemLabel(type: "cd9660") == "ISO 9660",
               "file system label maps optical media")
        expect(DiskSupport.fileSystemLabel(type: "udf") == "UDF",
               "file system label uppercases short unknown tokens")
        expect(DiskSupport.fileSystemLabel(type: "lifs") == "LIFS",
               "file system label keeps acronym-sized tokens")
        expect(DiskSupport.fileSystemLabel(type: "someverylongdriver") == nil,
               "file system label drops long driver tokens")
        expect(DiskSupport.fileSystemLabel(type: "a") == nil,
               "file system label drops single letters")
        expect(DiskSupport.fileSystemLabel(type: "123456") == nil,
               "file system label needs at least one letter")
        expect(DiskSupport.fileSystemLabel(type: "") == nil,
               "file system label ignores empty type")
        expect(DiskSupport.fileSystemLabel(type: nil) == nil,
               "file system label ignores missing type")
        let diskRate = MetricFormat.diskSpeed(
            previous: DiskIOCounters(read: 1_000, written: 500),
            current: DiskIOCounters(read: 3_048, written: 1_524),
            elapsed: 2
        )
        expectClose(diskRate.read, 1_024, "disk read speed uses elapsed time")
        expectClose(diskRate.write, 512, "disk write speed uses elapsed time")
        let resetDiskRate = MetricFormat.diskSpeed(
            previous: DiskIOCounters(read: 3_048, written: 1_524),
            current: DiskIOCounters(read: 2_000, written: 800),
            elapsed: 2
        )
        expectClose(resetDiskRate.read, 0, "disk read counter reset does not spike")
        expectClose(resetDiskRate.write, 0, "disk write counter reset does not spike")
        let smart = DiskSupport.smartReading(
            status: "Verified",
            vendorKeys: [
                "DATA_UNITS_READ_0": 2,
                "DATA_UNITS_WRITTEN_0": 4,
                "TEMPERATURE": 302,
                "PERCENTAGE_USED": 7,
                "POWER_CYCLES_0": 11,
                "POWER_ON_HOURS_0": 12,
                "UNSAFE_SHUTDOWNS_0": 13,
                "MEDIA_ERRORS_0": 14,
            ]
        )
        expect(smart?.status == "Verified", "SMART status is preserved")
        expect(smart?.totalReadBytes == 1_024_000, "SMART total read uses NVMe units")
        expect(smart?.totalWrittenBytes == 2_048_000, "SMART total written uses NVMe units")
        expectClose(smart?.temperatureCelsius ?? -1, 28.85, "SMART reading includes temperature")
        expect(smart?.healthPercent == 93, "SMART reading includes estimated health")
        expect(smart?.powerCycles == 11, "SMART reading includes power cycles")
        expect(smart?.powerOnHours == 12, "SMART reading includes power-on hours")
        expect(smart?.unsafeShutdowns == 13, "SMART reading includes unsafe shutdowns")
        expect(smart?.mediaErrors == 14, "SMART reading includes media errors")

        let diskDevice = DiskDeviceReading(
            id: "disk3s1",
            name: "Macintosh HD",
            mountPath: "/",
            bsdName: "disk3s1",
            wholeDisk: "disk3",
            ioCounterID: "disk3",
            fileSystem: "APFS",
            totalBytes: 245_000_000_000,
            freeBytes: 110_000_000_000,
            purgeableBytes: 28_000_000_000,
            usedBytes: 163_000_000_000,
            isInternal: true,
            isRemovable: false,
            isEjectable: false,
            smart: nil,
            readBytesPerSec: nil,
            writeBytesPerSec: nil,
            totalReadBytes: nil,
            totalWrittenBytes: nil
        )
        expect(diskDevice.purgeableBytes == 28_000_000_000, "disk reading preserves purgeable bytes")
        expectClose(diskDevice.usedFraction, 163.0 / 245.0, "disk used fraction reflects physical used bytes")

        // MARK: Clipboard history search

        let clipboardCandidates = [
            ClipboardHistorySearchCandidate(index: 0, text: "Deploy checklist final", isPinned: false),
            ClipboardHistorySearchCandidate(index: 1, text: "Token cleanup note", isPinned: true),
            ClipboardHistorySearchCandidate(index: 2, text: "Final database deploy plan", isPinned: false),
            ClipboardHistorySearchCandidate(index: 3, text: "Reunião com João", isPinned: false),
        ]
        expect(ClipboardHistorySearch.matches("Reunião com João", query: "reuniao joao"),
               "clipboard search ignores case and accents")
        expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "deploy final") == [0, 2],
               "clipboard search matches multiple words in any order and ranks prefix matches first")
        expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "cleanup token") == [1],
               "clipboard search matches pinned entries with reordered query terms")
        expect(ClipboardHistorySearch.rankedIndexes(candidates: clipboardCandidates,
                                                    matching: "missing") == [],
               "clipboard search returns no results for unmatched terms")

        // MARK: Clipboard auto clear preferences

        expect(Defaults.sanitizedClipboardAutoClearDelay(20) == 20,
               "auto clear delay in range passes through")
        expect(Defaults.sanitizedClipboardAutoClearDelay(4) == 5,
               "auto clear delay below the floor clamps up, so a typed 4 does not jump to the default")
        expect(Defaults.sanitizedClipboardAutoClearDelay(0) == 5,
               "auto clear delay of zero clamps up instead of clearing instantly")
        expect(Defaults.sanitizedClipboardAutoClearDelay(99_999) == 3_600,
               "auto clear delay above the ceiling clamps down")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnDelay] as? Bool == false,
               "auto clear is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnSleep] as? Bool == false,
               "clear on computer sleep is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnDisplaySleep] as? Bool == false,
               "clear on display sleep is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearOnScreenLock] as? Bool == false,
               "clear on screen lock is off until asked for")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardAutoClearDelay] as? Int == 20,
               "auto clear starts at twenty seconds")
        expect(Defaults.registeredDefaults[DefaultsKey.clipboardHistoryQuickPreview] as? Bool == false,
               "clipboard history quick preview is closed by default")

        // MARK: Clipboard auto clear timing

        let autoClearCopiedAt = Date(timeIntervalSince1970: 1_000_000)
        expect(ClipboardAutoClearSupport.decide(changeCount: 8,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(600),
                                                delay: 20) == .noteChange,
               "a new change count restarts the clock however long the old content sat there")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(19),
                                                delay: 20) == .wait,
               "unchanged content waits until the delay is up")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(20),
                                                delay: 20) == .clear,
               "unchanged content clears once the delay is exactly up")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 0,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(8 * 3_600),
                                                delay: 20) == .clear,
               "waking after hours of sleep clears at once instead of waiting out another delay")
        expect(ClipboardAutoClearSupport.decide(changeCount: 7,
                                                lastChangeCount: 7,
                                                lastClearedChangeCount: 7,
                                                lastChangeDate: autoClearCopiedAt,
                                                now: autoClearCopiedAt.addingTimeInterval(600),
                                                delay: 20) == .wait,
               "the count our own clear produced never clears again, so clearing cannot loop")
        expect(ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                           currentGeneration: 3,
                                                           featureIsAvailable: true,
                                                           triggerIsEnabled: true)
               && !ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                                currentGeneration: 4,
                                                                featureIsAvailable: true,
                                                                triggerIsEnabled: true)
               && !ClipboardAutoClearSupport.clearIsAuthorized(enqueuedGeneration: 3,
                                                                currentGeneration: 3,
                                                                featureIsAvailable: true,
                                                                triggerIsEnabled: false),
               "a queued clear is invalidated when its setting changes before pasteboard access")

        expect(FeatureStrings.clipboard(.ptBR).shortcutHint.contains("colar no app anterior"),
               "clipboard shortcut hint exposes row click paste in Portuguese")
        expect(FeatureStrings.clipboard(.ptBR).shortcutHint.contains("⌘+clique seleciona"),
               "clipboard shortcut hint exposes command click multi-select in Portuguese")
        expect(FeatureStrings.clipboard(.ptBR).clickRowShortcut == "Clique na linha",
               "clipboard visual shortcut exposes row click in Portuguese")
        expect(FeatureStrings.clipboard(.enUS).shortcutHint.contains("paste it into the previous app"),
               "clipboard shortcut hint exposes row click paste in English")
        expect(FeatureStrings.clipboard(.enUS).shortcutHint.contains("⌘-click selects"),
               "clipboard shortcut hint exposes command click multi-select in English")
        expect(FeatureStrings.clipboard(.enUS).commandClickShortcut == "⌘ Click",
               "clipboard visual shortcut exposes command click in English")
        expect(FeatureStrings.clipboard(.tr).shortcutHint.contains("yapıştırın"),
               "clipboard shortcut hint exposes row click paste in Turkish")
        expect(FeatureStrings.clipboard(.tr).shortcutHint.contains("birden çok öğe seçer"),
               "clipboard shortcut hint exposes command click multi-select in Turkish")
        expect(FeatureStrings.clipboard(.tr).clickRowShortcut == "Satıra tıkla",
               "clipboard visual shortcut exposes row click in Turkish")
        let featureTitles: [(AppLanguage, String, String, String, String)] = [
            (.enUS, "Clipboard", "Window layout", "Utilities", "Alerts"),
            (.ptBR, "Clipboard", "Layout de janelas", "Utilitários", "Alertas"),
            (.tr, "Pano", "Pencere yerleşimi", "Araçlar", "Uyarılar"),
            (.es, "Portapapeles", "Diseño de ventanas", "Utilidades", "Alertas"),
            (.de, "Zwischenablage", "Fensterlayout", "Dienstprogramme", "Warnungen"),
            (.fr, "Presse-papiers", "Disposition des fenêtres", "Utilitaires", "Alertes"),
            (.it, "Appunti", "Layout finestre", "Utilità", "Avvisi"),
            (.ja, "クリップボード", "ウインドウ配置", "ユーティリティ", "アラート"),
            (.ko, "클립보드", "윈도우 정렬", "유틸리티", "알림"),
            (.ru, "Буфер обмена", "Раскладка окон", "Утилиты", "Оповещения"),
            (.zhHans, "剪贴板", "窗口布局", "实用工具", "提醒"),
            (.zhTW, "剪貼簿", "視窗排列", "工具程式", "提醒"),
            (.zhHK, "剪貼簿", "視窗排列", "工具", "提示"),
        ]
        for (language, clipboardTitle, windowTitle, utilitiesTitle, alertsTitle) in featureTitles {
            expect(FeatureStrings.clipboard(language).title == clipboardTitle,
                   "\(language.rawValue) clipboard title is localized")
            expect(FeatureStrings.windowLayout(language).title == windowTitle,
                   "\(language.rawValue) window layout title is localized")
            expect(FeatureStrings.settingsCategories(language).utilities == utilitiesTitle,
                   "\(language.rawValue) settings category title is localized")
            expect(FeatureStrings.monitorAlerts(language).section == alertsTitle,
                   "\(language.rawValue) monitor alert section is localized")
        }
        for language in AppLanguage.allCases {
            let clipboardStrings = FeatureStrings.clipboard(language)
            expectFormat(clipboardStrings.pasteSelectedFormat, ["d"],
                         "\(language.rawValue) paste-selected button format")
            expectFormat(clipboardStrings.copySelectedFormat, ["d"],
                         "\(language.rawValue) copy-selected button format")
            expect(!clipboardStrings.autoClearEnable.isEmpty
                   && !clipboardStrings.autoClearSecondsSuffix.isEmpty
                   && !clipboardStrings.autoClearOnSleep.isEmpty
                   && !clipboardStrings.autoClearOnDisplaySleep.isEmpty
                   && !clipboardStrings.autoClearOnScreenLock.isEmpty
                   && !clipboardStrings.autoClearCaption.isEmpty,
                   "\(language.rawValue) clipboard auto clear labels are localized")
            let layoutStrings = FeatureStrings.windowLayout(language)
            expect(!layoutStrings.sixths.isEmpty
                   && !layoutStrings.topLeftSixth.isEmpty
                   && !layoutStrings.topCenterSixth.isEmpty
                   && !layoutStrings.topRightSixth.isEmpty
                   && !layoutStrings.bottomLeftSixth.isEmpty
                   && !layoutStrings.bottomCenterSixth.isEmpty
                   && !layoutStrings.bottomRightSixth.isEmpty,
                   "\(language.rawValue) window sixth layout labels are localized")
            expect(!layoutStrings.gestureSection.isEmpty
                   && !layoutStrings.gestureEnable.isEmpty
                   && !layoutStrings.gestureCaption.isEmpty
                   && !layoutStrings.gestureModifiers.isEmpty
                   && !layoutStrings.gestureMove.isEmpty
                   && !layoutStrings.gestureResize.isEmpty
                   && !layoutStrings.gestureResizeHint.isEmpty
                   && !layoutStrings.gestureRaiseWindow.isEmpty,
                   "\(language.rawValue) window gesture controls are localized")
            expect(!layoutStrings.edgeSnapEnable.isEmpty
                   && !layoutStrings.edgeSnapCaption.isEmpty
                   && !layoutStrings.edgeSnapSystemConflict.isEmpty
                   && !layoutStrings.edgeSnapOpenSystemSettings.isEmpty
                   && !layoutStrings.edgeSnapWaitingForSystem.isEmpty
                   && !layoutStrings.edgeSnapEnable.contains("—")
                   && !layoutStrings.edgeSnapCaption.contains("—")
                   && !layoutStrings.edgeSnapSystemConflict.contains("—")
                   && !layoutStrings.edgeSnapOpenSystemSettings.contains("—")
                   && !layoutStrings.edgeSnapWaitingForSystem.contains("—"),
                   "\(language.rawValue) window edge snap controls are localized")
            let alertStrings = FeatureStrings.monitorAlerts(language)
            expect(alertStrings.caption.contains("12"),
                   "\(language.rawValue) monitor alert caption explains the sustained alert window")
            expectFormat(alertStrings.cpuBodyFormat, ["d"], "\(language.rawValue) CPU alert format")
            expectFormat(alertStrings.cpuTemperatureBodyFormat, ["d"],
                         "\(language.rawValue) CPU temperature alert format")
            expectFormat(alertStrings.diskBodyFormat, ["@", "d"], "\(language.rawValue) disk alert format")
            expectFormat(alertStrings.batteryBodyFormat, ["d"], "\(language.rawValue) battery alert format")
            expectFormat(alertStrings.batteryTemperatureBodyFormat, ["d"],
                         "\(language.rawValue) battery temperature alert format")
        }
        expect(FeatureStrings.monitorAlerts(.enUS).cooldown == "Repeat the same alert after",
               "English monitor repeat control is explicit")
        expect(FeatureStrings.monitorAlerts(.ptBR).cooldown == "Repetir o mesmo alerta depois de",
               "Portuguese monitor repeat control is explicit")
        expect(ClipboardHistorySelection.initialIndex(totalCount: 3) == 0,
               "clipboard quick window starts keyboard navigation on the first item")
        expect(ClipboardHistorySelection.initialIndex(totalCount: 0) == 0,
               "clipboard quick window keeps an empty selection index safe")

        // MARK: Settings search navigation

        expect(SettingsSearchSupport.moveSelection(index: 0, delta: -1, count: 3) == 2,
               "Settings search Up wraps from first to last")
        expect(SettingsSearchSupport.moveSelection(index: 2, delta: 1, count: 3) == 0,
               "Settings search Down wraps from last to first")
        expect(SettingsSearchSupport.moveSelection(index: nil, delta: 1, count: 3) == 0,
               "Settings search Down starts a nil selection at the first result")
        expect(SettingsSearchSupport.moveSelection(index: nil, delta: -1, count: 3) == 2,
               "Settings search Up starts a nil selection at the last result")
        expect(SettingsSearchSupport.moveSelection(index: 0, delta: 1, count: 0) == nil,
               "Settings search navigation leaves an empty result set unselected")
        expect(SettingsSearchSupport.moveSelection(index: 0, delta: 10, count: 3) == 1,
               "Settings search navigation wraps large positive deltas")
        expect(SettingsSearchSupport.moveSelection(index: 0, delta: -10, count: 3) == 2,
               "Settings search navigation wraps large negative deltas")
        expect(SettingsSearchSupport.clampedSelection(index: 4, count: 2) == 1,
               "Settings search selection clamps after results shrink")
        expect(SettingsSearchSupport.reconciledSelection(index: 2,
                                                         previousIDs: ["a", "b", "c"],
                                                         resultIDs: ["a", "b"]) == 1,
               "Settings search reconciliation clamps after results shrink")
        expect(SettingsSearchSupport.reconciledSelection(index: nil,
                                                         previousIDs: [String](),
                                                         resultIDs: ["new"]) == 0,
               "Settings search selects the first newly available result")
        expect(SettingsSearchSupport.clampedSelection(index: 0, count: 0) == nil,
               "Settings search clamping clears an empty result set")
        expect(SettingsSearchSupport.reconciledSelection(index: 1,
                                                         previousIDs: ["a", "b", "c"],
                                                         resultIDs: ["b", "a"]) == 0,
               "Settings search selection follows the same result after reranking")

        expect(!ClipboardHistoryPreview.handlesSpace(selectionIsVisible: false, hasModifiers: false),
               "clipboard preview leaves spaces typed into search alone")
        expect(ClipboardHistoryPreview.handlesSpace(selectionIsVisible: true, hasModifiers: false),
               "clipboard preview uses Space after keyboard navigation")
        expect(!ClipboardHistoryPreview.handlesSpace(selectionIsVisible: true, hasModifiers: true),
               "clipboard preview never steals modified Space shortcuts")
        expect(ClipboardHistoryEscape.action(batchCount: 0) == .hideWindow,
               "Esc closes the panel when nothing is selected")
        expect(ClipboardHistoryEscape.action(batchCount: 2) == .clearBatchSelection,
               "Esc clears a batch selection before it closes the panel")
        expect(ClipboardHistoryFocus.textViewOwnsKeys(isComposing: true,
                                                      isFieldEditor: true,
                                                      isEditable: true),
               "a composing search field keeps Return, the arrows and Esc")
        expect(!ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                       isFieldEditor: true,
                                                       isEditable: true),
               "the list keeps its shortcuts over a search field that is not composing")
        expect(ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                      isFieldEditor: false,
                                                      isEditable: true),
               "the multiline editor owns its editing keys")
        expect(!ClipboardHistoryFocus.textViewOwnsKeys(isComposing: false,
                                                       isFieldEditor: false,
                                                       isEditable: false),
               "the read-only preview leaves the list's shortcuts intact")
        expect(ClipboardHistoryEditing.canSave(original: "First draft", draft: "Second draft"),
               "clipboard text can save a real edit")
        expect(!ClipboardHistoryEditing.canSave(original: "Same", draft: "Same"),
               "clipboard text does not save an unchanged draft")
        expect(ClipboardHistoryEditing.storableText("  keep spacing  ") == "  keep spacing  ",
               "clipboard editing preserves intentional outer spacing")
        expect(ClipboardHistoryEditing.storableText(" \n\t ") == nil,
               "clipboard editing rejects an empty text item")
        let largeClipboardText = String(repeating: "long copied text ", count: 10_000)
        expect(ClipboardHistoryEditing.storableText(largeClipboardText) == largeClipboardText,
               "clipboard history keeps copied documents larger than the old short-text bound")
        expect(ClipboardHistoryEditing.storableText(
            String(repeating: "a", count: ClipboardHistoryEditing.maxCharacters + 1)) == nil,
               "clipboard editing keeps the history text size bound")
        let budgetPinned = ClipboardHistoryEntry(text: "123456", pinnedAt: Date())
        let budgetRecentA = ClipboardHistoryEntry(text: "abcd")
        let budgetRecentB = ClipboardHistoryEntry(text: "efgh")
        let budgetedHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetPinned, budgetRecentA, budgetRecentB],
            recentLimit: 10,
            textByteLimit: 10)
        expect(budgetedHistory.map(\.id) == [budgetPinned.id, budgetRecentA.id],
               "clipboard history keeps pinned and newest entries inside one aggregate text budget")
        let protectedPinned = ClipboardHistoryEntry(text: "1234", pinnedAt: Date())
        var enlargedPinned = budgetPinned
        enlargedPinned.text = "12345678"
        let trimmedPinned = ClipboardHistoryEditing.retainedEntries(
            [enlargedPinned, protectedPinned],
            recentLimit: 10,
            textByteLimit: 10)
        expect(!ClipboardHistoryEditing.preservesPinnedEntries(
            from: [budgetPinned, protectedPinned],
            in: trimmedPinned),
               "an edit that would evict another pinned clipboard item is rejected")
        expect(ClipboardHistoryEditing.canLoadEncodedHistory(
            byteCount: ClipboardHistoryEditing.maxEncodedHistoryBytes)
                && !ClipboardHistoryEditing.canLoadEncodedHistory(
                    byteCount: ClipboardHistoryEditing.maxEncodedHistoryBytes + 1)
                && !ClipboardHistoryEditing.canLoadEncodedHistory(byteCount: nil),
               "clipboard history size is checked before its store file is loaded")
        let escapingHistory = (0..<8).map { index in
            ClipboardHistoryEntry(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!,
                text: String(repeating: "\\", count: 1_000),
                copiedAt: Date(timeIntervalSince1970: Double(index))
            )
        }
        let encodedHistoryLimit = 5_000
        if let encodedHistory = ClipboardHistoryEditing.encodedHistory(
            escapingHistory, byteLimit: encodedHistoryLimit) {
            expect(encodedHistory.data.count <= encodedHistoryLimit
                    && (try? JSONDecoder().decode([ClipboardHistoryEntry].self,
                                                 from: encodedHistory.data)) == encodedHistory.entries
                    && encodedHistory.entries.count < escapingHistory.count,
                   "clipboard persistence trims against actual escaped JSON before writing")
        } else {
            expect(false, "clipboard persistence encodes a bounded escaped history")
        }
        let largeClipboardPreview = ClipboardHistoryEntry(text: largeClipboardText).preview
        expect(largeClipboardPreview.hasSuffix("…")
                && largeClipboardPreview.count <= ClipboardHistoryEditing.previewCharacters + 1,
               "clipboard rows keep very large text previews bounded")
        expect(Defaults.allowedClipboardHistoryLimits == [20, 50, 100, 250, 500, 1_000, 10_000, 0],
               "clipboard history limits include 10k and unlimited options")
        expect(Defaults.sanitizedClipboardHistoryLimit(10_000) == 10_000
                && Defaults.sanitizedClipboardHistoryLimit(0) == 0
                && Defaults.sanitizedClipboardHistoryLimit(50) == 50
                && Defaults.sanitizedClipboardHistoryLimit(-99) == 50,
               "sanitized clipboard history limits accept 10k and 0 (unlimited)")
        let unlimitedHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetRecentA, budgetRecentB],
            recentLimit: 0,
            textByteLimit: 1_000)
        expect(unlimitedHistory.count == 2,
               "clipboard history retainedEntries preserves all entries when recentLimit is 0 (unlimited)")
        let tenThousandHistory = ClipboardHistoryEditing.retainedEntries(
            [budgetRecentA, budgetRecentB],
            recentLimit: 10_000,
            textByteLimit: 1_000)
        expect(tenThousandHistory.count == 2,
               "clipboard history retainedEntries preserves entries with 10_000 limit")
        let previewID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        let nextPreviewID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        let updatedPreview = ClipboardHistoryEntry(id: previewID, text: "updated")
        let nextPreview = ClipboardHistoryEntry(id: nextPreviewID, text: "next")
        expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [updatedPreview, nextPreview],
                                                      selectedEntry: nextPreview)?.text == "updated",
               "clipboard preview resolves the current payload for its UUID")
        expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [nextPreview],
                                                      selectedEntry: nextPreview)?.id == nextPreviewID,
               "clipboard search falls back to the selected visible entry")
        expect(ClipboardHistorySelection.previewEntry(preferredID: previewID,
                                                      visibleEntries: [],
                                                      selectedEntry: nil) == nil,
               "clipboard preview clears after removing the final visible entry")
        expectEqual(ClipboardHistoryBatch.combinedText(["First", "Second", "Third"]),
                    "First\nSecond\nThird",
                    "clipboard batch joins selected entries as a single paste")
        expect(ClipboardHistoryBatch.orderedSelectedIndexes(allIDs: ["a", "b", "c", "d"],
                                                           selectedIDs: Set(["d", "b"])) == [1, 3],
               "clipboard batch preserves the visible history order")
        expect(ClipboardHistoryBatch.rangeSelectionIDs(allIDs: ["a", "b", "c", "d"],
                                                       anchor: 3, target: 1) == ["b", "c", "d"],
               "shift-click selects the whole range in either direction")
        expect(ClipboardHistoryBatch.rangeSelectionIDs(allIDs: ["a"], anchor: 9, target: -2) == ["a"],
               "shift-click range clamps out-of-bounds anchors")
        let batchTextA = ClipboardHistoryEntry(text: "alpha")
        let batchTextB = ClipboardHistoryEntry(text: "beta")
        let batchFiles = ClipboardHistoryEntry(text: "", kind: .files,
                                               filePaths: ["/tmp/a.txt", "/tmp/b.txt"])
        let batchImage = ClipboardHistoryEntry(text: "", kind: .image, imageFile: "x.png")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchFiles, batchFiles])
                   == .files(["/tmp/a.txt", "/tmp/b.txt", "/tmp/a.txt", "/tmp/b.txt"]),
               "an all-files selection pastes as the files themselves")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchTextB])
                   == .text("alpha\nbeta"),
               "an all-text selection combines as lines")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchFiles])
                   == .text("alpha\n/tmp/a.txt\n/tmp/b.txt"),
               "a mixed selection combines as text with file paths inlined")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchTextA, batchImage])
                   == .rich([.text("alpha"), .image("x.png")]),
               "a selection with an image pastes as rich text with the image embedded")
        expect(ClipboardHistoryBatch.pasteMode(for: [batchImage, batchFiles])
                   == .rich([.image("x.png"), .text("/tmp/a.txt\n/tmp/b.txt")]),
               "files in a rich selection contribute their paths as text")
        expect(ClipboardHistoryBatch.richPlainText([.text("alpha"), .image("x.png"), .text("beta")])
                   == "alpha\nbeta",
               "the plain-text fallback of a rich batch keeps only the text parts")

        let legacyClipboardJSON = Data("""
        [{"text":"hello","copiedAt":700000000}]
        """.utf8)
        if let legacy = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: legacyClipboardJSON) {
            expect(legacy.count == 1 && legacy[0].kind == .text && legacy[0].text == "hello",
                   "clipboard histories saved before images and files decode as text")
        } else {
            expect(false, "clipboard legacy history decodes")
        }
        var editedTextEntry = ClipboardHistoryEntry(text: "before", pinnedAt: Date(timeIntervalSince1970: 42))
        editedTextEntry.text = ClipboardHistoryEditing.storableText("after") ?? editedTextEntry.text
        if let encoded = try? JSONEncoder().encode([editedTextEntry]),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: encoded) {
            expect(decoded.first?.id == editedTextEntry.id
                   && decoded.first?.text == "after"
                   && decoded.first?.pinnedAt == editedTextEntry.pinnedAt,
                   "clipboard text edits persist without losing item identity or pinning")
        } else {
            expect(false, "clipboard text edit round-trips")
        }
        let imageEntry = ClipboardHistoryEntry(text: "",
                                               kind: .image,
                                               imageFile: "a.png",
                                               imageHash: "h1",
                                               imageWidth: 1470,
                                               imageHeight: 956)
        if let encoded = try? JSONEncoder().encode([imageEntry]),
           let decoded = try? JSONDecoder().decode([ClipboardHistoryEntry].self, from: encoded) {
            expect(decoded.first?.kind == .image
                       && decoded.first?.imageFile == "a.png"
                       && decoded.first?.imageWidth == 1470,
                   "clipboard image entries round-trip through storage")
        } else {
            expect(false, "clipboard image entry round-trips")
        }
        expectEqual(imageEntry.preview, "1470×956",
                    "clipboard image preview shows the dimensions")
        expect(imageEntry.searchableText(imageLabel: "Imagem").contains("Imagem"),
               "clipboard image entries match the localized image word in search")
        expect(imageEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                   kind: .image,
                                                                   imageFile: "b.png",
                                                                   imageHash: "h1")),
               "clipboard image dedupe matches by content hash, not by file")
        expect(!imageEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                    kind: .image,
                                                                    imageFile: "c.png",
                                                                    imageHash: "h2")),
               "clipboard image dedupe rejects different content")
        expect(!ClipboardHistoryEntry(text: "", kind: .image).matchesContent(
                   of: ClipboardHistoryEntry(text: "", kind: .image)),
               "clipboard image dedupe never matches entries without a hash")
        let filesEntry = ClipboardHistoryEntry(text: "",
                                               kind: .files,
                                               filePaths: ["/Users/a/Documents/Report.pdf",
                                                           "/Users/a/Pictures/Photo.png"])
        expectEqual(filesEntry.preview, "Report.pdf, Photo.png",
                    "clipboard files preview lists the file names")
        expect(filesEntry.searchableText(imageLabel: "Image").contains("Report.pdf"),
               "clipboard files entries are searchable by file name")
        expect(filesEntry.searchableText(imageLabel: "Image").contains("Image"),
               "clipboard files with images include the localized image label in search")
        expect(ClipboardHistoryImageSupport.isImageFileName("screenshot.PNG"),
               "clipboard image file support recognizes png case-insensitively")
        expect(ClipboardHistoryImageSupport.isImageFileName("photo.jpeg")
               && ClipboardHistoryImageSupport.isImageFileName("picture.heic")
               && ClipboardHistoryImageSupport.isImageFileName("art.webp"),
               "clipboard image file support recognizes standard image extensions")
        expect(!ClipboardHistoryImageSupport.isImageFileName("document.pdf")
               && !ClipboardHistoryImageSupport.isImageFileName("archive.zip"),
               "clipboard image file support rejects non-image extensions")
        expect(filesEntry.matchesContent(of: ClipboardHistoryEntry(text: "",
                                                                   kind: .files,
                                                                   filePaths: filesEntry.filePaths)),
               "clipboard files dedupe matches the same path set")
        expect(!filesEntry.matchesContent(of: ClipboardHistoryEntry(text: "Report.pdf, Photo.png",
                                                                    kind: .text)),
               "clipboard dedupe never crosses kinds")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "http://localhost:3000/page",
                                                                 plainText: "//localhost:3000/page") ?? "",
                    "http://localhost:3000/page",
                    "clipboard history preserves the scheme for scheme-relative browser URLs")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://example.com/docs",
                                                                 plainText: "example.com/docs") ?? "",
                    "https://example.com/docs",
                    "clipboard history restores the scheme for scheme-stripped browser URLs")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "https://example.com/docs",
                                                                 plainText: "Open docs") ?? "",
                    "Open docs",
                    "clipboard history keeps ordinary link text when it is not a URL")
        expectEqual(ClipboardHistoryPasteboardText.preferredText(webURLString: "file:///tmp/example.txt",
                                                                 plainText: "/tmp/example.txt") ?? "",
                    "/tmp/example.txt",
                    "clipboard history ignores non-web URL pasteboard types")
        expect(!ClipboardHistorySensitiveText.looksSensitive("http://localhost:3000/page"),
               "clipboard history does not treat normal web URLs as secrets")
        expect(ClipboardHistorySensitiveText.looksSensitive("https://example.com/callback?token=abc"),
               "clipboard history still skips URLs with obvious secret words")
        expect(ClipboardHistorySensitiveText.looksSensitive("abc1234567890-xyz-abc"),
               "clipboard history still skips compact secret-looking text")
        // Issue #423: an identifier code is ordinary content to copy around,
        // and losing it is what stopped people from leaving the skip on.
        expect(!ClipboardHistorySensitiveText.looksSensitive("3f2504e0-4f89-11d3-9a0c-0305e82c3301"),
               "clipboard history keeps a plain identifier code")
        expect(!ClipboardHistorySensitiveText.looksSensitive("3F2504E0-4F89-11D3-9A0C-0305E82C3301"),
               "clipboard history keeps an identifier code written in capitals")
        expect(!ClipboardHistorySensitiveText.looksSensitive("{3f2504e0-4f89-11d3-9a0c-0305e82c3301}"),
               "clipboard history keeps an identifier code wrapped in braces")
        expect(ClipboardHistorySensitiveText.looksSensitive("3f2504e0-4f89-11d3-9a0c-0305e82c33x1"),
               "a string that only resembles an identifier code is still treated as a secret")
        expect(ClipboardHistorySensitiveText.looksSensitive("3f2504e04f8911d39a0c0305e82c3301!x"),
               "dropping the dashes does not turn a secret into an identifier code")
        // The mark an app puts on the pasteboard when it hands over a secret.
        // It travels with every item, so one read of the pasteboard types
        // answers for a mark written on its own item too (measured).
        expect(ClipboardHistorySensitiveText.isConcealed(["public.utf8-plain-text",
                                                          ClipboardHistorySensitiveText
                                                              .concealedPasteboardType]),
               "clipboard history leaves out content an app marked as a secret")
        expect(!ClipboardHistorySensitiveText.isConcealed(["public.utf8-plain-text",
                                                            "NSStringPboardType"]),
               "ordinary copied text carries no secret mark")
        expectEqual(ClipboardHistorySensitiveText.concealedPasteboardType,
                    "org.nspasteboard.ConcealedType",
                    "the secret mark keeps the exact name the apps that write it use")

        let pasteboardAccess = GeneralPasteboardAccess(label: "Chikit.Tests.PasteboardAccess")
        let pasteboardGroup = DispatchGroup()
        let pasteboardStateLock = NSLock()
        var activePasteboardOperations = 0
        var maximumPasteboardOperations = 0
        for _ in 0..<16 {
            pasteboardGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pasteboardAccess.async {
                    pasteboardStateLock.lock()
                    activePasteboardOperations += 1
                    maximumPasteboardOperations = max(maximumPasteboardOperations,
                                                       activePasteboardOperations)
                    pasteboardStateLock.unlock()
                    usleep(1_000)
                    pasteboardStateLock.lock()
                    activePasteboardOperations -= 1
                    pasteboardStateLock.unlock()
                    pasteboardGroup.leave()
                }
            }
        }
        expect(pasteboardGroup.wait(timeout: .now() + 5) == .success,
               "pasteboard access operations finish without deadlock")
        expect(maximumPasteboardOperations == 1,
               "pasteboard access serializes concurrent service work")

        // The freeze this lane exists to prevent (issue #887): a read stuck
        // behind an app that promised pasteboard content and stopped answering
        // holds the lane, and any caller that waited for it would be frozen
        // with it. Wedge the lane, then ask for work from the main thread: the
        // ask must return at once and the answer must arrive later, on main.
        let wedgeReleased = DispatchSemaphore(value: 0)
        pasteboardAccess.async { wedgeReleased.wait() }
        // Released on its own, so a caller that waited for the lane comes out
        // measurably late instead of hanging the whole test run.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.3) {
            wedgeReleased.signal()
        }
        var laneAnswer: Int?
        var laneAnsweredOnMain = false
        let askedAt = Date()
        pasteboardAccess.async({ 887 }, then: { value in
            laneAnswer = value
            laneAnsweredOnMain = Thread.isMainThread
        })
        let askDuration = Date().timeIntervalSince(askedAt)
        expect(askDuration < 0.1,
               "asking the wedged pasteboard lane for work returns without waiting "
                   + "(took \(askDuration)s)")
        expect(laneAnswer == nil, "the wedged lane has not answered yet")
        let laneDeadline = Date().addingTimeInterval(5)
        while laneAnswer == nil, Date() < laneDeadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        expect(laneAnswer == 887, "the queued work runs once the lane comes free")
        expect(laneAnsweredOnMain, "the pasteboard lane answers on the main queue")

        let maxCapacityStringJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"93%"}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityStringJSON) == 93,
               "battery maximum capacity parses percentage strings")
        let maxCapacityNumberJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":93}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNumberJSON) == 93,
               "battery maximum capacity parses numeric JSON")
        let maxCapacityNestedJSON = Data(#"{"SPPowerDataType":[{"_items":[{"_items":[{"Maximum Capacity":"93%"}]}]}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityNestedJSON) == 93,
               "battery maximum capacity parses nested System Report keys")
        let maxCapacityUnavailableJSON = Data(#"{"SPPowerDataType":[{"sppower_battery_health_info":{"sppower_battery_health_maximum_capacity":"EM_DASH"}}]}"#.utf8)
        expect(MaxCapacityProbe.percent(fromSystemProfilerJSON: maxCapacityUnavailableJSON) == nil,
               "battery maximum capacity ignores placeholder values")

        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: false) == 13_320,
               "battery time converts the public time-to-empty minutes")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: -1,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time preserves the system calculating state")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: true,
                                                   isCharging: false) == nil,
               "battery time stays hidden on external power")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 222,
                                                   externalConnected: false,
                                                   isCharging: true) == nil,
               "battery time stays hidden while charging")
        expect(BatteryTimeSupport.remainingSeconds(timeToEmptyMinutes: 65_535,
                                                   externalConnected: false,
                                                   isCharging: false) == nil,
               "battery time ignores the public unavailable sentinel")
        expect(BatteryTimeSupport.formatted(seconds: 13_320) == "3h 42m",
               "battery time formats hours and minutes")
        expect(BatteryTimeSupport.formatted(seconds: 30) == "0h 1m",
               "battery time keeps a positive final minute visible")

        expect(MetricFormat.systemPowerWatts(measured: 3,
                                             batteryWatts: 10,
                                             externalConnected: true) == 3,
               "system power keeps its independent sensor while connected to power")
        expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: 10,
                                             externalConnected: true) == nil,
               "system power does not mirror adapter input while connected to power")
        expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: -4,
                                             externalConnected: false) == 4,
               "battery discharge remains a valid system-power fallback")
        expect(MetricFormat.systemPowerWatts(measured: nil,
                                             batteryWatts: -4,
                                             externalConnected: true) == nil,
               "battery flow alone does not claim total system power while plugged in")

        // MARK: Peripheral battery helpers

        expect(PeripheralBatterySupport.percent(from: "87%") == 87,
               "peripheral battery parses percentage strings")
        expect(PeripheralBatterySupport.percent(from: NSNumber(value: 62.4)) == 62,
               "peripheral battery rounds numeric values")
        expect(PeripheralBatterySupport.percent(from: 140) == nil,
               "peripheral battery ignores invalid percentages")
        let usageMouse = [["DeviceUsagePage": 1, "DeviceUsage": 2]]
        expect(PeripheralBatterySupport.kind(product: "Wireless Device",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: usageMouse) == .mouse,
               "peripheral battery infers mouse from HID usage")
        expect(PeripheralBatterySupport.kind(product: "soundcore Space Q45",
                                             minorType: "Headset",
                                             primaryUsagePage: nil,
                                             primaryUsage: nil,
                                             usagePairs: []) == .audio,
               "peripheral battery infers Bluetooth headsets as audio devices")
        let bluetoothJSON = Data("""
        {"SPBluetoothDataType":[{"device_connected":[
          {"soundcore Space Q45":{"device_address":"F4:9D:8A:A2:4C:12","device_batteryLevelMain":"100%","device_minorType":"Headset"}},
          {"AirPods Pro":{"device_address":"E5:04:BE:68:C2:93","device_batteryLevelCase":"88%","device_batteryLevelLeft":"92%","device_batteryLevelRight":"90%"}},
          {"Travel Pointer":{"device_address":"F0:00:00:00:00:01","device_minorType":"Mouse"}}
        ],"device_not_connected":[
          {"Old Mouse":{"device_address":"00:00:00:00:00:00","device_batteryLevelMain":"12%","device_minorType":"Mouse"}}
        ]}]}
        """.utf8)
        let bluetoothDevices = PeripheralBatterySupport.bluetoothDevices(fromSystemProfilerJSON: bluetoothJSON)
        expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:F4:9D:8A:A2:4C:12",
                                                                 name: "soundcore Space Q45",
                                                                 percent: 100,
                                                                 kind: .audio)),
               "peripheral battery parses connected Bluetooth headset battery")
        expect(bluetoothDevices.contains(PeripheralBatteryDevice(id: "Bluetooth:E5:04:BE:68:C2:93",
                                                                 name: "AirPods Pro",
                                                                 percent: 88,
                                                                 kind: .audio)),
               "peripheral battery uses the lowest connected AirPods component")
        expect(!bluetoothDevices.contains { $0.name == "Old Mouse" },
               "peripheral battery ignores disconnected Bluetooth devices")
        let bluetoothKinds = PeripheralBatterySupport.bluetoothKindsByName(
            fromSystemProfilerJSON: bluetoothJSON
        )
        expect(bluetoothKinds["travel pointer"] == .mouse,
               "peripheral battery keeps the kind of connected devices without profiler charge data")
        let gattDevices = PeripheralBatterySupport.mergingBluetoothReadings(
            [
                BluetoothBatteryReading(id: "pointer", name: "Travel Pointer", percent: 73),
                BluetoothBatteryReading(id: "pointer", name: "Renamed Pointer", percent: 64),
                BluetoothBatteryReading(id: "duplicate", name: "soundcore space q45", percent: 17),
                BluetoothBatteryReading(id: "invalid", name: "Invalid Accessory", percent: 101),
            ],
            into: bluetoothDevices,
            knownKinds: bluetoothKinds
        )
        expect(gattDevices.contains(PeripheralBatteryDevice(id: "BluetoothGATT:pointer",
                                                            name: "Travel Pointer",
                                                            percent: 73,
                                                            kind: .mouse)),
               "peripheral battery adds a standard Bluetooth battery reading with its known kind")
        expect(gattDevices.first { $0.name.caseInsensitiveCompare("soundcore Space Q45") == .orderedSame }?.percent == 100,
               "peripheral battery keeps richer profiler data instead of a duplicate standard reading")
        expect(!gattDevices.contains { $0.name == "Renamed Pointer" },
               "peripheral battery keeps one row per Bluetooth identity")
        expect(!gattDevices.contains { $0.name == "Invalid Accessory" },
               "peripheral battery rejects invalid standard Bluetooth percentages")
        let keyboard = PeripheralBatteryDevice(id: "keyboard",
                                               name: "Magic Keyboard",
                                               percent: 78,
                                               kind: .keyboard)
        let mouse = PeripheralBatteryDevice(id: "mouse",
                                            name: "Magic Mouse",
                                            percent: 24,
                                            kind: .mouse)
        expect(PeripheralBatterySupport.sorted([keyboard, mouse]).map(\.id) == ["mouse", "keyboard"],
               "peripheral battery devices sort by lowest charge first")
        let menuMetric = PeripheralBatterySupport.menuBarMetric(for: [keyboard, mouse])
        expect(menuMetric?.label == "MOU" && menuMetric?.value == "24%+1",
               "peripheral battery menu metric shows the lowest device and extra count")
        expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 300,
            lastStartedAt: -.greatestFiniteMagnitude,
            lastFinishedAt: -.greatestFiniteMagnitude,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh starts when no cache exists")
        expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 400,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: true,
            interval: 300
        ), "peripheral Bluetooth refresh is single-flight")
        expect(!PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 500,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh respects its cache interval")
        expect(PeripheralBatteryRefreshPolicy.shouldStartBluetoothRefresh(
            now: 606,
            lastStartedAt: 300,
            lastFinishedAt: 305,
            isRunning: false,
            interval: 300
        ), "peripheral Bluetooth refresh runs again only after the interval")

        // MARK: Keyboard debounce

        // MARK: Mouse click debounce

        let featureRuntimeSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/FeatureRuntime.swift",
            encoding: .utf8)) ?? ""
        // A modifying tap belongs in the chain only while this login session is
        // the one on screen: fast user switching leaves the process running
        // behind another account, where the tap still takes every scroll event
        // and stalls it (issue #1075).
        expect(SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                   accessibilityGranted: true,
                                                   sessionIsActive: true),
               "a wanted modifying tap runs in the session on screen")
        expect(!SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                    accessibilityGranted: true,
                                                    sessionIsActive: false),
               "a wanted modifying tap is handed back while its session is switched away")
        expect(!SessionActivitySupport.tapShouldRun(featureWanted: false,
                                                    accessibilityGranted: true,
                                                    sessionIsActive: true),
               "an unwanted modifying tap stays off in the session on screen")
        expect(!SessionActivitySupport.tapShouldRun(featureWanted: true,
                                                    accessibilityGranted: false,
                                                    sessionIsActive: true),
               "a modifying tap needs Accessibility even in the session on screen")

        // Launching into a session that is already switched away is announced
        // before the tap owners exist to hear it, so the state is read rather
        // than assumed. Anything unreadable counts as on screen because a
        // wrong off state would never be corrected.
        let onConsoleKey = kCGSessionOnConsoleKey as String
        expect(SessionActivitySupport.isOnConsole([onConsoleKey: true]),
               "a session dictionary saying it holds the console reads as on screen")
        expect(!SessionActivitySupport.isOnConsole([onConsoleKey: false]),
               "a session dictionary saying it does not hold the console reads as off screen")
        expect(SessionActivitySupport.isOnConsole([onConsoleKey: NSNumber(value: 1)]),
               "the console flag is read when it arrives as a number")
        expect(SessionActivitySupport.isOnConsole(nil),
               "an unreadable session reads as on screen because a wrong off would never be corrected")
        expect(SessionActivitySupport.isOnConsole([:]),
               "a session without the console flag reads as on screen because a wrong off would never be corrected")
        expect(SessionActivitySupport.isOnConsole([onConsoleKey: "unexpected"]),
               "an unexpected console flag reads as on screen because a wrong off would never be corrected")

        let privateCenter = NotificationCenter()
        let activity = SessionActivity(center: privateCenter, initialIsActive: { true })
        var observedTransitions: [Bool] = []
        activity.onChange { observedTransitions.append($0) }
        expect(activity.isActive, "session activity starts with the injected initial state")
        privateCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        expect(!activity.isActive, "session activity transitions to inactive on resign")
        privateCenter.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        privateCenter.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        expect(activity.isActive, "session activity transitions to active on become-active")
        expect(observedTransitions == [false, true],
               "the session activity handler records each state change and ignores duplicate notifications")

        // MARK: Watts & percent

        expectEqual(MetricFormat.watts(8.5), "8.5 W", "watts under 10")
        expectEqual(MetricFormat.watts(23.4), "23 W", "watts over 10 rounds")
        expectEqual(MetricFormat.wattsCompact(8.6), "9W", "watts compact rounds")
        expectEqual(MetricFormat.percent(0), "0%", "percent 0")
        expectEqual(MetricFormat.percent(0.125), "13%", "percent rounds")
        expectEqual(MetricFormat.percent(1), "100%", "percent full")
        expectEqual(MetricFormat.percent(1.4), "100%", "percent clamps high")
        expectEqual(MetricFormat.percent(-0.2), "0%", "percent clamps low")
        expectClose(MetricFormat.boundedPercentage(130), 100,
                    "process percentage clamps above full hardware utilization")
        expectClose(MetricFormat.boundedPercentage(-5), 0,
                    "process percentage clamps negative utilization")
        expect(MetricFormat.machTimeNanoseconds(48_000_000,
                                                numerator: 125,
                                                denominator: 3) == 2_000_000_000,
               "libproc CPU ticks convert through the platform Mach timebase")
        expectClose(MetricFormat.processCPUPercentage(previousNanoseconds: 1_000_000_000,
                                                       currentNanoseconds: 2_800_000_000,
                                                       elapsed: 2,
                                                       processorCount: 18), 5,
                    "process CPU delta uses the monitor wall-clock interval and machine capacity")
        expectClose(MetricFormat.processCPUPercentage(previousNanoseconds: 2_000_000_000,
                                                       currentNanoseconds: 1_000_000_000,
                                                       elapsed: 2,
                                                       processorCount: 18), 0,
                    "process CPU counter resets do not create utilization spikes")
        expectClose(MetricFormat.processReconciliationScale(sampledTotal: 12,
                                                             aggregatePercentage: 7), 7.0 / 12.0,
                    "process usage scales down when attribution exceeds the aggregate")
        expectClose(MetricFormat.processReconciliationScale(sampledTotal: 5,
                                                             aggregatePercentage: 7), 1,
                    "unattributed aggregate usage does not inflate process rows")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: 100), "79%",
                    "menu bar memory shows the current RAM percentage")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: nil, total: 100), "--%",
                    "menu bar memory keeps a placeholder when used RAM is unavailable")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: nil), "--%",
                    "menu bar memory keeps a placeholder when total RAM is unavailable")
        expectEqual(MetricFormat.menuBarMemoryPercent(used: 79, total: 0), "--%",
                    "menu bar memory keeps a placeholder when total RAM is invalid")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.03, current: 0.80), 0.23,
                    "GPU usage readout caps one-tick upward spikes")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.23, current: 0.80), 0.43,
                    "GPU usage readout still climbs during sustained load")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: 0.60, current: 0.10), 0.275,
                    "GPU usage readout falls quickly after transient load")
        expectClose(MetricFormat.stabilizedGPUUsage(previous: nil, current: 1.4), 1.0,
                    "GPU usage readout clamps first sample")
        expectEqual(MetricFormat.temperature(0, unit: .celsius), "0 °C", "celsius freezing")
        expectEqual(MetricFormat.temperature(0, unit: .fahrenheit), "32 °F", "fahrenheit freezing")
        expectEqual(MetricFormat.temperature(41, unit: .fahrenheit), "106 °F", "fahrenheit rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .celsius), "50°", "compact celsius rounds")
        expectEqual(MetricFormat.temperatureCompact(49.6, unit: .fahrenheit), "121°", "compact fahrenheit rounds")
        expectEqual(MetricFormat.temperatureUnitSuffix(.celsius), "°C", "celsius suffix is explicit")
        expectEqual(MetricFormat.temperatureUnitSuffix(.fahrenheit), "°F", "fahrenheit suffix is explicit")

        // MARK: Temperature sensor selection

        expect(TemperatureSensorSelector.platform(brandString: "Apple M1") == .appleM1Family,
               "Apple M1 uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M2 Pro") == .appleM2Family,
               "Apple M2 Pro uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M3 Max") == .appleM3Family,
               "Apple M3 Max uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M4 Ultra") == .appleM4Family,
               "Apple M4 Ultra uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M5") == .appleM5Family,
               "Apple M5 uses the mapped CPU core sensor set")
        expect(TemperatureSensorSelector.platform(brandString: "Apple M10") == .unmappedAppleSilicon
               && TemperatureSensorSelector.platform(brandString: "Apple A18 Pro") == .unmappedAppleSilicon,
               "unmapped Apple Silicon never falls through to arbitrary CPU sensors")
        expect(TemperatureSensorSelector.platform(brandString: "Generic CPU") == .generic,
               "other processors keep the generic CPU sensor path")
        expect(TemperatureSensorSelector.isCPUTemperatureKey("Tf4E", platform: .appleM3Family)
                && !TemperatureSensorSelector.isCPUTemperatureKey("Tf4E", platform: .appleM4Family)
                && TemperatureSensorSelector.isCPUTemperatureKey("Tp01", platform: .appleM4Family),
               "M3 discovery includes its mapped Tf family without broadening later chips")
        let m1CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp09", 43.0), ("Tp01", 49.0), ("Tp02", 70.0)],
            platform: .appleM1Family
        )
        expectClose(m1CPU ?? -1, 49.0, "M1 family uses hottest mapped CPU core")
        let m2CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp1h", 7.0), ("Tp0j", 52.0), ("Tp0k", 75.0)],
            platform: .appleM2Family
        )
        expectClose(m2CPU ?? -1, 52.0, "M2 family ignores broken low CPU readings")
        expect(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp1h", 7.0), ("Tp1t", 6.0)],
            platform: .appleM2Family
        ) == nil, "M2 family rejects a sample made only of broken low readings")
        var chipTemperatureCache: CachedSensorReading?
        expectClose(TemperatureSensorSelector.stabilizedTemperature(
            49.25, cache: &chipTemperatureCache, now: 100, maxAge: 30,
            minimum: TemperatureSensorSelector.minimumChipTemperature
        ) ?? -1, 49.25, "legitimate chip temperature becomes the cached reading")
        expectClose(TemperatureSensorSelector.stabilizedTemperature(
            7, cache: &chipTemperatureCache, now: 101, maxAge: 30,
            minimum: TemperatureSensorSelector.minimumChipTemperature
        ) ?? -1, 49.25, "broken low CPU or GPU reading preserves the last valid value")
        expect(chipTemperatureCache?.updatedAt == 100 && chipTemperatureCache?.missedSamples == 1,
               "broken low chip reading does not become a fresh cached value")
        expectClose(TemperatureSensorSelector.stabilizedTemperature(
            50, cache: &chipTemperatureCache, now: 102, maxAge: 30,
            minimum: TemperatureSensorSelector.minimumChipTemperature
        ) ?? -1, 50, "next legitimate chip reading replaces the bridged value")
        var batteryTemperatureCache: CachedSensorReading?
        expectClose(TemperatureSensorSelector.stabilizedTemperature(
            7, cache: &batteryTemperatureCache, now: 100, maxAge: 30
        ) ?? -1, 7, "chip floor does not reject a legitimate low battery reading")
        expectClose(TemperatureSensorSelector.stabilizedTemperature(
            1, cache: &batteryTemperatureCache, now: 101, maxAge: 30
        ) ?? -1, 7, "an invalid battery sample bridges the last valid reading")
        expect(batteryTemperatureCache?.updatedAt == 100,
               "a bridged battery temperature keeps the real sample timestamp")
        var invalidBatteryTemperatureCache: CachedSensorReading?
        expect(TemperatureSensorSelector.stabilizedTemperature(
            1, cache: &invalidBatteryTemperatureCache, now: 100, maxAge: 30
        ) == nil, "existing battery lower bound remains unchanged")
        let m3CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Te05", 44.0), ("Tf4E", 53.0), ("Tf4F", 76.0)],
            platform: .appleM3Family
        )
        expectClose(m3CPU ?? -1, 53.0, "M3 family uses hottest mapped CPU core")
        let m4CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6), ("Tp0W", 67.0), ("Te04", 43.2)],
            platform: .appleM4Family
        )
        expectClose(m4CPU ?? -1, 51.6, "M4 family uses hottest mapped CPU core instead of auxiliary hotspots")
        let m5CPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 45.0), ("Tp0y", 54.0), ("Tp0z", 80.0)],
            platform: .appleM5Family
        )
        expectClose(m5CPU ?? -1, 54.0, "M5 family uses hottest mapped CPU core")
        let m4InvalidCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp01", 0.5), ("Tp05", 130.0), ("Tp09", 49.25), ("Tp0W", 67.0)],
            platform: .appleM4Family
        )
        expectClose(m4InvalidCPU ?? -1, 49.25, "mapped CPU core selection ignores invalid temperatures")
        let m4FallbackCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp0W", 67.0)],
            platform: .appleM4Family
        )
        expect(m4FallbackCPU == nil,
               "mapped Apple Silicon never substitutes an auxiliary hotspot for a missing core sensor")
        expect(TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp0W", 113.0)],
            platform: .unmappedAppleSilicon
        ) == nil, "unmapped Apple Silicon hides unknown sensors instead of reporting an unsafe value")
        let genericCPU = TemperatureSensorSelector.displayedCPUTemperature(
            readings: [("Tp00", 44.5), ("Tp01", 51.6)],
            platform: .generic
        )
        expectClose(genericCPU ?? -1, 51.6, "generic CPU sensor selection preserves previous hottest behavior")

        // MARK: Hot CPU alert

        var spikeGate = SustainedAlertGate()
        expect(!spikeGate.shouldAlert(reading: 99, threshold: 90, readAt: 100),
               "a single hot reading is not a hot CPU yet")
        expect(!spikeGate.shouldAlert(reading: 99, threshold: 90, readAt: 108),
               "a second hot reading inside the window still waits")
        expect(spikeGate.shouldAlert(reading: 99, threshold: 90, readAt: 112),
               "a temperature that holds past the window alerts")

        var carriedGate = SustainedAlertGate()
        expect(!carriedGate.shouldAlert(reading: 101, threshold: 90, readAt: 200),
               "the reading behind a spike starts the window")
        var carriedAlerts = 0
        for _ in 0..<60 {
            if carriedGate.shouldAlert(reading: 101, threshold: 90, readAt: 200) {
                carriedAlerts += 1
            }
        }
        expect(carriedAlerts == 0,
               "the same reading served again never ages into an alert on its own")

        var coolingGate = SustainedAlertGate()
        _ = coolingGate.shouldAlert(reading: 99, threshold: 90, readAt: 300)
        expect(!coolingGate.shouldAlert(reading: 52, threshold: 90, readAt: 315),
               "a reading back under the limit does not alert")
        expect(!coolingGate.shouldAlert(reading: 99, threshold: 90, readAt: 330),
               "cooling down restarts the window instead of resuming the old one")
        expect(coolingGate.shouldAlert(reading: 99, threshold: 90, readAt: 345),
               "the restarted window alerts on its own merits")

        var quietGate = SustainedAlertGate()
        expect(!quietGate.shouldAlert(reading: 89, threshold: 90, readAt: 400),
               "a reading under the limit is not hot")
        expect(!quietGate.shouldAlert(reading: 89, threshold: 90, readAt: 500),
               "staying under the limit never alerts")
        expect(!quietGate.shouldAlert(reading: nil, threshold: 90, readAt: 600),
               "a missing temperature does not alert")
        expect(!quietGate.shouldAlert(reading: 99, threshold: 90, readAt: nil),
               "a temperature with no reading time does not alert")

        // MARK: Uptime formatting

        expectEqual(MetricFormat.uptime(0), "0min", "uptime zero")
        expectEqual(MetricFormat.uptime(59), "0min", "uptime under one minute")
        expectEqual(MetricFormat.uptime(60), "1min", "uptime one minute")
        expectEqual(MetricFormat.uptime(3_600), "1h 0min", "uptime one hour")
        expectEqual(MetricFormat.uptime(93_600), "1d 2h", "uptime days and hours")
        expectEqual(MetricFormat.uptime(8 * 86_400 + 21 * 3_600 + 8 * 60), "8d 21h",
                    "uptime keeps days compact")

        // MARK: Memory used

        let used = MetricFormat.memoryUsed(totalBytes: 16 * 1024,
                                           appBytes: 5 * 1024,
                                           pageSize: 1024,
                                           wiredPages: 2,
                                           compressorPages: 1,
                                           tagStoragePages: 1)
        expect(used == 9 * 1024, "memory used includes app, wired, compressed and tagged storage")
        expect(MetricFormat.memoryUsed(totalBytes: 16, appBytes: 20,
                                       pageSize: 1, wiredPages: 0,
                                       compressorPages: 0, tagStoragePages: 0) == 16,
               "memory used clamps impossible used memory")

        var vmStats = chikit_vm_statistics64_rev3_t()
        vmStats.wire_count = 2
        vmStats.purgeable_count = 3
        vmStats.compressor_page_count = 4
        vmStats.external_page_count = 5
        vmStats.internal_page_count = 6
        vmStats.total_tag_storage_pages = 7
        expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev1Count - 1) == nil,
               "VM statistics rejects a truncated legacy payload")
        expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev1Count) ==
                   VMStatisticsSnapshot(wiredPages: 2,
                                        purgeablePages: 3,
                                        compressorPages: 4,
                                        externalPages: 5,
                                        internalPages: 6,
                                        tagStoragePages: 0),
               "VM statistics decodes the typed legacy prefix")
        expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev2Count)?.tagStoragePages == 0,
               "VM statistics does not read tagged storage from a rev2 payload")
        expect(VMStatisticsDecoder.decode(vmStats,
                                          returnedCount: VMStatisticsDecoder.rev3Count)?.tagStoragePages == 7,
               "VM statistics reads tagged storage from a rev3 payload")
        expect(VMStatisticsDecoder.validatedTagStoragePages(2, totalBytes: 16, pageSize: 4) == 2,
               "VM statistics accepts plausible tagged storage")
        expect(VMStatisticsDecoder.validatedTagStoragePages(5, totalBytes: 16, pageSize: 4) == 0,
               "VM statistics rejects tagged storage larger than physical memory")
        expect(VMStatisticsDecoder.validatedTagStoragePages(1, totalBytes: 16, pageSize: 0) == 0,
               "VM statistics rejects tagged storage without a page size")

        // MARK: App memory

        let appUsed = MetricFormat.appMemory(totalBytes: 16 * 1024,
                                             pageSize: 1024,
                                             internalPages: 10,
                                             purgeablePages: 3)
        expect(appUsed == 7 * 1024, "app memory excludes purgeable pages from internal pages")
        expect(MetricFormat.appMemory(totalBytes: 16 * 1024, pageSize: 1024,
                                      internalPages: 2, purgeablePages: 5) == 0,
               "app memory is zero when purgeable pages exceed internal pages")
        expect(MetricFormat.appMemory(totalBytes: 16, pageSize: 1,
                                      internalPages: 100, purgeablePages: 0) == 16,
               "app memory clamps to total physical memory")
        expect(MetricFormat.appMemory(totalBytes: 0, pageSize: 1024,
                                      internalPages: 10, purgeablePages: 0) == 0,
               "app memory is zero when total is zero")
        expect(MetricFormat.appMemory(totalBytes: 16 * 1024, pageSize: 0,
                                      internalPages: 10, purgeablePages: 0) == 0,
               "app memory is zero when page size is zero")
        expect(MetricFormat.selectedMemory(used: 12, app: 7, metric: "app") == 7,
               "the shared memory selector returns app memory")
        expect(MetricFormat.selectedMemory(used: 12, app: 7, metric: "unknown") == 12,
               "an unknown shared memory selector falls back to used memory")

        expect(MetricFormat.compressedMemory(totalBytes: 16 * 1024, pageSize: 1024, compressorPages: 5)
               == 5 * 1024,
               "compressed memory is compressor pages in bytes")
        expect(MetricFormat.compressedMemory(totalBytes: 16, pageSize: 1, compressorPages: 100) == 16,
               "compressed memory clamps to total physical memory")
        expect(MetricFormat.compressedMemory(totalBytes: 0, pageSize: 1024, compressorPages: 5) == 0,
               "compressed memory is zero when total is zero")
        expect(MetricFormat.cachedFiles(totalBytes: 16 * 1024, pageSize: 1024, fileBackedPages: 3)
               == 3 * 1024,
               "cached files are file-backed pages in bytes")
        expect(MetricFormat.cachedFiles(totalBytes: 16, pageSize: 1, fileBackedPages: 100) == 16,
               "cached files clamp to total physical memory")
        expect(MetricFormat.cachedFiles(totalBytes: 16 * 1024, pageSize: 0, fileBackedPages: 3) == 0,
               "cached files are zero when page size is zero")

        // MARK: Registered defaults

        let registeredDefaults = Defaults.registeredDefaults
        expect(registeredDefaults[DefaultsKey.monitorMemoryMetric] as? String == "used",
               "monitor memory metric defaults to memory used")
        expect(Defaults.sanitizedMonitorMemoryMetric("app") == "app",
               "app is an allowed memory metric")
        expect(Defaults.sanitizedMonitorMemoryMetric("bogus") == "used",
               "unknown memory metric values fall back to used")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.monitorMemoryMetric),
               "monitor memory metric is included in settings backups")
        expect(registeredDefaults[DefaultsKey.appearance] as? String == AppAppearance.system.rawValue,
               "the app follows the system appearance until the user picks a side")
        expect(registeredDefaults[DefaultsKey.liquidGlassEnabled] as? Bool == false,
               "liquid glass appearance is opt-in")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.liquidGlassEnabled),
               "liquid glass appearance follows settings backups")
        expect(AppAppearance.sanitized(nil) == .system
                && AppAppearance.sanitized("nonsense") == .system,
               "an unknown stored appearance falls back to the system one")
        expect(AppAppearance.sanitized("dark") == .dark && AppAppearance.sanitized("light") == .light,
               "stored appearance values survive a relaunch")
        expect(AppAppearance.allCases.map(\.rawValue) == ["system", "light", "dark"],
               "appearance raw values are persisted keys and their order is the picker order")
        let sleepDisabledReport = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
        """
        let sleepEnabledReport = """
        System-wide power settings:
         SleepDisabled\t\t0
        Currently in use:
         standby              1
        """
        // The rule is granted by uid so every short name works, including the
        // email-style ones SSO enrollment produces (#915). The uid renders as
        // bare digits and the rest is a fixed literal, so the whole line must
        // stay inside a character set that neither sudoers nor a single-quoted
        // shell string can read as anything but itself.
        expect(SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [4], visibleSpaces: [3]),
               "a window whose only Space is not visible is parked on a hidden Space")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [3], visibleSpaces: [3]),
               "a window on the visible Space is not parked")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [], visibleSpaces: [3]),
               "a surface on no Space is a leftover, never a parked window")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [4], visibleSpaces: []),
               "an unreadable visible-Space set never claims a parked window")
        expect(!SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: [3, 4], visibleSpaces: [3]),
               "a window pinned to several Spaces including a visible one is reachable")
        expect(SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [4, 8], fullscreenSpaces: [8])
               && !SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [4], fullscreenSpaces: [8])
               && !SpaceHopSupport.isOnFullscreenSpace(windowSpaces: [], fullscreenSpaces: [8]),
               "App Switcher identifies fullscreen from Space type instead of window size")
        expect(SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: 1 << 18),
               "a window-server surface marked to ignore cycling is excluded from the switcher")
        expect(!SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: (1 << 19) | (1 << 22)),
               "other window-server tags do not hide a legitimate cross-Space window")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4, 5]],
                                          visibleSpaces: [3],
                                          target: 5) == 2,
               "space travel counts the presses to the right")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4, 5]],
                                          visibleSpaces: [5],
                                          target: 3) == -2,
               "space travel counts the presses to the left")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4]],
                                          visibleSpaces: [3],
                                          target: 3) == nil,
               "space travel is never suggested toward a visible Space")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4]],
                                          visibleSpaces: [3],
                                          target: 9) == nil,
               "space travel is never suggested toward an unknown Space")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [[3, 4], [8, 9]],
                                          visibleSpaces: [3, 8],
                                          target: 9) == 1,
               "space travel counts the presses on the target display when multiple displays exist")
        expect(SpaceHopSupport.arrowSteps(orderedSpacesPerDisplay: [(0...40).map { UInt64($0) }],
                                          visibleSpaces: [0],
                                          target: 40) == nil,
               "space travel refuses hops beyond the press cap")
        expect(SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: true) == .moveASpace,
               "an app with a window on the visible Space cannot travel by being activated, so the move is asked for right away")
        expect(SpaceHopSupport.firstStage(appHasWindowOnVisibleSpace: false) == .waitForActivationTravel,
               "an app with no window on the visible Space travels on activation, so that travel is waited on")
        expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x840000) == [.maskControl, .maskSecondaryFn],
               "the registered control+function mask replays with both flags")
        expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x20000 | 0x100000) == [.maskShift, .maskCommand],
               "shift and command translate independently")
        expect(SpaceHopSupport.eventFlags(fromCarbonModifiers: 0x80000) == [.maskAlternate],
               "option translates to the alternate flag")
        let regularBundlePaths: [pid_t: String] = [101: "/Applications/Primary.app"]
        let embeddedHostPIDs: [pid_t: pid_t] = [202: 101, 203: 101, 302: 301]
        // MARK: Hidden app windows (issue #656)
        // MARK: Stale surfaces without an Accessibility witness (issue #807)

        // MARK: Which display the switcher opens on
        let leftDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let rightDisplay = CGRect(x: 1920, y: 0, width: 1440, height: 900)
        // Window-server coordinates grow downward, so a display below the
        // menu bar display has a positive y origin. An AppKit frame for the
        // same window would carry a negative y and land on the wrong display.
        let upperDisplay = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let lowerDisplay = CGRect(x: 0, y: 1080, width: 1920, height: 1080)
        // MARK: Switcher entries for apps with no window (issue #351)
        expect(WindowUseOrder.promoting(target: 7, previous: 3, in: [3, 5, 7]) == [7, 3, 5],
               "committing to a window puts it first and the one left behind second")
        expect(WindowUseOrder.promoting(target: nil, previous: 3, in: [5, 3, 9]) == [3, 5, 9],
               "committing to an app with no window leaves the window behind as the most recent one")
        expect(WindowUseOrder.promoting(target: nil, previous: nil, in: [5, 3]) == [5, 3],
               "committing to an app with no window and coming from none changes no history")
        // A card is dragged for the same reason whatever state its window is in:
        // the user wants that window here. Minimized and parked-on-another-Space
        // used to refuse the gesture, which read as the drag doing nothing --
        // releasing then counted as a click and the window went back to its own
        // old place instead of the drop point.
        // The preview size setting sizes the thumbnail, not the writing around
        // it. Both halves of that are checked across every size on offer: the
        // picture tracks the setting exactly, and the chrome does not move at
        // all — a title band that scaled with the card once left a 12pt line
        // adrift in 31pt of nothing at the largest setting.
        let previewScales = Defaults.allowedPreviewSizes.map { PreviewSizing.scale(for: $0) }
        expect(previewScales.count == 4 && previewScales.contains(1.0),
               "every preview size on offer has a scale, including the unscaled one")
        expect(registeredDefaults[DefaultsKey.autoCheckUpdates] as? Bool == true,
               "update checks are on for clean installs")
        expect(registeredDefaults[DefaultsKey.updateShowcaseIntroVersion] as? String == "",
               "update showcase intro starts unseen")
        expect(registeredDefaults[DefaultsKey.updateShowcaseMediaOverride] as? String == "",
               "update showcase media override is empty by default")
        expect(SupportUpdateIntroInfo.releaseVersion == "3.3.2",
               "support prompt is deliberately pinned to 3.3.2")
        expect(SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.1"),
               "support prompt shows once after updating to its pinned release")
        expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.2"),
               "support prompt stays hidden after it is seen")
        expect(!SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.0", lastSeenVersion: nil)
               && !SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.1", lastSeenVersion: nil)
               && !SupportUpdateIntroInfo.shouldShow(appVersion: "3.3.3", lastSeenVersion: nil),
               "support prompt never leaks into another release")
        expect(SupportUpdateIntroStep.discord.next == .social
               && SupportUpdateIntroStep.social.next == .support
               && SupportUpdateIntroStep.support.next == nil,
               "update intro moves from Discord to social updates and support")
        expect(SupportUpdateIntroStep.discord.previous == nil
               && SupportUpdateIntroStep.social.previous == .discord
               && SupportUpdateIntroStep.support.previous == .social,
               "update intro navigates back without closing")
        expect(SupportUpdateIntroStep.allCases == [.discord, .social, .support],
               "update intro page indicators follow the navigation order")
        expect(AppInfo.discordURL.absoluteString == "https://discord.gg/M6BwWH4BJp",
               "the community action uses the permanent Discord invitation")
        expect(AppInfo.coffeeURL.absoluteString == "https://buymeacoffee.com/vorssaint",
               "financial support uses Buy Me a Coffee")
        expect(AppInfo.socialURL.absoluteString == "https://x.com/vorssaint",
               "social previews keep the official X profile")
        // AppInfo.version falls back to "dev" in this bare harness, so read
        // the plist the shipped app will actually carry. The pin is a
        // per-release decision: this check fails on every version bump so the
        // decision above is made consciously, never by omission.
        let releasePlist = NSDictionary(contentsOfFile: "Resources/Info.plist")
        let plistVersion = (releasePlist?["CFBundleShortVersionString"] as? String) ?? ""
        expect(plistVersion == "3.3.3-beta.3",
               "bumping the app version requires re-deciding the support prompt pin above")
        let plistBuild = (releasePlist?["CFBundleVersion"] as? String) ?? ""
        expect(plistBuild == "82",
               "every app version needs its own incremented bundle build")
        expect(SupportUpdateIntroInfo.releaseVersion == "3.3.2",
               "the support prompt remains deliberately pinned to 3.3.2")
        // 3.3.2 adds several headline features, so the tour is re-curated
        // around only what this update genuinely introduces.
        expect(UpdateHighlightsInfo.releaseVersion == "3.3.2",
               "re-decide the highlights tour on a feature release: re-curate its rows and move the pin to the shipping version")
        expect(UpdateHighlightsInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.1")
               && UpdateHighlightsInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: nil),
               "highlights tour shows once after updating to its pinned release")
        expect(!UpdateHighlightsInfo.shouldShow(appVersion: "3.3.2", lastSeenVersion: "3.3.2"),
               "highlights tour stays hidden after it is seen")
        expect(!UpdateHighlightsInfo.shouldShow(appVersion: "3.3.1", lastSeenVersion: nil)
               && !UpdateHighlightsInfo.shouldShow(appVersion: "3.3.3", lastSeenVersion: nil),
               "highlights tour never leaks into another release")
        expect(FileManager.default.fileExists(atPath: "Resources/Images/highlights-capture.png")
               && FileManager.default.fileExists(atPath: "Resources/Images/highlights-clipboard.png"),
               "3.3.2 highlights tour includes curated real captures for screenshot palette and clipboard")
        expect(registeredDefaults[DefaultsKey.mixerLowerVolumeOnHeadphonesDisconnect] as? Bool == false,
               "headphone disconnect volume lowering is opt-in")
        expect(registeredDefaults[DefaultsKey.mixerHeadphonesDisconnectVolumePercent] as? Int
               == Defaults.defaultMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect protection starts at an audible volume, never at silence")
        expect(Defaults.defaultMixerHeadphonesDisconnectVolumePercent
               >= Defaults.minimumMixerHeadphonesDisconnectVolumePercent
               && Defaults.defaultMixerHeadphonesDisconnectVolumePercent < 100,
               "the headphone disconnect default is a real reduction that can still be heard")
        expect(registeredDefaults[DefaultsKey.mixerShowFinder] as? Bool == true,
               "Finder returns to the mixer by default")
        expect(registeredDefaults[DefaultsKey.mixerHideInactiveApps] as? Bool == false,
               "inactive mixer apps remain visible by default")
        expect(registeredDefaults[DefaultsKey.soundOutputSwitcherEnabled] as? Bool == false,
               "sound output switcher is opt-in")
        expect(registeredDefaults[DefaultsKey.soundOutputSwitcherShortcut] as? String
               == GlobalShortcut.soundOutputSwitcherDefault.storageValue,
               "sound output switcher shortcut has a registered default")
        expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcutEnabled] as? Bool == true,
               "clipboard history shortcut is ready when clipboard history is enabled")
        expect(registeredDefaults[DefaultsKey.clipboardHistoryShortcut] as? String
               == GlobalShortcut.clipboardDefault.storageValue,
               "clipboard history shortcut defaults to Ctrl+Opt+Cmd+V")
        expect(registeredDefaults[DefaultsKey.finderRenameEnabled] as? Bool == false,
               "the Finder rename shortcut is opt-in")
        expect(registeredDefaults[DefaultsKey.finderRenameShortcut] as? String == ":120",
               "the Finder rename shortcut starts on bare F2")
        expect(GlobalShortcut(keyCode: Int64(kVK_ANSI_V), modifiers: [.command])
                   .isStandardPasteCommand,
               "Cmd+V is recognized when plain-text paste must release its own hotkey")
        expect(!GlobalShortcut(keyCode: Int64(kVK_ANSI_C), modifiers: [.command])
                   .isStandardPasteCommand,
               "other Command shortcuts never release the plain-text paste hotkey")
        expect(registeredDefaults[DefaultsKey.panelUtilityCleaning] as? Bool == true,
               "panel cleaning utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityURLCleaner] as? Bool == true,
               "panel URL cleaner utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityUninstaller] as? Bool == true,
               "panel uninstaller utility is visible by default")
        expect(registeredDefaults[DefaultsKey.panelUtilityConverter] as? Bool == true,
               "panel converter utility is visible by default")
        // File converter
        expect(ConvertKind.kind(forExtension: "XLSX") == .spreadsheet
               && ConvertKind.kind(forExtension: "mkv") == .video
               && ConvertKind.kind(forExtension: "pdf") == .pdf
               && ConvertKind.kind(forExtension: "xyz") == nil,
               "the converter classifies files by extension")
        let xlsxTargets = ConvertFormats.targets(forExtension: "xlsx", libreOfficeAvailable: false).map(\.id)
        expect(xlsxTargets == ["sheet-csv", "sheet-tsv", "sheet-txt"],
               "XLSX converts to text natively when LibreOffice is missing, got \(xlsxTargets)")
        expect(ConvertFormats.targets(forExtension: "xls", libreOfficeAvailable: false).isEmpty,
               "legacy Excel needs LibreOffice")
        expect(ConvertFormats.targets(forExtension: "xlsx", libreOfficeAvailable: true).map(\.id).contains("sheet-pdf"),
               "XLSX offers PDF through LibreOffice")
        expect(!ConvertFormats.targets(forExtension: "csv", libreOfficeAvailable: true).map(\.id).contains("sheet-csv"),
               "a format is never offered as its own target")
        expect(ConvertFormats.commonTargets(for: [URL(fileURLWithPath: "/a.mp4"), URL(fileURLWithPath: "/b.wav")],
                                            libreOfficeAvailable: false).map(\.id).contains("mp3"),
               "video and audio mix on the audio formats")
        expect(ConvertFormats.commonTargets(for: [URL(fileURLWithPath: "/a.png"), URL(fileURLWithPath: "/b.mp4")],
                                            libreOfficeAvailable: true).isEmpty,
               "images and video share no target")
        expect(ConverterSupport.uniqueURL(directory: URL(fileURLWithPath: "/t"), baseName: "song", ext: "mp3",
                                          exists: { $0.lastPathComponent != "song 3.mp3" }).lastPathComponent == "song 3.mp3",
               "converted files never overwrite existing ones")
        expectEqual(ConverterSupport.delimited([["a", "b,c"], ["say \"hi\"", ""]], delimiter: ","),
                    "a,\"b,c\"\n\"say \"\"hi\"\"\",\n", "CSV quoting")
        expect(ConverterSupport.columnIndex(fromReference: "A1") == 0
               && ConverterSupport.columnIndex(fromReference: "AB12") == 27,
               "spreadsheet column references map to indexes")
        expectEqual(ConverterSupport.isoString(fromExcelSerial: 44927) ?? "", "2023-01-01", "Excel serial date")
        expectEqual(ConverterSupport.isoString(fromExcelSerial: 44927.5) ?? "", "2023-01-01 12:00:00", "Excel serial date-time")
        expect(ConverterSupport.isDateFormatCode("yyyy-mm-dd") && ConverterSupport.isDateFormatCode("[$-409]d-mmm;@")
               && !ConverterSupport.isDateFormatCode("0.00") && !ConverterSupport.isDateFormatCode("\"day\"0"),
               "date number formats are told apart from numeric ones")
        expect(registeredDefaults[DefaultsKey.panelUtilityMedia] as? Bool == true,
               "panel Media utility is visible by default")
        expect(registeredDefaults[DefaultsKey.menuBarMetricSpacing] as? String == "compact",
               "menu bar metric spacing defaults to the compact look")
        expect(registeredDefaults[DefaultsKey.menuBarMetricAppearance] as? String == "values",
               "menu bar usage metrics keep numeric values by default")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarNormalColor] as? String == "#64D2FF",
               "menu bar bars use a bright normal color by default")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarElevatedColor] as? String == "#FFD60A"
               && registeredDefaults[DefaultsKey.menuBarUsageBarCriticalColor] as? String == "#FF453A",
               "menu bar bars keep visible elevated and critical defaults")
        expect(registeredDefaults[DefaultsKey.menuBarUsageBarMediumThreshold] as? Int == 70
               && registeredDefaults[DefaultsKey.menuBarUsageBarHighThreshold] as? Int == 90,
               "menu bar bar thresholds default to seventy and ninety percent")
        expect(Defaults.sanitizedMonitorAlertCooldown(2) == 2,
               "the two minute alert cooldown is a valid stored choice")
        expect(Defaults.sanitizedMonitorAlertCooldown(7) == 15,
               "unknown alert cooldowns fall back to fifteen minutes")
        expect(registeredDefaults[DefaultsKey.monitorAlertBatteryTemperature] as? Bool == false,
               "battery temperature alerts are opt-in")
        expect(registeredDefaults[DefaultsKey.monitorAlertBatteryTemperatureThreshold] as? Int == 40,
               "battery temperature alerts default to forty degrees")
        expect(Defaults.sanitizedMenuBarMetricSpacing("standard") == "standard",
               "standard menu bar spacing is a valid stored choice")
        expect(Defaults.sanitizedMenuBarMetricSpacing("banana") == "compact",
               "unknown menu bar spacing values fall back to the compact default")
        expect(Defaults.sanitizedMenuBarMetricAppearance("bars") == "bars",
               "bar appearance is a valid stored choice")
        expect(Defaults.sanitizedMenuBarMetricAppearance("banana") == "values",
               "unknown menu bar appearances fall back to numeric values")
        expect(MenuBarMetricAppearance.values.allowsCombinedTemperatures,
               "numeric menu bar values may combine usage and temperature")
        expect(!MenuBarMetricAppearance.bars.allowsCombinedTemperatures,
               "menu bar bars keep usage and temperature separate")
        expectClose(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 4) ?? -1, 0.75,
                    "menu bar memory bars use the current used fraction")
        expect(MenuBarUsageBarSupport.memoryFraction(used: 3, total: 0) == nil,
               "menu bar memory bars keep missing totals unavailable")
        expectClose(MenuBarUsageBarSupport.clampedFraction(-0.2), 0,
                    "menu bar bars clamp negative readings")
        expectClose(MenuBarUsageBarSupport.clampedFraction(1.4), 1,
                    "menu bar bars clamp readings above full")
        expect(MenuBarUsageBarSupport.fillLevel(for: 0.5, steps: 16) == 8,
               "menu bar bars quantize fractions to visible fill steps")
        expect(MenuBarUsageBarSupport.level(for: 0.69) == .normal,
               "menu bar usage stays blue below seventy percent")
        expect(MenuBarUsageBarSupport.level(for: 0.70) == .elevated,
               "menu bar usage turns yellow at seventy percent")
        expect(MenuBarUsageBarSupport.level(for: 0.89) == .elevated,
               "menu bar usage stays yellow below ninety percent")
        expect(MenuBarUsageBarSupport.level(for: 0.90) == .critical,
               "menu bar usage turns red at ninety percent")
        expect(MenuBarUsageBarSupport.level(for: 0.50,
                                            mediumPercent: 40,
                                            highPercent: 80) == .elevated,
               "custom menu bar medium thresholds change the bar level")
        expect(MenuBarUsageBarSupport.level(for: 0.80,
                                            mediumPercent: 40,
                                            highPercent: 80) == .critical,
               "custom menu bar high thresholds change the bar level")
        let repairedBarThresholds = MenuBarUsageBarSupport.thresholds(medium: 100, high: 20)
        expect(repairedBarThresholds.medium == 99 && repairedBarThresholds.high == 100,
               "invalid menu bar thresholds keep medium below high")
        expect(MenuBarUsageBarSupport.sanitizedColorHex(" 64d2ff ", fallback: "#000000") == "#64D2FF",
               "menu bar colors normalize stored hex values")
        expect(MenuBarUsageBarSupport.sanitizedColorHex("bad", fallback: "#FFD60A") == "#FFD60A",
               "invalid menu bar colors use their visible fallback")
        let customBarRGB = MenuBarUsageBarSupport.rgb(for: "#804020", fallback: "#000000")
        expectClose(customBarRGB.red, 128.0 / 255.0, "menu bar color parses red")
        expectClose(customBarRGB.green, 64.0 / 255.0, "menu bar color parses green")
        expectClose(customBarRGB.blue, 32.0 / 255.0, "menu bar color parses blue")
        expect(MenuBarUsageBarSupport.hex(red: 1, green: 0.5, blue: 0) == "#FF8000",
               "menu bar color picker writes stable hex values")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%") == "88%",
               "compact spacing reserves the current digit count for percentages")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "999°") == "888°",
               "compact spacing reserves the current digit count for temperatures")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "1.5M") == "8.8M",
               "compact spacing keeps units and separators while widening digits")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "") == "",
               "compact spacing reserve of an empty value stays empty")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "4%", minimumDigits: 2) == "88%",
               "compact spacing pads single digits up to the stability floor")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "14%", minimumDigits: 2) == "88%",
               "a one and a two digit value reserve the same width, so 4% to 10% never moves the bar")
        expect(MenuBarSpacingSupport.digitMatchedReserve(for: "100%", minimumDigits: 2) == "888%",
               "values above the floor keep their own digit count")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 1, highWater: nil) == 2,
               "the compact floor starts at two digits")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 3, highWater: 2) == 3,
               "a three digit value raises the floor")
        expect(MenuBarSpacingSupport.compactFloor(currentDigits: 2, highWater: 3) == 3,
               "the session high-water mark keeps a block from shrinking back and wobbling")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .standard) == " ",
               "standard dense spacing keeps the full space between blocks")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: false, spacing: .compact) == "\u{200A}",
               "compact dense spacing joins blocks with a hair space")
        expect(MenuBarSpacingSupport.blockGlue(readableStyle: true, spacing: .compact) == " ",
               "compact readable spacing tightens the double space to a single one")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1135, reportedMidX: 1452, buttonWidth: 38) == -317,
               "a click far left of the status item's reported frame re-anchors the panel at the click")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1452, reportedMidX: 1135, buttonWidth: 38) == 317,
               "a click far right of the status item's reported frame re-anchors the panel at the click")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1150, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a click inside the status button never counts as drift")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1186, reportedMidX: 1144, buttonWidth: 38) == nil,
               "a sloppy click just past the button edge stays within the drift slack")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1188, reportedMidX: 1144, buttonWidth: 38) == 44,
               "a click beyond the slack re-anchors by the full offset")
        expect(StatusItemAnchorSupport.anchorDriftX(clickX: 1240, reportedMidX: 1144, buttonWidth: 197) == nil,
               "clicks near the edge of a wide metrics item stay anchored to the item")

        // The built-in display and a taller one placed to its left.
        let builtInScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let secondScreen = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let attachedScreens = [builtInScreen, secondScreen]
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 932, width: 0, height: 0),
                                                                 screenFrames: attachedScreens),
               "a status item frame with no size is never an anchor")
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 950, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a status item parked above the top edge is not an anchor")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 919, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "a status item sitting in the menu bar band is a trustworthy anchor")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: -1000, y: 1143, width: 38, height: 37),
                                                                screenFrames: attachedScreens),
               "the menu bar band follows each screen's own top edge")
        expect(!StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 0, width: 38, height: 37),
                                                                 screenFrames: attachedScreens),
               "a frame down at the bottom of a screen is not a menu bar item")

        // A screen showing a fullscreen window reserves no menu bar: its
        // visible area is the whole frame. The band is a fixed thickness off
        // the screen's own top edge, so an item revealed on hover still counts;
        // a band measured as `frame.maxY - visibleFrame.maxY` would collapse to
        // nothing here and decline the icon while it is visible and clickable.
        let fullscreenScreen = CGRect(x: 0, y: 0, width: 1470, height: 956)
        let fullscreenVisibleFrame = fullscreenScreen
        expect(StatusItemAnchorSupport.menuBarBand > fullscreenScreen.maxY - fullscreenVisibleFrame.maxY,
               "the menu bar band does not shrink to what a fullscreen screen reserves")
        expect(StatusItemAnchorSupport.isTrustworthyStatusFrame(CGRect(x: 1135, y: 919, width: 38, height: 37),
                                                                screenFrames: [fullscreenScreen]),
               "a status item revealed over a fullscreen window is a trustworthy anchor")

        // These AppKit owners are not part of the pure-helper test binary, so
        // pin that neither caller can consume a parked status-item frame.
        let statusAnchorAppDelegateSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift",
            encoding: .utf8)) ?? ""
        let stripCommentLines: (String) -> String = {
            $0.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
        }
        let statusControllerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/StatusItemController.swift",
            encoding: .utf8)) ?? ""
        let statusHitTestCode = stripCommentLines((statusControllerSource
            .components(separatedBy: "func containsStatusItem(at screenPoint: NSPoint) -> Bool {").last ?? "")
            .components(separatedBy: "\n    }").first ?? "")
        let statusFrameCall = "StatusItemAnchorSupport.isTrustworthyStatusFrame("
        expect(statusHitTestCode.contains(statusFrameCall) && statusHitTestCode.contains("return false"),
               "status-item hit testing rejects an untrustworthy frame")

        // The panel keeps its top edge and its center while its content resizes.
        let panelArea = CGRect(x: 0, y: 0, width: 1470, height: 932)
        let shortPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                  anchorMidX: 1283, anchorTop: 932,
                                                                  visibleFrame: panelArea)
        let tallPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                                 anchorMidX: 1283, anchorTop: 932,
                                                                 visibleFrame: panelArea)
        let shrunkPanel = StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                                   anchorMidX: 1283, anchorTop: 932,
                                                                   visibleFrame: panelArea)
        expect(shortPanel.midX == 1283 && tallPanel.midX == 1283 && shrunkPanel.midX == 1283,
               "the pinned panel stays centered on its anchor through a content resize")
        expect(shortPanel.maxY == 932 && tallPanel.maxY == 932 && shrunkPanel.maxY == 932,
               "a taller panel grows downward instead of moving its top edge")
        expect(shortPanel == shrunkPanel,
               "going back to the first tab lands the panel exactly where it started")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 20, anchorTop: 932,
                                                        visibleFrame: panelArea).minX == 8,
               "a panel anchored past the left edge stops at the margin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: 1465, anchorTop: 932,
                                                        visibleFrame: panelArea).maxX == 1462,
               "a panel anchored past the right edge stops at the margin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 375),
                                                        anchorMidX: -1910, anchorTop: 1155,
                                                        visibleFrame: CGRect(x: -1920, y: 100,
                                                                             width: 1920, height: 1055))
                == CGRect(x: -1912, y: 780, width: 332, height: 375),
               "a display left of the built-in one clamps against its own negative origin")
        expect(StatusItemAnchorSupport.pinnedPanelFrame(size: CGSize(width: 332, height: 633),
                                                        anchorMidX: 700, anchorTop: 300,
                                                        visibleFrame: CGRect(x: 0, y: 0,
                                                                             width: 1470, height: 300)).maxY == 300,
               "a screen too short for the panel still shows its top")
        expect(registeredDefaults[DefaultsKey.menuBarHideIconWithMetrics] as? Bool == false,
               "the menu bar icon stays visible by default")
        expect(MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                          metricsEnabled: true, renderedTitleLength: 12,
                                                          mustShowForSignal: false),
               "the glyph hides when metrics render in the title and the option is on")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: false, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: false),
               "the glyph never hides while the option is off")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 0,
                                                           mustShowForSignal: false),
               "an empty rendered title keeps the glyph, so the item can never turn invisible")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: false, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "a countdown-only title keeps the glyph when no metric is enabled")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: true,
                                                           metricsEnabled: true, renderedTitleLength: 6,
                                                           mustShowForSignal: false),
               "separate metric items keep the glyph in the otherwise empty main item")
        expect(!MenuBarSpacingSupport.shouldHideStatusIcon(optionEnabled: true, separateMetrics: false,
                                                           metricsEnabled: true, renderedTitleLength: 12,
                                                           mustShowForSignal: true),
               "an available update or muted mic brings the glyph back to carry the signal")
        expect(MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                              metricItemsShown: 2, renderedTitleLength: 0,
                                                              mustShowForSignal: false),
               "with separate metric items installed the whole main item may step aside")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 0, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "no installed metric items keep the main item, so the app never vanishes")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 5,
                                                               mustShowForSignal: false),
               "an active countdown renders in the main item and keeps it visible")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: false,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: false),
               "the whole-item hiding only applies to the separate-items mode")

        // A pinned metric that momentarily has nothing to show keeps its item
        // instead of being taken away and put back every tick.
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: false),
               "a metric with something to show gets its own item")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: true,
                                                           consecutiveEmptyRenders: 1),
               "a reading that goes missing for a tick blanks its item instead of removing it")
        expect(!MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: false, itemExists: true,
            consecutiveEmptyRenders: MenuBarSpacingSupport.emptyMetricRendersBeforeRemoval),
               "a reading that stops for good takes its item away instead of leaving a gap")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(
            hasRenderedTitle: true, itemExists: true,
            consecutiveEmptyRenders: 99),
               "a reading that comes back keeps its item whatever came before")
        expect(!MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: false, itemExists: false),
               "a metric with nothing to show yet gets no item at all")
        expect(MenuBarSpacingSupport.keepsMetricStatusItem(hasRenderedTitle: true, itemExists: true),
               "an item already showing a reading stays")
        expect(!MenuBarSpacingSupport.shouldHideMainStatusItem(optionEnabled: true, separateMetrics: true,
                                                               metricItemsShown: 2, renderedTitleLength: 0,
                                                               mustShowForSignal: true),
               "a signal brings the main item back even in the separate-items mode")
        expect(MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                            showsCountdown: true,
                                                            hasEndDate: true),
               "a visible finite Keep Awake countdown owns the title timer")
        expect(!MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: false,
                                                             showsCountdown: true,
                                                             hasEndDate: true)
                && !MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                                  showsCountdown: false,
                                                                  hasEndDate: true)
                && !MenuBarSpacingSupport.needsTitleRefreshTimer(keepAwakeActive: true,
                                                                  showsCountdown: true,
                                                                  hasEndDate: false),
               "idle, hidden and indefinite Keep Awake titles need no timer")
        let statusPlacementSuite = "com.chikit.tests.statusItemPlacement"
        if let statusDefaults = UserDefaults(suiteName: statusPlacementSuite) {
            statusDefaults.removePersistentDomain(forName: statusPlacementSuite)
            expect(StatusItemPlacementSupport.placementGeneration(in: statusDefaults) == 0,
                   "initial placement generation is 0")
            expect(StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults) == "ChikitMenuBarItem",
                   "generation 0 uses base autosave name")

            let legacyKey = "NSStatusItem Preferred Position ChikitMenuBarItem"
            statusDefaults.set(64.0, forKey: legacyKey)
            StatusItemPlacementSupport.sanitizeStalePlacement(in: statusDefaults)
            expect(statusDefaults.object(forKey: legacyKey) == nil,
                   "sanitizeStalePlacement removes the buggy 64.0 system-colliding offset")

            statusDefaults.set(320.5, forKey: legacyKey)
            StatusItemPlacementSupport.sanitizeStalePlacement(in: statusDefaults)
            expect(statusDefaults.double(forKey: legacyKey) == 320.5,
                   "sanitizeStalePlacement preserves legitimate user-arranged coordinates")

            StatusItemPlacementSupport.bumpPlacementGeneration(in: statusDefaults)
            let gen1Name = StatusItemPlacementSupport.mainAutosaveName(in: statusDefaults)
            expect(gen1Name == "ChikitMenuBarItem.1",
                   "bumped generation produces numbered autosave name")
            expect(statusDefaults.object(forKey: "NSStatusItem Preferred Position ChikitMenuBarItem.1") == nil,
                   "bumpPlacementGeneration does not seed any hardcoded preferred position")
            statusDefaults.removePersistentDomain(forName: statusPlacementSuite)
        }
        expect(registeredDefaults[DefaultsKey.panelControlAutoQuit] as? Bool == true,
               "panel auto quit control is visible by default")
        expect(registeredDefaults[DefaultsKey.panelShowUtilities] as? Bool == true,
               "Utilities panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowControls] as? Bool == true,
               "Quick Controls panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.panelShowToggles] as? Bool == true,
               "Quick toggles panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorInterval] as? Int == 2,
               "monitor default interval stays at 2 seconds")
        expect(registeredDefaults[DefaultsKey.monitorShowDisk] as? Bool == true,
               "disk monitor panel section is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorSysAlerts] as? Bool == true,
               "system alert controls are shown by default")
        expect(registeredDefaults[DefaultsKey.monitorGraphDisk] as? Bool == true,
               "disk monitor graph is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorNetApps] as? Bool == true,
               "network app usage block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskUsage] as? Bool == true,
               "disk usage block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskActivity] as? Bool == true,
               "disk activity block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskSMART] as? Bool == true,
               "disk SMART block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskProtection] as? Bool == true,
               "disk protection block is shown by default")
        expect(registeredDefaults[DefaultsKey.monitorDiskTools] as? Bool == true,
               "disk tools block is shown by default")
        expect(registeredDefaults[DefaultsKey.temperatureUnit] as? String == TemperatureUnit.celsius.rawValue,
               "temperature defaults to Celsius")
        expect(registeredDefaults[DefaultsKey.menuBarCPUTemperature] as? Bool == false,
               "menu bar CPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarGPUTemperature] as? Bool == false,
               "menu bar GPU temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarBatteryTemperature] as? Bool == false,
               "menu bar battery temperature is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarBatteryTime] as? Bool == false,
               "menu bar battery time is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarDiskUsage] as? Bool == false,
               "menu bar disk usage is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarDiskActivity] as? Bool == false,
               "menu bar disk activity is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarPeripheralBattery] as? Bool == false,
               "menu bar peripheral battery is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarFanSpeed] as? Bool == false,
               "menu bar fan speed is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarMetricOrder] as? String
               == "cpu,cpuTemperature,gpu,gpuTemperature,memory,battery,batteryTime,batteryTemperature,peripheralBattery,network,diskUsage,diskActivity,power,fanSpeed",
               "menu bar metric order keeps temperature sensors next to their components and disk near live I/O")
        expect(registeredDefaults[DefaultsKey.menuBarCombineTemperatures] as? Bool == true,
               "menu bar combines usage and temperature by default")
        expect(registeredDefaults[DefaultsKey.menuBarSeparateMetrics] as? Bool == false,
               "separate menu bar metric items are opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarNetworkUploadFirst] as? Bool == false,
               "network menu bar upload-first layout is opt-in")
        expect(registeredDefaults[DefaultsKey.menuBarLabelStyle] as? String == "compact",
               "menu bar label style defaults to compact")
        expect(registeredDefaults[DefaultsKey.menuBarMemoryStyle] as? String == "percent",
               "memory menu bar style defaults to percent")
        expect(registeredDefaults[DefaultsKey.monitorPwrTimeRemaining] as? Bool == true,
               "battery time is shown in the Power panel by default")
        expect(registeredDefaults[DefaultsKey.windowLayoutShortcutsEnabled] as? Bool == true,
               "window layout shortcuts (Rectangle's Control-Option set) are on by default")
        expect(registeredDefaults[DefaultsKey.windowEdgeSnapEnabled] as? Bool == false,
               "dragging windows to screen edges is opt-in")
        expect(registeredDefaults[DefaultsKey.windowGestureEnabled] as? Bool == false,
               "window move and resize gestures are opt-in")
        expect(registeredDefaults[DefaultsKey.windowGestureModifiers] as? String == "control+command",
               "window gestures start with the deliberate control-command chord")
        expect(registeredDefaults[DefaultsKey.windowGestureRaiseWindow] as? Bool == false,
               "window gestures do not change app focus unless requested")
        let assignedLayoutShortcutKeys = [
            DefaultsKey.windowLayoutShortcutLeft,
            DefaultsKey.windowLayoutShortcutRight,
            DefaultsKey.windowLayoutShortcutTop,
            DefaultsKey.windowLayoutShortcutBottom,
            DefaultsKey.windowLayoutShortcutTopLeft,
            DefaultsKey.windowLayoutShortcutTopRight,
            DefaultsKey.windowLayoutShortcutBottomLeft,
            DefaultsKey.windowLayoutShortcutBottomRight,
            DefaultsKey.windowLayoutShortcutMaximize,
            DefaultsKey.windowLayoutShortcutCenter,
            DefaultsKey.windowLayoutShortcutRestore,
            DefaultsKey.windowLayoutShortcutLeftThird,
            DefaultsKey.windowLayoutShortcutCenterThird,
            DefaultsKey.windowLayoutShortcutRightThird,
            DefaultsKey.windowLayoutShortcutLeftTwoThirds,
            DefaultsKey.windowLayoutShortcutRightTwoThirds,
            DefaultsKey.windowLayoutShortcutNextDisplay,
        ]
        let assignedLayoutShortcutValues = assignedLayoutShortcutKeys.compactMap {
            registeredDefaults[$0] as? String
        }
        expect(assignedLayoutShortcutValues.count == assignedLayoutShortcutKeys.count,
               "every established window layout action has a registered shortcut")
        let unassignedLayoutShortcutKeys = [
            DefaultsKey.windowLayoutShortcutTopLeftSixth,
            DefaultsKey.windowLayoutShortcutTopCenterSixth,
            DefaultsKey.windowLayoutShortcutTopRightSixth,
            DefaultsKey.windowLayoutShortcutBottomLeftSixth,
            DefaultsKey.windowLayoutShortcutBottomCenterSixth,
            DefaultsKey.windowLayoutShortcutBottomRightSixth,
            DefaultsKey.windowLayoutShortcutPreviousDisplay,
            DefaultsKey.windowLayoutShortcutMarginMaximize,
        ]
        expect(unassignedLayoutShortcutKeys.allSatisfy {
                   registeredDefaults[$0] as? String == WindowLayoutAction.clearedShortcutStorageValue
               },
               "new window layout shortcuts start unassigned")
        expect(Set(assignedLayoutShortcutValues).count == assignedLayoutShortcutValues.count,
               "window layout shortcuts do not conflict with each other by default")
        let globalShortcutValues = GlobalShortcutRole.allCases
            .compactMap { registeredDefaults[$0.storageKey] as? String }
        expect(Set(assignedLayoutShortcutValues).intersection(globalShortcutValues).isEmpty,
               "window layout shortcuts do not conflict with other global shortcuts by default")
        // Two features shipping the same combination means one of them is dead
        // on arrival: the second registration is simply refused by the system,
        // and which one loses depends on the order they happen to sync in.
        expect(Set(globalShortcutValues).count == globalShortcutValues.count,
               "no two features ship the same default combination")
        expect(globalShortcutValues.count == GlobalShortcutRole.allCases.count,
               "every role ships with a default combination registered")
        expect(GlobalShortcut(keyCode: Int64(kVK_ISO_Section),
                              modifiers: [.control, .option, .command]).isValid,
               "the extra ISO key (paragraph/caret above Tab) is recordable as a shortcut")
        GlobalShortcut.startObservingKeyboardLayout()
        GlobalShortcut.refreshLayoutLabels()
        let backgroundISOKeyIsValid = DispatchQueue.global().sync {
            GlobalShortcut(keyCode: Int64(kVK_ISO_Section),
                           modifiers: [.control, .option, .command]).isValid
        }
        expect(backgroundISOKeyIsValid,
               "layout-dependent shortcut labels are safe to read off the main thread")
        let shortcutM = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: [.control, .option, .command])
        let shortcutSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: [.control, .option, .command])
        expect(shortcutM.isValid && !shortcutM.displayString.isEmpty,
               "letter shortcuts resolve valid caps on the active keyboard layout")
        expect(shortcutSemi.isValid && !shortcutSemi.displayString.isEmpty,
               "punctuation and layout-specific keys resolve valid caps on the active keyboard layout")

        // Multi-layout dynamic keycap resolution tests
        let layoutTestModifiers: GlobalShortcutModifiers = [.control, .option, .command]
        let layoutDict = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        let allLayoutSources = (TISCreateInputSourceList(layoutDict, true)?.takeRetainedValue() as? [TISInputSource]) ?? []
        func testLayoutData(for idString: String) -> Data? {
            guard let src = allLayoutSources.first(where: {
                guard let id = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
                let str = Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
                return str == idString
            }), let ptr = TISGetInputSourceProperty(src, kTISPropertyUnicodeKeyLayoutData) else {
                return nil
            }
            return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        }

        if let frenchData = testLayoutData(for: "com.apple.keylayout.French") {
            GlobalShortcut.refreshLayoutLabels(layoutData: frenchData)
            let frenchM = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            let frenchComma = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers)
            let frenchA = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: layoutTestModifiers)
            let frenchQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_A), modifiers: layoutTestModifiers)
            let frenchZ = GlobalShortcut(keyCode: Int64(kVK_ANSI_W), modifiers: layoutTestModifiers)
            let frenchW = GlobalShortcut(keyCode: Int64(kVK_ANSI_Z), modifiers: layoutTestModifiers)
            expectEqual(frenchM.displayString, "⌃⌥⌘M", "French AZERTY resolves physical semicolon key as M")
            expectEqual(frenchComma.displayString, "⌃⌥⌘ ,", "French AZERTY resolves physical M key as comma")
            expectEqual(frenchA.displayString, "⌃⌥⌘A", "French AZERTY resolves physical Q key as A")
            expectEqual(frenchQ.displayString, "⌃⌥⌘Q", "French AZERTY resolves physical A key as Q")
            expectEqual(frenchZ.displayString, "⌃⌥⌘Z", "French AZERTY resolves physical W key as Z")
            expectEqual(frenchW.displayString, "⌃⌥⌘W", "French AZERTY resolves physical Z key as W")
        }

        if let germanData = testLayoutData(for: "com.apple.keylayout.German") {
            GlobalShortcut.refreshLayoutLabels(layoutData: germanData)
            let germanZ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Y), modifiers: layoutTestModifiers)
            let germanY = GlobalShortcut(keyCode: Int64(kVK_ANSI_Z), modifiers: layoutTestModifiers)
            let germanOuml = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(germanZ.displayString, "⌃⌥⌘Z", "German QWERTZ resolves physical Y key as Z")
            expectEqual(germanY.displayString, "⌃⌥⌘Y", "German QWERTZ resolves physical Z key as Y")
            expectEqual(germanOuml.displayString, "⌃⌥⌘Ö", "German QWERTZ resolves physical semicolon key as Ö")
        }

        if let abntData = testLayoutData(for: "com.apple.keylayout.Brazilian-ABNT2") {
            GlobalShortcut.refreshLayoutLabels(layoutData: abntData)
            let abntC = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(abntC.displayString, "⌃⌥⌘Ç", "Brazilian ABNT2 resolves physical semicolon key as Ç")
        }

        if let usData = testLayoutData(for: "com.apple.keylayout.US") {
            GlobalShortcut.refreshLayoutLabels(layoutData: usData)
            let usM = GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers)
            let usSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers)
            expectEqual(usM.displayString, "⌃⌥⌘M", "US layout resolves physical M key as M")
            expectEqual(usSemi.displayString, "⌃⌥⌘ ;", "US layout resolves physical semicolon key as semicolon")
        }

        // A keycap names a combination, not a key, and macOS resolves a Command
        // combination through the layout's Command table. Layouts that type a
        // non-Latin script answer differently there than they do bare, and
        // DVORAK-QWERTYCMD exists for nothing but that difference, so both
        // tables have to come out of the same layout.
        if let russianData = testLayoutData(for: "com.apple.keylayout.Russian") {
            GlobalShortcut.refreshLayoutLabels(layoutData: russianData)
            let russianCommandQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: layoutTestModifiers)
            let russianBareQ = GlobalShortcut(keyCode: Int64(kVK_ANSI_Q), modifiers: [.control, .option])
            expectEqual(russianCommandQ.displayString, "⌃⌥⌘Q",
                        "Russian reads a Command shortcut off the layout's Command table")
            expectEqual(russianBareQ.displayString, "⌃⌥Й",
                        "Russian reads a shortcut without Command off the character the key types")
        }

        if let dvorakCommandData = testLayoutData(for: "com.apple.keylayout.DVORAK-QWERTYCMD") {
            GlobalShortcut.refreshLayoutLabels(layoutData: dvorakCommandData)
            let dvorakCommandSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon),
                                                   modifiers: layoutTestModifiers)
            let dvorakBareSemi = GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon),
                                                modifiers: [.control, .option])
            expectEqual(dvorakCommandSemi.displayString, "⌃⌥⌘ ;",
                        "Dvorak with QWERTY Command keeps Command shortcuts on the QWERTY cap")
            expectEqual(dvorakBareSemi.displayString, "⌃⌥S",
                        "Dvorak with QWERTY Command keeps the rest on the Dvorak cap")
        }

        // The ANSI table answers when no layout can be read at all. On a live
        // system that is a caller off the main thread meeting a cold cache:
        // Text Input Services cannot be asked from there, so nothing derives a
        // cap and nothing warms the entry either.
        GlobalShortcut.refreshLayoutLabels(layoutData: nil)
        var coldCacheCaps: [String] = []
        let coldCacheDone = DispatchSemaphore(value: 0)
        // A thread of its own, not `sync`: dispatch runs a synchronous block on
        // whichever thread called it, so `sync` would still be the main thread
        // and would reach Text Input Services after all.
        Thread {
            coldCacheCaps = [
                GlobalShortcut(keyCode: Int64(kVK_ANSI_M), modifiers: layoutTestModifiers).displayString,
                GlobalShortcut(keyCode: Int64(kVK_ANSI_Semicolon), modifiers: layoutTestModifiers).displayString,
            ]
            coldCacheDone.signal()
        }.start()
        coldCacheDone.wait()
        expectEqual(coldCacheCaps.first ?? "", "⌃⌥⌘M",
                    "a cold cache off the main thread falls back to ANSI M")
        expectEqual(coldCacheCaps.last ?? "", "⌃⌥⌘ ;",
                    "a cold cache off the main thread falls back to ANSI semicolon")

        GlobalShortcut.refreshLayoutLabels()

        // Every assertion above compares labels the live input source produced,
        // so on a Latin-layout Mac they all pass whichever source the keycaps
        // are read from, and the one thing that made them wrong is invisible:
        // an input method answers the current-layout call with the layout it
        // types through, not the one printed on the keys. Pinned on the public
        // symbols rather than on the private member holding them, so renaming
        // it stays green and dropping the ASCII-capable lookup goes red.
        let shortcutSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Core/GlobalShortcut.swift",
            encoding: .utf8)) ?? ""
        let shortcutCode = shortcutSource.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(shortcutCode.contains("TISCopyCurrentASCIICapableKeyboardLayoutInputSource")
                && shortcutCode.contains("TISCopyCurrentKeyboardInputSource")
                && shortcutCode.contains("kTISPropertyInputSourceType"),
               "keycaps come from the ASCII-capable layout while an input method is active")

        // The native full screen action, wired like the sixths: real strings,
        // a stable id, and no system-wide key claimed until someone asks.
        expect(WindowLayoutAction.allCases.contains(.fullScreen)
                && WindowLayoutAction.fullScreen.shortcutID == 53
                && WindowLayoutAction(shortcutID: 53) == .fullScreen,
               "full screen exists and answers to its own shortcut id")
        expect(WindowLayoutAction.fullScreen.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutFullScreen] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "full screen starts with no combination of its own")
        expect(WindowLayoutAction.allCases.contains(.previousDisplay)
                && WindowLayoutAction.previousDisplay.shortcutID == 54
                && WindowLayoutAction(shortcutID: 54) == .previousDisplay,
               "previous display exists and answers to its own shortcut id")
        expect(WindowLayoutAction.previousDisplay.defaultShortcut == nil,
               "previous display does not claim a new system-wide combination")
        expect(WindowLayoutAction.allCases.contains(.marginMaximize)
                && WindowLayoutAction.marginMaximize.shortcutID == 55
                && WindowLayoutAction(shortcutID: 55) == .marginMaximize,
               "margin maximize exists and answers to its own shortcut id")
        expect(WindowLayoutAction.marginMaximize.defaultShortcut == nil
                && Defaults.registeredDefaults[DefaultsKey.windowLayoutShortcutMarginMaximize] as? String
                    == WindowLayoutAction.clearedShortcutStorageValue,
               "margin maximize starts with no combination of its own")
        expect(Set(WindowLayoutAction.allCases.map(\.shortcutID)).count
                == WindowLayoutAction.allCases.count,
               "every layout action keeps a distinct shortcut id")
        for language in AppLanguage.allCases {
            let layoutStrings = FeatureStrings.windowLayout(language)
            expect(!layoutStrings.fullScreen.isEmpty && !layoutStrings.previousDisplay.isEmpty
                    && !layoutStrings.marginMaximize.isEmpty,
                   "\(language.rawValue) names the latest window layout actions")
        }
        expect(WindowLayoutGeometry.accepts(actualRect: .zero, targetRect: .zero,
                                            action: .fullScreen, anchorTolerance: 10) == false,
               "full screen never joins the frame-based gesture acceptance")
        expect(WindowLayoutAction.center.targetCapability == .position
                && WindowLayoutAction.fullScreen.targetCapability == .fullScreen
                && WindowLayoutAction.maximize.targetCapability == .frame
                && WindowLayoutAction.restore.targetCapability == .position,
               "window layout targets only the attributes each action changes")

        // MARK: Editing, navigation and upper function keys as shortcuts (#308)

        let recorderModifiers: GlobalShortcutModifiers = [.control, .option, .command]
        let editingAndNavigationKeys: [(Int, String)] = [
            (kVK_Delete, "delete"), (kVK_ForwardDelete, "forward delete"),
            (kVK_Home, "home"), (kVK_End, "end"),
            (kVK_PageUp, "page up"), (kVK_PageDown, "page down"),
            (kVK_ANSI_KeypadEnter, "keypad enter"),
        ]
        for (keyCode, name) in editingAndNavigationKeys {
            let shortcut = GlobalShortcut(keyCode: Int64(keyCode), modifiers: recorderModifiers)
            expect(shortcut.isValid, "\(name) is recordable as a shortcut")
            expect(!shortcut.displayString.isEmpty
                   && shortcut.displayString != "Key \(keyCode)",
                   "\(name) prints a real cap instead of a raw key code")
        }
        let upperFunctionKeys: [(Int, String)] = [
            (kVK_F13, "F13"), (kVK_F14, "F14"), (kVK_F15, "F15"), (kVK_F16, "F16"),
            (kVK_F17, "F17"), (kVK_F18, "F18"), (kVK_F19, "F19"), (kVK_F20, "F20"),
        ]
        for (keyCode, name) in upperFunctionKeys {
            let shortcut = GlobalShortcut(keyCode: Int64(keyCode), modifiers: recorderModifiers)
            expect(shortcut.isValid, "\(name) is recordable as a shortcut")
            expect(shortcut.displayString.hasSuffix(name), "\(name) prints its own cap")
        }
        expect(Set(editingAndNavigationKeys.map {
                   GlobalShortcut(keyCode: Int64($0.0), modifiers: recorderModifiers).displayString
               }).count == editingAndNavigationKeys.count,
               "each editing and navigation key prints a cap of its own")

        // Delete on its own clears the field; held with a real modifier it is
        // an ordinary key and records like any other.
        expect(GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_Delete), modifiers: []),
               "delete alone clears the shortcut")
        expect(GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_ForwardDelete), modifiers: [.shift]),
               "forward delete with only Shift still clears the shortcut")
        expect(!GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_Delete), modifiers: recorderModifiers),
               "delete with a real modifier records instead of clearing")
        expect(!GlobalShortcut.clearsShortcut(keyCode: Int64(kVK_ANSI_D), modifiers: []),
               "an ordinary key never clears the shortcut")
        expect(GlobalShortcut.finderRenameDefault.isValid
                && GlobalShortcut.finderRenameDefault.displayString == "F2"
                && GlobalShortcut(storageValue: GlobalShortcut.finderRenameDefault.storageValue)
                    == .finderRenameDefault,
               "a standalone function key records, displays and survives storage")
        expect(!GlobalShortcut(keyCode: Int64(kVK_ANSI_F), modifiers: []).isValid,
               "a bare letter still cannot become a shortcut")
        expect(GlobalShortcut.finderRenameDefault.matches(keyCode: Int64(kVK_F2), modifiers: [])
                && !GlobalShortcut.finderRenameDefault.matches(
                    keyCode: Int64(kVK_F2), modifiers: [.command]),
               "Finder rename matches the chosen key and no extra modifiers")

        // MARK: Shortcuts the app silences while a field is listening (#308)

        let silenced = GlobalShortcutRole.featuresToSilenceWhileRecording
        expect(Set(silenced).count == silenced.count,
               "the list of features to silence has no repeats")
        expect(GlobalShortcutRole.allCases.allSatisfy { silenced.contains($0.feature) },
               "every configurable shortcut's feature is silenced while recording")
        expect(silenced.contains(.windowLayout),
               "the window layout keys are silenced too, though they have no role")
        expect(silenced.contains(.finderRename),
               "the scoped Finder key steps aside while its recorder is listening")
        expect(silenced.allSatisfy { AppFeature.allCases.contains($0) },
               "the silenced list only names real features, so re-syncing them restores the keys")
        expect(registeredDefaults[DefaultsKey.panelUtilityCleaner] as? Bool == true,
               "the cleaner row is visible in the panel utilities like its siblings")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleFrequency] as? String == "off",
               "automatic cleanup is opt-in")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleHour] as? Int == 9
               && registeredDefaults[DefaultsKey.cleanerScheduleMinute] as? Int == 0
               && registeredDefaults[DefaultsKey.cleanerScheduleWeekday] as? Int == 2,
               "the schedule defaults to nine in the morning on Mondays")
        expect(registeredDefaults[DefaultsKey.cleanerScheduleNotify] as? Bool == true,
               "the schedule reports its outcome unless the user opts out")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsEnabled] as? Bool == false,
               "WhatsApp downloads stay hidden until the user turns them on")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsAutomaticEnabled] as? Bool == false,
               "WhatsApp automatic cleanup is opt-in")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsCategories] as? String
               == "image,video,audio",
               "WhatsApp cleanup starts with conservative media categories")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsRetentionDays] as? Int == 7,
               "WhatsApp downloads keep a seven day default window")
        expect(registeredDefaults[DefaultsKey.whatsAppDownloadsAccessConfirmed] as? Bool == false,
               "WhatsApp cleanup never probes Downloads in the background before explicit access")
        expect(registeredDefaults[DefaultsKey.whatsAppOrganizerEnabled] as? Bool == false,
               "the experimental WhatsApp organizer is opt-in")
        expect(registeredDefaults[DefaultsKey.whatsAppOrganizerDelayMinutes] as? Int == 5
                && registeredDefaults[DefaultsKey.whatsAppOrganizerLayout] as? String == "flat"
                && registeredDefaults[DefaultsKey.whatsAppOrganizerDuplicateAction] as? String
                    == "trashNew",
               "the organizer starts with a five minute grace period and safe duplicate policy")
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func scheduleDate(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            utcCalendar.date(from: DateComponents(year: 2026, month: 7, day: day,
                                                  hour: hour, minute: minute)) ?? Date()
        }
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 8, 0), frequency: .daily,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(9, 9, 0),
               "a daily schedule still due today fires today")
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .daily,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(10, 9, 0),
               "a daily schedule already past fires tomorrow")
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .weekly,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == scheduleDate(13, 9, 0),
               "a weekly Monday schedule queried on Thursday fires next Monday")
        expect(CleanerSchedule.nextFireDate(after: scheduleDate(9, 10, 0), frequency: .off,
                                            hour: 9, minute: 0, weekday: 2,
                                            calendar: utcCalendar) == nil,
               "an off schedule never fires")
        expect(CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0),
                                         lastRun: scheduleDate(8, 9, 30),
                                         frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                         calendar: utcCalendar),
               "a fire that passed while the Mac was off counts as missed")
        expect(!CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0),
                                          lastRun: scheduleDate(9, 9, 30),
                                          frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                          calendar: utcCalendar),
               "a run that already happened today is not missed")
        expect(!CleanerSchedule.missedRun(now: scheduleDate(9, 10, 0), lastRun: nil,
                                          frequency: .daily, hour: 9, minute: 0, weekday: 2,
                                          calendar: utcCalendar),
               "enabling the schedule never triggers a surprise first run")
        expect(CleanerSchedule.hour24(hour12: 12, isPM: false) == 0
               && CleanerSchedule.hour24(hour12: 12, isPM: true) == 12
               && CleanerSchedule.hour24(hour12: 1, isPM: true) == 13
               && CleanerSchedule.hour24(hour12: 11, isPM: false) == 11,
               "twelve hour picks map to the right clock hours, midnight and noon included")
        expect(CleanerSchedule.hour12Components(fromHour24: 0) == (12, false)
               && CleanerSchedule.hour12Components(fromHour24: 12) == (12, true)
               && CleanerSchedule.hour12Components(fromHour24: 18) == (6, true)
               && CleanerSchedule.hour12Components(fromHour24: 9) == (9, false),
               "clock hours split back into the twelve hour pickers")
        expect((0...23).allSatisfy { hour in
                   let parts = CleanerSchedule.hour12Components(fromHour24: hour)
                   return CleanerSchedule.hour24(hour12: parts.hour12, isPM: parts.isPM) == hour
               },
               "every hour of the day round trips through the twelve hour pickers")

        // MARK: WhatsApp downloads

        let whatsAppEnabledSuite = "chikit.tests.whatsapp.enabled"
        if let migrationDefaults = UserDefaults(suiteName: whatsAppEnabledSuite) {
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil,
                   "an untouched setup keeps WhatsApp downloads off by leaving the new switch unset")
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppDownloadsAutomaticEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "an existing automatic WhatsApp cleanup keeps its Cleaner surface")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppOrganizerEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "an existing WhatsApp organizer keeps its Cleaner surface")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
            migrationDefaults.set(true, forKey: DefaultsKey.whatsAppDownloadsAccessConfirmed)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(migrationDefaults.object(forKey: DefaultsKey.whatsAppDownloadsEnabled) == nil,
                   "only opening Downloads does not keep the WhatsApp Cleaner surface")
            migrationDefaults.set(false, forKey: DefaultsKey.whatsAppDownloadsEnabled)
            Defaults.migrateWhatsAppDownloadsEnabled(in: migrationDefaults)
            expect(!migrationDefaults.bool(forKey: DefaultsKey.whatsAppDownloadsEnabled),
                   "the WhatsApp downloads migration preserves a newer off choice")
            migrationDefaults.removePersistentDomain(forName: whatsAppEnabledSuite)
        } else {
            expect(false, "WhatsApp downloads migration suite can be created")
        }
        expect(WhatsAppDownloadSupport.isWhatsAppAgent("WhatsApp")
                && WhatsAppDownloadSupport.isWhatsAppAgent(" whatsapp ")
                && !WhatsAppDownloadSupport.isWhatsAppAgent("SomeBrowser")
                && !WhatsAppDownloadSupport.isWhatsAppAgent(nil),
               "only an explicit WhatsApp quarantine agent is trusted")
        expect(WhatsAppDownloadSupport.category(contentTypeIdentifier: "public.jpeg",
                                                 extension: "jpeg") == .image
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: "public.mpeg-4",
                                                     extension: "mp4") == .video
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: "public.mp3",
                                                     extension: "mp3") == .audio
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: "com.adobe.pdf",
                                                     extension: "pdf") == .document
                && WhatsAppDownloadSupport.category(contentTypeIdentifier: nil,
                                                     extension: "zip") == .archive,
               "WhatsApp files land in the expected user-facing buckets")
        expect(WhatsAppDownloadSupport.isIncompleteFile(extension: "download")
                && WhatsAppDownloadSupport.isIncompleteFile(extension: "PART")
                && !WhatsAppDownloadSupport.isIncompleteFile(extension: "pdf"),
               "partial downloads can never become cleanup candidates")
        let whatsNow = scheduleDate(20, 12, 0)
        let whatsOld = scheduleDate(10, 12, 0)
        let whatsRecent = scheduleDate(19, 12, 0)
        expect(WhatsAppDownloadSupport.isOldEnough(downloadedAt: whatsOld,
                                                   modifiedAt: whatsOld,
                                                   now: whatsNow, retentionDays: 7,
                                                   calendar: utcCalendar),
               "an untouched old WhatsApp download passes retention")
        expect(!WhatsAppDownloadSupport.isOldEnough(downloadedAt: whatsOld,
                                                    modifiedAt: whatsRecent,
                                                    now: whatsNow, retentionDays: 7,
                                                    calendar: utcCalendar),
               "a recent edit postpones WhatsApp cleanup")
        expect(!WhatsAppDownloadSupport.isEligibleForAutomaticCleanup(
                    category: .image, downloadedAt: whatsOld, modifiedAt: whatsOld,
                    now: whatsNow, retentionDays: 7, enabledCategories: [.image],
                    includeExisting: false, automaticStartDate: whatsRecent),
               "future-only automation leaves pre-existing downloads alone")
        expect(WhatsAppDownloadSupport.isEligibleForAutomaticCleanup(
                    category: .image, downloadedAt: whatsOld, modifiedAt: whatsOld,
                    now: whatsNow, retentionDays: 7, enabledCategories: [.image],
                    includeExisting: true, automaticStartDate: whatsRecent),
               "explicitly including existing downloads admits old matches")
        let downloadsRoot = URL(fileURLWithPath: "/Users/test/Downloads")
        expect(WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Downloads/file.pdf"), of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Downloads/folder/file.pdf"), of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDirectChild(
                    URL(fileURLWithPath: "/Users/test/Documents/file.pdf"), of: downloadsRoot),
               "WhatsApp cleanup accepts only direct children of Downloads")
        let organizedFile = URL(fileURLWithPath: "/Users/test/Downloads/WhatsApp/2026/07/file.pdf")
        expect(WhatsAppDownloadSupport.isDescendant(organizedFile, of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDescendant(downloadsRoot, of: downloadsRoot)
                && !WhatsAppDownloadSupport.isDescendant(
                    URL(fileURLWithPath: "/Users/test/Download/file.pdf"), of: downloadsRoot),
               "organized cleanup accepts descendants without path-prefix confusion")
        let fourMinutesAgo = whatsNow.addingTimeInterval(-4 * 60)
        let sixMinutesAgo = whatsNow.addingTimeInterval(-6 * 60)
        expect(!WhatsAppDownloadSupport.isStableForOrganization(
                    downloadedAt: sixMinutesAgo, modifiedAt: fourMinutesAgo,
                    now: whatsNow, delayMinutes: 5)
                && WhatsAppDownloadSupport.isStableForOrganization(
                    downloadedAt: sixMinutesAgo, modifiedAt: sixMinutesAgo,
                    now: whatsNow, delayMinutes: 5)
                && WhatsAppDownloadSupport.sanitizedOrganizerDelayMinutes(999) == 5,
               "organization waits for both download and modification activity to settle")
        let undoCreatedAt = whatsNow.addingTimeInterval(-6 * 86_400)
        expect(WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: undoCreatedAt, now: whatsNow)
                && !WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: whatsNow.addingTimeInterval(-7 * 86_400), now: whatsNow)
                && !WhatsAppDownloadSupport.organizerUndoIsValid(
                    createdAt: whatsNow.addingTimeInterval(1), now: whatsNow),
               "organizer undo is executable only during its seven day window")
        expect(WhatsAppDownloadSupport.organizerRelativeComponents(
                    layout: .flat, category: .image, date: whatsNow,
                    calendar: utcCalendar).isEmpty
                && WhatsAppDownloadSupport.organizerRelativeComponents(
                    layout: .category, category: .image, date: whatsNow,
                    calendar: utcCalendar) == ["Images"]
                && WhatsAppDownloadSupport.organizerRelativeComponents(
                    layout: .month, category: .image, date: whatsNow,
                    calendar: utcCalendar) == ["2026", "07"],
               "the organizer produces stable flat, type and month folder layouts")
        let volumeA = NSData(bytes: [0x67, 0x45, 0x64, 0x00] as [UInt8], length: 4)
        let volumeB = NSData(bytes: [0x69, 0x98, 0x66, 0x00] as [UInt8], length: 4)
        expect(WhatsAppDownloadSupport.isSameVolume(
                    source: volumeA,
                    destination: NSData(bytes: [0x67, 0x45, 0x64, 0x00] as [UInt8], length: 4)),
               "two equal volume identifiers are one volume even as separate objects")
        expect(!WhatsAppDownloadSupport.isSameVolume(source: volumeA, destination: volumeB),
               "two different volume identifiers never skip the destination check")
        expect(!WhatsAppDownloadSupport.isSameVolume(source: NSNumber(value: 1),
                                                     destination: NSString(string: "1")),
               "unequal identities that print the same string still take the verified path")
        expect(!WhatsAppDownloadSupport.isSameVolume(source: volumeA, destination: nil)
                && !WhatsAppDownloadSupport.isSameVolume(source: nil, destination: volumeB)
                && !WhatsAppDownloadSupport.isSameVolume(source: nil, destination: nil),
               "an unknown volume identity keeps the verified copy rather than an unchecked rename")
        expect(WhatsAppDownloadSupport.nextAutomaticCheck(
                    after: scheduleDate(20, 8, 0), calendar: utcCalendar) == scheduleDate(20, 9, 0)
                && WhatsAppDownloadSupport.nextAutomaticCheck(
                    after: scheduleDate(20, 10, 0), calendar: utcCalendar) == scheduleDate(21, 9, 0),
               "the hidden daily WhatsApp check targets nine in the morning")
        expect(WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 12, 0), lastRun: scheduleDate(19, 9, 0),
                    calendar: utcCalendar)
                && !WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 8, 0), lastRun: scheduleDate(19, 9, 0),
                    calendar: utcCalendar)
                && !WhatsAppDownloadSupport.missedAutomaticCheck(
                    now: scheduleDate(20, 12, 0), lastRun: nil, calendar: utcCalendar),
               "missed WhatsApp checks recover after nine without a first-enable surprise")
        expect(CleanerSupport.isProtectedBundleID("com.apple.Music")
               && CleanerSupport.isProtectedBundleID("com.apple")
               && CleanerSupport.isProtectedBundleID("group.com.apple.notes")
               && CleanerSupport.isProtectedBundleID("com.chikit.utils"),
               "system domains and this app can never be junk owners")
        expect(!CleanerSupport.isProtectedBundleID("com.vendor.editor"),
               "third party identifiers are eligible for the leftover check")
        expect(UninstallerSupport.verifiedBundleID("com.vendor.editor") == "com.vendor.editor"
               && UninstallerSupport.verifiedBundleID("com.vendor.editor.helper") == "com.vendor.editor.helper"
               && UninstallerSupport.verifiedBundleID("test.editor") == "test.editor"
               && UninstallerSupport.verifiedBundleID("editor.test") == "editor.test",
               "the uninstaller accepts exact third party bundle identifiers, two-component IDs, and embedded helpers")
        expect(UninstallerSupport.verifiedBundleID(nil) == nil
               && UninstallerSupport.verifiedBundleID("") == nil
               && UninstallerSupport.verifiedBundleID("plain-name") == nil
               && UninstallerSupport.verifiedBundleID("com.vendor../escape") == nil
               && UninstallerSupport.verifiedBundleID("com.chikit.utils") == nil
               && UninstallerSupport.verifiedBundleID("com.apple.system") == nil,
               "malformed, protected and current app identifiers never enter uninstall paths")
        let uninstallAppURL = URL(fileURLWithPath: "/Applications/Editor.app")
        expect(UninstallerSupport.isNestedBundle(
                   URL(fileURLWithPath: "/Applications/Editor.app/Contents/Library/LoginItems/Background.app"),
                   in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(uninstallAppURL, in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(
                   URL(fileURLWithPath: "/Applications/Editor.app-copy/Contents/Background.app"),
                   in: uninstallAppURL)
               && !UninstallerSupport.isNestedBundle(nil, in: uninstallAppURL),
               "the uninstaller stops only background apps nested inside the selected bundle")
        expect(!UninstallerSupport.sharedDataIsExclusive(
            selectedURL: URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"),
            bundleID: "com.vendor.editor",
            knownApplications: [
                (URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"), "com.vendor.editor"),
                (URL(fileURLWithPath: "/Applications/Editor.app"), "com.vendor.editor"),
            ])
            && UninstallerSupport.sharedDataIsExclusive(
                selectedURL: URL(fileURLWithPath: "/Applications/Editor.app"),
                bundleID: "com.vendor.editor",
                knownApplications: [
                    (URL(fileURLWithPath: "/Applications/Editor.app"), "com.vendor.editor"),
                    (URL(fileURLWithPath: "/Applications/Other.app"), "com.vendor.other"),
                ]),
               "shared app data is eligible only when no other installed copy owns the bundle identifier")
        expect(UninstallerSupport.sharedDataIsExclusive(
            selectedURL: URL(fileURLWithPath: "/Applications/Editor.app"),
            bundleID: "com.vendor.editor.helper",
            knownApplications: [
                (URL(fileURLWithPath: "/Applications/Editor.app/Contents/Helpers/Helper.app"),
                 "com.vendor.editor.helper"),
            ])
            && UninstallerSupport.applicationIsInTrustedInstallRoot(
                URL(fileURLWithPath: "/Applications/Editor.app"),
                home: URL(fileURLWithPath: "/Users/test"))
            && !UninstallerSupport.applicationIsInTrustedInstallRoot(
                URL(fileURLWithPath: "/Users/test/Downloads/Editor.app"),
                home: URL(fileURLWithPath: "/Users/test")),
               "embedded helpers belong to the selected app while unregistered download copies never own shared data")
        let uninstallCandidateIDs: Set<String> = ["com.vendor.editor", "com.vendor.editor.helper"]
        expect(UninstallerSupport.exclusiveBundleIDs(
                   uninstallCandidateIDs,
                   selectedURL: uninstallAppURL,
                   knownApplications: []) == uninstallCandidateIDs
               && UninstallerSupport.exclusiveBundleIDs(
                   uninstallCandidateIDs,
                   selectedURL: uninstallAppURL,
                   knownApplications: [
                       (URL(fileURLWithPath: "/Applications/Other.app"),
                        "com.vendor.editor.helper"),
                   ]) == ["com.vendor.editor"],
               "package removal preserves helper candidates while excluding an owner installed elsewhere")
        let uninstallIDs: Set<String> = ["com.vendor.editor", "com.vendor.editor.helper"]
        let leftoverIdentity = UninstallerSupport.identity(
            bundleIDs: uninstallIDs, displayNames: ["Editor", "Editor.app"])
        expect(leftoverIdentity.nameTokens.contains("editor")
               && !leftoverIdentity.nameTokens.contains("helper"),
               "display names become match tokens and helper suffixes do not")
        expect(UninstallerSupport.leftoverMatch("Editor", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch("com.vendor.editor.plist", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.plist",
                   identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("COM.VENDOR.EDITOR.PLIST", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("Editor.prefPane", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "ABCD123456.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "group.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.wrapper.com.vendor.editor", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch("Google", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch("com.vendor.editor2", identity: leftoverIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.extra", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.helper.plist", identity: leftoverIdentity) == .exact
               && UninstallerSupport.leftoverMatch("Editorial", identity: leftoverIdentity) == .related
               && UninstallerSupport.leftoverMatch("Editor/Nested", identity: leftoverIdentity) == .none,
               "owned identifiers are exact, while prefixes and names stay optional without unsigned wrappers")
        let technicalIdentity = UninstallerSupport.technicalIdentity(leftoverIdentity)
        expect(UninstallerSupport.leftoverMatch("Editor", identity: technicalIdentity) == .none
               && UninstallerSupport.leftoverMatch(
                   "com.vendor.editor.plist", identity: technicalIdentity) == .exact,
               "sensitive roots accept technical ownership and never a display name")
        expect(UninstallerSupport.leftoverEntryMatches(
                   "Editor_2024-01-01-120000_Mac.plist",
                   identity: leftoverIdentity, crashReporter: true)
               && !UninstallerSupport.leftoverEntryMatches(
                   "Editor_2024-01-01-120000_Mac.plist",
                   identity: leftoverIdentity, crashReporter: false),
               "crash reports may use the app name as a prefix only in that folder")
        expect(UninstallerSupport.ownerBundleID(for: "com.vendor.editor.helper.plist",
                                                identity: leftoverIdentity)
                == "com.vendor.editor.helper"
               && UninstallerSupport.ownerBundleID(for: "Editor", identity: leftoverIdentity)
                == "com.vendor.editor",
               "a helper identifier wins when it is in the name, otherwise the app identifier owns a name match")
        expect(UninstallerSupport.normalizedToken("Example App 2") == "exampleapp2"
               && UninstallerSupport.nameWithoutTrailingVersion("Example App 2") == "Example App"
               && UninstallerSupport.nameWithoutTrailingVersion("Example App Nightly") == "Example App"
               && UninstallerSupport.leftoverMatch(
                   "Example App",
                   identity: UninstallerSupport.identity(bundleIDs: ["com.vendor.exampleapp"],
                                                         displayNames: ["Example App 2"])) == .related
               && UninstallerSupport.leftoverEntryMatches(
                   "ExampleApp2.plist",
                   identity: UninstallerSupport.identity(bundleIDs: ["com.vendor.exampleapp"],
                                                         displayNames: ["Example App 2"])),
               "spaces and trailing version numbers do not hide a leftover named after the app")
        let twoPartIdentity = UninstallerSupport.identity(
            primaryBundleID: "test.editor",
            bundleIDs: ["test.editor"],
            displayNames: ["Editor", "Editor.app"])
        expect(twoPartIdentity.nameTokens.contains("editor")
               && twoPartIdentity.bundleIDs.contains("test.editor"),
               "two-part bundle identifiers yield both display name tokens and exact bundle IDs")
        expect(UninstallerSupport.leftoverMatch("Editor", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("editor", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("test.editor.plist", identity: twoPartIdentity) == .exact
               && UninstallerSupport.leftoverMatch("test.editor", identity: twoPartIdentity) == .exact
               && UninstallerSupport.leftoverMatch("test.editor.helper", identity: twoPartIdentity) == .related
               && UninstallerSupport.leftoverMatch("Unrelated", identity: twoPartIdentity) == .none,
               "two-part bundle identifiers match exact and related leftovers correctly")
        expect(UninstallerSupport.identity(primaryBundleID: "com.vendor.browser",
                                           bundleIDs: ["com.vendor.browser"],
                                           displayNames: ["Vendor Browser"]).nameTokens.contains("browser"),
               "the last identifier component is a token when it names the app")
        let browserIdentity = UninstallerSupport.identity(primaryBundleID: "com.vendor.browser",
                                                          bundleIDs: ["com.vendor.browser"],
                                                          displayNames: ["Vendor Browser"])
        let browserListings = [
            UninstallerSupport.DirListing(name: "Vendor", children: [
                UninstallerSupport.DirListing(name: "Browser", children: []),
                UninstallerSupport.DirListing(name: "Docs", children: []),
            ]),
            UninstallerSupport.DirListing(name: "SuiteApp", children: [
                UninstallerSupport.DirListing(name: "logs", children: []),
            ]),
            UninstallerSupport.DirListing(name: "com.vendor.browser", children: []),
        ]
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: browserListings,
                   identity: browserIdentity,
                   extraChildDepth: 1).map(\.path) == ["Vendor/Browser", "com.vendor.browser"],
               "a leftover nested under a vendor folder is found without taking the whole vendor folder")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: browserListings,
                   identity: browserIdentity,
                   extraChildDepth: 0).map(\.path) == ["com.vendor.browser"],
               "vendor nesting is not searched when the folder is a leaf location")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(name: "Browser", children: [
                       UninstallerSupport.DirListing(name: "com.vendor.browser", children: [])
                   ])],
                   identity: browserIdentity,
                   extraChildDepth: 1).map(\.path) == ["Browser/com.vendor.browser"],
               "an exact child wins over a broader related parent folder")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(
                       name: "Unrelated.component", children: [],
                       bundleIdentifier: "com.vendor.browser")],
                   identity: browserIdentity,
                   extraChildDepth: 0).first?.confidence == .exact,
               "plugin bundle metadata finds a component whose filename does not identify the app")
        expect(UninstallerSupport.leftoverHitRecords(
                   listings: [UninstallerSupport.DirListing(name: "Vendor", children: [
                       UninstallerSupport.DirListing(name: "Mid", children: [
                           UninstallerSupport.DirListing(name: "Editor", children: [])
                       ])
                   ])],
                   identity: leftoverIdentity,
                   extraChildDepth: 2).map(\.path) == ["Vendor/Mid/Editor"],
               "Application Support is searched two levels for vendor/mid/app nesting")
        let teamedIdentity = UninstallerSupport.identity(
            bundleIDs: ["com.vendor.editor"], displayNames: [],
            teamIDs: ["abcd123456"], groupIDs: ["group.com.vendor.editor"])
        expect(UninstallerSupport.leftoverMatch("ABCD123456.com.other", identity: teamedIdentity) == .related
               && UninstallerSupport.leftoverMatch(
                   "ABCD123456.com.vendor.editor", identity: teamedIdentity) == .exact
               && UninstallerSupport.leftoverMatch(
                   "ZZZZ123456.com.vendor.editor", identity: teamedIdentity) == .none
               && UninstallerSupport.leftoverMatch("group.com.vendor.editor", identity: teamedIdentity) == .exact
               && UninstallerSupport.matchingGroupID(
                   "group.com.vendor.editor", identity: teamedIdentity) == "group.com.vendor.editor"
               && UninstallerSupport.containerMetadataMatches("com.vendor.editor",
                                                              identity: leftoverIdentity) == .exact,
               "team prefixes are related, app groups and container metadata keep the exact owner")
        let leftoverFolders = UninstallerSupport.searchFolders(
            home: URL(fileURLWithPath: "/Users/tester"), darwinCache: nil, darwinTemp: nil)
        expect(leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Group Containers" && $0.kind == .containers
                   && $0.readsContainerMetadata && !$0.allowsNameMatches
                   && $0.requiresSignedGroup
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/PreferencePanes" && $0.kind == .other
               })
               && leftoverFolders.contains(where: {
                   $0.url.path.hasSuffix("CrashReporter") && $0.crashReporter
               })
               && leftoverFolders.contains(where: { $0.url.path == "/private/var/db/receipts" })
               && leftoverFolders.contains(where: { $0.url.path.hasSuffix("/Automator") })
               && leftoverFolders.contains(where: { $0.url.path.hasSuffix("/Frameworks") })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/.config" && !$0.allowsNameMatches
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Preferences/ByHost"
                       && !$0.allowsNameMatches
               })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Caches/com.apple.nsurlsessiond/Downloads"
                       && !$0.allowsNameMatches
               })
               && !leftoverFolders.contains(where: { $0.url.path.contains("/Desktop") })
               && leftoverFolders.contains(where: {
                   $0.url.path == "/Users/tester/Library/Application Support" && $0.extraChildDepth == 2
               }),
               "leftover search covers Library support, plugins and receipts, not the Desktop")
        let spotlightQuery = UninstallerSupport.leftoverSpotlightExpression(identity: leftoverIdentity) ?? ""
        expect(spotlightQuery.contains("com.vendor.editor")
               && spotlightQuery.contains("editor")
               && UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Library/Caches/Editor",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library")])
               && !UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Desktop/Editor",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library")]),
               "Spotlight leftovers stay inside Library-like roots")
        let spotlightGroupIdentity = UninstallerSupport.spotlightIdentity(
            for: "/Users/tester/Library/Group Containers/group.com.vendor.editor",
            identity: teamedIdentity)
        let spotlightLaunchIdentity = UninstallerSupport.spotlightIdentity(
            for: "/Users/tester/Library/LaunchAgents/Editor.plist",
            identity: teamedIdentity)
        expect(spotlightGroupIdentity.bundleIDs.isEmpty
               && spotlightGroupIdentity.groupIDs == ["group.com.vendor.editor"]
               && spotlightLaunchIdentity.nameTokens.isEmpty,
               "Spotlight preserves signed-group and technical-only rules for sensitive roots")
        let safetyFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("chikit-uninstaller-\(UUID().uuidString)", isDirectory: true)
        let safetyRoot = safetyFixture.appendingPathComponent("root", isDirectory: true)
        let outsideRoot = safetyFixture.appendingPathComponent("outside", isDirectory: true)
        let safeFile = safetyRoot.appendingPathComponent("safe.plist")
        let replacementFile = safetyRoot.appendingPathComponent("replacement.plist")
        let outsideFile = outsideRoot.appendingPathComponent("foreign.plist")
        let link = safetyRoot.appendingPathComponent("link", isDirectory: true)
        try? FileManager.default.createDirectory(at: safetyRoot, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: safeFile.path, contents: Data("old".utf8))
        _ = FileManager.default.createFile(atPath: replacementFile.path, contents: Data("new".utf8))
        _ = FileManager.default.createFile(atPath: outsideFile.path, contents: Data("foreign".utf8))
        try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: outsideRoot)
        let originalFileIdentity = UninstallerSupport.fileIdentity(at: safeFile)
        let safePathWasAccepted = UninstallerSupport.removalPathIsSafe(safeFile, within: safetyRoot)
        let linkedPathWasRejected = !UninstallerSupport.removalPathIsSafe(
            link.appendingPathComponent("foreign.plist"), within: safetyRoot)
        try? FileManager.default.removeItem(at: safeFile)
        try? FileManager.default.moveItem(at: replacementFile, to: safeFile)
        expect(safePathWasAccepted && linkedPathWasRejected
               && originalFileIdentity != nil
               && UninstallerSupport.fileIdentity(at: safeFile) != originalFileIdentity,
               "removal stays inside its scan root, rejects symlink escapes and detects path replacement")
        try? FileManager.default.removeItem(at: safetyFixture)
        func sourceBody(of source: String, from opening: String, to closing: String) -> String {
            guard let start = source.range(of: opening),
                  let end = source.range(of: closing, range: start.upperBound..<source.endIndex)
            else { return "" }
            return String(source[start.upperBound..<end.lowerBound])
        }
        // Building the installed-apps oracle walks the application folders, and
        // the removal guard reads it under `.leftovers` alone — with leftover
        // rows unchecked by default, the common clean must not pay for that
        // walk. JunkCleaner is not part of this test binary, so pin the gate
        // and the premise that makes an empty oracle safe at their source.
        let junkCleanerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Cleaner/JunkCleaner.swift",
            encoding: .utf8)) ?? ""
        let cleanSelectedBody = sourceBody(of: junkCleanerSource, from: "func cleanSelected()",
                                           to: "private static func mayRemove")
        expect(cleanSelectedBody.contains("chosen.contains { $0.category == .leftovers }")
               && cleanSelectedBody.contains("? Self.installedBundleIDs() : []")
               && !cleanSelectedBody.contains("let installed = Self.installedBundleIDs()"),
               "a clean builds the installed-apps oracle only when a leftover row is selected")
        let mayRemoveBody = sourceBody(of: junkCleanerSource, from: "private static func mayRemove",
                                       to: "private static func trashViaFinder")
        let leftoverBranch = mayRemoveBody.range(of: "if item.category == .leftovers")
        expect(mayRemoveBody.components(separatedBy: "installed: installed").count == 2,
               "the removal guard consults the installed-apps oracle exactly once")
        expect(leftoverBranch.map { branch in
                   mayRemoveBody.range(of: "installed: installed",
                                       range: branch.upperBound..<mayRemoveBody.endIndex) != nil
               } == true,
               "the removal guard reads the installed-apps oracle inside its leftovers branch")
        // The known-application roster opens every installed app, and only the
        // shared-data claims read it. AppUninstaller is not part of this test
        // binary either, so pin the gate that keeps a removal that cannot claim
        // shared data from paying for the roster.
        let appUninstallerSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Uninstall/AppUninstaller.swift",
            encoding: .utf8)) ?? ""
        let removeSelectedBody = sourceBody(of: appUninstallerSource, from: "func removeSelected()",
                                            to: "func removeSelectedWithHomebrew()")
        expect(removeSelectedBody.contains("let knownApplications = mayClaimSharedData"),
               "a removal builds the known-application roster only when it may claim shared data")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "com.vendor.editor.prefPane")
                == "com.vendor.editor",
               "preference panes map to their owning bundle identifier")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "app-0.0.409") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "0.0.409") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "1.57.0") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.v2.editor")
                == "com.v2.editor",
               "version directories never become deletion ownership evidence")
        let supportRoot = URL(fileURLWithPath: "/Users/tester/Library/Application Support")
        expect(CleanerSupport.isDirectChild(
                   supportRoot.appendingPathComponent("com.vendor.editor"), of: supportRoot)
               && !CleanerSupport.isDirectChild(
                   supportRoot.appendingPathComponent("vendor/app-0.0.409"), of: supportRoot),
               "the general Cleaner accepts only direct children of each leftover root")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.editor.Helper.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.plist")
                == "com.vendor.editor.Helper"
               && CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.editor") == nil
               && CleanerSupport.bundleIDCandidate(fromEntryName: "ABCD123456.com.vendor.editor")
                == "com.vendor.editor",
               "ByHost UUIDs and team prefixes unwrap to the owning identifier")
        expect(CleanerSupport.hasSharedContainerWrapper("group.com.vendor.editor")
               && CleanerSupport.hasSharedContainerWrapper("ABCD123456.com.vendor.editor")
               && !CleanerSupport.hasSharedContainerWrapper("abcd123456.com.vendor.editor")
               && !CleanerSupport.hasSharedContainerWrapper("com.vendor.editor"),
               "the general Cleaner leaves shared-container wrappers to signed app-specific scans")
        let helperAppIdentity = UninstallerSupport.identity(
            primaryBundleID: "com.vendor.chat",
            bundleIDs: ["com.vendor.chat", "com.vendor.chat.helper.Renderer", "com.vendor.chat.helper.GPU"],
            displayNames: ["Chat App"])
        expect(!helperAppIdentity.nameTokens.contains("renderer")
               && !helperAppIdentity.nameTokens.contains("gpu")
               && helperAppIdentity.nameTokens.contains("chatapp")
               && UninstallerSupport.leftoverMatch("renderer.log", identity: helperAppIdentity) == .none
               && !UninstallerSupport.leftoverSpotlightPathIsAllowed(
                    "/Users/tester/Library/Application Support/OtherApp/logs/sub/renderer.log",
                    roots: [URL(fileURLWithPath: "/Users/tester/Library/Application Support")]),
               "helper subprocess roles and deeply nested foreign logs are never claimed as leftovers")
        expect(CleanerSupport.isProtectedBundleID("systemgroup.com.apple.icloud.searchpartyd.sharedsettings")
               && CleanerSupport.isProtectedBundleID("243LU875E5.groups.com.apple.podcasts")
               && CleanerSupport.isProtectedBundleID("developer.apple.wwdc")
               && CleanerSupport.isProtectedBundleID("is.workflow.my.app")
               && CleanerSupport.isProtectedBundleID("vorss.tests.switcher.shortcut"),
               "system domains stay protected in every wrapping, team prefixes included")
        expect(CleanerSupport.sharedInfrastructurePrefixes.allSatisfy {
                   CleanerSupport.isProtectedBundleID($0)
               },
               "embedded updaters and crash reporters can never be junk owners")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "systemgroup.com.apple.icloud.sharedsettings.plist")
               == "com.apple.icloud.sharedsettings",
               "systemgroup wrappers unwrap to the real owner")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName:
               "com.vendor.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F.editor") == nil,
               "a UUID in the middle of a name stays unattributable")
        expect(CleanerSupport.containsUUIDComponent("x.B787EFF9-B8E2-5296-96AF-DF9D3CD3AC4F")
               && !CleanerSupport.containsUUIDComponent("com.vendor.editor"),
               "the UUID detector matches dashed UUIDs and nothing else")
        expect(CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.backgroundtool",
                                                    withInstalled: ["com.vendor.editor"])
               && CleanerSupport.sharesVendorNamespace(candidate: "com.publisher.agent",
                                                       withInstalled: ["com.publisher.browser"]),
               "a vendor's updaters are owned while any app of that vendor is installed")
        expect(!CleanerSupport.sharesVendorNamespace(candidate: "com.vendor.editor",
                                                     withInstalled: ["com.publisher.browser"]),
               "different vendors never own each other")
        expect(!CleanerSupport.sharesVendorNamespace(candidate: "io.github.account.tool",
                                                     withInstalled: ["io.github.other.app"]),
               "code hosting namespaces are shared by unrelated developers and never match")
        expect(CleanerPolicy.precheckCacheEntry("Homebrew")
               && CleanerPolicy.precheckCacheEntry("com.vendor.editor"),
               "download caches and third party app caches start checked")
        expect(!CleanerPolicy.precheckCacheEntry("PlainVendorFolder")
               && !CleanerPolicy.precheckCacheEntry("com.apple.Music")
               && !CleanerPolicy.precheckCacheEntry("com.spotify.client")
               && !CleanerPolicy.precheckCacheEntry("ms-playwright"),
               "system, sensitive and unattributable caches start unchecked")
        expect(CleanerSupport.Category.deviceBackups.rawValue == 6
               && CleanerSupport.Category.allCases.count == 7,
               "device backups joined the cleaner with a stable category id")
        expect(!CleanerPolicy.precheckDeviceBackups,
               "device backups never start checked, they are the user's safety net")
        expect(CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/iOS DeviceSupport")
               && CleanerPolicy.developerJunkPaths.contains("/Library/Developer/Xcode/watchOS DeviceSupport"),
               "stale DeviceSupport symbol caches count as developer junk")
        expect(CleanerSupport.looksLikeBundleID("com.vendor.editor")
               && CleanerSupport.looksLikeBundleID("com.foo.Bar-Helper_2")
               && CleanerSupport.looksLikeBundleID("test.editor")
               && CleanerSupport.looksLikeBundleID("editor.test")
               && CleanerSupport.looksLikeBundleID("com.foo"),
               "reverse DNS names and two-component bundle identifiers are recognized")
        expect(!CleanerSupport.looksLikeBundleID("VendorFolder")
               && !CleanerSupport.looksLikeBundleID("Editor")
               && !CleanerSupport.looksLikeBundleID("com..foo")
               && !CleanerSupport.looksLikeBundleID(".com.foo")
               && !CleanerSupport.looksLikeBundleID("com.foo.")
               && !CleanerSupport.looksLikeBundleID("com.foo.bár"),
               "plain names, empty parts and odd characters never match by name")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "com.vendor.editor.plist") == "com.vendor.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "test.editor.plist") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "group.com.foo.bar") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "group.test.editor") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "ABCD123456.test.editor") == "test.editor"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.savedState") == "com.foo.bar"
               && CleanerSupport.bundleIDCandidate(fromEntryName: "com.foo.bar.binarycookies") == "com.foo.bar",
               "entry names map to their owning bundle identifier")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "VendorFolder") == nil,
               "folders without a bundle shaped name are never candidates")
        expect(CleanerSupport.isOwned(candidate: "com.vendor.editor.startuphelper",
                                      byInstalled: ["com.vendor.editor"]),
               "embedded helper identifiers are owned by their installed app")
        expect(CleanerSupport.isOwned(candidate: "com.maker",
                                      byInstalled: ["com.maker.app"]),
               "a family prefix of an installed app counts as owned")
        expect(!CleanerSupport.isOwned(candidate: "com.vendor.editor", byInstalled: ["com.publisher.browser"]),
               "identifiers with no installed relative are unowned")
        expect(!CleanerSupport.isOwned(candidate: "com.makerapp.tool", byInstalled: ["com.maker.app"]),
               "prefix ownership requires a dot boundary, not a string prefix")
        expect(CleanerSupport.executablePaths(inLaunchPlist: [
                   "Program": "/Applications/Gone.app/Contents/MacOS/agent",
                   "ProgramArguments": ["/usr/local/bin/gone-tool", "--flag"],
                   "BundleProgram": "Contents/MacOS/relative",
               ]) == ["/Applications/Gone.app/Contents/MacOS/agent", "/usr/local/bin/gone-tool"],
               "launch plists yield their absolute executables and skip relative ones")
        expect(CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                           executables: ["/Applications/Gone.app/x"],
                                                           executableExists: { _ in false }),
               "a plist whose executables are all gone is a removable orphan")
        expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.vendor.editor.launchdaemon",
                                                            executables: ["/bin/ls"],
                                                            executableExists: { _ in true }),
               "a plist with a living executable is never an orphan")
        expect(!CleanerSupport.launchPlistIsRemovableOrphan(label: "com.apple.something",
                                                            executables: ["/gone"],
                                                            executableExists: { _ in false })
               && !CleanerSupport.launchPlistIsRemovableOrphan(label: nil,
                                                               executables: [],
                                                               executableExists: { _ in false }),
               "system agents and undecidable plists are never offered")
        expect((registeredDefaults[DefaultsKey.autoQuitExceptions] as? [String]) == Defaults.mandatoryAutoQuitExceptionBundleIDs,
               "Finder stays in the default auto-quit exception list")
        expect(registeredDefaults[DefaultsKey.panelCollapsedSections] == nil,
               "panel collapsed sections intentionally has no registered default")
        expect(registeredDefaults[DefaultsKey.panelUtilityOrder] == nil,
               "panel utility order intentionally has no registered default")
        expect(registeredDefaults[DefaultsKey.panelToggleOrder] == nil,
               "panel toggle order intentionally has no registered default")
        expect(Defaults.sanitizedClipboardHistoryLimit(1_000) == 1_000,
               "larger clipboard history limits are preserved")
        expect(Defaults.sanitizedClipboardHistoryLimit(999) == 50,
               "unsupported clipboard history limits fall back to default")
        expect(Defaults.sanitizedMonitorInterval(5) == 5, "valid monitor interval is preserved")
        expect(Defaults.sanitizedMonitorInterval(7) == 2, "invalid monitor interval falls back to default")
        expect(Defaults.sanitizedMenuBarLabelStyle("classic") == "classic", "valid label style is preserved")
        expect(Defaults.sanitizedMenuBarLabelStyle("bad") == "compact", "invalid label style falls back to compact")
        expect(Defaults.sanitizedMenuBarMemoryStyle("percent") == "percent", "percent memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("dot") == "dot", "valid memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("both") == "both", "combined memory style is preserved")
        expect(Defaults.sanitizedMenuBarMemoryStyle("bad") == "percent", "invalid memory style falls back to percent")
        expect(Defaults.sanitizedMenuBarMetricOrder("cpu,gpu,memory,network,battery,power")
               == ["cpu", "gpu", "memory", "network", "battery", "power",
                   "cpuTemperature", "gpuTemperature", "batteryTime", "batteryTemperature", "peripheralBattery", "diskUsage", "diskActivity", "fanSpeed"],
               "menu bar metric order appends temperature sensors without rewriting existing saved order")
        expect(Defaults.sanitizedMenuBarMetricOrder("temperature,cpu,cpu,bad")
               == ["cpuTemperature", "gpuTemperature", "batteryTemperature",
                   "cpu", "gpu", "memory", "battery", "batteryTime", "peripheralBattery", "network", "diskUsage", "diskActivity", "power", "fanSpeed"],
               "menu bar metric order migrates the old generic temperature value")
        expect(Defaults.sanitizedBundleIdentifierList([" com.example.One ", "", "com.example.One", "com.example.Two"])
               == ["com.example.One", "com.example.Two"],
               "bundle id lists are trimmed and deduplicated")
        expect(Defaults.sanitizedAutoQuitExceptions(["com.example.One", Defaults.finderBundleIdentifier])
               == [Defaults.finderBundleIdentifier, "com.example.One"],
               "Finder is mandatory in the auto-quit exception list")
        expect(AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.direct",
                                          bundleURL: nil,
                                          exceptions: ["com.example.direct"]),
               "AutoQuit recognizes a direct bundle identifier exception")
        expect(AutoQuitSupport.isExcepted(
            bundleIdentifier: "com.parallels.winapp.0123456789abcdef.guest",
            bundleURL: nil,
            exceptions: ["com.parallels.desktop.console"]
        ), "AutoQuit extends a guest-window host exception to its generated app helpers")
        expect(!AutoQuitSupport.isExcepted(
            bundleIdentifier: "com.parallels.winapp.0123456789abcdef.guest",
            bundleURL: nil,
            exceptions: ["com.example.unrelated"]
        ), "AutoQuit does not protect a generated guest app without its host exception")
        let outerApp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChikitAutoQuitTests-\(UUID().uuidString)")
            .appendingPathComponent("Container.app")
        let nestedApp = outerApp.appendingPathComponent("Contents/MacOS/WindowHost.app")
        try? FileManager.default.createDirectory(at: nestedApp.appendingPathComponent("Contents"),
                                                 withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.container"])
            .write(to: outerApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.window-host"])
            .write(to: nestedApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        expect(AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.window-host",
                                          bundleURL: nestedApp,
                                          exceptions: ["com.example.container"]),
               "AutoQuit extends an outer app exception to its bundled window host")
        expect(!AutoQuitSupport.isExcepted(bundleIdentifier: "com.example.window-host",
                                           bundleURL: nestedApp,
                                           exceptions: ["com.example.unrelated"]),
               "AutoQuit does not extend unrelated exceptions to a bundled window host")
        let dependentApp = outerApp.appendingPathComponent("Contents/Hosted.app")
        try? FileManager.default.createDirectory(at: dependentApp.appendingPathComponent("Contents"),
                                                 withIntermediateDirectories: true)
        NSDictionary(dictionary: ["CFBundleIdentifier": "com.example.dependent",
                                  "CrBundleIdentifier": "com.example.host"])
            .write(to: dependentApp.appendingPathComponent("Contents/Info.plist"), atomically: true)
        expect(AutoQuitSupport.hasDependentApplication(hostBundleIdentifier: "com.example.host",
                                                       applicationBundleURLs: [dependentApp]),
               "AutoQuit keeps a host running while a declared dependent app is open")
        expect(!AutoQuitSupport.hasDependentApplication(hostBundleIdentifier: "com.example.unrelated",
                                                        applicationBundleURLs: [dependentApp]),
               "AutoQuit does not protect an unrelated host")
        try? FileManager.default.removeItem(at: outerApp.deletingLastPathComponent())
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appDeactivated,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat app deactivation as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appActivated,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat app activation as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .mainWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat main window changes as a window close")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .focusedWindowChanged,
                                                          hasRecentCloseRequest: false),
               "AutoQuit does not treat focused window changes as a window close")
        expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .windowDestroyed,
                                                         hasRecentCloseRequest: false),
               "AutoQuit checks windows after a destroyed window")
        expect(!AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                          hasRecentCloseRequest: false),
               "AutoQuit ignores hidden apps without a recent close request")
        expect(AutoQuitSupport.shouldScheduleWindowCheck(for: .appHidden,
                                                         hasRecentCloseRequest: true),
               "AutoQuit checks hidden apps after a recent close request")
        expect(AutoQuitSupport.isCommandW(keyCode: 13, command: true, control: false),
               "AutoQuit treats Command W as a close request")
        expect(!AutoQuitSupport.isCommandW(keyCode: 18, command: true, control: true),
               "AutoQuit does not treat Control number Space switching as a close request")
        expect(AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                          appIsTerminated: false,
                                                          appIsExcepted: false,
                                                          appIsHidden: false,
                                                          hiddenByCloseRequest: false,
                                                          hasKnownMinimizedWindow: false,
                                                          hasUserFacingWindow: false),
               "AutoQuit can quit when an app that had windows is now windowless")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: false,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit does not quit apps that started windowless")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: true,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps excepted apps running")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: true,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps hidden apps running without explicit close intent")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: true,
                                                           hasUserFacingWindow: false),
               "AutoQuit keeps apps running when a minimized window is known")
        expect(!AutoQuitSupport.shouldQuitAfterWindowCheck(hadWindows: true,
                                                           appIsTerminated: false,
                                                           appIsExcepted: false,
                                                           appIsHidden: false,
                                                           hiddenByCloseRequest: false,
                                                           hasKnownMinimizedWindow: false,
                                                           hasUserFacingWindow: true),
               "AutoQuit keeps apps with user-facing windows running")
        expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [4],
                                                            visibleSpaces: [3],
                                                            hasTitle: true),
               "a window parked on another Space keeps its app running")
        expect(!AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [3],
                                                             visibleSpaces: [3],
                                                             hasTitle: true),
               "a window the app hid on the Space in front does not keep it running")
        expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [],
                                                            visibleSpaces: [3],
                                                            hasTitle: true),
               "a window with no Space answer falls back to the title rule")
        expect(!AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [],
                                                             visibleSpaces: nil,
                                                             hasTitle: false),
               "an untitled off-screen window never keeps an app running")
        expect(AutoQuitSupport.offscreenWindowKeepsAppAlive(windowSpaces: [3],
                                                            visibleSpaces: nil,
                                                            hasTitle: true),
               "without Spaces to compare, the old cautious rule stands")

        expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                     listedWindows: 0,
                                                     foundUserWindow: true,
                                                     hadPriorWindows: false),
               "an app the window server still shows a window for is watched again")
        expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 1,
                                                     listedWindows: 2,
                                                     foundUserWindow: true,
                                                     hadPriorWindows: false),
               "a listed window whose notification failed is watched again")
        expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 2,
                                                       listedWindows: 2,
                                                       foundUserWindow: true,
                                                       hadPriorWindows: false),
               "two registered windows cover the two Accessibility listed windows")
        expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 1,
                                                       listedWindows: 1,
                                                       foundUserWindow: true,
                                                       hadPriorWindows: false),
               "a registered window is the watch, so nothing is retried")
        expect(AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                     listedWindows: 0,
                                                     foundUserWindow: false,
                                                     hadPriorWindows: false),
               "an app with no window on launch is retried during the initial watch window")
        expect(!AutoQuitSupport.needsWindowWatchRetry(registeredWindows: 0,
                                                       listedWindows: 0,
                                                       foundUserWindow: false,
                                                       hadPriorWindows: true),
               "an app that had prior windows and now closed its last window needs no watch retry")
        expect(AutoQuitSupport.isWindowNotificationRegistered(.success),
               "a window whose notification was accepted is watched")
        expect(AutoQuitSupport.isWindowNotificationRegistered(.notificationAlreadyRegistered),
               "a window already registered on this observer stays watched across refreshes")
        expect(!AutoQuitSupport.isWindowNotificationRegistered(.cannotComplete),
               "a window whose registration was refused is not watched")
        let autoQuitServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/AutoQuit/AutoQuitService.swift",
            encoding: .utf8)) ?? ""
        let autoQuitServiceLines = autoQuitServiceSource.components(separatedBy: "\n")
        func autoQuitServiceCodeLines(containing fragment: String) -> [Int] {
            autoQuitServiceLines.enumerated().compactMap { index, line in
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//"), code.contains(fragment) else { return nil }
                return index + 1
            }
        }
        // The retry has to stop: an app whose windows Accessibility can never
        // describe would otherwise be polled for as long as it runs. The
        // service is not part of this test binary, so pin the load-bearing
        // timing, stale-timer guard, and Space re-arm at their source lines.
        let windowWatchRetryCode = [
            "let serverWindow = windows.isEmpty ? hasWindowServerUserWindow(pid: pid) : nil",
            "let foundUserWindow = !windows.isEmpty || serverWindow == true",
            "private static let windowWatchRetryOffsets: [TimeInterval] = [0.5, 1.5, 4.0]",
            "retry.attemptsScheduled < Self.windowWatchRetryOffsets.count else { return }",
            "deadline: retry.origin + Self.windowWatchRetryOffsets[attempt]",
            "retry.pendingTimerID == timerID",
            "windowWatchRetries.removeAll()",
            "NSWorkspace.activeSpaceDidChangeNotification",
            "rearmWindowWatchRetries()",
            // The count the retry reads must be windows actually watched, not
            // windows Accessibility listed: AXObserverAddNotification can
            // refuse, and a refused registration is exactly the state the
            // retry exists for. Only the destroyed notification decides it.
            "if watch(window: window, observer: observer, refcon: refcon) { watchedWindows += 1 }",
            "needsWindowWatchRetry(registeredWindows: watchedWindows,",
            "listedWindows: windows.count,",
            "if notification == kAXUIElementDestroyedNotification {",
            "watched = AutoQuitSupport.isWindowNotificationRegistered(result)",
        ]
        let missingWindowWatchRetryCode = windowWatchRetryCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        expect(missingWindowWatchRetryCode.isEmpty,
               "the AutoQuit window-watch retry stays bounded, origin-based, re-armed by Space changes, and counts only windows whose destroy notification registered: missing \(missingWindowWatchRetryCode)")
        // Coalescing is only safe while the state it reads is torn down with
        // the app: a refresh left pending for a detached app would run against
        // an observer that is gone.
        let refreshCoalescingCode = [
            "guard pendingRefreshes.insert(pid).inserted else { return }",
            "self.pendingRefreshes.remove(pid) != nil",
            "pendingRefreshes.removeAll()",
        ]
        let missingRefreshCoalescingCode = refreshCoalescingCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        expect(missingRefreshCoalescingCode.isEmpty,
               "AutoQuit collapses a burst of notifications into one refresh and drops it when the app goes: missing \(missingRefreshCoalescingCode)")
        // Two lines drop the pending refresh: the deferred block's own guard
        // and `detach`. Losing the second is the case this counts.
        expect(autoQuitServiceCodeLines(containing: "pendingRefreshes.remove(pid)").count == 2,
               "a pending AutoQuit refresh is dropped both when it runs and when the app is detached")
        let closeCheckOffsetCode = [
            "private static let closeCheckOffsets: [TimeInterval] = [0.35, 1.0, 2.2]",
            "for offset in Self.closeCheckOffsets",
            "DispatchQueue.main.asyncAfter(deadline: origin + offset)",
        ]
        let missingCloseCheckOffsetCode = closeCheckOffsetCode.filter {
            autoQuitServiceCodeLines(containing: $0).isEmpty
        }
        expect(missingCloseCheckOffsetCode.isEmpty,
               "AutoQuit close checks remain offsets from one origin: missing \(missingCloseCheckOffsetCode)")

        // Attaching to a watched app must never ask its application element for
        // a role. A Chromium app (Electron, and the browsers) answers that by
        // switching its renderers into full accessibility mode, and then pays
        // to rebuild and ship an accessibility tree on every DOM change for the
        // rest of its life — measured on an idle app that this feature only
        // ever needed a window count from (issue #953). Windows are the same
        // liveness signal and leave that mode alone. Comments are stripped
        // first: the note above the probe names the attribute it avoids, and a
        // check that cannot tell prose from a call would go red for it.
        let autoQuitServiceCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/AutoQuit/AutoQuitService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        expect(autoQuitServiceCode.contains(
                   "AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windows) == .cannotComplete"),
               "AutoQuit probes a watched app for liveness by asking for its windows")
        // The same read reached the application element a second way, up the
        // parent chain of an element that never yields a window. Two files
        // carried that walk, so both the rule and its guard are repo wide
        // further down rather than a grep per copy here.
        expect(Defaults.sanitizedPanelItemOrder("uninstaller,homebrew,homebrew,bad",
                                                defaultOrder: ["homebrew", "media", "uninstaller", "cleanURL", "cleaning"])
               == ["uninstaller", "homebrew", "media", "cleanURL", "cleaning"],
               "panel item order keeps saved valid items first and appends defaults")

        // MARK: Window layout shortcut resolution (issue #169)

        expect(WindowLayoutAction.resolvedShortcut(storedValue: nil,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "window layout falls back to the default shortcut when nothing was saved")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: WindowLayoutAction.clearedShortcutStorageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault) == nil,
               "a cleared window layout shortcut resolves to no shortcut at all")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value",
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutLeftDefault,
               "a corrupt stored shortcut falls back to the default, never to cleared")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: GlobalShortcut.windowLayoutRightDefault.storageValue,
                                                   defaultShortcut: .windowLayoutLeftDefault)
               == .windowLayoutRightDefault,
               "a saved window layout shortcut wins over the default")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: nil, defaultShortcut: nil) == nil,
               "a window layout action without a default shortcut stays unassigned")
        expect(WindowLayoutAction.resolvedShortcut(storedValue: "garbage-value", defaultShortcut: nil) == nil,
               "a corrupt shortcut cannot assign an action that has no default")

        // MARK: Window layout restore history (issue #414)

        let historyWindow = WindowLayoutWindowKey(processID: 41,
                                                  processLaunchTime: 100,
                                                  windowID: 414)
        let otherHistoryWindow = WindowLayoutWindowKey(processID: 42,
                                                       processLaunchTime: 100,
                                                       windowID: 414)
        let reusedHistoryWindow = WindowLayoutWindowKey(processID: 41,
                                                        processLaunchTime: 101,
                                                        windowID: 414)
        let historyFrames: [WindowLayoutFrame] = (0...WindowLayoutHistory.perWindowLimit).map { index in
            let origin = CGPoint(x: index * 10, y: index * 20)
            let size = CGSize(width: 800 + index, height: 500 + index)
            return WindowLayoutFrame(origin: origin, size: size)
        }
        var layoutHistory = WindowLayoutHistory()
        layoutHistory.record(historyFrames[0], for: historyWindow)
        layoutHistory.record(historyFrames[1], for: historyWindow)
        layoutHistory.record(historyFrames[2], for: historyWindow)
        layoutHistory.record(historyFrames[3], for: otherHistoryWindow)
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[3]) == historyFrames[2]
               && layoutHistory.popPrevious(for: historyWindow, current: historyFrames[2]) == historyFrames[1]
               && layoutHistory.popPrevious(for: historyWindow, current: historyFrames[1]) == historyFrames[0],
               "window layout restore walks backward through each window's placement history")
        expect(layoutHistory.popPrevious(for: otherHistoryWindow, current: historyFrames[4]) == historyFrames[3],
               "window layout restore histories stay isolated across processes")
        layoutHistory.record(historyFrames[5], for: historyWindow)
        layoutHistory.record(historyFrames[6], for: historyWindow)
        layoutHistory.discardLatest(for: historyWindow)
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[7]) == historyFrames[5],
               "a failed window layout action removes only the frame it recorded")
        layoutHistory.record(historyFrames[8], for: historyWindow)
        layoutHistory.record(historyFrames[9], for: historyWindow)
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[9]) == historyFrames[8],
               "restore skips a saved frame that already matches the current placement")
        layoutHistory.record(historyFrames[10], for: historyWindow)
        layoutHistory.record(historyFrames[11], for: reusedHistoryWindow)
        layoutHistory.removeStaleWindows(keeping: [reusedHistoryWindow])
        expect(layoutHistory.popPrevious(for: historyWindow, current: historyFrames[12]) == nil
               && layoutHistory.popPrevious(for: reusedHistoryWindow,
                                            current: historyFrames[12]) == historyFrames[11],
               "closed windows and earlier process lifetimes cannot leak restore history")
        var boundedHistory = WindowLayoutHistory()
        for frame in historyFrames {
            boundedHistory.record(frame, for: historyWindow)
        }
        var boundedFrames: [WindowLayoutFrame] = []
        var boundedCurrent = WindowLayoutFrame(origin: CGPoint(x: -1, y: -1),
                                               size: CGSize(width: 1, height: 1))
        while let previous = boundedHistory.popPrevious(for: historyWindow, current: boundedCurrent) {
            boundedFrames.append(previous)
            boundedCurrent = previous
        }
        expect(boundedFrames.count == WindowLayoutHistory.perWindowLimit
               && boundedFrames.last == historyFrames[1],
               "window layout history keeps only the most recent bounded set of placements")

        // MARK: Window layout geometry

        let visibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 860)
        let currentWindow = CGRect(x: 200, y: 200, width: 800, height: 500)
        let snapVisibleFrame = CGRect(x: 0, y: 40, width: 1440, height: 835)
        let snapScreen = WindowEdgeSnapScreen(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                              visibleFrame: snapVisibleFrame)
        func snapTarget(_ point: CGPoint,
                        screens: [WindowEdgeSnapScreen] = [snapScreen]) -> WindowEdgeSnapTarget? {
            WindowEdgeSnapSupport.target(at: point, screens: screens)
        }
        let topSnapFrame = WindowLayoutGeometry.rect(for: .topHalf,
                                                     current: snapVisibleFrame,
                                                     visibleFrame: snapVisibleFrame)
        expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY))
               == WindowEdgeSnapTarget(action: .topHalf,
                                       frame: topSnapFrame,
                                       visibleFrame: snapVisibleFrame),
               "touching the lower edge of the menu bar previews the upper half")
        expect(snapTarget(CGPoint(x: 720, y: 900))?.action == .topHalf,
               "the full menu bar band remains a top snap target")
        expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY - 13)) == nil,
               "the top target does not reach below its activation band")
        expect(snapTarget(CGPoint(x: 0, y: 450))?.action == .leftHalf
               && snapTarget(CGPoint(x: 1440, y: 450))?.action == .rightHalf
               && snapTarget(CGPoint(x: 720, y: 0))?.action == .bottomHalf,
               "all four straight edges choose their matching halves")
        expect(snapTarget(CGPoint(x: 0, y: snapVisibleFrame.maxY))?.action == .topLeft
               && snapTarget(CGPoint(x: 1440, y: snapVisibleFrame.maxY))?.action == .topRight
               && snapTarget(CGPoint(x: 0, y: 0))?.action == .bottomLeft
               && snapTarget(CGPoint(x: 1440, y: 0))?.action == .bottomRight,
               "inclusive screen corners take priority over straight edges")
        expect(snapTarget(CGPoint(x: 720, y: 450)) == nil,
               "dragging inside a display never creates a snap target")

        let leftSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: -1280, y: 0, width: 1280, height: 800),
            visibleFrame: CGRect(x: -1280, y: 25, width: 1280, height: 775)
        )
        expect(snapTarget(CGPoint(x: -1280, y: 400), screens: [leftSnapScreen])?.frame
               == CGRect(x: -1280, y: 25, width: 640, height: 775),
               "edge snapping keeps negative display origins and its visible frame")
        let rightSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 1440, y: 40, width: 1920, height: 1040)
        )
        expect(snapTarget(CGPoint(x: 1440, y: 450),
                          screens: [snapScreen, rightSnapScreen]) == nil,
               "a shared display seam stays open for moving a window across")
        expect(WindowEdgeSnapSupport.target(at: CGPoint(x: 1415, y: 450),
                                            screens: [snapScreen, rightSnapScreen],
                                            distance: 30) == nil,
               "the whole activation band around a shared seam stays open")
        let upperSnapScreen = WindowEdgeSnapScreen(
            frame: CGRect(x: 0, y: 900, width: 1280, height: 800),
            visibleFrame: CGRect(x: 0, y: 900, width: 1280, height: 775)
        )
        expect(snapTarget(CGPoint(x: 720, y: snapVisibleFrame.maxY),
                          screens: [snapScreen, upperSnapScreen]) == nil,
               "a menu bar boundary below another display remains an open seam")
        expect(WindowEdgeSnapSupport.systemTilingEnabled { _ in nil },
               "unwritten system tiling choices keep their enabled default")
        expect(!WindowEdgeSnapSupport.systemTilingEnabled { _ in false },
               "edge snapping can start after every conflicting system choice is off")
        expect(WindowEdgeSnapSupport.systemTilingEnabled {
                   $0 == "EnableTilingByEdgeDrag" ? true : false
               },
               "one enabled system edge gesture is enough to prevent competing previews")

        let dragFrame = CGRect(x: 100, y: 100, width: 800, height: 500)
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 40, dy: 20),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 220)) == .moving,
               "edge snap confirms a window that follows the pointer")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame,
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 300, y: 300)) == .waiting,
               "a content drag with a still window never becomes window snapping")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: CGRect(x: 100, y: 100, width: 840, height: 500),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 200)) == .resizing,
               "native window resizing cancels edge snapping")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                   currentFrame: CGRect(x: 100, y: 50, width: 800, height: 500),
                   pointerStart: CGPoint(x: 200, y: 100),
                   pointerNow: CGPoint(x: 300, y: 150)) == .moving,
               "a tiled window restoring its size while dragged is still a window move")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: CGRect(x: 0, y: 0, width: 720, height: 900),
                   currentFrame: CGRect(x: 100, y: 0, width: 800, height: 900),
                   pointerStart: CGPoint(x: 200, y: 100),
                   pointerNow: CGPoint(x: 300, y: 100)) == .moving,
               "a side tile restoring only its width is still a horizontal window move")
        expect(WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.maxX, y: dragFrame.maxY),
                   frame: dragFrame),
               "a symmetric corner resize is rejected before movement classification")
        expect(WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.midX, y: dragFrame.minY + 3),
                   frame: dragFrame),
               "a symmetric edge resize is rejected at the native resize handle")
        expect(!WindowEdgeSnapSupport.startsAtResizeHandle(
                   CGPoint(x: dragFrame.midX, y: dragFrame.minY + 14),
                   frame: dragFrame),
               "the title bar stays available away from resize corners")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 40, dy: 0),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 160, y: 200)) == .unrelated,
               "an unrelated window move cannot follow a pointer going the other way")
        expect(WindowEdgeSnapSupport.classify(
                   initialFrame: dragFrame,
                   currentFrame: dragFrame.offsetBy(dx: 10, dy: 0),
                   pointerStart: CGPoint(x: 200, y: 200),
                   pointerNow: CGPoint(x: 240, y: 200)) == .moving,
               "a short Accessibility lag still confirms the same drag")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 860),
               "window layout left half targets the full left side")
        expect(WindowLayoutGeometry.rect(for: .rightHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 860),
               "window layout right half targets the full right side")
        expect(WindowLayoutGeometry.rect(for: .topHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 1440, height: 430),
               "window layout top half targets the upper visible frame")
        expect(WindowLayoutGeometry.rect(for: .bottomHalf, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1440, height: 430),
               "window layout bottom half targets the lower visible frame")
        expect(WindowLayoutGeometry.rect(for: .leftThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 480, height: 860),
               "window layout left third targets the first third")
        expect(WindowLayoutGeometry.rect(for: .centerThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 480, height: 860),
               "window layout center third targets the middle third")
        expect(WindowLayoutGeometry.rect(for: .rightThird, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 960, y: 40, width: 480, height: 860),
               "window layout right third targets the final third")
        expect(WindowLayoutGeometry.rect(for: .leftTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 960, height: 860),
               "window layout left two thirds targets the first two thirds")
        expect(WindowLayoutGeometry.rect(for: .rightTwoThirds, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 480, y: 40, width: 960, height: 860),
               "window layout right two thirds targets the final two thirds")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 0, y: 40, width: 712, height: 860),
               "the window gap shaves half the gap off the shared edge and leaves screen edges flush")
        expect(WindowLayoutGeometry.rect(for: .rightHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 728, y: 40, width: 712, height: 860),
               "two gapped halves end up exactly one window gap apart")
        expect(WindowLayoutGeometry.rect(for: .centerThird, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16)
               == CGRect(x: 488, y: 40, width: 464, height: 860),
               "a middle placement gives up half the gap on each shared edge")
        expect(WindowLayoutGeometry.rect(for: .topLeft, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 32)
               == CGRect(x: 0, y: 486, width: 704, height: 414),
               "a corner shaves only its two interior edges")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         screenGap: 32)
               == CGRect(x: 32, y: 72, width: 688, height: 796),
               "the screen gap insets the visible frame before placement")
        expect(WindowLayoutGeometry.rect(for: .maximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == CGRect(x: 32, y: 72, width: 1376, height: 796),
               "maximize respects the screen gap and ignores the window gap")
        expect(WindowLayoutGeometry.rect(for: .leftHalf, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == CGRect(x: 32, y: 72, width: 680, height: 796),
               "window and screen gaps combine")
        expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 64)
               == WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame),
               "centering has no neighbours, so the window gap leaves it alone")
        expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 64)
               == WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame),
               "margin maximize keeps its own margin instead of the window gap")
        expect(WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame,
                                         windowGap: 16, screenGap: 32)
               == WindowLayoutGeometry.rect(for: .marginMaximize, current: currentWindow, visibleFrame: visibleFrame),
               "margin maximize keeps its plain percentage margin under a screen gap instead of compounding")
        expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame,
                                         screenGap: 32)
               == WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame),
               "centering keeps the window's size under a screen gap instead of clamping to the inset frame")
        expect(WindowLayoutGeometry.screenGapFrame(CGRect(x: 0, y: 0, width: 100, height: 100), screenGap: 128)
               == CGRect(x: 10, y: 10, width: 80, height: 80),
               "an oversized screen gap keeps 80pt of layout space instead of inverting the frame")
        let sixthLayouts: [(WindowLayoutAction, CGRect, CGRect)] = [
            (.topLeftSixth,
             CGRect(x: 0, y: 470, width: 480, height: 430),
             CGRect(x: 0, y: 400, width: 600, height: 500)),
            (.topCenterSixth,
             CGRect(x: 480, y: 470, width: 480, height: 430),
             CGRect(x: 420, y: 400, width: 600, height: 500)),
            (.topRightSixth,
             CGRect(x: 960, y: 470, width: 480, height: 430),
             CGRect(x: 840, y: 400, width: 600, height: 500)),
            (.bottomLeftSixth,
             CGRect(x: 0, y: 40, width: 480, height: 430),
             CGRect(x: 0, y: 40, width: 600, height: 500)),
            (.bottomCenterSixth,
             CGRect(x: 480, y: 40, width: 480, height: 430),
             CGRect(x: 420, y: 40, width: 600, height: 500)),
            (.bottomRightSixth,
             CGRect(x: 960, y: 40, width: 480, height: 430),
             CGRect(x: 840, y: 40, width: 600, height: 500)),
        ]
        for (action, target, anchored) in sixthLayouts {
            expect(WindowLayoutGeometry.rect(for: action,
                                             current: currentWindow,
                                             visibleFrame: visibleFrame) == target,
                   "\(action.rawValue) targets its cell in the 3 by 2 grid")
            expect(WindowLayoutGeometry.anchoredRect(for: action,
                                                     targetRect: target,
                                                     actualSize: CGSize(width: 600, height: 500),
                                                     visibleFrame: visibleFrame) == anchored,
                   "\(action.rawValue) preserves its requested horizontal and vertical anchors")
            expect(WindowLayoutGeometry.accepts(actualRect: anchored,
                                                targetRect: target,
                                                action: action,
                                                anchorTolerance: 36),
                   "\(action.rawValue) accepts a larger minimum-sized window on the same anchors")
        }
        let nextDisplayFrame = CGRect(x: 1440, y: 80, width: 1920, height: 1000)
        let rightHalfWindow = CGRect(x: 720, y: 40, width: 720, height: 860)
        expect(WindowLayoutGeometry.rectForDisplay(current: rightHalfWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == CGRect(x: 2640, y: 220, width: 720, height: 860),
               "window layout display transfer keeps a right-half on the right and under the menu bar")
        let leftHalfWindow = CGRect(x: 0, y: 40, width: 720, height: 860)
        expect(WindowLayoutGeometry.rectForDisplay(current: leftHalfWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == CGRect(x: 1440, y: 220, width: 720, height: 860),
               "window layout display transfer keeps a left-half on the left and under the menu bar")
        let oversizedWindow = CGRect(x: -40, y: 0, width: 2000, height: 1200)
        expect(WindowLayoutGeometry.rectForDisplay(current: oversizedWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "window layout display transfer clamps oversized windows to the destination visible frame")
        expect(WindowLayoutGeometry.rectForDisplay(current: visibleFrame,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "display transfer fills the destination when the window already fills the source")
        let almostFilled = CGRect(x: 4, y: 44, width: 1432, height: 852)
        expect(WindowLayoutGeometry.rectForDisplay(current: almostFilled,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: nextDisplayFrame)
               == nextDisplayFrame,
               "display transfer treats a window within settle tolerance of maximize as filling the destination")
        let ultrawideFrame = CGRect(x: 1440, y: 0, width: 3440, height: 1400)
        expect(WindowLayoutGeometry.rectForDisplay(current: currentWindow,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1640, y: 700, width: 800, height: 500),
               "display transfer keeps a laptop window's size and top-left insets on an ultrawide")
        let nearFullWidth = CGRect(x: 2, y: 200, width: 1436, height: 500)
        expect(WindowLayoutGeometry.rectForDisplay(current: nearFullWidth,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1442, y: 700, width: 1436, height: 500),
               "display transfer keeps a near-full-width window's left inset on an ultrawide")
        let nearFullWidthRightish = CGRect(x: 6, y: 200, width: 1432, height: 500)
        expect(WindowLayoutGeometry.rectForDisplay(current: nearFullWidthRightish,
                                                   sourceVisibleFrame: visibleFrame,
                                                   destinationVisibleFrame: ultrawideFrame)
               == CGRect(x: 1446, y: 700, width: 1432, height: 500),
               "display transfer does not treat a few points of leftover width as a right edge")
        let shortDisplay = CGRect(x: 1440, y: 80, width: 1920, height: 400)
        let shrunkWindow = WindowLayoutGeometry.rectForDisplay(current: currentWindow,
                                                               sourceVisibleFrame: visibleFrame,
                                                               destinationVisibleFrame: shortDisplay)
        expect(shrunkWindow == CGRect(x: 1640, y: 80, width: 800, height: 400),
               "display transfer shrinks a taller window to fit a shorter display")
        expect(WindowLayoutGeometry.rectForDisplay(current: shrunkWindow,
                                                   sourceVisibleFrame: shortDisplay,
                                                   destinationVisibleFrame: visibleFrame)
               == CGRect(x: 200, y: 500, width: 800, height: 400),
               "display transfer does not restore the original height after shrinking to fit")
        let horizontalDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: -1200, y: -200, width: 1200, height: 1920),
            CGRect(x: 1440, y: 300, width: 2560, height: 1440),
        ]
        expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: horizontalDisplays,
                                                         movingForward: false) == 1
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 2,
                                                             frames: horizontalDisplays,
                                                             movingForward: true) == 1,
               "window layout orders unequal displays left to right and wraps both ways")
        let verticalDisplays = [
            CGRect(x: 0, y: 0, width: 1440, height: 900),
            CGRect(x: 0, y: 900, width: 900, height: 1440),
            CGRect(x: 0, y: -1200, width: 1920, height: 1200),
        ]
        expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: verticalDisplays,
                                                         movingForward: false) == 2
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                             frames: verticalDisplays,
                                                             movingForward: true) == 1,
               "window layout orders stacked displays by their vertical origin")
        expect(WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 0,
                                                         frames: [visibleFrame],
                                                         movingForward: false) == nil
                && WindowLayoutGeometry.adjacentDisplayIndex(currentIndex: 3,
                                                             frames: horizontalDisplays,
                                                             movingForward: true) == nil,
               "window layout leaves one display and invalid selections unchanged")
        let portraitFrame = CGRect(x: -1200, y: -200, width: 1200, height: 1800)
        let scaledFrame = CGRect(x: 1440, y: 100, width: 2000, height: 1000)
        let portraitWindow = CGRect(x: -900, y: 1000, width: 600, height: 400)
        let scaledWindow = WindowLayoutGeometry.rectForDisplay(current: portraitWindow,
                                                               sourceVisibleFrame: portraitFrame,
                                                               destinationVisibleFrame: scaledFrame)
        expect(scaledWindow == CGRect(x: 1740, y: 500, width: 600, height: 400)
                && WindowLayoutGeometry.rectForDisplay(current: scaledWindow,
                                                       sourceVisibleFrame: scaledFrame,
                                                       destinationVisibleFrame: portraitFrame)
                    == portraitWindow,
               "display transfer keeps size and edge insets across rotated frames")
        // The trimmed-down Window Layout module offers only the 9 core
        // layouts (4 halves, 4 quarters, maximize) for shortcut assignment;
        // every other case stays defined (for engine reuse and so a
        // previously stored shortcut/hidden-action/radial-menu value never
        // orphans) but is no longer shortcut-assignable.
        expect(WindowLayoutAction.shortcutActions.count == 9,
               "only the 9 core layouts can register a global shortcut")
        expect(!WindowLayoutAction.shortcutActions.contains(.previousDisplay)
                && !WindowLayoutAction.shortcutActions.contains(.nextDisplay),
               "display-move actions are no longer shortcut-assignable")
        expect(Set(WindowLayoutAction.shortcutActions.map(\.shortcutKey)).count
               == WindowLayoutAction.shortcutActions.count,
               "every window layout shortcut has its own defaults key")
        expect(WindowLayoutAction.shortcutActions.contains(.leftHalf),
               "existing half actions keep global shortcuts")
        expect([WindowLayoutAction.topLeft, .topRight, .bottomLeft, .bottomRight]
               .allSatisfy { $0.supportsShortcut },
               "the 4 quarter actions remain shortcut-assignable")
        expect([WindowLayoutAction.topLeftSixth, .topCenterSixth, .topRightSixth,
                .bottomLeftSixth, .bottomCenterSixth, .bottomRightSixth]
               .allSatisfy { !$0.supportsShortcut },
               "sixth actions are hidden from shortcut assignment in the trimmed module")
        expect(WindowLayoutGeometry.rect(for: .topLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 470, width: 720, height: 430),
               "window layout top left targets the upper-left quadrant")
        expect(WindowLayoutGeometry.rect(for: .topRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 470, width: 720, height: 430),
               "window layout top right targets the upper-right quadrant")
        expect(WindowLayoutGeometry.rect(for: .bottomLeft, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 720, height: 430),
               "window layout bottom left targets the lower-left quadrant")
        expect(WindowLayoutGeometry.rect(for: .bottomRight, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 720, y: 40, width: 720, height: 430),
               "window layout bottom right targets the lower-right quadrant")
        expect(WindowLayoutGeometry.rect(for: .maximize, current: currentWindow, visibleFrame: visibleFrame)
               == visibleFrame,
               "window layout maximize uses the full visible frame")
        let marginMaximizeTarget = WindowLayoutGeometry.rect(for: .marginMaximize,
                                                              current: currentWindow,
                                                              visibleFrame: visibleFrame)
        expect(marginMaximizeTarget == CGRect(x: 72, y: 83, width: 1296, height: 774),
               "window layout margin maximize keeps five percent on every usable edge")
        expect(WindowLayoutGeometry.rect(for: .center, current: currentWindow, visibleFrame: visibleFrame)
               == CGRect(x: 320, y: 220, width: 800, height: 500),
               "window layout center preserves current size and centers inside the visible frame")
        expect(WindowLayoutGeometry.rect(for: .restore, current: currentWindow, visibleFrame: visibleFrame)
               == currentWindow,
               "window layout restore keeps the saved frame")
        let topWindow = CGRect(x: 0, y: 470, width: 1440, height: 430)
        let bottomWindow = CGRect(x: 0, y: 40, width: 1440, height: 430)
        let leftWindow = CGRect(x: 0, y: 40, width: 720, height: 860)
        let topLeftWindow = CGRect(x: 0, y: 470, width: 720, height: 430)
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays direct when the previous layout action was not top")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .maximize,
               "window layout top half promotes only when top is used twice in a row")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top half stays top when the window is elsewhere")
        expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom does not promote while at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .topHalf) == .leftHalf,
               "window layout left does not become a corner after top")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: topWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the top")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct when the window is already at the bottom")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame) == .rightHalf,
               "window layout right stays direct when the window is already at the bottom")
        expect(WindowLayoutGeometry.effectiveAction(for: .leftHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .leftHalf,
               "window layout left stays direct from the upper-left corner")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: topLeftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct from the upper-left corner")
        expect(WindowLayoutGeometry.effectiveAction(for: .topHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .topHalf,
               "window layout top stays direct when the window is already on the left")
        expect(WindowLayoutGeometry.effectiveAction(for: .bottomHalf,
                                                    current: leftWindow,
                                                    visibleFrame: visibleFrame) == .bottomHalf,
               "window layout bottom stays direct when the window is already on the left")
        expect(WindowLayoutGeometry.effectiveAction(for: .rightHalf,
                                                    current: bottomWindow,
                                                    visibleFrame: visibleFrame,
                                                    previousAction: .bottomHalf) == .rightHalf,
               "window layout right does not become a corner after bottom")
        let leftTarget = WindowLayoutGeometry.rect(for: .leftHalf,
                                                   current: currentWindow,
                                                   visibleFrame: visibleFrame)
        let rightTarget = WindowLayoutGeometry.rect(for: .rightHalf,
                                                    current: currentWindow,
                                                    visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 0, y: 40, width: 720, height: 430),
                                            targetRect: leftTarget,
                                            action: .leftHalf,
                                            anchorTolerance: 36) == false,
               "window layout left half does not accept a lower-left corner as the full side")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 720, y: 40, width: 720, height: 430),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36) == false,
               "window layout right half does not accept a lower-right corner as the full side")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 540, y: 40, width: 900, height: 860),
                                            targetRect: rightTarget,
                                            action: .rightHalf,
                                            anchorTolerance: 36),
               "window layout right half accepts a larger app minimum size when it spans the full height")
        expect(WindowLayoutGeometry.anchoredRect(for: .rightHalf,
                                                 targetRect: rightTarget,
                                                 actualSize: CGSize(width: 900, height: 700),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 700),
               "window layout right anchors the accepted app size to the right edge")
        let bottomTarget = WindowLayoutGeometry.rect(for: .bottomHalf,
                                                     current: currentWindow,
                                                     visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.anchoredRect(for: .bottomHalf,
                                                 targetRect: bottomTarget,
                                                 actualSize: CGSize(width: 1000, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 0, y: 40, width: 1000, height: 620),
               "window layout bottom anchors the accepted app size to the bottom edge")
        let bottomRightTarget = WindowLayoutGeometry.rect(for: .bottomRight,
                                                          current: currentWindow,
                                                          visibleFrame: visibleFrame)
        expect(WindowLayoutGeometry.anchoredRect(for: .bottomRight,
                                                 targetRect: bottomRightTarget,
                                                 actualSize: CGSize(width: 900, height: 620),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 540, y: 40, width: 900, height: 620),
               "window layout bottom right anchors the accepted app size to both requested edges")
        expect(WindowLayoutGeometry.anchoredRect(for: .marginMaximize,
                                                 targetRect: marginMaximizeTarget,
                                                 actualSize: CGSize(width: 1400, height: 820),
                                                 visibleFrame: visibleFrame)
               == CGRect(x: 20, y: 60, width: 1400, height: 820),
               "window layout margin maximize keeps a constrained app centered")
        expect(WindowLayoutGeometry.accepts(actualRect: CGRect(x: 320, y: 220, width: 800, height: 500),
                                            targetRect: marginMaximizeTarget,
                                            action: .marginMaximize,
                                            anchorTolerance: 36) == false,
               "window layout margin maximize rejects a merely centered small window")

        // MARK: Window move and resize gestures

        expect(WindowGestureSupport.modifiers(from: nil) == [.control, .command],
               "window gestures fall back to control-command")
        expect(WindowGestureSupport.modifiers(from: "option+shift") == [.option],
               "shift stays reserved for trackpad resizing")
        expect(WindowGestureSupport.modifiers(from: "shift") == [.control, .command],
               "shift alone never takes over ordinary system dragging")
        expect(WindowGestureSupport.modifiers(from: "invalid") == [.control, .command],
               "corrupt window gesture modifiers fall back safely")
        expect(WindowGestureSupport.storageValue(for: [.command, .control]) == "control+command",
               "window gesture modifiers serialize in stable order")
        expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand],
                                                   expected: [.control, .command]),
               "window gestures match their exact modifier chord")
        expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                    expected: [.control, .command]),
               "the resize chord does not trigger window movement")
        let resizeModifiers = WindowGestureSupport.resizeModifiers(from: [.control, .command])
        expect(resizeModifiers == [.control, .shift, .command],
               "trackpad resizing adds shift to the chosen move chord")
        expect(WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift],
                                                   expected: resizeModifiers),
               "trackpad resizing matches its exact primary-drag chord")
        expect(!WindowGestureSupport.modifiersMatch(eventFlags: [.maskControl, .maskCommand, .maskShift, .maskAlternate],
                                                    expected: resizeModifiers),
               "unexpected extra modifiers do not trigger trackpad resizing")
        expect(WindowGestureSupport.movedOrigin(from: CGPoint(x: 100, y: 80),
                                                pointerStart: CGPoint(x: 300, y: 200),
                                                pointerNow: CGPoint(x: 345, y: 175))
               == CGPoint(x: 145, y: 55),
               "window movement follows the full pointer delta")
        let gestureFrame = CGRect(x: 100, y: 80, width: 600, height: 420)
        expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 110, y: 90), in: gestureFrame)
               == [.left, .top],
               "a top-left press resizes from both matching edges")
        expect(WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 90), in: gestureFrame)
               == [.top],
               "a top-center press resizes only the top edge")
        expect(!WindowGestureSupport.resizeEdges(at: CGPoint(x: 400, y: 290), in: gestureFrame).isEmpty,
               "the center region always chooses a usable nearest edge")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 110, y: 90),
                                                 pointerNow: CGPoint(x: 160, y: 120),
                                                 edges: [.left, .top])
               == CGRect(x: 150, y: 110, width: 550, height: 390),
               "top-left resizing keeps the opposite corner anchored")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 690, y: 490),
                                                 pointerNow: CGPoint(x: 760, y: 540),
                                                 edges: [.right, .bottom])
               == CGRect(x: 100, y: 80, width: 670, height: 470),
               "bottom-right resizing grows in both axes")
        expect(WindowGestureSupport.resizedFrame(from: gestureFrame,
                                                 pointerStart: CGPoint(x: 100, y: 80),
                                                 pointerNow: CGPoint(x: 900, y: 700),
                                                 edges: [.left, .top])
               == CGRect(x: 580, y: 420, width: 120, height: 80),
               "gesture minimum size keeps the far corner fixed")
        expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: CGPoint(x: 580, y: 420),
                                                   acceptedSize: CGSize(width: 260, height: 180),
                                                   edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "an app-specific minimum size keeps the opposite corner anchored")
        expect(WindowGestureSupport.anchoredOrigin(original: gestureFrame,
                                                   requestedOrigin: gestureFrame.origin,
                                                   acceptedSize: CGSize(width: 760, height: 540),
                                                   edges: [.right, .bottom])
               == gestureFrame.origin,
               "right and bottom resizing keep the original window origin")
        expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: gestureFrame.origin,
                                                           acceptedSize: CGSize(width: 760, height: 540),
                                                           edges: [.right, .bottom]) == nil,
               "right and bottom resizing never adds a redundant position mutation")
        expect(WindowGestureSupport.anchoredOriginIfNeeded(original: gestureFrame,
                                                           requestedOrigin: CGPoint(x: 580, y: 420),
                                                           acceptedSize: CGSize(width: 260, height: 180),
                                                           edges: [.left, .top])
               == CGPoint(x: 440, y: 320),
               "left and top resizing reanchors only after the accepted size is known")

        // MARK: Click versus drag custody (issue #321)

        let slopOrigin = CGPoint(x: 100, y: 80)
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: slopOrigin),
               "a press that never moves stays a click")
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 106, y: 80)),
               "movement exactly at the slop still counts as a click")
        expect(WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 106.1, y: 80)),
               "movement past the slop becomes a window gesture")
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 94, y: 80)),
               "the slop is symmetric in both directions")
        expect(WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 105, y: 85)),
               "diagonal movement is measured as a distance, not per axis")
        expect(!WindowGestureSupport.exceedsDragSlop(from: slopOrigin, to: CGPoint(x: 95, y: 77)),
               "hand jitter under the slop keeps the click")

        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDown(sameButton: false, chordMatched: false)) == .passThrough,
               "a press without the chord is never touched")
        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDown(sameButton: false, chordMatched: true)) == .arm,
               "a press with the chord is only held, not taken")
        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .buttonDragged(tracked: false, pastSlop: true)) == .passThrough,
               "movement with nothing held is never touched")
        expect(WindowGestureSupport.decide(state: .idle, input: .buttonUp(tracked: false)) == .passThrough,
               "a release with nothing held is never touched")
        expect(WindowGestureSupport.decide(state: .idle,
                                           input: .tapDisabled(buttonStillDown: false)) == .passThrough,
               "an idle tap has nothing to give back when it is switched off")

        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: true, pastSlop: false)) == .hold,
               "jitter under the slop keeps the press held")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: true, pastSlop: true)) == .promote,
               "movement past the slop turns the held press into a gesture")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDragged(tracked: false, pastSlop: true)) == .flushThenPass,
               "movement of another button gives the held press back")
        expect(WindowGestureSupport.decide(state: .pending, input: .buttonUp(tracked: true)) == .replayThenPass,
               "a release without movement gives the whole click back to the app")
        expect(WindowGestureSupport.decide(state: .pending, input: .buttonUp(tracked: false)) == .flushThenPass,
               "a release of another button gives the held press back")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: true, chordMatched: true)) == .restartAsIdle,
               "the same button pressing again replaces a held press whose release went missing")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: true, chordMatched: false)) == .restartAsIdle,
               "a stale held press is cleared even when the new press has no chord")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: false, chordMatched: true)) == .flushThenRestart,
               "a second button gives the first press back instead of eating it")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .buttonDown(sameButton: false, chordMatched: false)) == .flushThenRestart,
               "a second button without the chord also gives the first press back")
        expect(WindowGestureSupport.decide(state: .pending, input: .otherEvent) == .flushThenPass,
               "anything unexpected gives the held press back")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .tapDisabled(buttonStillDown: true)) == .flushThenPass,
               "a tap switched off while the button is still down gives the click back")
        expect(WindowGestureSupport.decide(state: .pending,
                                           input: .tapDisabled(buttonStillDown: false)) == .dropState,
               "a press whose release already reached the app is never handed back pressed")
        expect(WindowGestureSupport.decide(state: .pending, input: .accessibilityLost) == .flushThenPass,
               "losing Accessibility mid press still gives the click back")

        expect(WindowGestureSupport.decide(state: .active,
                                           input: .buttonDragged(tracked: true, pastSlop: false)) == .applyMove,
               "a running gesture keeps following the pointer")
        expect(WindowGestureSupport.decide(state: .active, input: .buttonUp(tracked: true)) == .applyFinish,
               "releasing ends a running gesture")
        expect(WindowGestureSupport.decide(state: .active, input: .buttonUp(tracked: false)) == .passThrough,
               "another button is never swallowed by a running gesture")
        expect(WindowGestureSupport.decide(state: .active, input: .otherEvent) == .passThrough,
               "a running gesture never swallows unrelated events")
        expect(WindowGestureSupport.decide(state: .active,
                                           input: .tapDisabled(buttonStillDown: true)) == .dropState,
               "a gesture that already took the press has nothing to give back")
        expect(WindowGestureSupport.decide(state: .active, input: .accessibilityLost) == .dropState,
               "losing Accessibility mid gesture drops it without a phantom click")

        // No path may invent a release, and every held press is given back
        // exactly once: only these decisions replay, and none of them can be
        // reached twice for the same press.
        let allInputs: [WindowGestureInput] = [
            .buttonDown(sameButton: true, chordMatched: true),
            .buttonDown(sameButton: true, chordMatched: false),
            .buttonDown(sameButton: false, chordMatched: true),
            .buttonDown(sameButton: false, chordMatched: false),
            .buttonDragged(tracked: true, pastSlop: true),
            .buttonDragged(tracked: true, pastSlop: false),
            .buttonDragged(tracked: false, pastSlop: true),
            .buttonDragged(tracked: false, pastSlop: false),
            .buttonUp(tracked: true), .buttonUp(tracked: false),
            .otherEvent, .tapDisabled(buttonStillDown: true),
            .tapDisabled(buttonStillDown: false), .accessibilityLost,
        ]
        var pendingExits = 0
        var pendingReplays = 0
        for input in allInputs {
            let decision = WindowGestureSupport.decide(state: .pending, input: input)
            if decision != .hold {
                pendingExits += 1
                if decision == .replayThenPass || decision == .flushThenPass
                    || decision == .flushThenRestart { pendingReplays += 1 }
            }
            let replaying: [WindowGestureDecision] = [.replayThenPass, .flushThenPass, .flushThenRestart]
            expect(!replaying.contains(WindowGestureSupport.decide(state: .idle, input: input)),
                   "nothing is ever replayed while no press is held")
            expect(!replaying.contains(WindowGestureSupport.decide(state: .active, input: input)),
                   "a press already spent on a gesture is never replayed")
        }
        expect(pendingExits == 13 && pendingReplays == 9,
               "every way out of a held press either promotes it, replaces it or gives it back")

        // MARK: Directional pointer layout

        let dirOrigin = CGPoint(x: 200, y: 200)
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: dirOrigin) == nil,
               "stationary pointer does not trigger directional layout")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 220, y: 200)) == nil,
               "pointer movement below activation distance produces no action")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 200)) == .rightHalf,
               "moving right triggers right half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 350, y: 200)) == .rightHalf,
               "fast long flick right triggers right half reliably")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 200)) == .leftHalf,
               "moving left triggers left half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 240)) == .topHalf,
               "moving up triggers top half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 350)) == .topHalf,
               "fast long flick up triggers top half reliably")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 160)) == .bottomHalf,
               "moving down triggers bottom half")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 200, y: 50)) == .bottomHalf,
               "fast long flick down triggers bottom half without accidental minimize")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 240)) == .topRight,
               "moving up-right triggers top right")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 240)) == .topLeft,
               "moving up-left triggers top left")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 240, y: 160)) == .bottomRight,
               "moving down-right triggers bottom right")
        expect(WindowDirectionalGestureSupport.action(from: dirOrigin, to: CGPoint(x: 160, y: 160)) == .bottomLeft,
               "moving down-left triggers bottom left")

        let rotatedImageProperties: [CFString: Any] = [
            kCGImagePropertyPixelWidth: 640,
            kCGImagePropertyPixelHeight: 480,
            kCGImagePropertyOrientation: 6,
        ]
        let oversizedImageProperties: [CFString: Any] = [
            kCGImagePropertyPixelWidth: Double.greatestFiniteMagnitude,
            kCGImagePropertyPixelHeight: 1,
            kCGImagePropertyOrientation: 6,
        ]
        let renameDate = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01 UTC
        let legacyResizeJSON = #"{"kind":"exact","maxDimension":1600,"width":320,"height":180}"#
        // MARK: Media size targets

        // The case the mode exists for: a minute of 1080p that has to fit the
        // 20 MB a chat service accepts without paid tiers.
        // Short clips have bitrate to spare, so nothing is thrown away.
        // A budget too thin to be watchable is refused rather than encoded.
        // Rate control lands near the budget, so an overshoot is measured and
        // scaled down rather than retried at the same setting.
        // A GIF has no bitrate, so overshoot is corrected on frames first.
        let sizeTargetStrings: [(String, Strings)] = [
            ("en-US", .enUS), ("pt-BR", .ptBR), ("tr", .tr), ("ru", .ru), ("es", .es),
            ("de", .de), ("fr", .fr), ("it", .it), ("ja", .ja), ("ko", .ko),
            ("zh-Hans", .zhHans), ("zh-HK", .zhHK), ("zh-TW", .zhTW),
        ]
        for (name, strings) in sizeTargetStrings {
            expect(!strings.mediaSizingResolution.isEmpty
                    && !strings.mediaSizingFileSize.isEmpty
                    && !strings.mediaTargetSize.isEmpty
                    && !strings.mediaTargetSizeHint.isEmpty
                    && !strings.mediaErrorTargetTooSmall.isEmpty
                    && !strings.mediaMegabytesSuffix.isEmpty,
                   "\(name) names the size target controls")
        }
        for language in AppLanguage.allCases {
            let strings = MediaImageConverterStrings.localized(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 56 && values.allSatisfy { !$0.isEmpty },
                   "every image converter string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible image converter strings (\(language.rawValue))")
            expect(strings.filesSelectedFormat.contains("%d")
                   && strings.profileDefaultNameFormat.contains("%d")
                   && strings.savedBytesFormat.contains("%@")
                   && strings.grewBytesFormat.contains("%@")
                   && strings.batchSavedFormat.contains("%d")
                   && strings.batchPartialFormat.filter { $0 == "%" }.count == 2
                   && strings.batchSummaryHeaderFormat.filter { $0 == "%" }.count == 2
                   && strings.batchSummaryItemFormat.filter { $0 == "%" }.count == 2,
                   "image converter formats keep their arguments in \(language.rawValue)")
        }

        expectClose(Defaults.sanitizedAppVolume(1.5), 1.5, "valid app volume is preserved")
        expectClose(Defaults.sanitizedAppVolume(3), 2, "high app volume clamps to boost maximum")
        expectClose(Defaults.sanitizedAppVolume(-1), 0, "negative app volume clamps to mute")
        expectClose(Defaults.sanitizedAppVolume(.infinity), 1, "non-finite app volume falls back to unity")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "40",
                                                       maximumPercent: 200) ?? -1,
                    0.4,
                    "mixer percentage input becomes app gain")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: " 75% ",
                                                       maximumPercent: 100) ?? -1,
                    0.75,
                    "mixer percentage input accepts a percent sign")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "250",
                                                       maximumPercent: 200) ?? -1,
                    2,
                    "mixer percentage input clamps to the row maximum")
        expectClose(MixerRoutingSupport.volumeFraction(fromPercentageText: "-10",
                                                       maximumPercent: 100) ?? -1,
                    0,
                    "mixer percentage input clamps negative values")
        expect(MixerRoutingSupport.volumeFraction(fromPercentageText: "loud",
                                                  maximumPercent: 100) == nil,
               "mixer percentage input rejects non-numbers")
        expect(MixerRoutingSupport.volumeFraction(fromPercentageText: "nan",
                                                  maximumPercent: 100) == nil,
               "mixer percentage input rejects non-finite numbers")
        let percentWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 80, height: 24),
                                     styleMask: .borderless,
                                     backing: .buffered,
                                     defer: false)
        let percentField = MixerPercentNativeTextField(frame: percentWindow.contentView!.bounds)
        percentField.stringValue = "37"
        var percentFieldAttached = false
        percentField.didAttachToWindow = { percentFieldAttached = true }
        percentWindow.contentView?.addSubview(percentField)
        expect(percentFieldAttached,
               "mixer percentage field notices when it joins its popover window")
        expect(percentField.focusAndSelectAll(),
               "mixer percentage field becomes the native first responder")
        expect((percentField.currentEditor() as? NSTextView)?.selectedRange()
                == NSRange(location: 0, length: 2),
               "mixer percentage field selects its existing value for direct replacement")
        percentWindow.orderOut(nil)
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(35) == 35,
               "headphone disconnect volume preserves valid percentages")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(-5)
               == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect volume never drops below the audible floor")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(0)
               == Defaults.minimumMixerHeadphonesDisconnectVolumePercent,
               "headphone disconnect protection lowers the speakers, it never silences them")
        expect(Defaults.sanitizedMixerHeadphonesDisconnectVolumePercent(105) == 100,
               "headphone disconnect volume clamps high values")
        let headphonesSuite = "chikit.tests.mixer.headphones"
        if let silentHeadphoneVolume = UserDefaults(suiteName: headphonesSuite) {
            silentHeadphoneVolume.removePersistentDomain(forName: headphonesSuite)
            silentHeadphoneVolume.set(0, forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
            Defaults.migrateSilentHeadphonesDisconnectVolume(in: silentHeadphoneVolume)
            expect(silentHeadphoneVolume.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
                   == Defaults.defaultMixerHeadphonesDisconnectVolumePercent,
                   "a stored volume of zero from the first release of the option migrates to the default")
            silentHeadphoneVolume.set(60, forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent)
            Defaults.migrateSilentHeadphonesDisconnectVolume(in: silentHeadphoneVolume)
            expect(silentHeadphoneVolume.integer(forKey: DefaultsKey.mixerHeadphonesDisconnectVolumePercent) == 60,
                   "a volume the user chose is never migrated")
            silentHeadphoneVolume.removePersistentDomain(forName: headphonesSuite)
        }
        expect(Defaults.sanitizedAppOutputDeviceUID(" BuiltInSpeakerDevice ") == "BuiltInSpeakerDevice",
               "audio output device UIDs are trimmed")
        expect(Defaults.sanitizedAppOutputDeviceUID("") == nil,
               "empty audio output device UIDs are ignored")
        expect(Defaults.sanitizedAppOutputDeviceUID("bad\nuid") == nil,
               "control characters are rejected from audio output device UIDs")
        expect(Defaults.sanitizedPreferredInputDeviceUID(" BuiltInMicrophoneDevice ") == "BuiltInMicrophoneDevice",
               "audio input device UIDs are trimmed")
        expect(Defaults.sanitizedPreferredInputDeviceUID("") == nil,
               "empty audio input device UIDs are ignored")
        let savedRoutes = Defaults.sanitizedAppOutputDevices([
            "com.apple.Safari": "BuiltInSpeakerDevice",
            "bad\napp": "ExternalDisplay",
            "com.example.Empty": "",
        ])
        expect(savedRoutes == ["com.apple.Safari": "BuiltInSpeakerDevice"],
               "app output device routes keep only valid app and device ids")
        expect(Defaults.sanitizedSoundOutputSwitcherDeviceUIDs([
            " BuiltInSpeakerDevice ",
            "bad\nuid",
            "BuiltInSpeakerDevice",
            "ExternalDisplay",
            7,
        ]) == ["BuiltInSpeakerDevice", "ExternalDisplay"],
               "sound output switcher keeps valid unique device ids in order")
        let savedMixerVolumes = ["com.apple.Safari": 0.35, "com.apple.Music": 1.4]
        let successfulUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: true)
        expect(successfulUniversalOutput.outputDeviceUIDs.isEmpty,
               "universal output clears per-app routes after a successful switch")
        expect(successfulUniversalOutput.volumes == savedMixerVolumes,
               "universal output preserves saved app volumes")
        let failedUniversalOutput = MixerRoutingSupport.preferencesAfterUniversalOutputSwitch(
            outputDeviceUIDs: savedRoutes,
            volumes: savedMixerVolumes,
            switchSucceeded: false)
        expect(failedUniversalOutput.outputDeviceUIDs == savedRoutes,
               "failed universal output keeps per-app routes")
        expect(failedUniversalOutput.volumes == savedMixerVolumes,
               "failed universal output keeps saved app volumes")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher moves from the current selected output to the next")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "ExternalDisplay",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher wraps selected outputs")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "USBHeadphones",
            selectedUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "BuiltInSpeakerDevice",
               "sound output switcher starts at the first selected output when current is outside the cycle")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice", "MissingDisplay", "ExternalDisplay"],
            availableUIDs: ["BuiltInSpeakerDevice", "ExternalDisplay"]) == "ExternalDisplay",
               "sound output switcher skips unavailable selected outputs")
        expect(MixerRoutingSupport.nextSelectedOutputDeviceUID(
            currentUID: "BuiltInSpeakerDevice",
            selectedUIDs: ["BuiltInSpeakerDevice"],
            availableUIDs: ["BuiltInSpeakerDevice"]) == nil,
               "sound output switcher does nothing when the only selected output is already current")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "AirPods Pro",
                                                             uid: "",
                                                             dataSourceName: nil),
               "AirPods are treated as headphones")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Built-in Output",
                                                             uid: "",
                                                             dataSourceName: "Headphones"),
               "wired headphone data source is treated as headphones")
        expect(MixerRoutingSupport.outputLooksLikeHeadphones(name: "Sony WH-1000XM5",
                                                             uid: "",
                                                             dataSourceName: nil),
               "common Bluetooth headphone names are treated as headphones")
        expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "MacBook Pro Speakers",
                                                              uid: "BuiltInSpeakerDevice",
                                                              dataSourceName: nil),
               "built-in speakers are not treated as headphones")
        expect(!MixerRoutingSupport.outputLooksLikeHeadphones(name: "JBL Flip",
                                                              uid: "",
                                                              dataSourceName: nil),
               "Bluetooth speakers are not treated as headphones")
        // Issue #256: some browsers' audio helpers answer for themselves, so
        // the mixer walks the parent chain to the nearest regular app.
        let helperParents: [pid_t: pid_t] = [500: 100, 100: 1, 700: 1,
                                             900: 901, 901: 902, 902: 903, 903: 904,
                                             904: 905, 905: 906, 906: 907, 907: 100]
        func owningApp(of responsible: pid_t, regularApps: Set<pid_t> = [100]) -> pid_t? {
            MixerRoutingSupport.owningRegularAppPid(
                responsiblePid: responsible,
                isRegularApp: { regularApps.contains($0) },
                parentPid: { helperParents[$0] ?? 0 })
        }
        expect(owningApp(of: 100) == 100,
               "a responsible regular app is billed directly")
        expect(owningApp(of: 500) == 100,
               "a helper answering for itself is billed to the app that spawned it")
        expect(owningApp(of: 700) == nil,
               "daemons whose parent chain ends at launchd stay unlisted")
        expect(owningApp(of: 42) == nil,
               "a failed parent lookup stops the walk")
        expect(owningApp(of: 900) == nil,
               "the parent walk gives up beyond the depth cap")
        expect(owningApp(of: 902) == 100,
               "a regular app within the depth cap is still found")
        expect(owningApp(of: 0) == nil,
               "a missing responsible pid maps to no app")
        func resolvedOwningApp(responsible: pid_t, pid: pid_t, regularApps: Set<pid_t> = [100]) -> pid_t? {
            let isRegular: (pid_t) -> Bool = { regularApps.contains($0) }
            let parent: (pid_t) -> pid_t = { helperParents[$0] ?? 0 }
            return MixerRoutingSupport.owningRegularAppPid(
                responsiblePid: responsible,
                isRegularApp: isRegular,
                parentPid: parent
            ) ?? (responsible != pid ? MixerRoutingSupport.owningRegularAppPid(
                responsiblePid: pid,
                isRegularApp: isRegular,
                parentPid: parent
            ) : nil)
        }
        expect(resolvedOwningApp(responsible: 700, pid: 500) == 100,
               "a helper whose responsibility returns a daemon still falls back to its parent app")
        expect(!MixerRoutingSupport.requiresEngine(volume: 1,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output at 100 percent stays passthrough")
        expect(MixerRoutingSupport.requiresEngine(volume: 0.5,
                                                  selectedOutputDeviceUID: nil,
                                                  targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "default output with changed volume uses an engine")
        expect(MixerRoutingSupport.requiresEngine(volume: 1,
                                                  selectedOutputDeviceUID: "ExternalDisplay",
                                                  targetOutputDeviceUID: "ExternalDisplay",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "specific non-default output at 100 percent uses an engine")
        expect(!MixerRoutingSupport.requiresEngine(hasAudioObjects: false,
                                                   volume: 0.5,
                                                   selectedOutputDeviceUID: nil,
                                                   targetOutputDeviceUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a persistent mixer row waits for an audio connection before building a tap")
        expect(MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                 volume: 1,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: false),
               "the inactive-app filter changes nothing until the user enables it")
        expect(!MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                  volume: 1,
                                                  selectedOutputDeviceUID: nil,
                                                  hideInactiveApps: true),
               "an idle uncustomized mixer app can be hidden")
        expect(MixerRoutingSupport.shouldShowApp(isPlaying: true,
                                                 volume: 1,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: true),
               "a playing mixer app remains visible")
        expect(MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                 volume: 0.75,
                                                 selectedOutputDeviceUID: nil,
                                                 hideInactiveApps: true)
                && MixerRoutingSupport.shouldShowApp(isPlaying: false,
                                                     volume: 1,
                                                     selectedOutputDeviceUID: "ExternalDisplay",
                                                     hideInactiveApps: true),
               "custom volume and output choices keep inactive mixer apps visible")

        // Issue #296. A tap mutes the app on the real output, so which build
        // may be installed, when an engine is allowed to go away and who may
        // be tapped at all decide whether an app suddenly plays at full
        // volume, plays twice as loud, or goes silent.
        expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                   savedRouteUID: nil,
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "an app with no saved volume and no saved route is never tapped")
        expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: 1,
                                                   savedRouteUID: nil,
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row saved at 100 percent is never tapped")
        expect(!MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                   savedRouteUID: "BuiltInSpeakerDevice",
                                                   defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row routed to the device that is already the default is never tapped")
        expect(MixerRoutingSupport.rowMayBeTapped(savedVolume: 0.4,
                                                  savedRouteUID: nil,
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row the user turned down is tapped")
        expect(MixerRoutingSupport.rowMayBeTapped(savedVolume: nil,
                                                  savedRouteUID: "ExternalDisplay",
                                                  defaultOutputDeviceUID: "BuiltInSpeakerDevice"),
               "a row routed to another output is tapped")

        var mixerBuilds = MixerEngineBuilds()
        expect(mixerBuilds.isEmpty, "a mixer with nothing being built has no builds in flight")
        // No real token is ever negative, so the sentinel cannot pass a check.
        let firstBuild = mixerBuilds.begin("com.example.Player") ?? -1
        expect(firstBuild > 0, "the first engine build for a row starts")
        expect(mixerBuilds.begin("com.example.Player") == nil,
               "a second engine build for the same row is refused while one is in flight")
        expect(mixerBuilds.isCurrent("com.example.Player", token: firstBuild),
               "a build that nothing invalidated is the one to install")
        mixerBuilds.finish("com.example.Player", token: firstBuild)
        expect(mixerBuilds.isEmpty,
               "finishing a build frees the row for the next one")
        let staleBuild = mixerBuilds.begin("com.example.Player") ?? -1
        mixerBuilds.invalidateAll()
        expect(!mixerBuilds.isCurrent("com.example.Player", token: staleBuild),
               "an engine build that lands after everything was invalidated is discarded")
        let freshBuild = mixerBuilds.begin("com.example.Player") ?? -1
        expect(freshBuild > 0 && freshBuild != staleBuild
               && mixerBuilds.isCurrent("com.example.Player", token: freshBuild),
               "the build started after an invalidation is the one to install")
        mixerBuilds.finish("com.example.Player", token: staleBuild)
        expect(mixerBuilds.isCurrent("com.example.Player", token: freshBuild),
               "a stale build landing late leaves the current build alone")
        var manyBuilds = MixerEngineBuilds()
        let firstRow = manyBuilds.begin("com.example.Player") ?? -1
        let secondRow = manyBuilds.begin("com.example.Radio") ?? -1
        manyBuilds.invalidateAll()
        expect(manyBuilds.isEmpty,
               "invalidating clears every engine build in flight")
        expect(!manyBuilds.isCurrent("com.example.Player", token: firstRow)
               && !manyBuilds.isCurrent("com.example.Radio", token: secondRow),
               "one invalidation makes every row's build in flight stale")

        var mixerRecovery = MixerEngineRecovery()
        let firstAudioPath = MixerEngineRecovery.Configuration(objects: [41],
                                                                outputDeviceUID: "speaker-a")
        expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "a new mixer audio path may build")
        expect(mixerRecovery.recordFailure("player", configuration: firstAudioPath),
               "a dead mixer engine gets one replacement")
        expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "the one replacement may build")
        expect(!mixerRecovery.recordFailure("player", configuration: firstAudioPath)
               && !mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "the same dead replacement stays untapped instead of muting forever")
        let changedAudioPath = MixerEngineRecovery.Configuration(objects: [42],
                                                                  outputDeviceUID: "speaker-a")
        expect(mixerRecovery.allowsBuild("player", configuration: changedAudioPath),
               "a new audio object gets its own recovery attempt")
        mixerRecovery.clear("player")
        expect(mixerRecovery.allowsBuild("player", configuration: firstAudioPath),
               "an explicit mixer change re-enables the audio path")

        var refreshes = MixerRefreshCoordinator()
        expect(!refreshes.isReading, "a mixer that is not reading the audio devices holds no slot")
        // No real generation is ever negative, so the sentinel cannot pass.
        let firstRefresh = refreshes.begin() ?? -1
        expect(firstRefresh > 0 && refreshes.isReading, "the first refresh takes the slot")
        expect(refreshes.begin() == nil,
               "a second refresh is refused while one is still reading the audio devices")
        expect(refreshes.takeRepeatRequest(),
               "the refused refresh is remembered so nothing asked for is lost")
        expect(!refreshes.takeRepeatRequest(),
               "a remembered refresh runs once, not on every landing")
        expect(refreshes.finish(firstRefresh), "the refresh that owns the slot publishes what it read")
        expect(!refreshes.isReading, "finishing a refresh frees the slot for the next one")
        let secondRefresh = refreshes.begin() ?? -1
        expect(secondRefresh > firstRefresh, "generations move forward, never repeat")
        expect(!refreshes.finish(firstRefresh),
               "a refresh from an older generation never publishes")
        expect(refreshes.isReading,
               "an older refresh landing late leaves the current one holding the slot")
        expect(refreshes.finish(secondRefresh), "the current refresh still publishes after that")

        var discarded = MixerRefreshCoordinator()
        let staleRefresh = discarded.begin() ?? -1
        _ = discarded.begin()
        discarded.discardInFlight()
        expect(!discarded.isReading, "discarding what is in flight frees the slot at once")
        expect(!discarded.finish(staleRefresh),
               "a refresh reading while the output changed publishes nothing")
        expect(!discarded.takeRepeatRequest(),
               "discarding also drops the repeat request, since a fresh refresh follows it")
        let afterDiscard = discarded.begin() ?? -1
        expect(afterDiscard > staleRefresh && discarded.finish(afterDiscard),
               "the refresh started after a discard is the one that publishes")

        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: true,
                                                       lastChangeAt: nil,
                                                       now: 100) == nil,
               "a row that still has audio is never left waiting for its tap")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: true,
                                                       lastChangeAt: 99.9,
                                                       now: 100) == nil,
               "a row that got its audio back is handled at once")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: nil,
                                                       now: 100,
                                                       window: 0.2) == 0.2,
               "a row that just lost its audio objects keeps its tap for one window")
        expectClose(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                            lastChangeAt: 99.95,
                                                            now: 100,
                                                            window: 0.2) ?? -1,
                    0.15,
                    "repeated churn in one window waits out the remainder instead of acting again")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: 99.5,
                                                       now: 100,
                                                       window: 0.2) == nil,
               "a row still without audio after the window loses its tap")
        expect(MixerRoutingSupport.engineTeardownDelay(hasAudioObjects: false,
                                                       lastChangeAt: 101,
                                                       now: 100,
                                                       window: 0.2) == 0.2,
               "a clock that jumps backwards falls back to a full window")

        // Render health of a live engine (issue #341): a tap whose aggregate
        // stopped rendering after wake keeps muting the app and must be caught.
        typealias RenderLook = MixerRoutingSupport.EngineRenderObservation
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 90),
                                                       cycles: 7,
                                                       isPlaying: false,
                                                       now: 100) == nil,
               "a silent app gives no render verdict and clears the observation")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: nil,
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100,
                                                       window: 1.5)
               == .note(RenderLook(cycles: 7, at: 100), recheckAfter: 1.5),
               "the first look notes the count and schedules a conclusive recheck")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 9,
                                                       isPlaying: true,
                                                       now: 100.4,
                                                       window: 1.5)
               == .note(RenderLook(cycles: 9, at: 100.4), recheckAfter: nil),
               "an advancing count is healthy and needs no extra pass")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100.5,
                                                       window: 1.5)
               == .stalled(recheckAfter: 1.0),
               "a count at rest inside the window waits out the remainder")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 100),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 102,
                                                       window: 1.5) == .wedged,
               "a count at rest for the whole window while the app plays is wedged")
        expect(MixerRoutingSupport.engineRenderVerdict(previous: RenderLook(cycles: 7, at: 101),
                                                       cycles: 7,
                                                       isPlaying: true,
                                                       now: 100,
                                                       window: 1.5)
               == .stalled(recheckAfter: 1.5),
               "a clock that jumps backwards waits a full window before judging")

        // The wedged tap that verdict tears down is also the one whose
        // `AudioHardwareDestroyProcessTap` parks inside the HAL. Serialized,
        // that one parked call held every later engine's aggregate and tap
        // alive behind it; unbounded, each one strands a worker of the shared
        // pool, which is issue #971's exhaustion. Read as source text because
        // the engine lives in a file the test target does not compile.
        let mixerCode = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Audio/AppVolumeMixer.swift",
            encoding: .utf8)) ?? ""
        let teardownQueueSetup = mixerCode.range(of: "let teardownQueue").flatMap { start in
            mixerCode.range(of: "}()", range: start.upperBound..<mixerCode.endIndex)
                .map { String(mixerCode[start.upperBound..<$0.lowerBound]) }
        } ?? ""
        expect(teardownQueueSetup.contains("maxConcurrentOperationCount"),
               "engine teardown runs on a queue with a concurrency bound, not one thread and not one per engine")

        // The IO callback's two exits, read the same way: a cycle that never
        // found its tap must hand the device silence rather than what the HAL
        // left in the buffer (issue #326), and must leave without counting
        // itself alive — a callback that resolved no tap has done nothing for
        // the app that a callback which never ran would not have done, and
        // `tapChannels` is read once when the engine is built, so input that
        // never carried that shape never will. Ordering alone would not say
        // that: a count inside the missed-tap branch also reads as "after the
        // lookup". The branch is cut out by brace matching and the two halves
        // are checked apart.
        let mixerBody = mixerCode
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let missedTapBrace = mixerBody
            .range(of: "MixerRender.tapBufferIndex(in: inputBuffers")
            .flatMap { mixerBody.range(of: "else {", range: $0.upperBound..<mixerBody.endIndex) }
        var missedTapBranch = ""
        var afterMissedTap = ""
        if let missedTapBrace {
            var depth = 1
            var index = missedTapBrace.upperBound
            while index < mixerBody.endIndex, depth > 0 {
                if mixerBody[index] == "{" { depth += 1 }
                if mixerBody[index] == "}" { depth -= 1 }
                index = mixerBody.index(after: index)
            }
            if depth == 0 {
                missedTapBranch = String(mixerBody[missedTapBrace.upperBound..<mixerBody.index(before: index)])
                afterMissedTap = String(mixerBody[index...])
            }
        }
        expect(missedTapBranch.contains("MixerRender.silence(outputBuffers)")
               && missedTapBranch.contains("return"),
               "a callback that finds no tap silences the output before it leaves")
        expect(!missedTapBranch.isEmpty && !missedTapBranch.contains("cycles.increment()"),
               "a callback that finds no tap leaves without counting a cycle")
        let framesGuard = afterMissedTap.range(of: "guard frames > 0 else")?.upperBound
        let cycleCount = afterMissedTap.range(of: "cycles.increment()")?.lowerBound
        expect(framesGuard != nil && cycleCount != nil && framesGuard! < cycleCount!,
               "a cycle is counted only once the engine has handed the device audio")

        let identifiedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: "com.example.Player",
                                                           ownerPid: 501,
                                                           displayName: "Player")
        expect(identifiedRow.rowID == "com.example.Player"
               && identifiedRow.persistenceID == "com.example.Player",
               "an app with a bundle id keeps it as both row and storage identity")
        let namedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                       ownerPid: 501,
                                                       displayName: "Retro Game")
        let otherNamedRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                            ownerPid: 502,
                                                            displayName: "Retro Game")
        expect(namedRow.persistenceID == "Retro Game",
               "an app without a bundle id saves its volume under its display name, the same key older versions used")
        expect(!namedRow.rowID.isEmpty && namedRow.rowID != otherNamedRow.rowID,
               "two same-named processes without a bundle id stay separate rows")
        let namelessRow = MixerRoutingSupport.rowIdentity(bundleIdentifier: nil,
                                                          ownerPid: 501,
                                                          displayName: nil)
        expect(!namelessRow.rowID.isEmpty && namelessRow.persistenceID == nil,
               "a process with neither bundle id nor name is still listable but stores nothing")
        expect(MixerRoutingSupport.rowIdentity(bundleIdentifier: "   ",
                                               ownerPid: 501,
                                               displayName: "  ").persistenceID == nil,
               "blank identifiers are not identities")

        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["BuiltInMicrophoneDevice",
                                                                            "USBMicrophone"])
               == "BuiltInMicrophoneDevice",
               "the microphone the system had before the app changed it is put back")
        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "HeadsetMicrophone",
                                                            availableUIDs: ["BuiltInMicrophoneDevice",
                                                                            "USBMicrophone"]) == nil,
               "a microphone chosen elsewhere since is left alone")
        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: "BuiltInMicrophoneDevice",
                                                            appliedUID: "USBMicrophone",
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["USBMicrophone"]) == nil,
               "a microphone that is gone is not restored")
        expect(MixerRoutingSupport.restorableInputDeviceUID(originalUID: nil,
                                                            appliedUID: nil,
                                                            currentUID: "USBMicrophone",
                                                            availableUIDs: ["USBMicrophone"]) == nil,
               "nothing is restored when the app never changed the microphone")
        expect(MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.25),
               "a volume still at the value the app set goes back to what it was")
        expect(!MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: 0.6),
               "a volume changed since the app lowered it is left alone")
        expect(!MixerRoutingSupport.shouldRestoreOutputVolume(appliedVolume: 0.25, currentVolume: nil),
               "a volume that cannot be read is left alone")
        expect(!MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.apple.finder",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: true)),
               "Finder shows in the mixer when enabled")
        expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.apple.finder",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: false)),
               "Finder can be hidden from the mixer")
        expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.example.Player",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(
                        hiddenApps: ["com.example.Player": "Player"], showFinder: true)),
               "any app the user hid stays out of the mixer list")
        expect(!MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "com.example.Player",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(hiddenApps: [:], showFinder: false)),
               "hiding Finder leaves every other app visible")
        expect(MixerRoutingSupport.isHiddenFromMixer(
                    persistenceID: "Bare Tool",
                    hiddenIDs: MixerRoutingSupport.hiddenRowIDs(
                        hiddenApps: ["Bare Tool": "Bare Tool"], showFinder: true)),
               "apps saved under a display name can be hidden too")
        expect(!MixerRoutingSupport.isHiddenFromMixer(persistenceID: nil,
                                                      hiddenIDs: ["com.example.Player"]),
               "a row with nothing to remember it by is always listed")
        let hiddenSanitized = MixerRoutingSupport.sanitizedHiddenApps([
            "com.example.Player": "Player",
            "com.apple.finder": "Finder",
            "": "Nameless",
            "com.example.Silent": "",
            "com.example.Broken": 3,
        ])
        expect(hiddenSanitized == ["com.example.Player": "Player"],
               "the hidden map keeps only real entries and never carries the Finder")
        expect(MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                            hasFinderRow: false),
               "Finder gets a persistent row before Quick Look opens")
        expect(!MixerRoutingSupport.needsPersistentFinderRow(showFinder: true,
                                                             hasFinderRow: true)
                && !MixerRoutingSupport.needsPersistentFinderRow(showFinder: false,
                                                                 hasFinderRow: false),
               "Finder is never duplicated and stays absent when hidden")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.xos", name: "zoom.us"),
               "Zoom is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "us.zoom.ZoomAutoUpdater", name: "Zoom"),
               "Zoom helper bundle ids are kept out of process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.Safari", name: "Safari"),
               "regular apps remain eligible for process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: nil, name: "Zoomable Notes"),
               "unrelated app names are not treated as Zoom")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.apple.logic10", name: "Logic Pro"),
               "Logic Pro is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.ableton.live", name: "Live"),
               "Ableton Live is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.steinberg.cubase13", name: "Cubase"),
               "Cubase is kept out of process-tap audio routing")
        expect(MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.presonus.studioone6", name: "Studio One"),
               "Studio One is kept out of process-tap audio routing")
        expect(!MixerRoutingSupport.bypassesProcessTap(bundleIdentifier: "com.spotify.client", name: "Spotify"),
               "music players remain eligible for process-tap audio routing")
        expect(MixerRoutingSupport.effectiveDeviceUID(selectedUID: "ExternalDisplay",
                                                      availableUIDs: ["BuiltInSpeakerDevice"],
                                                      defaultUID: "BuiltInSpeakerDevice") == "BuiltInSpeakerDevice",
               "missing saved output falls back to default")
        expect(MixerRoutingSupport.selectedDeviceUnavailable(selectedUID: "ExternalDisplay",
                                                             availableUIDs: ["BuiltInSpeakerDevice"]),
               "missing saved output is marked unavailable without deleting the preference")
        let defaultInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: nil,
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(defaultInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                         selectedUnavailable: false,
                                                         shouldApplyPreferred: false),
               "no preferred input follows the current system input")
        let connectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(connectedPreferredInput == MixerInputRouteResolution(effectiveUID: "StudioMic",
                                                                    selectedUnavailable: false,
                                                                    shouldApplyPreferred: true),
               "connected preferred input is applied when different from current")
        let alreadyCurrentInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice", "StudioMic"],
            currentUID: "StudioMic")
        expect(!alreadyCurrentInput.shouldApplyPreferred,
               "preferred input is not reapplied when already current")
        let disconnectedPreferredInput = MixerRoutingSupport.resolveInputDevice(
            preferredUID: "StudioMic",
            availableUIDs: ["BuiltInMicrophoneDevice"],
            currentUID: "BuiltInMicrophoneDevice")
        expect(disconnectedPreferredInput == MixerInputRouteResolution(effectiveUID: "BuiltInMicrophoneDevice",
                                                                       selectedUnavailable: true,
                                                                       shouldApplyPreferred: false),
               "missing preferred input falls back visually without deleting preference")
        expect(MixerRoutingSupport.displayOrderedBefore(name: "Music", id: "com.apple.Music",
                                                        otherName: "Safari", otherID: "com.apple.Safari"),
               "mixer rows order by display name")
        expect(MixerRoutingSupport.displayOrderedBefore(name: "safari", id: "a",
                                                        otherName: "Safari", otherID: "b")
                   && !MixerRoutingSupport.displayOrderedBefore(name: "Safari", id: "b",
                                                                otherName: "safari", otherID: "a"),
               "mixer rows with equal names order deterministically by id")
        expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: true, name: "Zeta", uid: "z",
                                                              otherIsDefault: false, otherName: "Alpha",
                                                              otherUID: "a"),
               "the default device orders before any other device")
        expect(MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro", uid: "aa",
                                                              otherIsDefault: false, otherName: "AirPods Pro",
                                                              otherUID: "bb")
                   && !MixerRoutingSupport.deviceDisplayOrderedBefore(isDefault: false, name: "AirPods Pro",
                                                                      uid: "bb",
                                                                      otherIsDefault: false,
                                                                      otherName: "AirPods Pro",
                                                                      otherUID: "aa"),
               "identically named devices order deterministically by uid")

        // MARK: Boost limiter (issue #326)

        // A boost above 100% used to clamp overshooting samples, flattening
        // every peak into crackle. The limiter must cap peaks without touching
        // audio that already fits, and its gain must ride across buffers.

        func sine(amplitude: Float, frames: Int, channels: Int = 1) -> [Float] {
            var samples = [Float](repeating: 0, count: frames * channels)
            for frame in 0..<frames {
                let value = amplitude * Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
                for channel in 0..<channels { samples[frame * channels + channel] = value }
            }
            return samples
        }
        func limited(_ samples: [Float], channels: Int = 1,
                     release: Float = BoostLimiter.release(sampleRate: 48000),
                     with limiter: inout BoostLimiter) -> [Float] {
            var output = samples
            output.withUnsafeMutableBufferPointer { buffer in
                limiter.process(buffer.baseAddress!,
                                frames: samples.count / channels,
                                channels: channels,
                                release: release)
            }
            return output
        }

        var quietLimiter = BoostLimiter()
        let quiet = sine(amplitude: 0.6, frames: 4800)
        expect(limited(quiet, with: &quietLimiter) == quiet,
               "audio inside the ceiling passes through bit-identical")

        var loudLimiter = BoostLimiter()
        let loud = limited(sine(amplitude: 1.5, frames: 9600), with: &loudLimiter)
        expect(loud.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "boosted peaks never leave the ceiling")
        let steady = loud.dropFirst(4800)
        let pinned = steady.filter { abs($0) >= BoostLimiter.ceiling - 0.001 }.count
        expect(pinned < steady.count / 5,
               "the limiter rides the level instead of flattening the wave into clipping")

        var recoveryLimiter = BoostLimiter()
        _ = limited(sine(amplitude: 1.5, frames: 4800), with: &recoveryLimiter)
        let afterLoud = limited(sine(amplitude: 0.5, frames: 48000), with: &recoveryLimiter)
        expect(afterLoud.prefix(480).max()! < 0.45,
               "right after a loud stretch the gain is still turned down")
        expect(afterLoud.suffix(4800).max()! > 0.499,
               "the gain recovers to unity once the audio gets quiet")

        var wholeLimiter = BoostLimiter()
        var chunkedLimiter = BoostLimiter()
        let long = sine(amplitude: 1.5, frames: 2048)
        let whole = limited(long, with: &wholeLimiter)
        let chunked = limited(Array(long[0..<1024]), with: &chunkedLimiter)
            + limited(Array(long[1024...]), with: &chunkedLimiter)
        expect(whole == chunked,
               "splitting the stream into buffers does not change the result")

        var stereoLimiter = BoostLimiter()
        var stereo = [Float](repeating: 0, count: 9600 * 2)
        for frame in 0..<9600 {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            stereo[frame * 2] = 1.5 * value
            stereo[frame * 2 + 1] = 0.75 * value
        }
        let linked = limited(stereo, channels: 2, with: &stereoLimiter)
        var stereoLinked = true
        for frame in 0..<9600 where abs(linked[frame * 2 + 1] - linked[frame * 2] / 2) > 0.0001 {
            stereoLinked = false
            break
        }
        expect(stereoLinked,
               "both channels of a frame share one gain so the stereo image stays put")

        var lookaheadInput = sine(amplitude: 1.5, frames: 9600)
        let lookahead = BoostLookaheadLimiter(channels: 1)
        _ = lookaheadInput.withUnsafeMutableBufferPointer { buffer in
            lookahead.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                              release: BoostLimiter.release(sampleRate: 48000))
        }
        let delayedSine = Array(repeating: Float(0), count: BoostLookaheadLimiter.lookaheadFrames)
            + Array(sine(amplitude: BoostLimiter.ceiling,
                         frames: 9600 - BoostLookaheadLimiter.lookaheadFrames))
        expect(lookaheadInput.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "lookahead keeps every boosted sample inside the output range")
        expect(zip(lookaheadInput.dropFirst(960), delayedSine.dropFirst(960)).allSatisfy {
            abs($0 - $1) < 0.0001
        }, "lookahead preserves a steady loud waveform instead of reshaping its peaks")

        var quietLookahead = sine(amplitude: 0.6, frames: 2048)
        let quietLookaheadSource = quietLookahead
        let quietLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        _ = quietLookahead.withUnsafeMutableBufferPointer { buffer in
            quietLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                          release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(Array(quietLookahead.prefix(BoostLookaheadLimiter.lookaheadFrames))
                == Array(repeating: 0, count: BoostLookaheadLimiter.lookaheadFrames)
            && Array(quietLookahead.dropFirst(BoostLookaheadLimiter.lookaheadFrames))
                == Array(quietLookaheadSource.dropLast(BoostLookaheadLimiter.lookaheadFrames)),
               "quiet routed audio stays bit-identical after the fixed lookahead delay")

        let lookaheadSource = sine(amplitude: 1.5, frames: 4096)
        var wholeLookahead = lookaheadSource
        let wholeLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        _ = wholeLookahead.withUnsafeMutableBufferPointer { buffer in
            wholeLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                          release: BoostLimiter.release(sampleRate: 48000))
        }
        let chunkedLookaheadLimiter = BoostLookaheadLimiter(channels: 1)
        var chunkedLookahead = [Float]()
        for sourceChunk in [Array(lookaheadSource[0..<511]),
                            Array(lookaheadSource[511..<1537]),
                            Array(lookaheadSource[1537...])] {
            var chunk = sourceChunk
            _ = chunk.withUnsafeMutableBufferPointer { buffer in
                chunkedLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count,
                                                channels: 1,
                                                release: BoostLimiter.release(sampleRate: 48000))
            }
            chunkedLookahead += chunk
        }
        expect(wholeLookahead == chunkedLookahead,
               "lookahead produces the same signal across realtime buffer boundaries")

        var impulseTrain = [Float](repeating: 0.2, count: 4096)
        for frame in stride(from: 256, to: impulseTrain.count, by: 173) {
            impulseTrain[frame] = frame.isMultiple(of: 2) ? 2 : -2
        }
        let impulseLimiter = BoostLookaheadLimiter(channels: 1)
        _ = impulseTrain.withUnsafeMutableBufferPointer { buffer in
            impulseLimiter.process(buffer.baseAddress!, frames: buffer.count, channels: 1,
                                   release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(impulseTrain.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "overlapping future peaks are attenuated before they reach the output")

        var lookaheadStereo = [Float](repeating: 0, count: 4096 * 2)
        for frame in 0..<4096 {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            lookaheadStereo[frame * 2] = 1.5 * value
            lookaheadStereo[frame * 2 + 1] = 0.75 * value
        }
        let stereoLookaheadLimiter = BoostLookaheadLimiter(channels: 2)
        _ = lookaheadStereo.withUnsafeMutableBufferPointer { buffer in
            stereoLookaheadLimiter.process(buffer.baseAddress!, frames: buffer.count / 2,
                                           channels: 2,
                                           release: BoostLimiter.release(sampleRate: 48000))
        }
        expect((BoostLookaheadLimiter.lookaheadFrames..<4096).allSatisfy { frame in
            abs(lookaheadStereo[frame * 2 + 1] - lookaheadStereo[frame * 2] / 2) < 0.0001
        }, "lookahead applies one gain to every channel in a frame")

        func planarLookahead(_ sources: [[Float]], capacity: Int)
            -> (handled: Bool, output: [[Float]]) {
            let frames = sources.map(\.count).min() ?? 0
            let pointers = sources.map { source -> UnsafeMutablePointer<Float> in
                let pointer = UnsafeMutablePointer<Float>.allocate(capacity: max(1, source.count))
                pointer.update(from: source, count: source.count)
                return pointer
            }
            let list = AudioBufferList.allocate(maximumBuffers: max(1, sources.count))
            for index in sources.indices {
                list[index] = AudioBuffer(
                    mNumberChannels: 1,
                    mDataByteSize: UInt32(frames * MemoryLayout<Float>.size),
                    mData: pointers[index])
            }
            let limiter = BoostLookaheadBufferListLimiter(channelCapacity: capacity)
            let handled = limiter.process(list, frames: frames,
                                          release: BoostLimiter.release(sampleRate: 48_000))
            let output = pointers.map { Array(UnsafeBufferPointer(start: $0, count: frames)) }
            pointers.forEach { $0.deallocate() }
            free(list.unsafeMutablePointer)
            return (handled, output)
        }
        let planarFrames = 1_024
        let planarWave = (0..<planarFrames).map {
            Float(sin(2 * Double.pi * 440 * Double($0) / 48_000))
        }
        let planarStereo = planarLookahead(
            [planarWave.map { $0 * 1.5 }, planarWave.map { $0 * 0.5 }], capacity: 2)
        expect(planarStereo.handled
                && (BoostLookaheadLimiter.lookaheadFrames..<planarFrames).allSatisfy { frame in
                    abs(planarStereo.output[1][frame] - planarStereo.output[0][frame] / 3) < 0.0001
                },
               "non-interleaved stereo buffers share one lookahead gain")
        let ninePlanar = planarLookahead(
            (1...9).map { channel in
                Array(repeating: Float(channel) / 20, count: 512)
            }, capacity: 9)
        let thirtyThreePlanar = planarLookahead(
            (1...33).map { _ in Array(repeating: Float(0.2), count: 300) }, capacity: 33)
        expect(ninePlanar.handled && thirtyThreePlanar.handled
                && ninePlanar.output.allSatisfy {
                    Array($0.prefix(BoostLookaheadLimiter.lookaheadFrames))
                        == Array(repeating: 0, count: BoostLookaheadLimiter.lookaheadFrames)
                },
               "lookahead keeps one latency across nine buffers and 33 channels")

        var changedChannels = [Float](repeating: 0.4, count: 16)
        let adaptableLimiter = BoostLookaheadLimiter(channels: 2)
        let changedChannelsWereHandled = changedChannels.withUnsafeMutableBufferPointer { buffer in
            adaptableLimiter.process(
                buffer.baseAddress!, frames: 8, channels: 2,
                release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(changedChannelsWereHandled,
               "a stream shape change reuses the preallocated lookahead storage")

        var tooManyChannels = [Float](repeating: 1.2, count: 24)
        let overflowWasHandled = tooManyChannels.withUnsafeMutableBufferPointer { buffer in
            BoostLookaheadLimiter(channels: 2).process(
                buffer.baseAddress!, frames: 8, channels: 3,
                release: BoostLimiter.release(sampleRate: 48000))
        }
        expect(!overflowWasHandled && tooManyChannels.allSatisfy { $0 == 1.2 },
               "a stream larger than the preallocated capacity falls through safely")

        var fallbackLimiter = BoostLimiter()
        let fallbackLimited = limited(sine(amplitude: 1.5, frames: 480),
                                      release: BoostLimiter.release(sampleRate: 0),
                                      with: &fallbackLimiter)
        expect(fallbackLimited.allSatisfy { abs($0) <= BoostLimiter.ceiling + 0.0001 },
               "an unreadable sample rate still limits at the common device rate")

        // A headset that takes the microphone for a call changes the rate the
        // device runs at while the audio path stays up. The recovery has to
        // stay the same length of time, not the same number of samples.

        /// How many seconds the gain takes to come back after a loud stretch.
        func recoverySeconds(rate: Double, release: Float) -> Double {
            var limiter = BoostLimiter()
            let step = max(Int(rate / 1000), 1)
            func tone(_ amplitude: Float, seconds: Double) -> [Float] {
                let frames = Int(rate * seconds)
                var samples = [Float](repeating: 0, count: frames)
                for frame in 0..<frames {
                    samples[frame] = amplitude * Float(sin(2 * Double.pi * 440 * Double(frame) / rate))
                }
                return samples
            }
            _ = limited(tone(1.5, seconds: 0.1), release: release, with: &limiter)
            let quiet = limited(tone(0.5, seconds: 1.0), release: release, with: &limiter)
            let peaks = stride(from: 0, to: quiet.count, by: step).map { start in
                quiet[start..<min(start + step, quiet.count)].map { abs($0) }.max() ?? 0
            }
            guard let recovered = peaks.firstIndex(where: { $0 > 0.499 }) else { return .infinity }
            return Double(recovered) / 1000
        }

        let releaseAt48k = BoostLimiter.release(sampleRate: 48000)
        let releaseAt16k = BoostLimiter.release(sampleRate: 16000)
        expect(releaseAt16k < releaseAt48k,
               "a slower rate keeps less of the previous level in each sample")

        let recoveryAt48k = recoverySeconds(rate: 48000, release: releaseAt48k)
        let recoveryAt16k = recoverySeconds(rate: 16000, release: releaseAt16k)
        expect(abs(recoveryAt16k - recoveryAt48k) < 0.02,
               "the gain takes the same time to come back whatever rate the device runs at")

        // The defect this replaced: the figure was worked out once when the
        // engine was built, so a device that changed rate afterwards recovered
        // at the wrong speed for as long as it kept playing.
        let staleRecovery = recoverySeconds(rate: 16000, release: releaseAt48k)
        expect(staleRecovery > recoveryAt16k * 2,
               "keeping the old rate's figure after a change drags the recovery out")

        // MARK: Mixer render (issue #397)

        // The tap always hands over two interleaved channels; the device on
        // the other side does not have to match. Pouring stereo into a
        // headset's single channel used to copy every sample straight across,
        // which plays the audio an octave low and half as long.

        /// Runs `render` over freshly allocated buffers and hands back what
        /// each output buffer received, plus the frame count it reported.
        var renderedFrames = 0
        func rendered(source: [Float], sourceChannels: UInt32,
                      outputs: [(channels: UInt32, frames: Int)],
                      gain: Float = 1) -> [[Float]] {
            let sourceStorage = UnsafeMutablePointer<Float>.allocate(capacity: max(source.count, 1))
            sourceStorage.update(from: source, count: source.count)
            var storages: [UnsafeMutablePointer<Float>] = []
            let list = AudioBufferList.allocate(maximumBuffers: max(outputs.count, 1))
            for (index, output) in outputs.enumerated() {
                let count = max(output.frames * Int(output.channels), 1)
                let storage = UnsafeMutablePointer<Float>.allocate(capacity: count)
                storage.update(repeating: -99, count: count)
                storages.append(storage)
                list[index] = AudioBuffer(
                    mNumberChannels: output.channels,
                    mDataByteSize: UInt32(output.frames * Int(output.channels) * MemoryLayout<Float>.size),
                    mData: UnsafeMutableRawPointer(storage))
            }
            let buffer = AudioBuffer(
                mNumberChannels: sourceChannels,
                mDataByteSize: UInt32(source.count * MemoryLayout<Float>.size),
                mData: UnsafeMutableRawPointer(sourceStorage))
            renderedFrames = MixerRender.render(source: buffer, into: list, gain: gain)
            var results: [[Float]] = []
            for (index, output) in outputs.enumerated() {
                let count = output.frames * Int(output.channels)
                results.append(Array(UnsafeBufferPointer(start: storages[index], count: count)))
            }
            storages.forEach { $0.deallocate() }
            sourceStorage.deallocate()
            free(list.unsafeMutablePointer)
            return results
        }

        /// Positive-going zero crossings, the cheap way to hear speed change.
        func crossings(_ samples: [Float], channels: Int) -> Int {
            var count = 0
            var previous: Float = 0
            for frame in 0..<(samples.count / channels) {
                let value = samples[frame * channels]
                if previous <= 0, value > 0 { count += 1 }
                previous = value
            }
            return count
        }

        expect(MixerRender.frames(bytes: 4096, channels: 2) == 512,
               "a stereo buffer of 4096 bytes carries 512 frames")
        expect(MixerRender.frames(bytes: 2048, channels: 1) == 512,
               "a mono buffer of 2048 bytes carries the same 512 frames")
        expect(MixerRender.frames(bytes: 4096, channels: 0) == 0,
               "a buffer with no channels carries nothing")
        let missingOutputSource = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        missingOutputSource.initialize(repeating: 0.5, count: 2)
        let missingOutputList = AudioBufferList.allocate(maximumBuffers: 1)
        missingOutputList[0] = AudioBuffer(mNumberChannels: 2,
                                           mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                           mData: nil)
        let missingOutputFrames = MixerRender.render(
            source: AudioBuffer(mNumberChannels: 2,
                                mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                mData: missingOutputSource),
            into: missingOutputList,
            gain: 1)
        expect(missingOutputFrames == 0,
               "mixer progress advances only when a destination received audio")
        missingOutputSource.deallocate()
        free(missingOutputList.unsafeMutablePointer)

        let unmappedOutputSource = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        unmappedOutputSource.initialize(repeating: 0.5, count: 2)
        let unmappedOutputDestination = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        unmappedOutputDestination.initialize(to: -99)
        let unmappedOutputList = AudioBufferList.allocate(maximumBuffers: 2)
        unmappedOutputList[0] = AudioBuffer(
            mNumberChannels: 2,
            mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
            mData: nil)
        unmappedOutputList[1] = AudioBuffer(
            mNumberChannels: 1,
            mDataByteSize: UInt32(MemoryLayout<Float>.size),
            mData: unmappedOutputDestination)
        let unmappedOutputFrames = MixerRender.render(
            source: AudioBuffer(mNumberChannels: 2,
                                mDataByteSize: 2 * UInt32(MemoryLayout<Float>.size),
                                mData: unmappedOutputSource),
            into: unmappedOutputList,
            gain: 1)
        expect(unmappedOutputFrames == 0 && unmappedOutputDestination.pointee == 0,
               "a writable channel that can only receive silence does not advance mixer progress")
        unmappedOutputSource.deallocate()
        unmappedOutputDestination.deallocate()
        free(unmappedOutputList.unsafeMutablePointer)

        // MARK: Unwritten output frames (issue #326)

        // The output buffer arrives holding whatever CoreAudio last left in
        // that memory. A tap shorter than the buffer used to fill the front
        // and leave the rest, and a cycle that found no tap left the whole
        // buffer, so the device played back a fragment of older audio.
        let shortTap = rendered(source: [0.5, 0.5, 0.5, 0.5], sourceChannels: 2,
                                outputs: [(channels: 2, frames: 4)])[0]
        expect(renderedFrames == 2,
               "a tap shorter than the output writes only the frames it has")
        expect(shortTap == [0.5, 0.5, 0.5, 0.5, 0, 0, 0, 0],
               "the frames the tap could not fill are silenced, not left as the device found them")
        let splitTail = rendered(source: [0.5, 0.5], sourceChannels: 2,
                                 outputs: [(channels: 1, frames: 3), (channels: 1, frames: 3)])
        expect(splitTail[0] == [0.5, 0, 0] && splitTail[1] == [0.5, 0, 0],
               "every buffer of a split output is silenced past the frames the tap filled")
        let staleOutput = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        staleOutput.update(repeating: -99, count: 4)
        let staleList = AudioBufferList.allocate(maximumBuffers: 1)
        staleList[0] = AudioBuffer(mNumberChannels: 2,
                                   mDataByteSize: 4 * UInt32(MemoryLayout<Float>.size),
                                   mData: staleOutput)
        MixerRender.silence(staleList)
        expect(Array(UnsafeBufferPointer(start: staleOutput, count: 4)) == [0, 0, 0, 0],
               "a cycle with no tap to read hands the device silence, not what it left behind")
        staleOutput.deallocate()
        free(staleList.unsafeMutablePointer)

        let toneFrames = 4800
        var toneStereo = [Float](repeating: 0, count: toneFrames * 2)
        for frame in 0..<toneFrames {
            let value = Float(sin(2 * Double.pi * 440 * Double(frame) / 48000))
            toneStereo[frame * 2] = value
            toneStereo[frame * 2 + 1] = value
        }
        let toneCrossings = crossings(toneStereo, channels: 2)

        let toMono = rendered(source: toneStereo, sourceChannels: 2,
                              outputs: [(channels: 1, frames: toneFrames)])[0]
        expect(crossings(toMono, channels: 1) == toneCrossings,
               "a device with one channel plays the tapped audio at its own speed")
        var monoMatches = true
        for frame in 0..<toneFrames
        where abs(toMono[frame] - (toneStereo[frame * 2] + toneStereo[frame * 2 + 1]) / 2) > 0.0001 {
            monoMatches = false
            break
        }
        expect(monoMatches, "one channel gets both sides of the stereo, averaged")

        let quieterMono = rendered(source: toneStereo, sourceChannels: 2,
                                   outputs: [(channels: 1, frames: toneFrames)], gain: 0.4)[0]
        var quieterMatches = true
        for frame in 0..<toneFrames where abs(quieterMono[frame] - toMono[frame] * 0.4) > 0.0001 {
            quieterMatches = false
            break
        }
        expect(quieterMatches && quieterMono.map({ abs($0) }).max()! > 0.39,
               "the chosen volume still applies when the audio is folded to one channel")
        expect(renderedFrames == toneFrames,
               "the fold reports every frame it wrote, which is what bounds the limiter")

        let toStereo = rendered(source: toneStereo, sourceChannels: 2,
                                outputs: [(channels: 2, frames: toneFrames)], gain: 0.5)[0]
        var stereoMatches = true
        for index in 0..<(toneFrames * 2) where abs(toStereo[index] - toneStereo[index] * 0.5) > 0.0001 {
            stereoMatches = false
            break
        }
        expect(stereoMatches, "a stereo device still gets a plain scaled copy")

        let toSurround = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                  outputs: [(channels: 4, frames: 2)])[0]
        expect(toSurround == [1, 2, 0, 0, 3, 4, 0, 0],
               "a device with more channels than the tap fills the first pair and silences the rest")

        let split = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                             outputs: [(channels: 1, frames: 2), (channels: 1, frames: 2)])
        expect(split == [[1, 3], [2, 4]],
               "a device that keeps its channels in separate buffers gets one channel each")

        let quieterSplit = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                    outputs: [(channels: 1, frames: 2), (channels: 1, frames: 2)],
                                    gain: 0.5)
        expect(quieterSplit == [[0.5, 1.5], [1, 2]],
               "the chosen volume applies to every channel a spread-out device carries")

        let quieterSurround = rendered(source: [1, 2, 3, 4], sourceChannels: 2,
                                       outputs: [(channels: 4, frames: 2)], gain: 0.5)[0]
        expect(quieterSurround == [0.5, 1, 0, 0, 1.5, 2, 0, 0],
               "the chosen volume applies when the tap is spread over more channels")

        let fromMono = rendered(source: [1, 2], sourceChannels: 1,
                                outputs: [(channels: 2, frames: 2)])[0]
        expect(fromMono == [1, 1, 2, 2],
               "a single-channel source is heard on both sides, not only the left")

        let shortOutput = rendered(source: [1, 2, 3, 4, 5, 6], sourceChannels: 2,
                                   outputs: [(channels: 2, frames: 2)])[0]
        expect(shortOutput == [1, 2, 3, 4] && renderedFrames == 2,
               "an output buffer smaller than the tap's is filled without running past its end")

        let tapOnly = AudioBufferList.allocate(maximumBuffers: 2)
        let deviceInput = UnsafeMutablePointer<Float>.allocate(capacity: 1)
        let tapSamples = UnsafeMutablePointer<Float>.allocate(capacity: 2)
        defer {
            deviceInput.deallocate()
            tapSamples.deallocate()
        }
        tapOnly[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 4,
                                 mData: UnsafeMutableRawPointer(deviceInput))
        tapOnly[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8,
                                 mData: UnsafeMutableRawPointer(tapSamples))
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 2) == 1,
               "on an output device that also records, the tap is not the first buffer")
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 1) == 0,
               "the tap is picked by the shape it announced, not by its position")
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 7) == nil,
               "with nothing matching the tap, the microphone is never played out of the speakers")
        tapOnly[1] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8, mData: nil)
        expect(MixerRender.tapBufferIndex(in: tapOnly, tapChannels: 2) == nil,
               "a buffer with no samples is never mistaken for the tap")
        free(tapOnly.unsafeMutablePointer)

        let lonely = AudioBufferList.allocate(maximumBuffers: 1)
        lonely[0] = AudioBuffer(mNumberChannels: 2, mDataByteSize: 8,
                                mData: UnsafeMutableRawPointer(tapSamples))
        expect(MixerRender.tapBufferIndex(in: lonely, tapChannels: 7) == 0,
               "an output device with nothing of its own leaves only the tap to render")
        free(lonely.unsafeMutablePointer)

        expect(MixerRender.sourceChannel(for: 0, sourceChannels: 2) == 0
            && MixerRender.sourceChannel(for: 1, sourceChannels: 2) == 1,
               "stereo feeds the first two channels in order")
        expect(MixerRender.sourceChannel(for: 2, sourceChannels: 2) == nil,
               "channels the tap cannot fill stay silent")
        expect(MixerRender.sourceChannel(for: 1, sourceChannels: 1) == 0,
               "a single channel is copied to the right as well as the left")

        // Every field at once, none left at its default. `CodingKeys` is written
        // out by hand next to the stored properties, and a property missing from
        // it is silently dropped by both the custom decoder and the synthesized
        // encoder, so a ninth field added without a case would stop being saved
        // and read with nothing else complaining.
        expect(ClipboardHistoryBatch.listOwnsCopyShortcut(batchCount: 2)
                   && !ClipboardHistoryBatch.listOwnsCopyShortcut(batchCount: 0),
               "the list only claims command-C over an explicit selection")
        expect(ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 0, queryIsEmpty: true)
                   && !ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 0, queryIsEmpty: false)
                   && ClipboardHistoryBatch.listOwnsSelectAllShortcut(batchCount: 1, queryIsEmpty: false),
               "the list claims command-A over a selection or an empty search field")
        expect(ClipboardHistoryBatch.listOwnsDeleteShortcut(batchCount: 2)
                   && !ClipboardHistoryBatch.listOwnsDeleteShortcut(batchCount: 0),
               "the list only claims command-delete over an explicit selection")
        expect(String(format: FeatureStrings.clipboard(.enUS).deleteSelectedFormat, 3) == "Delete 3",
               "English bulk delete string formats count correctly")
        expect(String(format: FeatureStrings.clipboard(.ptBR).deleteSelectedFormat, 3) == "Apagar 3",
               "Portuguese bulk delete string formats count correctly")

        // MARK: Shelf tile tooltip

        let longText = String(repeating: "a", count: 600)
        // MARK: Middle click tap (issue #161)

        // MARK: Cut and paste move progress (issue #168)

        expect(!CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                      destination: NSNumber(value: 1)),
               "a move inside one volume never shows progress")
        expect(CutPasteProgressSupport.isCrossVolume(source: NSNumber(value: 1),
                                                     destination: NSNumber(value: 2)),
               "a move between volumes is recognized as a real copy")
        expect(!CutPasteProgressSupport.isCrossVolume(source: nil,
                                                      destination: NSNumber(value: 2)),
               "unknown volume identities fall back to the silent same-volume path")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 0, currentBytes: 0, totalBytes: 0) == nil,
               "an unknown byte total yields an indeterminate bar, not a broken fraction")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 50, currentBytes: 25, totalBytes: 150) == 0.5,
               "progress combines finished files with the growing destination")
        expect(CutPasteProgressSupport.fraction(finishedBytes: 100, currentBytes: 200, totalBytes: 150) == 1.0,
               "progress clamps at full when the destination briefly over-reports")
        expect(CutPasteProgressSupport.fraction(finishedBytes: -5, currentBytes: -5, totalBytes: 100) == 0.0,
               "negative byte readings clamp to an empty bar")
        expect(CutPasteProgressSupport.displayPosition(completed: 1, total: 5) == 2,
               "the counter shows the item currently moving, one past the finished count")
        expect(CutPasteProgressSupport.displayPosition(completed: 5, total: 5) == 5,
               "the counter never runs past the batch size")

        // MARK: Paste copied image as file (issue #429)

        expect(FinderPasteImageSupport.preferredImageType(in: ["public.utf8-plain-text"]) == nil,
               "text never replaces Finder's normal paste")
        expect(FinderPasteImageSupport.preferredImageType(in: ["public.tiff", "public.png"])
                == "public.png",
               "PNG wins when the pasteboard offers several image representations")
        expect(FinderPasteImageSupport.preferredImageType(
            in: ["public.file-url", "public.png"]
        ) == nil, "a copied image file stays a normal Finder file paste")
        expect(FinderPasteImageSupport.preferredImageType(in: ["public.jpeg"])
                == "public.jpeg",
               "a non-PNG image representation can be converted")
        expect(FinderPasteImageSupport.fileName(
            for: Date(timeIntervalSince1970: 0),
            timeZone: TimeZone(secondsFromGMT: 0)!
        ) == "Pasted_Image_19700101_000000.png",
               "pasted images receive the stable timestamped PNG name")

        // MARK: Update installer helpers

        expect(GlobalShortcutRole.activeRoles(isOn: { _ in false }).isEmpty,
               "no enabled gates means no active shortcuts")
        expect(!GlobalShortcutRole.activeRoles(isOn: { $0 == DefaultsKey.clipboardHistoryShortcutEnabled })
                   .contains(.clipboard),
               "the clipboard shortcut needs the feature on too")
        expect(GlobalShortcutRole.activeRoles(isOn: {
                   $0 == DefaultsKey.clipboardHistoryEnabled
                       || $0 == DefaultsKey.clipboardHistoryShortcutEnabled
               }).contains(.clipboard),
               "the clipboard shortcut activates with both gates on")
        // macOS stores its own shortcuts as [character, key code, modifier mask],
        // the mask in NSEvent.ModifierFlags bits. 1 is S, 655360 is shift+option
        // — the combination "save picture of selected area as a file" carries
        // when someone moves it off its factory keys.
        func systemHotKey(_ id: String, enabled: Bool,
                          keyCode: Int, mask: Int, type: String = "standard") -> [String: Any] {
            [id: ["enabled": NSNumber(value: enabled),
                  "value": ["type": type,
                            "parameters": [NSNumber(value: 115),
                                           NSNumber(value: keyCode),
                                           NSNumber(value: mask)]]]]
        }
        let systemAreaShot = systemHotKey("30", enabled: true, keyCode: 1, mask: 655360)
        let optionShiftS = GlobalShortcut(keyCode: 1, modifiers: [.option, .shift])

        expect(GlobalShortcut.matchesSystemShortcut(optionShiftS,
                                                    symbolicHotKeys: systemAreaShot),
               "a combination macOS already answers is reported as taken")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    GlobalShortcut(keyCode: 1, modifiers: [.command, .shift]),
                    symbolicHotKeys: systemAreaShot),
               "the same key with other modifiers is a different shortcut")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: systemHotKey("30", enabled: false, keyCode: 1, mask: 655360)),
               "a system shortcut the user switched off is not in the way")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    GlobalShortcut(keyCode: 0xFFFF, modifiers: [.option, .shift]),
                    symbolicHotKeys: systemHotKey("30", enabled: true,
                                                  keyCode: 0xFFFF, mask: 655360)),
               "an entry with no key assigned matches nothing")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: systemHotKey("30", enabled: true, keyCode: 1,
                                                  mask: 655360, type: "modifier")),
               "an entry that is not a plain key combination is left alone")
        expect(!GlobalShortcut.matchesSystemShortcut(
                    optionShiftS,
                    symbolicHotKeys: ["30": ["enabled": NSNumber(value: true)]]),
               "an entry with no parameters is ignored rather than guessed at")
        expect(!GlobalShortcut.matchesSystemShortcut(optionShiftS, symbolicHotKeys: nil),
               "an unreadable system list reserves nothing")

        expect(UpdateInstallerSupport.progressStepAdvanced(from: nil, to: 0.004),
               "the first known download fraction always publishes")
        expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.011, to: 0.019),
               "fractions inside the same percent stay quiet")
        expect(UpdateInstallerSupport.progressStepAdvanced(from: 0.019, to: 0.021),
               "crossing into the next percent publishes")
        expect(!UpdateInstallerSupport.progressStepAdvanced(from: 0.5, to: 0.5),
               "an unchanged fraction stays quiet")

        let updateCeiling = UpdateInstallerSupport.downloadCeilingBytes
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: 9_638_011) == 9_638_011,
               "a download stops at the size the release advertises")
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: nil) == updateCeiling,
               "an asset with no size still stops at the ceiling")
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: 0) == updateCeiling,
               "a zero size is not a limit of zero")
        expect(UpdateInstallerSupport.downloadByteLimit(expectedBytes: updateCeiling + 1) == updateCeiling,
               "an advertised size beyond the ceiling cannot raise it")

        expect(UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                       receivedBytes: 9_638_011,
                                                       expectedBytes: 9_638_011),
               "a complete asset download is handed to the installer")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 404,
                                                        receivedBytes: 1_200,
                                                        expectedBytes: 9_638_011),
               "an error page is refused whatever it contains")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: 4_000_000,
                                                        expectedBytes: 9_638_011),
               "a truncated body is refused")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: 0,
                                                        expectedBytes: nil),
               "an empty body is refused even with no advertised size")
        expect(!UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                        receivedBytes: updateCeiling + 1,
                                                        expectedBytes: nil),
               "a body past the ceiling is refused with no advertised size")
        expect(UpdateInstallerSupport.downloadIsUsable(status: 200,
                                                       receivedBytes: 9_638_011,
                                                       expectedBytes: nil),
               "a plausible body with no advertised size is accepted")

        // The showcase loader is a @StateObject, so it can be released without
        // `.onDisappear` running. Its session holds the download delegate, and
        // that delegate's deinit is what deletes the scratch file, so the
        // release path has to invalidate the session too.
        let showcaseSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Update/UpdateShowcaseMedia.swift",
            encoding: .utf8)) ?? ""
        let showcaseDeinitBody = (showcaseSource.components(separatedBy: "\n    deinit {")
            .dropFirst().first ?? "").components(separatedBy: "\n    }").first ?? ""
        expect(showcaseDeinitBody.contains("session?.invalidateAndCancel()"),
               "a released showcase loader invalidates its session, freeing the delegate and its scratch file")
        expect(!showcaseDeinitBody.contains("finishTasksAndInvalidate"),
               "a released showcase loader cancels its download instead of letting it finish")

        expect(SettingsSearchSupport.matches(query: "", title: "Monitor"),
               "a blank settings search matches everything")
        expect(SettingsSearchSupport.matches(query: "moni", title: "Monitor"),
               "settings search is case-insensitive prefix-friendly")
        expect(SettingsSearchSupport.matches(query: "musica", title: "Música"),
               "settings search ignores accents")
        expect(!SettingsSearchSupport.matches(query: "shelf", title: "Monitor"),
               "settings search filters out non-matches")
        expect(SettingsSearchSupport.matches(query: "  switcher ", title: "Switcher"),
               "settings search trims surrounding whitespace")
        expect(SettingsSearchSupport.filteredIndices(query: "mo",
                                                     sections: [["Monitor", "Shelf"], ["Mouse"]])
                   == [[0], [0]],
               "settings search keeps matching rows per section")
        expect(SettingsSearchSupport.matches(query: "lid", title: "Energy",
                                             keywords: ["Keep going with the lid closed"]),
               "settings search finds a page by an option living inside it")
        expect(!SettingsSearchSupport.matches(query: "lid", title: "Energy", keywords: []),
               "without keywords the same query stays a miss")
        expect(SettingsSearchSupport.matches(
            query: "preview position",
            title: FeatureStrings.screenshot(.enUS).pageTitle,
            keywords: [FeatureStrings.screenshot(.enUS).previewPositionLabel]),
               "preview position is a searchable Screenshot keyword")
        expect(SettingsSearchSupport.matches(query: "hide",
                                             title: Strings.enUS.tabSwitcher,
                                             keywords: [Strings.enUS.dockClickHide]),
               "Dock hiding is findable through a localized Settings keyword")
        // MARK: Settings search structural deduplication
        let monitorPage = SettingsSearchItem(id: .page(.monitor),
                                             destination: FeatureSettingsDestination(.monitor),
                                             title: "Monitor", icon: "display")
        let monitorCPUFeature = SettingsSearchSupport.featureItems(language: .enUS) {
            $0 == .monitorCPU ? "Generated CPU Monitor" : $0.rawValue
        }.first { $0.id == .feature(.monitorCPU) }!
        let multiFeatureMerged = SettingsSearchSupport.combinedItems(
            pageItems: [monitorPage], featureItems: [monitorCPUFeature])
        expect(monitorPage.destination == monitorCPUFeature.destination
                && monitorCPUFeature.destination == AppFeature.monitorCPU.settingsDestination
                && monitorCPUFeature.destination.sectionAnchor == nil
                && multiFeatureMerged.map(\.id) == [.page(.monitor), .feature(.monitorCPU)],
               "the real shared Monitor destination does not merge a multi-feature page")

        // MARK: Settings search routing

        let genericFeaturesItem = SettingsSearchItem(id: .page(.features),
                                                     destination: FeatureSettingsDestination(.features),
                                                     title: "Features", icon: "square.grid.2x2")
        let genericFeaturesRoute = SettingsSearchSupport.route(for: genericFeaturesItem) { _ in true }
        expect(genericFeaturesRoute.destination == FeatureSettingsDestination(.features)
                && genericFeaturesRoute.targetFeature == nil,
               "a generic Features selection carries no feature target")

        let keywordBeforePartialTitle = SettingsSearchItem(
            id: .page(.features), destination: FeatureSettingsDestination(.features),
            title: "Features", icon: "square.grid.2x2", keywords: ["Homebrew Packages"])
        // MARK: Grouped Settings search suggestions
        let freshSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                 availableHeight: 1200)
        expect(freshSize.width == 772 && freshSize.height == 838,
               "settings window opens at the tall default when nothing is saved")
        let clampedSize = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                   availableHeight: 700)
        expect(clampedSize.height == 700,
               "the tall default shrinks to what the screen fits")
        let tinyScreen = SettingsWindowSupport.initialContentSize(savedWidth: 0, savedHeight: 0,
                                                                  availableHeight: 400)
        expect(tinyScreen.height == 528,
               "the default never goes below the design height")
        let savedSize = SettingsWindowSupport.initialContentSize(savedWidth: 900, savedHeight: 950,
                                                                 availableHeight: 700)
        expect(savedSize.width == 900 && savedSize.height == 950,
               "a user-chosen size is restored as is")
        let bogusSaved = SettingsWindowSupport.initialContentSize(savedWidth: 300, savedHeight: 200,
                                                                  availableHeight: 1200)
        expect(bogusSaved.width == 772 && bogusSaved.height == 838,
               "a saved size below the minimum falls back to the default")
        expect(!SettingsWindowSupport.isValidContentSize(width: 300, height: 200),
               "sub-minimum sizes are rejected by isValidContentSize")
        expect(SettingsWindowSupport.isValidContentSize(width: 772, height: 528),
               "exact minimum size is valid")
        expect(SettingsWindowSupport.isValidContentSize(width: 1000, height: 800),
               "larger size is valid")
        let preferredSettingsFrame = CGRect(x: -50, y: 100, width: 1000, height: 700)
        let overlappingPlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: preferredSettingsFrame,
            panelFrame: CGRect(x: 450, y: 500, width: 300, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        expect(overlappingPlacement.closesPanel
                && overlappingPlacement.frame == CGRect(x: 20, y: 100, width: 1000, height: 700),
               "failed avoidance closes the panel and clamps the preferred settings frame")
        let separatePlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: CGRect(x: 600, y: 100, width: 800, height: 700),
            panelFrame: CGRect(x: 1200, y: 500, width: 300, height: 300),
            visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        expect(!separatePlacement.closesPanel
                && separatePlacement.frame.maxX == 1172,
               "successful avoidance keeps the panel beside settings")
        let verticalPlacement = SettingsWindowSupport.panelPlacement(
            preferredFrame: CGRect(x: 100, y: 400, width: 1000, height: 300),
            panelFrame: CGRect(x: 450, y: 500, width: 300, height: 100),
            visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
        expect(!verticalPlacement.closesPanel
                && verticalPlacement.frame.maxY == 472,
               "vertical avoidance moves settings below the panel with the standard gap")

        expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-copy"),
               "a copy failure retries through the admin prompt")
        expect(UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-swap"),
               "a swap failure retries through the admin prompt")
        expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: "fail-verify"),
               "a verification failure is not a permission problem")
        expect(!UpdateInstallerSupport.shouldForceAdminInstall(afterFailureCode: nil),
               "no remembered failure means the normal path")

        let adminSource = AdminShell.appleScriptSource(
            command: #"printf "quoted" \ path"#,
            prompt: #"Approve "update" \ now"#)
        expect(adminSource == #"do shell script "printf \"quoted\" \\ path" with administrator privileges with prompt "Approve \"update\" \\ now""#,
               "administrator source keeps commands and prompts inside AppleScript strings")
        var adminCompileError: NSDictionary?
        expect(NSAppleScript(source: adminSource)?.compileAndReturnError(&adminCompileError) == true,
               "administrator source compiles in process")
        let inProcessScript = AppleScriptRunner.run(
            #"do shell script "/usr/bin/printf admin-probe""#)
        expect(inProcessScript.ok && inProcessScript.output == "admin-probe",
               "in-process AppleScript executes a shell command and returns its output")
        let cancelledScript = AppleScriptRunner.runDetailed("error number -128")
        expect(!cancelledScript.ok && cancelledScript.errorNumber == -128,
               "in-process AppleScript preserves cancellation as a failed request")

        let hiddenLayout = WindowLayoutAction.hiddenActions(from: "leftHalf, restore,bogus")
        expect(hiddenLayout == [.leftHalf, .restore],
               "hidden layout actions parse names and drop unknown ones")
        expect(WindowLayoutAction.hiddenActionsStorageValue([.restore, .leftHalf])
                   == "leftHalf,restore",
               "hidden layout actions serialize sorted for stable storage")
        expect(WindowLayoutAction.hiddenActions(from: "").isEmpty,
               "an empty stored value hides nothing")

        expect(UpdateInstallerSupport.shellSingleQuoted("/Applications/My App.app")
                   == "'/Applications/My App.app'",
               "shell quoting wraps paths with spaces")
        expect(UpdateInstallerSupport.shellSingleQuoted("it's") == "'it'\\''s'",
               "shell quoting survives embedded single quotes")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: "ok\n") == nil,
               "an ok marker is not a failure")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: " fail-verify\n") == "fail-verify",
               "a fail marker surfaces its step code")
        expect(UpdateInstallerSupport.installFailureCode(fromMarker: "") == nil,
               "an empty marker is not a failure")
        expect(UpdateInstallerSupport.runsFromImmutableLocation(
                   appPath: "/private/var/folders/ab/xyz/T/AppTranslocation/1F2/d/Chikit.app",
                   volumeIsReadOnly: { _ in false }),
               "translocated apps are flagged as not updatable in place")
        expect(UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/Chikit/Chikit.app",
                                                                volumeIsReadOnly: { _ in true }),
               "apps on a read-only volume (the DMG) are flagged as not updatable in place")
        expect(!UpdateInstallerSupport.runsFromImmutableLocation(appPath: "/Volumes/ExternalSSD/Chikit.app",
                                                                 volumeIsReadOnly: { _ in false }),
               "apps on a writable external volume stay updatable in place")
        let installerScript = UpdateInstallerSupport.installerScript()
        for step in ["fail-dmg-verify", "fail-tempdir", "fail-mount", "fail-no-app-in-dmg",
                     "fail-copy", "fail-version", "fail-verify", "fail-swap", "note ok"] {
            expect(installerScript.contains(step),
                   "installer script reports the \(step) step")
        }
        expect(installerScript.contains("spctl --status"),
               "installer script skips Gatekeeper assessment when the user disabled it")
        let dmgVerification = installerScript.range(of: "DMG_VERIFY_REQ")
        let dmgMount = installerScript.range(of: "/usr/bin/hdiutil attach")
        expect(dmgVerification != nil && dmgMount != nil
               && dmgVerification!.lowerBound < dmgMount!.lowerBound,
               "installer verifies the release signer before mounting the DMG")
        expect(installerScript.contains("BUNDLE_VERSION=")
               && installerScript.contains("\"$BUNDLE_VERSION\" = \"$EXPECTED_VERSION\""),
               "installer requires the signed app to match the offered release version")
        expect(installerScript.contains("chown -R"),
               "an elevated install hands the bundle back to the user")
        expect(installerScript.contains("update-old.$PID"),
               "the swap backup name is unique per run so a stale root-owned one never blocks it")
        expect(installerScript.contains("launchctl asuser"),
               "installer script relaunches as the user when running as root")
        expect(installerScript.contains("$RESULT.progress") && installerScript.contains("finalize"),
               "installer markers stay in a progress file until the run finishes")
        expect(installerScript.contains("/usr/bin/sudo -n -u \"#$ASUSER\" /bin/sh -c")
                && installerScript.contains("'/bin/echo \"$1\" > \"$2.progress\"' marker \"$1\" \"$RESULT\"")
                && installerScript.contains("/usr/bin/sudo -n -u \"#$ASUSER\" /bin/mv -f")
                && !installerScript.contains("note() { /bin/echo \"$1\" > \"$RESULT.progress\""),
               "elevated marker writes drop to the original user's credentials")
        let elevated = UpdateInstallerSupport.elevatedInstallCommand(
            appPath: "/Applications/Chikit.app",
            dmgPath: "/tmp/Chikit-update.dmg",
            pid: 123,
            resultPath: "/tmp/result",
            uid: 501,
            expectedVersion: "3.3.3")
        expect(elevated.contains("POSIX::setsid()") && elevated.hasSuffix("&"),
               "elevated installer leaves this app's session so it outlives the app it replaces")
        expect(elevated.contains("nohup"),
               "elevated installer keeps the nohup fallback if setsid is unavailable")
        expect(elevated.contains("'/Applications/Chikit.app'"),
               "elevated installer passes the app path quoted for the shell")
        expect(elevated.contains("'3.3.3'"),
               "elevated installer passes the expected version quoted for the shell")
        // The script travels inline and is long; it must be spelled once, with
        // both the setsid attempt and the fallback reusing the same "$@".
        expect(elevated.components(separatedBy: "DMG_VERIFY_REQ=").count == 2
               && elevated.components(separatedBy: "\"$@\"").count == 3,
               "elevated installer names its arguments once and reuses them for the fallback")

        // The fallback branch has to be chosen on whether perl is there, never
        // on an exit code: perl execs the payload, so the status the shell sees
        // is the payload's own. Every `exit 1` inside the installer script would
        // otherwise start the whole installer a second time, as root.
        let detachRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChikitDetachTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: detachRoot, withIntermediateDirectories: true)
        let detachPayload = detachRoot.appendingPathComponent("payload.sh")
        let detachLedger = detachRoot.appendingPathComponent("runs")
        try? "#!/bin/sh\n/bin/echo ran >> \"$1\"\nexit 1\n"
            .write(to: detachPayload, atomically: true, encoding: .utf8)
        let detachCommand = DetachedProcess.detachedShellCommand(
            quotedArgv: ["/bin/sh", detachPayload.path, detachLedger.path]
                .map(UpdateInstallerSupport.shellSingleQuoted)
                .joined(separator: " "))
        let detachShell = Process()
        detachShell.executableURL = URL(fileURLWithPath: "/bin/sh")
        detachShell.arguments = ["-c", detachCommand]
        try? detachShell.run()
        detachShell.waitUntilExit()
        func detachedRunCount() -> Int {
            (try? String(contentsOf: detachLedger, encoding: .utf8))?
                .split(separator: "\n").count ?? 0
        }
        for _ in 0..<300 where detachedRunCount() == 0 { usleep(10_000) }
        expect(detachedRunCount() == 1, "a detached command starts its payload once")
        // The rerun is counted again at the very end of this suite instead of
        // after a fixed wait here: a second run arriving late must not read as
        // a pass.

        // A detached spawn is only detached if the child really is its own
        // session leader; `nohup` alone leaves it in ours.
        do {
            let child = try DetachedProcess.spawn("/bin/sleep", ["30"])
            expect(getsid(child) == child,
                   "a detached child is its own session leader")
            expect(getsid(child) != getsid(0),
                   "a detached child is not in this process's session")
            kill(child, SIGKILL)
            var reaped: Int32 = 0
            waitpid(child, &reaped, 0)
        } catch {
            expect(false, "detached spawn failed: \(error.localizedDescription)")
        }

        // A child built to outlive this app must not carry this app's open
        // descriptors with it: the app is gone before the child does its work,
        // so anything it inherited is held open by a process nobody can see or
        // close. `Process` gave its children a clean table; these children get
        // the same. 0/1/2 must still be open (on /dev/null), or the child's
        // first open() takes stdout's slot.
        let fdRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChikitDetachFDTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: fdRoot, withIntermediateDirectories: true)
        let fdHolder = fdRoot.appendingPathComponent("holder")
        let fdReport = fdRoot.appendingPathComponent("report")
        // Opened WITHOUT O_CLOEXEC, the way a plain open() anywhere in the app
        // leaves it — that is the descriptor that must not travel.
        let holderDescriptor = open(fdHolder.path, O_RDWR | O_CREAT | O_TRUNC, 0o644)
        expect(holderDescriptor >= 3, "fd probe holds a descriptor above stdio")
        do {
            let probe = "{ /bin/echo leaked >&\(holderDescriptor); } 2>/dev/null; INHERITED=$?; "
                + "{ /bin/echo stdio; } 2>/dev/null; STDIO=$?; "
                + "/bin/echo \"$INHERITED $STDIO\" > \(UpdateInstallerSupport.shellSingleQuoted(fdReport.path))"
            let child = try DetachedProcess.spawn("/bin/sh", ["-c", probe])
            var reaped: Int32 = 0
            waitpid(child, &reaped, 0)
            let report = ((try? String(contentsOf: fdReport, encoding: .utf8)) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let status = report.split(separator: " ").map(String.init)
            expect(status.count == 2 && status[0] != "0",
                   "a detached child does not inherit this app's open descriptors (probe: \"\(report)\")")
            expect(((try? String(contentsOf: fdHolder, encoding: .utf8)) ?? "").isEmpty,
                   "a detached child cannot write through a descriptor this app opened")
            expect(status.count == 2 && status[1] == "0",
                   "a detached child still has stdout open (probe: \"\(report)\")")
        } catch {
            expect(false, "detached fd probe failed: \(error.localizedDescription)")
        }
        close(holderDescriptor)
        try? FileManager.default.removeItem(at: fdRoot)

        // MARK: - UpdateServiceSupport & SemVer channel reconciliation

        let vStable = UpdateServiceSupport.SemanticVersion(raw: "3.3.3")
        expect(vStable?.major == 3 && vStable?.minor == 3 && vStable?.patch == 3 && !vStable!.isPrerelease,
               "parses standard stable version")

        let vBeta = UpdateServiceSupport.SemanticVersion(raw: "v3.3.4-beta.1")
        expect(vBeta?.major == 3 && vBeta?.minor == 3 && vBeta?.patch == 4 && vBeta!.isPrerelease,
               "parses beta version with leading v")

        let vBuild = UpdateServiceSupport.SemanticVersion(raw: "3.3.4-rc.2+20260822")
        expect(vBuild?.major == 3 && vBuild?.minor == 3 && vBuild?.patch == 4 && vBuild!.isPrerelease,
               "parses version with build metadata")

        // SemVer 2.0.0 ordering rules
        expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.3"),
               "newer major/minor/patch stable is newer")
        expect(!UpdateServiceSupport.isNewer("3.3.3", than: "3.3.4"),
               "older stable is not newer")
        expect(UpdateServiceSupport.isNewer("3.3.4-beta.1", than: "3.3.3"),
               "beta of higher version is newer than older stable")
        expect(UpdateServiceSupport.isNewer("3.3.4-beta.2", than: "3.3.4-beta.1"),
               "beta.2 is newer than beta.1 of the same cycle")
        expect(UpdateServiceSupport.isNewer("3.3.4-rc.1", than: "3.3.4-beta.2"),
               "rc.1 is newer than beta.2")
        expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.4-beta.2"),
               "final stable release is newer than beta of same version")
        expect(UpdateServiceSupport.isNewer("3.3.4", than: "3.3.4-rc.1"),
               "final stable release is newer than rc of same version")
        expect(!UpdateServiceSupport.isNewer("3.3.3", than: "3.3.4-beta.1"),
               "older stable is never newer than a beta of higher version (no downgrade)")
        expect(!UpdateServiceSupport.isNewer("3.3.4-beta.1", than: "3.3.4"),
               "beta is not newer than the released final version")

        // Release candidate selection
        let dummyDMG = URL(string: "https://github.com/vorssaintapp/vorssaint-utils/releases/download/v3.3.4/Vorssaint.dmg")!
        let dummyBetaDMG = URL(string: "https://github.com/vorssaintapp/vorssaint-utils/releases/download/v3.3.4-beta.1/Vorssaint.dmg")!

        let candidateList = [
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.4-beta.1", isPrerelease: true, isDraft: false, dmgURL: dummyBetaDMG, dmgExpectedBytes: 1000, body: "Beta notes"),
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.3", isPrerelease: false, isDraft: false, dmgURL: dummyDMG, dmgExpectedBytes: 1000, body: "Stable notes"),
            UpdateServiceSupport.ReleaseCandidate(tagName: "v3.3.5-beta.1", isPrerelease: true, isDraft: true, dmgURL: dummyBetaDMG, dmgExpectedBytes: 1000, body: "Draft notes")
        ]

        let selectedStable = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.2", includeBetas: false)
        expect(selectedStable?.tagName == "v3.3.3", "stable channel only picks stable releases")

        let selectedBeta = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.2", includeBetas: true)
        expect(selectedBeta?.tagName == "v3.3.4-beta.1", "beta channel picks highest non-draft release")

        let selectedFromHigherBeta = UpdateServiceSupport.selectUpdate(from: candidateList, currentVersion: "3.3.4-beta.1", includeBetas: false)
        expect(selectedFromHigherBeta == nil, "user on beta turning off betas does not downgrade to older stable")

        let knownDigest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        expect(UpdateServiceSupport.sha256Matches(Data("abc".utf8), expectedHex: knownDigest),
               "update media accepts its pinned SHA-256 digest")
        expect(!UpdateServiceSupport.sha256Matches(Data("altered".utf8), expectedHex: knownDigest),
               "update media rejects content that does not match its pinned digest")
        expect(!UpdateServiceSupport.sha256Matches(Data("abc".utf8), expectedHex: "invalid"),
               "update media rejects a malformed pinned digest")

        // Defaults registered
        expect(Defaults.registeredDefaults[DefaultsKey.includeBetaUpdates] as? Bool == false,
               "includeBetaUpdates defaults to false in registeredDefaults")

        let testDefaults = UserDefaults(suiteName: "com.chikit.tests.betaActivation")!
        testDefaults.removePersistentDomain(forName: "com.chikit.tests.betaActivation")
        Defaults.activateBetaChannelIfRunningBeta(in: testDefaults, version: "3.3.3-beta.1")
        expect(testDefaults.bool(forKey: DefaultsKey.includeBetaUpdates) == true,
               "beta channel is activated automatically on a beta build")
        testDefaults.set(false, forKey: DefaultsKey.includeBetaUpdates)
        Defaults.activateBetaChannelIfRunningBeta(in: testDefaults, version: "3.3.3-beta.1")
        expect(testDefaults.bool(forKey: DefaultsKey.includeBetaUpdates) == false,
               "manual opt-out on a beta build is preserved across launches")

        // Stable version does not activate beta channel
        let stableDefaults = UserDefaults(suiteName: "com.chikit.tests.stableActivation")!
        stableDefaults.removePersistentDomain(forName: "com.chikit.tests.stableActivation")
        Defaults.activateBetaChannelIfRunningBeta(in: stableDefaults, version: "3.3.3")
        expect(stableDefaults.object(forKey: DefaultsKey.includeBetaUpdates) == nil,
               "stable release does not touch beta channel default")
        stableDefaults.removePersistentDomain(forName: "com.chikit.tests.stableActivation")
        testDefaults.removePersistentDomain(forName: "com.chikit.tests.betaActivation")

        // Localization completeness & formatting
        for language in AppLanguage.allCases {
            L10n.shared.language = language
            let s = L10n.shared.s
            expect(!s.includeBetaUpdatesToggle.isEmpty, "\(language.rawValue) includeBetaUpdatesToggle non-empty")
            expect(!s.includeBetaUpdatesCaption.isEmpty, "\(language.rawValue) includeBetaUpdatesCaption non-empty")
            expect(!s.betaBadgeLabel.isEmpty, "\(language.rawValue) betaBadgeLabel non-empty")
            expect(!s.includeBetaUpdatesCaption.contains("—"), "\(language.rawValue) has no em dash")
        }
        L10n.shared.language = .enUS

        // MARK: Launch at login reconciliation

        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .off,
                                                  locationIsUnstable: false) == .register,
               "a lost registration the user wants is redone at startup")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .off,
                                                  locationIsUnstable: true) == .none,
               "no registration is redone from an unstable location")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .enabled,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: true, registration: .enabled,
                                                      locationIsUnstable: true) == .none,
               "a healthy registration is left alone")
        expect(LaunchAtLoginSupport.startupAction(wanted: false, registration: .enabled,
                                                  locationIsUnstable: false) == .adoptEnabled
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .enabled,
                                                      locationIsUnstable: true) == .adoptEnabled,
               "an enable made outside the app becomes the stored choice")
        expect(LaunchAtLoginSupport.startupAction(wanted: false, registration: .off,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .off,
                                                      locationIsUnstable: true) == .none,
               "startup never turns launch at login on for a user who never asked")
        expect(LaunchAtLoginSupport.startupAction(wanted: true, registration: .needsApproval,
                                                  locationIsUnstable: false) == .none
                && LaunchAtLoginSupport.startupAction(wanted: false, registration: .needsApproval,
                                                      locationIsUnstable: false) == .none,
               "an item awaiting approval in System Settings is never registered over (issue #260)")
        // `SMAppService.Status` cannot be driven without a real login item, so
        // what the service does with the third state is pinned by source. Both
        // needles are public symbols, not a line's spelling.
        let launchAtLoginSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/LaunchAtLogin.swift",
            encoding: .utf8)) ?? ""
        expect(launchAtLoginSource.contains(".requiresApproval"),
               "an approval-pending login item is read as its own state")
        expect(launchAtLoginSource.contains("throw NeedsApprovalError()"),
               "turning launch at login on says so when only approval is missing")

        // Both window server scans read the same list and must keep
        // disagreeing where they disagree today. A point exactly on a
        // window's far edge is inside for the click lookup and outside for
        // the traffic lights, and a window whose app the traffic lights are
        // told to leave alone ends that scan instead of handing the click to
        // whatever sits behind it.
        func windowServerEntry(_ frame: CGRect, pid: Int32, number: UInt32) -> [String: Any] {
            [kCGWindowBounds as String: ["X": NSNumber(value: Double(frame.minX)),
                                         "Y": NSNumber(value: Double(frame.minY)),
                                         "Width": NSNumber(value: Double(frame.width)),
                                         "Height": NSNumber(value: Double(frame.height))] as [String: Any],
             kCGWindowLayer as String: NSNumber(value: 0),
             kCGWindowAlpha as String: NSNumber(value: 1.0),
             kCGWindowOwnerPID as String: NSNumber(value: pid),
             kCGWindowNumber as String: NSNumber(value: number)]
        }
        let scannedWindow = CGRect(x: 0, y: 0, width: 200, height: 200)
        let scannedNeighbour = CGRect(x: 200, y: 96, width: 200, height: 200)
        let scannedEdgePoint = CGPoint(x: 200, y: 100)
        let scannedNeighbours = [windowServerEntry(scannedWindow, pid: 1001, number: 11),
                                 windowServerEntry(scannedNeighbour, pid: 1002, number: 12)]
        expect(WindowServerSupport.bounds(from: scannedNeighbours[0]) == scannedWindow
                && WindowServerSupport.bounds(from: [:]) == nil,
               "a window's rectangle comes from its bounds entry and from nothing else")
        expect(WindowServerSupport.windowCandidate(in: scannedNeighbours, at: scannedEdgePoint,
                                                   ownProcessID: 501,
                                                   pidIsEligible: { _ in true })?.pid == 1001,
               "a click on a window's far edge still belongs to that window")
        expect(WindowServerSupport.trafficLightCandidate(in: scannedNeighbours, at: scannedEdgePoint,
                                                         button: .close,
                                                         ownProcessID: 501,
                                                         pidIsEligible: { _ in true })?.pid == 1002,
               "a traffic light on a window's far edge belongs to the window that owns the pixel")
        let scannedStack = [windowServerEntry(scannedWindow, pid: 1001, number: 11),
                            windowServerEntry(scannedWindow, pid: 1002, number: 12)]
        let scannedCloseButtonPoint = CGPoint(x: 20, y: 20)
        expect(WindowServerSupport.trafficLightCandidate(in: scannedStack, at: scannedCloseButtonPoint,
                                                         button: .close,
                                                         ownProcessID: 501,
                                                         pidIsEligible: { $0 != 1001 }) == nil,
               "a traffic light click stops at the window in front, never reaching one behind it")
        expect(WindowServerSupport.windowCandidate(in: scannedStack, at: scannedCloseButtonPoint,
                                                   ownProcessID: 501,
                                                   pidIsEligible: { $0 != 1001 })?.pid == 1002,
               "the click lookup carries on behind a window it was told to leave alone")

        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hex), "#FF0000",
                    "color picker formats pure red as hex")
        expectEqual(QuickToolsSupport.colorString(red: 0.2, green: 0.4, blue: 0.6, format: .rgb),
                    "rgb(51, 102, 153)",
                    "color picker formats components as CSS rgb")
        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hsl),
                    "hsl(0, 100%, 50%)",
                    "color picker formats pure red as hsl")
        expectEqual(QuickToolsSupport.colorString(red: 0, green: 0.5, blue: 0, format: .hsl),
                    "hsl(120, 100%, 25%)",
                    "color picker formats dark green as hsl")
        expectEqual(QuickToolsSupport.colorString(red: 0.25, green: 0.5, blue: 0.75, format: .swiftui),
                    "Color(red: 0.250, green: 0.500, blue: 0.750)",
                    "color picker formats components as SwiftUI code")
        expectEqual(QuickToolsSupport.colorString(red: 1.4, green: -0.2, blue: 0.5, format: .hex), "#FF0080",
                    "color picker clamps extended-gamut components")
        expect(ColorCopyFormat.sanitized("banana") == .hex,
               "color picker falls back to hex for unknown stored formats")
        expectEqual(QuickToolsSupport.colorString(red: 1, green: 0, blue: 0, format: .hex, bareHex: true),
                    "FF0000",
                    "color picker drops the leading # when the bare hex option is on")
        expectEqual(QuickToolsSupport.colorString(red: 0.2, green: 0.4, blue: 0.6, format: .rgb, bareHex: true),
                    "rgb(51, 102, 153)",
                    "bare hex option leaves the other copy formats untouched")

        let ocrLines = [
            QuickToolsSupport.RecognizedLine(text: "world", x: 0.5, y: 0.8),
            QuickToolsSupport.RecognizedLine(text: "hello", x: 0.1, y: 0.81),
            QuickToolsSupport.RecognizedLine(text: "below", x: 0.1, y: 0.4),
            QuickToolsSupport.RecognizedLine(text: "   ", x: 0.2, y: 0.6),
        ]
        expectEqual(QuickToolsSupport.joinedRecognizedText(ocrLines, removingLineBreaks: false),
                    "hello\nworld\nbelow",
                    "screen OCR joins lines top to bottom, left to right, dropping blanks")
        expectEqual(QuickToolsSupport.joinedRecognizedText(ocrLines, removingLineBreaks: true),
                    "hello world below",
                    "screen OCR can join lines with spaces")
        let joinedOCRPair: (String, String, Bool) -> String = { first, second, removingLineBreaks in
            QuickToolsSupport.joinedRecognizedText([
                .init(text: first, x: 0.1, y: 0.8),
                .init(text: second, x: 0.1, y: 0.4),
            ], removingLineBreaks: removingLineBreaks)
        }
        expectEqual(joinedOCRPair("这是", "测试", true), "这是测试",
                    "screen OCR joins Chinese lines without spaces")
        expectEqual(joinedOCRPair("これは", "テストです", true), "これはテストです",
                    "screen OCR joins Japanese lines without spaces")
        expectEqual(joinedOCRPair("これは", "ﾃｽﾄです", true), "これはﾃｽﾄです",
                    "screen OCR joins halfwidth Japanese kana without spaces")
        expectEqual(joinedOCRPair("이것은", "테스트입니다", true), "이것은 테스트입니다",
                    "screen OCR keeps Korean word spaces at line seams")
        expectEqual(joinedOCRPair("ㅋㅋ", "ㅎㅎ", true), "ㅋㅋ ㅎㅎ",
                    "screen OCR keeps spaces between Hangul compatibility jamo")
        expectEqual(joinedOCRPair("version", "版本", true), "version 版本",
                    "screen OCR separates mixed Latin and CJK seams")
        expectEqual(joinedOCRPair("Hello ", " world", true), "Hello world",
                    "screen OCR normalizes spaced-script boundary whitespace")
        expectEqual(joinedOCRPair("这是 ", " 测试", true), "这是测试",
                    "screen OCR trims boundary whitespace before a tight CJK seam")
        expectEqual(joinedOCRPair("이것은 ", " 테스트", true), "이것은 테스트",
                    "screen OCR normalizes Korean boundary whitespace to one separator")
        expectEqual(joinedOCRPair("这是", "测试", false), "这是\n测试",
                    "screen OCR preserves Chinese line breaks when removal is off")
        expectEqual(joinedOCRPair("这是 ", " 测试", false), "这是 \n 测试",
                    "screen OCR preserves boundary whitespace when line removal is off")
        expectEqual(QuickToolsSupport.joinedRecognizedText([], removingLineBreaks: false), "",
                    "screen OCR joins an empty result to an empty string")

        // QR codes: several join top to bottom, left to right, blanks dropped.
        let qrCodes = [
            QuickToolsSupport.DecodedBarcode(payload: "second", x: 0.6, y: 0.8),
            QuickToolsSupport.DecodedBarcode(payload: "first", x: 0.1, y: 0.81),
            QuickToolsSupport.DecodedBarcode(payload: "bottom", x: 0.1, y: 0.3),
            QuickToolsSupport.DecodedBarcode(payload: "  ", x: 0.2, y: 0.5),
        ]
        expectEqual(QuickToolsSupport.joinedBarcodePayloads(qrCodes), "first\nsecond\nbottom",
                    "QR codes join top to bottom, left to right, dropping blanks")
        expectEqual(QuickToolsSupport.joinedBarcodePayloads([]), "",
                    "no QR codes joins to an empty string")

        // Open link is limited to http and https so a scanned code can never
        // launch another scheme.
        expect(QuickToolsSupport.openableURL(from: "https://example.com/menu")?.absoluteString
                    == "https://example.com/menu",
               "an https payload is offered as an open link")
        expect(QuickToolsSupport.openableURL(from: " http://example.com ")?.host == "example.com",
               "surrounding whitespace does not stop a plain web link")
        expect(QuickToolsSupport.openableURL(from: "WIFI:S:Net;T:WPA;P:secret;;") == nil,
               "a Wi-Fi payload is copied, never opened")
        expect(QuickToolsSupport.openableURL(from: "mailto:a@b.com") == nil,
               "a mailto payload is not treated as an open link")
        expect(QuickToolsSupport.openableURL(from: "just some text") == nil,
               "plain text is never an open link")
        expect(QuickToolsSupport.openableURL(from: "example.com") == nil,
               "a bare host with no scheme is not opened")

        // Paste plain delegates only to the universal ⌥⇧⌘V equivalent
        // (shift = 1, option = 2 in the AX modifier mask); anything else in
        // an app's menus is some other edit command and must not be pressed.
        expect(QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                        modifierMask: 3,
                                                        isEnabled: true),
               "V with shift+option is an app's own matching-style paste")
        expect(QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "v",
                                                        modifierMask: 3,
                                                        isEnabled: true),
               "the command character match ignores case")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 0,
                                                         isEnabled: true),
               "plain ⌘V is the regular paste, never pressed as match style")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 1,
                                                         isEnabled: true),
               "⇧⌘V alone is a different command in several apps")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3 | 4,
                                                         isEnabled: true),
               "a control variant is not the matching-style paste")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3 | 8,
                                                         isEnabled: true),
               "an equivalent without the command key does not qualify")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "C",
                                                         modifierMask: 3,
                                                         isEnabled: true),
               "other command characters never match")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: nil,
                                                         modifierMask: 3,
                                                         isEnabled: true),
               "an item with no key equivalent never matches")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: nil,
                                                         isEnabled: true),
               "an unreadable modifier mask never matches")
        expect(!QuickToolsSupport.isMatchStyleEquivalent(commandCharacter: "V",
                                                         modifierMask: 3,
                                                         isEnabled: false),
               "a disabled item is left alone so the fallback paste still runs")

        // Launcher grid: 8 items in 3 columns (rows of 3, 3, 2).
        expect(QuickToolsSupport.gridIndex(after: 0, count: 8, columns: 3, direction: .right) == 1,
               "launcher grid moves right within a row")
        expect(QuickToolsSupport.gridIndex(after: 2, count: 8, columns: 3, direction: .right) == 2,
               "launcher grid does not wrap at the row's right edge")
        expect(QuickToolsSupport.gridIndex(after: 3, count: 8, columns: 3, direction: .left) == 3,
               "launcher grid does not wrap at the row's left edge")
        expect(QuickToolsSupport.gridIndex(after: 1, count: 8, columns: 3, direction: .down) == 4,
               "launcher grid moves down one row")
        expect(QuickToolsSupport.gridIndex(after: 7, count: 8, columns: 3, direction: .down) == 7,
               "launcher grid stays put when there is no row below")
        expect(QuickToolsSupport.gridIndex(after: 4, count: 8, columns: 3, direction: .up) == 1,
               "launcher grid moves up one row")
        expect(QuickToolsSupport.gridIndex(after: 6, count: 8, columns: 3, direction: .right) == 7,
               "launcher grid moves right in the last partial row")
        expect(QuickToolsSupport.gridIndex(after: 99, count: 8, columns: 3, direction: .left) == 6,
               "launcher grid clamps an out-of-range index")
        expect(QuickToolsSupport.gridIndex(after: 0, count: 0, columns: 3, direction: .down) == 0,
               "launcher grid survives an empty item list")

        expect(QuickToolsSupport.hiddenIDs(from: "a,b,,c") == Set(["a", "b", "c"]),
               "launcher hidden set parses and drops empties")
        expectEqual(QuickToolsSupport.serializeHiddenIDs(Set(["b", "a"])), "a,b",
                    "launcher hidden set serializes deterministically")
        expect(QuickToolsSupport.hiddenIDs(from: QuickToolsSupport.serializeHiddenIDs(Set(["x", "y"])))
                   == Set(["x", "y"]),
               "launcher hidden set round-trips")
        let afterFirstSwitch = WindowUseOrder.promoting(2, previous: 1, in: [])
        expect(afterFirstSwitch == [2, 1],
               "App Switcher use history records the previous window immediately after a switch")
        let afterSecondSwitch = WindowUseOrder.promoting(1, previous: 2, in: afterFirstSwitch)
        expect(afterSecondSwitch == [1, 2],
               "App Switcher use history toggles back after two consecutive switcher uses")

        // Issue #388: the switcher put the app the user had just used far down
        // the list. The order used to come from a history that only the
        // switcher's own commits ever wrote to, so windows picked with the
        // mouse were invisible to it and windows picked once through the
        // switcher stayed ahead of them forever.
        let mouseEntries = [WindowUseOrder.Entry(windowID: 10, pid: 1),   // used through the switcher, long ago
                            WindowUseOrder.Entry(windowID: 11, pid: 2),   // used through the switcher, long ago
                            WindowUseOrder.Entry(windowID: 12, pid: 3),   // clicked a moment ago
                            WindowUseOrder.Entry(windowID: 13, pid: 4)]   // clicked just now, in front
        let mouseOrder = WindowUseOrder.ordered(mouseEntries,
                                                windowHistory: [13, 12, 11, 10],
                                                appHistory: [4, 3, 2, 1],
                                                frontToBack: [13, 12, 11, 10])
        expect(mouseOrder.map(\.windowID) == [13, 12, 11, 10],
               "App Switcher orders by real window use, so windows picked with the mouse keep their place")

        // Two windows of the same app: the system posts no activation for a
        // switch between them, so only the focus history can order them.
        let sameAppEntries = [WindowUseOrder.Entry(windowID: 20, pid: 1),
                              WindowUseOrder.Entry(windowID: 21, pid: 1),
                              WindowUseOrder.Entry(windowID: 22, pid: 2)]
        let sameAppOrder = WindowUseOrder.ordered(sameAppEntries,
                                                  windowHistory: [21, 22, 20],
                                                  appHistory: [1, 2],
                                                  frontToBack: [21, 22, 20])
        expect(sameAppOrder.map(\.windowID) == [21, 22, 20],
               "App Switcher toggles back to the last window used even when it belongs to the current app")

        // A window that was never focused cannot be ranked by use: it follows
        // everything that was, ordered by its app and then by how deep it sits.
        let unseenEntries = [WindowUseOrder.Entry(windowID: 30, pid: 1),
                             WindowUseOrder.Entry(windowID: 31, pid: 2),
                             WindowUseOrder.Entry(windowID: 32, pid: 3),
                             WindowUseOrder.Entry(windowID: nil, pid: 3)]
        let unseenOrder = WindowUseOrder.ordered(unseenEntries,
                                                 windowHistory: [30],
                                                 appHistory: [1, 2, 3],
                                                 frontToBack: [30, 31, 32])
        expect(unseenOrder.map(\.windowID) == [30, 31, 32, nil],
               "App Switcher places never-focused windows after used ones, by app and then by depth")

        // Cold start: nothing has been used yet, so front-to-back order is the
        // only account of what came last, and it has to be used as one.
        expect(WindowUseOrder.reconciled([], existing: [40, 41, 42], frontToBack: [42, 40, 41])
               == [42, 40, 41],
               "App Switcher seeds its use history from the window server instead of starting arbitrary")
        expect(WindowUseOrder.reconciled([50, 51], existing: [51, 52], frontToBack: [52, 51])
               == [51, 52],
               "App Switcher use history drops closed windows and files new ones behind what was used")
        expect(WindowUseOrder.reconciled([60, 61, 62], existing: [60, 61, 62], frontToBack: [62])
               == [60, 61, 62],
               "App Switcher use history is not reshuffled by the window server once it knows better")
        expect(WindowUseOrder.reconciled([70, 71, 72], existing: [70, 71, 72], frontToBack: [], limit: 2)
               == [70, 71],
               "App Switcher use history stays bounded")
        expect(WindowUseOrder.reconciled([], running: [80, 81, 82], frontToBack: [81, 82, 80])
               == [81, 82, 80],
               "App Switcher seeds its application history from the window server too")
        expect(WindowUseOrder.reconciled([90, 91], running: [91, 92], frontToBack: [92, 91])
               == [91, 92],
               "App Switcher application history drops closed apps and files new ones behind")
        // A French keyboard types z where the US one types w, and its own w
        // sits on another key: both answer by the letter, not the position.
        // Cyrillic and Greek type no Latin letter at all, so the key position
        // stands in, the same place macOS puts their command shortcuts.
        // S only pins the search field once the opt-in preference is on, so
        // existing users who search by typing "s" first see no change.
        // Caps Lock alongside the session's ⌥ turns S into "Í" instead of "ß" —
        // an accented letter that folds cleanly to "i", an unrelated letter, so
        // the pin must still fire from the key's position (issue: ⌥S + Caps Lock).
        let switcherPanelFrame = CGRect(x: 400, y: 300, width: 600, height: 400)
        // MARK: Release notes parsing

        let changelog = """
        # Changelog

        ## [2.17.2] - 2026-06-17

        ### Summary
        This update keeps **Shelf** clear
        and the update window centered.

        ### Fixed
        - **Shelf** no longer shows an extra outline.
        - The update window opens centered
          on the visible screen.

        ### Added
        - Coffee shortcut in the menu panel.
        ![Menu bar temperature metrics](Resources/Images/menu-bar-temperature-metrics.png)

        ### Website
        - Official site: [vorssaint.com](https://vorssaint.com).

        ## [2.17.1] - 2026-06-17

        ### Fixed
        - Older release note.
        """
        let notes = ReleaseNotes.notes(for: "2.17.2", changelog: changelog)
        expect(notes.version == "2.17.2", "release notes version is parsed")
        expect(notes.date == "2026-06-17", "release notes date is parsed")
        expect(notes.sections.count == 3, "release notes keep sections for the requested version")
        expect(notes.sections.first?.title == "Summary", "release notes first section title is parsed")
        expect(notes.sections.first?.paragraphItems.first == "This update keeps Shelf clear and the update window centered.",
               "release notes parse summary paragraphs")
        expect(notes.sections.dropFirst().first?.title == "Fixed", "release notes fixed section title is parsed")
        expect(notes.sections.dropFirst().first?.bulletItems.first == "Shelf no longer shows an extra outline.",
               "release notes strip simple markdown emphasis")
        expect(notes.sections.dropFirst().first?.bulletItems.dropFirst().first == "The update window opens centered on the visible screen.",
               "release notes join continuation lines")
        expect(notes.sections.last?.bulletItems == ["Coffee shortcut in the menu panel."],
               "release notes stop before the next version")
        expect(notes.sections.last?.items.last == .image(ReleaseNoteImage(alt: "Menu bar temperature metrics",
                                                                          path: "Resources/Images/menu-bar-temperature-metrics.png")),
               "release notes parse changelog images")
        expect(!notes.sections.contains(where: { $0.title == "Website" }),
               "release notes hide website sections from the feature list")
        let previewBodyWithoutSummaryHeading = """
        ## [2.17.3]

        A short release summary from the GitHub release body.

        ### Fixed
        - Preview bullet.
        """
        let previewNotes = ReleaseNotes.notes(for: "2.17.3", changelog: previewBodyWithoutSummaryHeading)
        expect(previewNotes.sections.first?.title == "Summary",
               "release notes preserve an unheaded release-body summary paragraph")
        expect(previewNotes.sections.first?.paragraphItems.first == "A short release summary from the GitHub release body.",
               "release notes keep summary text before the first subsection")
        let githubReleaseBodyWithFooter = """
        ### Fixed
        - Update preview stays focused on changes.

        Signed with an Apple Developer ID and notarized by Apple, so it downloads and opens normally. Requires macOS 14 or later. Open the .dmg below and drag Chikit to Applications.
        """
        let inAppUpdateBody = ReleaseNotes.inAppUpdateNotes(from: githubReleaseBodyWithFooter) ?? ""
        expect(!inAppUpdateBody.contains("Signed with an Apple Developer ID"),
               "in-app update notes remove the GitHub installation footer")
        let githubPreviewNotes = ReleaseNotes.notes(for: "2.17.4",
                                                    changelog: "## [2.17.4]\n\n" + inAppUpdateBody)
        expect(githubPreviewNotes.sections.first?.bulletItems == ["Update preview stays focused on changes."],
               "in-app update notes keep release changes after removing the footer")
        let unreleasedChangelog = """
        ## [Unreleased]

        ### Added
        - Feature pending release.

        ## [2.17.4] - 2026-06-18

        ### Fixed
        - Shipped fix.
        """
        let unreleasedNotes = ReleaseNotes.notes(for: "Unreleased", changelog: unreleasedChangelog)
        expect(unreleasedNotes.version == "Unreleased" && unreleasedNotes.date == nil
               && unreleasedNotes.sections.first?.bulletItems == ["Feature pending release."],
               "release notes parse unreleased blocks without dates")
        expect(ReleaseNotes.allVersions(changelog: unreleasedChangelog) == ["2.17.4"],
               "allVersions excludes the unreleased header")
        expect(ReleaseNotes.rawNotes(for: "dev", changelog: unreleasedChangelog).contains("Feature pending release."),
               "rawNotes for dev falls back to the unreleased block")

        // MARK: URL cleaning

        // A grouped Form keeps a label column even for an empty label, which
        // left every field on the right half of its row. The hint has to
        // travel as `prompt:` and the label has to be hidden for a field to
        // own its whole row.
        let urlCleanerSettingsSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/URLCleanerSettings.swift",
            encoding: .utf8)) ?? ""
        expect(!urlCleanerSettingsSource.contains("TextField(l10n.s."),
               "no Clean URL field spends its row on a label instead of the field")
        expect(urlCleanerSettingsSource.components(separatedBy: "TextField(").count
                == urlCleanerSettingsSource.components(separatedBy: ".labelsHidden()").count,
               "every Clean URL field hides its label so the field owns the row")

        // Rules are stored as a difference from the built-in tables, never as
        // a copy of them, so names a later version adds still reach someone
        // who has already edited their rules.
        let paddedLink = " https://example.com/?id=1 "
        // MARK: Homebrew command building and parsing

        expect(HomebrewPackageKind.allCases == [.cask, .formula],
               "Homebrew package kinds keep casks before formulae")
        expect(HomebrewCommandBuilder.isValidToken("jq"), "simple Homebrew token is valid")
        expect(HomebrewCommandBuilder.isValidToken("python@3.14"), "versioned formula token is valid")
        expect(HomebrewCommandBuilder.isValidToken("visual-studio-code"), "cask token is valid")
        expect(HomebrewCommandBuilder.isValidToken("homebrew/cask-fonts/font-iosevka"), "tapped token is valid")
        expect(!HomebrewCommandBuilder.isValidToken(""), "empty Homebrew token is invalid")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "Error: Refusing to load formula foo from untrusted tap someone/sometap.\nRun `brew trust someone/sometap` to trust it.")
            == "someone/sometap",
               "untrusted tap name is extracted from Homebrew's refusal")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput: "Error: no such formula") == nil,
               "other Homebrew errors extract no tap")
        expect(HomebrewCommandBuilder.untrustedTapName(fromOutput:
            "from untrusted tap ../evil") == nil,
               "a tap name that fails token validation is rejected")
        let trustCommand = HomebrewCommandBuilder.trustTap(brewPath: "/opt/homebrew/bin/brew", tap: "someone/sometap")
        expect(trustCommand.arguments == ["trust", "--tap", "someone/sometap"],
               "trust command targets the tap explicitly")
        expect(!HomebrewCommandBuilder.isValidToken("-bad"), "leading dash Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("../bad"), "path traversal Homebrew token is invalid")
        expect(!HomebrewCommandBuilder.isValidToken("bad token"), "spaced Homebrew token is invalid")

        let brewPath = "/opt/homebrew/bin/brew"
        let cask = HomebrewPackage(kind: .cask, name: "sample-tool",
                                   displayName: "Sample Tool", desc: nil,
                                   installedVersion: nil, stableVersion: nil, homepage: nil)
        expect(HomebrewCommandBuilder.search(brewPath: brewPath, kind: .formula, query: "jq").arguments
               == ["search", "--formula", "jq"],
               "formula search command uses separated arguments")
        expect(HomebrewCommandBuilder.outdated(brewPath: brewPath).arguments
               == ["outdated", "--json=v2"],
               "Homebrew outdated command uses read-only JSON v2 output")
        expect(HomebrewCommandBuilder.update(brewPath: brewPath).arguments
               == ["update"],
               "Homebrew update command refreshes Homebrew metadata")
        expect(HomebrewCommandBuilder.install(brewPath: brewPath, package: cask).arguments
               == ["install", "--cask", "sample-tool"],
               "cask install command uses --cask")
        expect(HomebrewCommandBuilder.uninstall(brewPath: brewPath, package: cask).arguments
               == ["uninstall", "--cask", "sample-tool"],
               "cask uninstall command uses --cask")
        expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: cask).arguments
               == ["upgrade", "--cask", "sample-tool"],
               "cask upgrade command uses --cask")
        let formula = HomebrewPackage(kind: .formula, name: "jq",
                                      displayName: "jq", desc: nil,
                                      installedVersion: "1.8.1", stableVersion: nil, homepage: nil)
        expect(HomebrewCommandBuilder.upgrade(brewPath: brewPath, package: formula).arguments
               == ["upgrade", "jq"],
               "formula upgrade command uses separated arguments")
        expect(HomebrewCommandBuilder.upgradeAll(brewPath: brewPath).arguments
               == ["upgrade"],
               "Homebrew update all command upgrades all outdated packages")
        expect(HomebrewOperation.Action.install.runningSystemImage == "arrow.down.circle.fill",
               "Homebrew install status uses a download icon")
        expect(HomebrewOperation.Action.uninstall.runningSystemImage == "trash.circle.fill",
               "Homebrew uninstall status uses a trash icon")
        expect(HomebrewOperation.Action.upgrade.runningSystemImage == "arrow.up.circle.fill",
               "Homebrew package update status uses an update icon")
        expect(HomebrewOperation.Action.updateHomebrew.runningSystemImage == "arrow.triangle.2.circlepath",
               "Homebrew metadata refresh status uses a refresh icon")
        expect(HomebrewOperation.Action.uninstall.clearsSelectionOnSuccess,
               "Homebrew uninstall clears details for the package that left the installed list")
        expect(!HomebrewOperation.Action.install.clearsSelectionOnSuccess
                && !HomebrewOperation.Action.upgrade.clearsSelectionOnSuccess,
               "Homebrew install and upgrade preserve package details after success")
        expect(HomebrewCommandBuilder.needsTerminalFallback(output: "sudo: a terminal is required to read the password"),
               "sudo terminal error triggers Homebrew terminal fallback")
        expect(HomebrewCommandBuilder.installerCommand == #"/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)""#,
               "Homebrew installer command matches the official install script entrypoint")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/zsh"),
                    "/Users/test/.zprofile",
                    "Homebrew shell setup uses zprofile for zsh")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/bin/bash"),
                    "/Users/test/.bash_profile",
                    "Homebrew shell setup uses bash_profile for bash")
        expectEqual(HomebrewCommandBuilder.shellProfilePath(homeDirectory: "/Users/test", shellPath: "/opt/homebrew/bin/fish"),
                    "/Users/test/.config/fish/config.fish",
                    "Homebrew shell setup uses the interactive shell config")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/bin/zsh"),
                    #"eval "$(/opt/homebrew/bin/brew shellenv)""#,
                    "Homebrew shell setup line uses brew shellenv")
        expectEqual(HomebrewCommandBuilder.shellEnvLine(brewPath: brewPath, shellPath: "/opt/homebrew/bin/fish"),
                    "eval (/opt/homebrew/bin/brew shellenv fish)",
                    "Homebrew shell setup line matches the interactive shell")
        expectEqual(HomebrewAnalytics.url(kind: .formula).absoluteString,
                    "https://formulae.brew.sh/api/analytics/install-on-request/homebrew-core/30d.json",
                    "Homebrew formula popularity uses install-on-request analytics")
        expectEqual(HomebrewAnalytics.url(kind: .cask).absoluteString,
                    "https://formulae.brew.sh/api/analytics/cask-install/homebrew-cask/30d.json",
                    "Homebrew cask popularity uses cask install analytics")
        expectEqual(HomebrewAnalytics.compactCount(999), "999", "Homebrew popularity under 1K stays plain")
        expectEqual(HomebrewAnalytics.compactCount(1_250), "1.2K", "Homebrew popularity compacts thousands")
        expectEqual(HomebrewAnalytics.compactCount(1_200_000), "1.2M", "Homebrew popularity compacts millions")
        let shellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(brewPath: brewPath,
                                                                          homeDirectory: "/Users/test",
                                                                          shellPath: "/bin/zsh")
        expect(shellSetupCommand.hasPrefix("/bin/sh -c ")
                && shellSetupCommand.contains("PROFILE=/Users/test/.zprofile")
                && shellSetupCommand.hasSuffix(#"; eval "$(/opt/homebrew/bin/brew shellenv)"; brew --version"#),
               "Homebrew shell setup command targets the detected profile")
        expect(shellSetupCommand.contains(#"grep -qxF "$LINE""#),
               "Homebrew shell setup command avoids duplicate profile lines")
        let alternateShellSetupCommand = HomebrewCommandBuilder.shellConfigCommand(
            brewPath: brewPath,
            homeDirectory: "/Users/test",
            shellPath: "/opt/homebrew/bin/fish"
        )
        expect(alternateShellSetupCommand.hasPrefix("/bin/sh -c ")
                && alternateShellSetupCommand.contains("/bin/mkdir -p /Users/test/.config/fish")
                && alternateShellSetupCommand.hasSuffix("; eval (/opt/homebrew/bin/brew shellenv fish); brew --version"),
               "Homebrew shell setup creates and activates the interactive shell config")
        expectClose(HomebrewProgressParser.progressFraction(in: "######## 42.5%") ?? -1,
                    0.425,
                    "Homebrew progress parser reads percentage output")
        expect(HomebrewProgressParser.phase(in: "==> Downloading https://example.com/file",
                                            action: .install) == .downloading,
               "Homebrew progress parser detects downloads")
        expect(HomebrewProgressParser.phase(in: "==> Installing Cask sample-tool",
                                            action: .install) == .installing,
               "Homebrew progress parser detects installs")
        expect(HomebrewProgressParser.phase(in: "==> Uninstalling Cask sample-tool",
                                            action: .uninstall) == .uninstalling,
               "Homebrew progress parser detects uninstalls")
        expect(HomebrewProgressParser.phase(in: "==> Upgrading sample-formula",
                                            action: .upgrade) == .upgrading,
               "Homebrew progress parser detects upgrades")
        expect(HomebrewProgressParser.phase(in: "Already up-to-date.",
                                            action: .updateHomebrew) == .refreshing,
               "Homebrew progress parser detects metadata refresh")
        expect(HomebrewProgressParser.activity(in: "\u{001B}[32m==> Moving App 'Sample.app'\u{001B}[0m")
               == "Moving App 'Sample.app'",
               "Homebrew progress parser cleans activity lines")
        expect(HomebrewProgressParser.visibleError(from: "$ brew install x\nError: Cask failed")
               == "Error: Cask failed",
               "Homebrew progress parser hides command lines from visible errors")

        let homebrewJSON = """
        {
          "formulae": [
            {
              "name": "sample-formula",
              "full_name": "sample-formula",
              "desc": "Sample formula",
              "homepage": "https://example.com/sample-formula",
              "versions": { "stable": "1.8.1" },
              "installed": [{ "version": "1.8.1" }]
            },
            {
              "name": "tapped-formula",
              "full_name": "example/tap/tapped-formula",
              "desc": "Formula from a third-party tap",
              "homepage": "https://example.com/tapped-formula",
              "versions": { "stable": "2.0.0" },
              "installed": [{ "version": "1.0.0" }]
            }
          ],
          "casks": [
            {
              "token": "sample-tool",
              "name": ["Sample Tool"],
              "desc": "Sample cask",
              "homepage": "https://example.com/sample-tool",
              "version": "1.108.1",
              "installed": "1.107.0"
            },
            {
              "token": "tapped-tool",
              "full_token": "example/tap/tapped-tool",
              "name": ["Tapped Tool"],
              "desc": "Cask from a third-party tap",
              "homepage": "https://example.com/tapped-tool",
              "version": "2.0.0",
              "installed": "1.0.0"
            }
          ]
        }
        """
        let homebrewPackages = (try? HomebrewParser.parseInfoJSON(Data(homebrewJSON.utf8))) ?? []
        expect(homebrewPackages.count == 4, "Homebrew JSON parser keeps formulae and casks")
        expect(homebrewPackages.first?.kind == .cask,
               "Homebrew JSON parser sorts casks before formulae")
        expect(homebrewPackages.first(where: { $0.name == "sample-formula" })?.installedVersion == "1.8.1",
               "Homebrew parser reads installed formula version")
        let tappedFormula = homebrewPackages.first { $0.name == "example/tap/tapped-formula" }
        expect(tappedFormula?.displayName == "example/tap/tapped-formula",
               "Homebrew parser keeps the canonical name for a formula from a tap")
        expect(homebrewPackages.first(where: { $0.name == "sample-tool" })?.displayName == "Sample Tool",
               "Homebrew parser reads cask display name")
        let tappedCask = homebrewPackages.first { $0.name == "tapped-tool" }
        expect(tappedCask != nil,
               "Homebrew parser identifies a cask from a tap by its short token")
        expect(tappedCask?.displayName == "Tapped Tool",
               "Homebrew parser keeps the human-readable name for a cask from a tap")
        let cleanCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(homebrewJSON)) ?? []
        expect(cleanCommandPackages.count == 4,
               "Homebrew command output parser keeps clean JSON")
        let noisyHomebrewOutput = """
        Warning: Skipping some beta metadata
        {"notice": "not package data"}
        \(homebrewJSON)
        Warning: A newer Homebrew beta changed an optional field
        """
        let noisyCommandPackages = (try? HomebrewParser.parseInfoCommandOutput(noisyHomebrewOutput)) ?? []
        expect(noisyCommandPackages.count == 4,
               "Homebrew command output parser accepts warnings around JSON")
        expect(noisyCommandPackages.first(where: { $0.name == "sample-tool" })?.installedVersion == "1.107.0",
               "Homebrew command output parser keeps package data from noisy output")
        expect((try? HomebrewParser.parseInfoCommandOutput("Warning: no JSON here")) == nil,
               "Homebrew command output parser rejects output without valid JSON")
        let outdatedJSON = """
        {
          "formulae": [
            {
              "name": "fmt",
              "installed_versions": ["12.1.0"],
              "current_version": "12.2.0",
              "pinned": false
            },
            {
              "name": "example/tap/tapped-formula",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ],
          "casks": [
            {
              "name": "sample-tool",
              "installed_versions": ["1.107.0"],
              "current_version": "1.108.1",
              "pinned": true
            },
            {
              "name": "tapped-tool",
              "installed_versions": ["1.0.0"],
              "current_version": "2.0.0",
              "pinned": false
            }
          ]
        }
        """
        let outdatedPackages = (try? HomebrewParser.parseOutdatedJSON(Data(outdatedJSON.utf8))) ?? [:]
        expect(outdatedPackages.count == 4,
               "Homebrew outdated parser keeps formulae and casks")
        expect(outdatedPackages["formula:fmt"]?.versionSummary == "12.1.0 -> 12.2.0",
               "Homebrew outdated parser renders installed to current version")
        expect(outdatedPackages["cask:sample-tool"]?.isPinned == true,
               "Homebrew outdated parser reads pinned status")
        expect(tappedFormula.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same ID for tapped formulae")
        expect(tappedCask?.id == "cask:tapped-tool",
               "Homebrew installed cask data stays on the short token brew outdated reports")
        expect(tappedCask.flatMap { outdatedPackages[$0.id] }?.currentVersion == "2.0.0",
               "Homebrew installed and outdated data use the same short-token ID for tapped casks")
        let noisyOutdatedOutput = """
        Warning: Homebrew updated metadata
        {"notice": "not outdated data"}
        \(outdatedJSON)
        """
        let noisyOutdatedPackages = (try? HomebrewParser.parseOutdatedCommandOutput(noisyOutdatedOutput)) ?? [:]
        expect(noisyOutdatedPackages["formula:fmt"]?.currentVersion == "12.2.0",
               "Homebrew outdated command output parser accepts warnings around JSON")
        let orderingPackages = [
            HomebrewPackage(kind: .cask, name: "alpha-tool", displayName: "Alpha Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil),
            HomebrewPackage(kind: .cask, name: "beta-tool", displayName: "Beta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .cask, name: "beta-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "gamma-tool", displayName: "Gamma Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil,
                            update: HomebrewPackageUpdate(kind: .formula, name: "gamma-tool",
                                                          installedVersions: ["1.0"],
                                                          currentVersion: "2.0", isPinned: false)),
            HomebrewPackage(kind: .formula, name: "delta-tool", displayName: "Delta Tool",
                            desc: nil, installedVersion: "1.0", stableVersion: nil, homepage: nil)
        ]
        expect(HomebrewPackageOrdering.updatesFirst(orderingPackages).map(\.name)
               == ["beta-tool", "gamma-tool", "alpha-tool", "delta-tool"],
               "Homebrew installed packages keep all pending updates first without reordering either group")
        let searchPackages = HomebrewParser.parseSearchOutput("sample-formula\nbad token\nsample-filter\nsample-tool\n",
                                                              kind: .formula,
                                                              installed: homebrewPackages)
        expect(searchPackages.map(\.name) == ["sample-formula", "sample-filter", "sample-tool"],
               "Homebrew search parser keeps valid one-token results")
        let analyticsJSON = """
        {
          "category": "formula_install_on_request",
          "formulae": {
            "sample-formula": [
              { "formula": "sample-formula", "count": "21,557" },
              { "formula": "sample-formula --HEAD", "count": "30" }
            ],
            "sample-filter": [
              { "formula": "sample-filter", "count": "42,001" }
            ]
          }
        }
        """
        let popularity = (try? HomebrewAnalytics.parse(Data(analyticsJSON.utf8), kind: .formula)) ?? [:]
        expect(popularity["sample-formula"]?.count == 21_557,
               "Homebrew analytics parser prefers the exact formula count")
        expect(popularity["sample-filter"]?.rank == 1,
               "Homebrew analytics parser ranks by count")
        let rankedPackages = HomebrewAnalytics.enrichAndSort(searchPackages, popularity: popularity)
        expect(rankedPackages.map(\.name) == ["sample-filter", "sample-formula", "sample-tool"],
               "Homebrew search results sort by popularity first")
        expect(rankedPackages.first?.popularity?.compactCount == "42K",
               "Homebrew search results keep compact popularity")

        // MARK: Localization format contracts

        let localizedStrings: [(AppLanguage, Strings)] = [
            (.enUS, .enUS),
            (.ptBR, .ptBR),
            (.tr, .tr),
            (.ru, .ru),
            (.es, .es),
            (.de, .de),
            (.fr, .fr),
            (.it, .it),
            (.ja, .ja),
            (.ko, .ko),
            (.zhHans, .zhHans),
            (.zhTW, .zhTW),
            (.zhHK, .zhHK)
        ]
        expect(localizedStrings.count == AppLanguage.allCases.count, "all app languages are covered by tests")
        for (language, strings) in localizedStrings {
            let prefix = "localization \(language.rawValue)"
            expect(!strings.smoothScrollStepLabel.isEmpty
                   && !strings.smoothScrollResponseLabel.isEmpty
                   && !strings.smoothScrollStepLabel.contains("—")
                   && !strings.smoothScrollResponseLabel.contains("—"),
                   "\(prefix) smooth scrolling controls are present without em dash")
            expect(strings.quickToolsTab == strings.launcherName,
                   "\(prefix) Quick panel keeps the same name in Settings")
            expectFormat(strings.cutMovedPluralFormat, ["d"], "\(prefix) cut plural format")
            expectFormat(strings.uninstallerSelectedFormat, ["d", "d"], "\(prefix) uninstaller selected format")
            expectFormat(strings.uninstallerFreedFormat, ["@"], "\(prefix) uninstaller freed format")
            expectFormat(strings.shelfSelectedFormat, ["d"], "\(prefix) shelf selection format")
            expectFormat(strings.powerAdapterMaxFormat, ["@"], "\(prefix) adapter max format")
            expectFormat(strings.mixerInputErrorFormat, ["@"], "\(prefix) mixer input error format")
            expect(!strings.mixerSoundEffectsOutputTitle.isEmpty
                   && !strings.mixerSoundEffectsOutputTooltip.isEmpty
                   && !strings.mixerSoundEffectsOutputTitle.contains("—")
                   && !strings.mixerSoundEffectsOutputTooltip.contains("—"),
                   "\(prefix) system sound output labels are present without em dash")
            expect(!strings.keepAwakeRightClickToggle.isEmpty
                   && !strings.keepAwakeRightClickToggleCaption.isEmpty
                   && !strings.keepAwakeRightClickToggle.contains("—")
                   && !strings.keepAwakeRightClickToggleCaption.contains("—"),
                   "\(prefix) right-click Keep Awake labels are present without em dash")
            expectFormat(strings.homebrewConfirmInstallBodyFormat, ["@"], "\(prefix) Homebrew install format")
            expectFormat(strings.homebrewConfirmUninstallBodyFormat, ["@"], "\(prefix) Homebrew uninstall format")
            expectFormat(strings.homebrewConfirmUpgradeBodyFormat, ["@"], "\(prefix) Homebrew upgrade format")
            expect(!strings.homebrewUpgradeAll.isEmpty, "\(prefix) Homebrew update all title is present")
            expect(!strings.homebrewUpdateHomebrew.isEmpty, "\(prefix) Homebrew update Homebrew title is present")
            expectFormat(strings.switcherIconRowMode, ["@"], "\(prefix) App Switcher icon-row title format")
            expect(!strings.switcherIconRowModeCaption.isEmpty, "\(prefix) App Switcher icon-row caption is present")
            expect(!strings.switcherSimpleMode.isEmpty, "\(prefix) App Switcher simple-mode title is present")
            expect(!strings.switcherSimpleModeCaption.isEmpty, "\(prefix) App Switcher simple-mode caption is present")
            expect(!strings.switcherCurrentSpaceOnly.isEmpty
                   && !strings.switcherCurrentSpaceOnly.contains("—"),
                   "\(prefix) App Switcher current-desktop title is present without em dash")
            expect(!strings.switcherCurrentSpaceOnlyCaption.isEmpty
                   && !strings.switcherCurrentSpaceOnlyCaption.contains("—"),
                   "\(prefix) App Switcher current-desktop caption is present without em dash")
            expect([strings.switcherScreenPlacementLabel,
                    strings.switcherScreenPlacementPointer,
                    strings.switcherScreenPlacementMenuBar,
                    strings.switcherScreenPlacementActiveWindow,
                    strings.switcherScreenPlacementCaption]
                   .allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) App Switcher screen placement labels are present without em dash")
            expect(!strings.switcherOtherDesktop.isEmpty
                   && !strings.switcherOtherDesktop.contains("—"),
                   "\(prefix) App Switcher other-desktop label is present without em dash")
            expect(!strings.switcherSearchPin.isEmpty
                   && !strings.switcherSearchPinCaption.isEmpty
                   && !strings.switcherSearchPin.contains("—")
                   && !strings.switcherSearchPinCaption.contains("—"),
                   "\(prefix) App Switcher pinned-search labels are present without em dash")
            expect(!strings.switcherShowShortcutHints.isEmpty
                   && !strings.switcherShowShortcutHintsCaption.isEmpty
                   && !strings.switcherShowShortcutHints.contains("—")
                   && !strings.switcherShowShortcutHintsCaption.contains("—"),
                   "\(prefix) App Switcher shortcut-hint labels are present without em dash")
            expect(!strings.switcherAppearanceDelay.isEmpty
                   && !strings.switcherAppearanceDelayCaption.isEmpty
                   && !strings.switcherAppearanceDelay.contains("—")
                   && !strings.switcherAppearanceDelayCaption.contains("—"),
                   "\(prefix) App Switcher appearance-delay labels are present without em dash")
            expect(!strings.switcherWindowlessApps.isEmpty
                   && !strings.switcherWindowlessApps.contains("—"),
                   "\(prefix) App Switcher windowless apps title is present without em dash")
            expect(!strings.switcherWindowlessAppsCaption.isEmpty
                   && !strings.switcherWindowlessAppsCaption.contains("—"),
                   "\(prefix) App Switcher windowless apps caption is present without em dash")
            expect(!strings.dockClickHide.isEmpty
                   && !strings.dockClickHideCaption.isEmpty
                   && !strings.dockClickHide.contains("—")
                   && !strings.dockClickHideCaption.contains("—"),
                   "\(prefix) Dock hide labels are present without em dash")
            expect(!strings.switcherWindowlessAppsOff.isEmpty
                   && !strings.switcherWindowlessAppsFinder.isEmpty
                   && !strings.switcherWindowlessAppsAll.isEmpty
                   && !strings.switcherWindowlessAppsOff.contains("—")
                   && !strings.switcherWindowlessAppsFinder.contains("—")
                   && !strings.switcherWindowlessAppsAll.contains("—"),
                   "\(prefix) App Switcher windowless apps choices are all present without em dash")
            expect(!strings.diskAvailable.isEmpty
                   && !strings.diskPurgeable.isEmpty
                   && !strings.diskAvailable.contains("—")
                   && !strings.diskPurgeable.contains("—"),
                   "\(prefix) disk available and purgeable labels are present without em dash")
            expect(!strings.switcherNoOpenWindow.isEmpty
                   && !strings.switcherNoOpenWindow.contains("—"),
                   "\(prefix) App Switcher no-open-window tile label is present without em dash")
            expect(!strings.dockPreviewBackgroundOpacity.isEmpty
                   && !strings.dockPreviewBackgroundOpacity.contains("—"),
                   "\(prefix) Dock Preview background title is present without em dash")
            expect(!strings.dockPreviewBackgroundOpacityCaption.isEmpty
                   && !strings.dockPreviewBackgroundOpacityCaption.contains("—"),
                   "\(prefix) Dock Preview background caption is present without em dash")
            expect(!strings.dockPreviewOpenDelay.isEmpty
                   && !strings.dockPreviewOpenDelay.contains("—"),
                   "\(prefix) Dock Preview open delay title is present without em dash")
            expect(!strings.dockPreviewOpenDelayCaption.isEmpty
                   && !strings.dockPreviewOpenDelayCaption.contains("—"),
                   "\(prefix) Dock Preview open delay caption is present without em dash")
            expect(!strings.dockPreviewQuitAppOnClose.isEmpty
                   && !strings.dockPreviewQuitAppOnClose.contains("—")
                   && !strings.dockPreviewQuitAppOnCloseCaption.isEmpty
                   && !strings.dockPreviewQuitAppOnCloseCaption.contains("—"),
                   "\(prefix) Dock Preview quit-on-close labels are present without em dash")
            expect(!strings.switcherShortcutHintApps.isEmpty, "\(prefix) App Switcher app shortcut hint is present")
            expect(!strings.switcherShortcutHintWindows.isEmpty, "\(prefix) App Switcher window shortcut hint is present")
            expect(!strings.networkApps.isEmpty, "\(prefix) network app usage title is present")
            expect(!strings.networkAppsIdle.isEmpty, "\(prefix) network app idle text is present")
            expect(!strings.monitorOpenActivityMonitor.isEmpty
                   && !strings.monitorOpenActivityMonitor.contains("—"),
                   "\(prefix) Activity Monitor action is present without em dash")
            expect(!strings.memoryCompressed.isEmpty
                   && !strings.memoryCompressed.contains("—")
                   && !strings.memoryCachedFiles.isEmpty
                   && !strings.memoryCachedFiles.contains("—"),
                   "\(prefix) memory compressed and cached labels are present without em dash")
            expect(!strings.launchAtLoginNeedsApplications.isEmpty
                   && !strings.launchAtLoginNeedsApplications.contains("—"),
                   "\(prefix) launch at login location note is present without em dash")
            // Shortcut recording: the waiting cap, the two hints under the row
            // and the honest message for a combination that never arrived (#308).
            let shortcutCaptureStrings = [strings.shortcutPressKeys, strings.shortcutEscapeHint,
                                          strings.shortcutDeleteHint, strings.shortcutNotCaptured,
                                          strings.shortcutRecording, strings.shortcutInvalid]
            expect(shortcutCaptureStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) shortcut recording strings are present without em dash")
            expect(!ShortcutRecordingCaption.text(strings, canClear: false).isEmpty
                   && !ShortcutRecordingCaption.text(strings, canClear: false)
                       .contains(strings.shortcutDeleteHint),
                   "\(prefix) a field that cannot clear never promises that Delete clears")
            expect(ShortcutRecordingCaption.text(strings, canClear: true)
                       .contains(strings.shortcutDeleteHint),
                   "\(prefix) a field that can clear says so")
            expect(strings.shortcutPressKeys.count <= 16,
                   "\(prefix) the waiting cap stays short enough for the field")
            let ocrStrings = [strings.ocrRemoveLineBreaksToggle, strings.ocrRemoveLineBreaksCaption,
                              strings.ocrQRToggle, strings.ocrQRCaption, strings.ocrQRCopied,
                              strings.qrResultTitle, strings.qrResultCopy, strings.qrResultOpen]
            expect(ocrStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) screen OCR strings are present without em dash")
            let cleaningStrings = [strings.cleaningKeepScreenVisibleToggle, strings.cleaningKeepScreenVisibleCaption,
                                   strings.cleaningStartNow, strings.cleaningOverlayTitle,
                                   strings.cleaningOverlaySubtitle, strings.cleaningOverlayUnlock,
                                   strings.cleaningOverlayMouseHint, strings.cleaningPanelCaption]
            expect(cleaningStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) cleaning mode strings are present without em dash")
            let highlightsStrings = [strings.highlightsTitle, strings.highlightsTitleClipboardRedesign,
                                     strings.highlightsCaptionDockPreview,
                                     strings.highlightsCaptionScreenshot,
                                     strings.highlightsCaptionSnippetLibrary,
                                     strings.highlightsCaptionCapturePalette,
                                     strings.highlightsCaptionClipboardRedesign,
                                     strings.highlightsConfigure,
                                     strings.highlightsTry, strings.highlightsSeeAll,
                                     strings.reviewIntro, strings.reviewHighlights]
            expect(highlightsStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) update highlights strings are present without em dash")
            let officialHomebrewIntroStrings = [
                strings.homebrewOfficialIntroTitle,
                strings.homebrewOfficialIntroMessage,
                strings.homebrewOfficialIntroInstallLabel,
                strings.homebrewOfficialIntroMigrationTitle,
                strings.homebrewOfficialIntroMigrationMessage,
                strings.homebrewOfficialIntroCopyButton,
                strings.supportIntroDoneButton,
            ]
            expect(officialHomebrewIntroStrings.allSatisfy { !$0.isEmpty },
                   "\(prefix) official Homebrew intro is complete")
            expect(officialHomebrewIntroStrings.allSatisfy { !$0.contains("—") },
                   "\(prefix) official Homebrew intro has no em dash")
            let supportCommunityStrings = [
                strings.donateHeading,
                strings.donateMessage,
                strings.donateButton,
                strings.supportIntroTitle,
                strings.supportIntroMessage,
                strings.supportIntroStarButton,
                strings.supportIntroStarMessage,
                strings.supportIntroCoffeeButton,
                strings.discordIntroTitle,
                strings.discordIntroMessage,
                strings.discordIntroBenefitHelp,
                strings.discordIntroBenefitFeedback,
                strings.discordIntroBenefitPreviews,
                strings.discordIntroJoinButton,
                strings.communityIntroTitle,
                strings.communityIntroMessage,
                strings.communityIntroFollowButton,
            ]
            expect(supportCommunityStrings.allSatisfy { !$0.isEmpty && !$0.contains("—") },
                   "\(prefix) support and community strings are complete without em dash")
            expect(strings.donateButton.contains("Buy Me a Coffee")
                   && strings.supportIntroCoffeeButton.contains("Buy Me a Coffee"),
                   "\(prefix) financial support points only to Buy Me a Coffee")
            expect(strings.supportIntroStarMessage.localizedCaseInsensitiveContains("GitHub")
                   && strings.discordIntroJoinButton.localizedCaseInsensitiveContains("Discord"),
                   "\(prefix) non-financial support and community actions name their destinations")
            expect(strings.discordIntroMessage.count <= 320,
                   "\(prefix) Discord introduction stays concise")
            expect(!strings.communityIntroMessage.isEmpty
                   && strings.communityIntroMessage.contains("X"),
                   "\(prefix) community intro invites users to follow previews on X")
            let retiredWeeklyPhrases = [
                "uma vez por semana", "once a week", "haftada bir", "раз в неделю",
                "una vez por semana", "einmal pro Woche", "une fois par semaine",
                "una volta a settimana", "週1回", "매주 한 번", "每周更新一次", "每週更新一次",
            ]
            expect(retiredWeeklyPhrases.allSatisfy {
                !strings.communityIntroMessage.localizedCaseInsensitiveContains($0)
            }, "\(prefix) community intro no longer promises weekly updates")
            expect(!strings.communityIntroMessage.contains("—")
                   && strings.communityIntroMessage.count <= 320,
                   "\(prefix) community intro stays concise and has no em dash")
            if language == .enUS {
                expect(strings.discordIntroMessage.contains("new")
                       && strings.discordIntroMessage.contains("still being built"),
                       "English Discord introduction says the community is new and in development")
            } else if language == .ptBR {
                expect(strings.discordIntroMessage.contains("nova")
                       && strings.discordIntroMessage.contains("em desenvolvimento"),
                       "Portuguese Discord introduction says the community is new and in development")
            }
            expect(!strings.updateShowcaseTitle.isEmpty, "\(prefix) update showcase title is present")
            expect(!strings.updateShowcaseMessage.isEmpty, "\(prefix) update showcase message is present")
            expect(!strings.updateShowcaseUnavailable.isEmpty, "\(prefix) update showcase fallback is present")
            expect(!strings.updateShowcaseRestart.isEmpty, "\(prefix) update showcase restart control is present")
            expect(!strings.homebrewConfirmUpgradeAllTitle.isEmpty, "\(prefix) Homebrew update all confirmation title is present")
            expect(!strings.homebrewConfirmUpgradeAllBody.isEmpty, "\(prefix) Homebrew update all confirmation body is present")
            expect(!strings.homebrewConfirmUpdateHomebrewTitle.isEmpty, "\(prefix) Homebrew update Homebrew confirmation title is present")
            expect(!strings.homebrewConfirmUpdateHomebrewBody.isEmpty, "\(prefix) Homebrew update Homebrew confirmation body is present")
            expectFormat(strings.homebrewPopularityFormat, ["@", "@"], "\(prefix) Homebrew popularity format")
            expectFormat(strings.homebrewOperationInstallFormat, ["@"], "\(prefix) Homebrew operation install format")
            expectFormat(strings.homebrewOperationUninstallFormat, ["@"], "\(prefix) Homebrew operation uninstall format")
            expectFormat(strings.homebrewOperationUpgradeFormat, ["@"], "\(prefix) Homebrew operation upgrade format")
            expect(!strings.homebrewOperationUpgradeAll.isEmpty, "\(prefix) Homebrew operation update all is present")
            expect(!strings.homebrewOperationUpdateHomebrew.isEmpty, "\(prefix) Homebrew operation update Homebrew is present")
            expectFormat(strings.homebrewOperationInstalledFormat, ["@"], "\(prefix) Homebrew operation installed format")
            expectFormat(strings.homebrewOperationUninstalledFormat, ["@"], "\(prefix) Homebrew operation uninstalled format")
            expectFormat(strings.homebrewOperationUpgradedFormat, ["@"], "\(prefix) Homebrew operation upgraded format")
            expect(!strings.homebrewOperationUpgradedAll.isEmpty, "\(prefix) Homebrew operation updated all is present")
            expect(!strings.homebrewOperationUpdatedHomebrew.isEmpty, "\(prefix) Homebrew operation updated Homebrew is present")
            expectFormat(strings.homebrewOperationFailedFormat, ["@"], "\(prefix) Homebrew operation failed format")
            expectFormat(strings.homebrewOperationElapsedFormat, ["@"], "\(prefix) Homebrew operation elapsed format")

            let rendered = [
                String(format: strings.cutMovedPluralFormat, 2),
                String(format: strings.uninstallerSelectedFormat, 1, 3),
                String(format: strings.uninstallerFreedFormat, "1 MB"),
                String(format: strings.shelfSelectedFormat, 2),
                String(format: strings.powerAdapterMaxFormat, "30 W"),
                String(format: strings.mixerInputErrorFormat, "OSStatus -1"),
                String(format: strings.homebrewConfirmInstallBodyFormat, "jq"),
                String(format: strings.homebrewConfirmUninstallBodyFormat, "jq"),
                String(format: strings.homebrewPopularityFormat, "1,234", "30"),
                String(format: strings.homebrewOperationInstallFormat, "jq"),
                String(format: strings.homebrewOperationUninstallFormat, "jq"),
                String(format: strings.homebrewOperationInstalledFormat, "jq"),
                String(format: strings.homebrewOperationUninstalledFormat, "jq"),
                String(format: strings.homebrewOperationFailedFormat, "jq"),
                String(format: strings.homebrewOperationElapsedFormat, "10s"),
            ]
            for value in rendered {
                expect(!value.isEmpty && !value.contains("%"), "\(prefix) renders format strings")
            }
        }
        let infoPlist = NSDictionary(contentsOfFile: "Resources/Info.plist") as? [String: Any]
        let bundleLocalizations = infoPlist?["CFBundleLocalizations"] as? [String] ?? []
        expect(bundleLocalizations.contains("tr"), "Info.plist declares Turkish as a bundle localization")
        expect(bundleLocalizations.contains("ko"), "Info.plist declares Korean as a bundle localization")
        let baseAudioPrompt = infoPlist?["NSAudioCaptureUsageDescription"] as? String ?? ""
        expect(baseAudioPrompt.contains("Chikit taps individual app audio"),
               "base audio permission prompt is an English fallback")
        let organizerFolderPromptKeys = [
            "NSDesktopFolderUsageDescription", "NSDocumentsFolderUsageDescription",
            "NSNetworkVolumesUsageDescription", "NSRemovableVolumesUsageDescription",
        ]
        expect(organizerFolderPromptKeys.allSatisfy {
                   !(infoPlist?[$0] as? String ?? "").isEmpty
               },
               "the organizer declares every supported custom destination permission")
        let localizedInfoPlists = (try? FileManager.default.contentsOfDirectory(
            atPath: "Resources"))?.filter { $0.hasSuffix(".lproj") } ?? []
        expect(localizedInfoPlists.allSatisfy { folder in
            let value = (try? String(contentsOfFile: "Resources/\(folder)/InfoPlist.strings",
                                     encoding: .utf8)) ?? ""
            return organizerFolderPromptKeys.allSatisfy(value.contains)
        }, "every localization explains custom organizer folder access")
        let turkishInfoPlistStrings = (try? String(contentsOfFile: "Resources/tr.lproj/InfoPlist.strings",
                                                   encoding: .utf8)) ?? ""
        expect(turkishInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && turkishInfoPlistStrings.contains("Hiçbir şey kaydedilmez"),
               "Turkish InfoPlist.strings localizes the audio permission prompt")
        let koreanInfoPlistStrings = (try? String(contentsOfFile: "Resources/ko.lproj/InfoPlist.strings",
                                                  encoding: .utf8)) ?? ""
        expect(koreanInfoPlistStrings.contains("NSAudioCaptureUsageDescription")
               && koreanInfoPlistStrings.contains("어떤 오디오도 녹음되거나"),
               "Korean InfoPlist.strings localizes the audio permission prompt")

        // MARK: Network speed math

        let slow = NetworkCounters(received: 1000, sent: 500)
        let fast = NetworkCounters(received: 1000 + 2048, sent: 500 + 1024)
        let speed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 2)
        expectClose(speed.down, 1024, "down speed over 2s")
        expectClose(speed.up, 512, "up speed over 2s")

        let zeroElapsed = MetricFormat.netSpeed(previous: slow, current: fast, elapsed: 0)
        expect(zeroElapsed.down == 0 && zeroElapsed.up == 0, "zero elapsed yields zero")

        // Counter reset (interface went down) must not produce a negative/huge spike.
        let afterReset = MetricFormat.netSpeed(previous: fast, current: slow, elapsed: 2)
        expect(afterReset.down == 0 && afterReset.up == 0, "counter reset yields zero")

        var networkFallback = NetworkCounterFallback()
        let firstFrozenDownload = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 500),
            current: NetworkCounters(received: 1_000, sent: 700)
        )
        expect(firstFrozenDownload.sampleProcesses && !firstFrozenDownload.useProcessDownload,
               "first frozen inbound sample primes the process fallback")
        let secondFrozenDownload = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 700),
            current: NetworkCounters(received: 1_000, sent: 900)
        )
        expect(secondFrozenDownload.sampleProcesses && secondFrozenDownload.useProcessDownload,
               "second frozen inbound sample activates the process fallback")
        let fallbackIdle = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 900),
            current: NetworkCounters(received: 1_000, sent: 900)
        )
        expect(fallbackIdle.sampleProcesses && fallbackIdle.useProcessDownload,
               "active fallback keeps sampling downloads even when upload is idle")
        let inboundRecovered = networkFallback.observe(
            previous: NetworkCounters(received: 1_000, sent: 900),
            current: NetworkCounters(received: 1_100, sent: 950)
        )
        expect(!inboundRecovered.sampleProcesses && !inboundRecovered.useProcessDownload,
               "moving inbound counters restore the lightweight interface reader")
        _ = networkFallback.observe(
            previous: NetworkCounters(received: 1_100, sent: 950),
            current: NetworkCounters(received: 1_100, sent: 1_000)
        )
        let counterResetFallback = networkFallback.observe(
            previous: NetworkCounters(received: 1_100, sent: 1_000),
            current: NetworkCounters(received: 10, sent: 20)
        )
        expect(!counterResetFallback.sampleProcesses && !counterResetFallback.useProcessDownload,
               "interface counter resets clear fallback suspicion")

        let fallbackCounters = [
            NetworkCounters(received: 1_000, sent: 500),
            NetworkCounters(received: 1_000, sent: 700),
            NetworkCounters(received: 1_000, sent: 900),
            NetworkCounters(received: 1_200, sent: 1_000),
        ]
        let fallbackProcessSamples = [
            [NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 1_000, bytesOut: 500)],
            [NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 5_000, bytesOut: 700)],
        ]
        var fallbackCounterIndex = 0
        var fallbackProcessIndex = 0
        let fallbackSampler = NetworkSampler(counterReader: {
            defer { fallbackCounterIndex += 1 }
            return fallbackCounters[fallbackCounterIndex]
        }, processReader: {
            defer { fallbackProcessIndex += 1 }
            return fallbackProcessSamples[fallbackProcessIndex]
        })
        let fallbackBaseline = fallbackSampler.sample(now: 0)
        let fallbackProbe = fallbackSampler.sample(now: 2)
        let fallbackReading = fallbackSampler.sample(now: 4)
        let recoveredReading = fallbackSampler.sample(now: 6)
        expect(fallbackBaseline.downBytesPerSec == nil && fallbackBaseline.upBytesPerSec == nil,
               "network sampler first reading remains a baseline")
        expect(fallbackProbe.downBytesPerSec == 0 && fallbackProbe.upBytesPerSec == 100,
               "first frozen inbound sample keeps interface output while priming fallback")
        expectClose(fallbackReading.downBytesPerSec ?? -1, 2_000,
                    "network sampler replaces frozen interface download with process traffic")
        expectClose(fallbackReading.upBytesPerSec ?? -1, 100,
                    "network sampler keeps the lightweight interface upload counter")
        expect(fallbackReading.totalDown == 4_000 && fallbackReading.totalUp == 400,
               "network fallback accumulates process download and interface upload totals")
        expectClose(recoveredReading.downBytesPerSec ?? -1, 100,
                    "network sampler returns to interface download after counter recovery")
        expect(recoveredReading.totalDown == 4_200 && recoveredReading.totalUp == 500,
               "network totals continue across fallback recovery")
        expect(fallbackProcessIndex == 2,
               "network sampler invokes the process reader only for suspect interface samples")

        let nettopCSV = """
        time,,bytes_in,bytes_out,
        08:31:45.865507,Codex (Service).78844,78288,477660,
        08:31:45.865507,codex.78880,3154372,13193590,
        time,,bytes_in,bytes_out,
        08:31:46.871245,Codex (Service).78844,416,98,
        08:31:46.871246,codex.78880,16245,20641,
        08:31:46.871247,launchd.1,0,0,
        """
        let nettopRows = NetworkProcessSupport.parseNettopCSV(nettopCSV)
        expect(nettopRows.count == 2,
               "nettop parser keeps only active rows from the final delta section")
        expect(nettopRows.first?.name == "Codex (Service)" && nettopRows.first?.pid == 78844,
               "nettop parser extracts process names containing spaces")
        expectClose(nettopRows.last?.bytesIn ?? -1, 16_245, "nettop parser reads numeric bytes in")
        expectClose(nettopRows.last?.bytesOut ?? -1, 20_641, "nettop parser reads numeric bytes out")

        var nettopStream = NetworkProcessDeltaStreamParser()
        let streamLines = [
            "time,,bytes_in,bytes_out,",
            "08:31:45.865507,Codex.78844,78288,477660,",
            "time,,bytes_in,bytes_out,",
            "08:31:46.871245,Codex.78844,416,98,",
            "08:31:46.871247,launchd.1,0,0,",
            "time,,bytes_in,bytes_out,",
        ]
        let streamedSections = streamLines.compactMap { nettopStream.consumeCSVLine($0) }
        expect(streamedSections.count == 1,
               "nettop stream parser skips the initial cumulative section")
        expect(streamedSections.first?.count == 1,
               "nettop stream parser emits only active rows from the first delta section")
        expectClose(streamedSections.first?.first?.bytesIn ?? -1, 416,
                    "nettop stream parser does not publish cumulative bytes")
        expect(NetworkProcessSupport.nettopArguments == ["-P", "-d", "-x", "-J", "bytes_in,bytes_out", "-L", "1", "-s", "1"],
               "nettop per-app sampling asks for one cumulative section and computes deltas in app")
        expect(NetworkProcessSupport.externalNettopArguments == ["-P", "-d", "-x", "-t", "external", "-J", "bytes_in,bytes_out", "-L", "1", "-s", "1"],
               "network fallback samples only external process traffic")
        let cappedProcess = BoundedProcessRunner.run(
            "/bin/sh", ["-c", "/usr/bin/yes x | /usr/bin/head -c 200000"],
            timeout: 2, maxOutputBytes: 1_024)
        expect(cappedProcess.status == 0 && cappedProcess.output.count == 1_024,
               "subprocess output is drained while retained memory stays bounded")
        let orphanStarted = Date()
        let orphanedPipe = BoundedProcessRunner.run(
            "/bin/sh", ["-c", "/bin/sleep 3 & /usr/bin/printf done"],
            timeout: 1, maxOutputBytes: 1_024)
        expect(orphanedPipe.status == 0
                && String(decoding: orphanedPipe.output, as: UTF8.self) == "done"
                && Date().timeIntervalSince(orphanStarted) < 1.5,
               "a child inheriting stdout cannot leave the subprocess reader blocked")
        let timeoutStarted = Date()
        let timedOutProcess = BoundedProcessRunner.run(
            "/bin/sleep", ["3"], timeout: 0.05, maxOutputBytes: 1_024)
        expect(timedOutProcess.timedOut && timedOutProcess.status == -1
                && Date().timeIntervalSince(timeoutStarted) < 1.5,
               "a stalled subprocess is terminated inside its deadline")

        // Reproduces the freeze in issue #971 from the other side: the app's
        // own abandoned waits had filled the shared dispatch pool, so nothing
        // submitted to it ran any more. A runner that waits on a pool thread
        // reports a timeout here for a command that exits instantly, and parks
        // one more worker doing it. Waiting on the child itself is immune, so
        // the pool the runner starved can no longer starve the runner.
        let poolGate = DispatchSemaphore(value: 0)
        let poolOccupied = DispatchSemaphore(value: 0)
        // The dispatch pool's soft limit is 64 threads blocked in synchronous
        // work; one block per thread takes every one of them.
        for _ in 0..<64 {
            DispatchQueue.global(qos: .utility).async {
                poolOccupied.signal()
                poolGate.wait()
            }
        }
        var occupiedWorkers = 0
        for _ in 0..<64 where poolOccupied.wait(timeout: .now() + 5) == .success { occupiedWorkers += 1 }
        let starvedProbe = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async { starvedProbe.signal() }
        let poolIsStarved = starvedProbe.wait(timeout: .now() + 0.5) == .timedOut
        let starvedStarted = Date()
        let starvedPoolProcess = BoundedProcessRunner.run(
            "/bin/echo", ["ready"], timeout: 1, maxOutputBytes: 1_024)
        let starvedPoolElapsed = Date().timeIntervalSince(starvedStarted)
        for _ in 0..<64 { poolGate.signal() }
        _ = starvedProbe.wait(timeout: .now() + 5)
        expect(occupiedWorkers == 64 && poolIsStarved,
               "the dispatch pool starvation this check needs was actually reached")
        expect(!starvedPoolProcess.timedOut && starvedPoolProcess.status == 0
                && String(decoding: starvedPoolProcess.output, as: UTF8.self) == "ready\n"
                && starvedPoolElapsed < 0.5,
               "a subprocess is watched off the dispatch pool, so a starved pool cannot strand it")

        var networkDelta = NetworkProcessDeltaTracker(maxGap: 10)
        let baselineNetwork = [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 1_000, bytesOut: 500),
            NetworkProcessSample(pid: 20, name: "Editor", bytesIn: 200, bytesOut: 300),
        ]
        expect(networkDelta.rates(from: baselineNetwork, now: 100).isEmpty,
               "network process delta primes the first cumulative sample")
        let rateNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 3_048, bytesOut: 1_524),
            NetworkProcessSample(pid: 20, name: "Editor", bytesIn: 200, bytesOut: 300),
        ], now: 102)
        expect(rateNetwork.count == 1 && rateNetwork.first?.pid == 10,
               "network process delta keeps only processes with traffic")
        expectClose(rateNetwork.first?.bytesIn ?? -1, 1_024,
                    "network process delta computes download bytes per second")
        expectClose(rateNetwork.first?.bytesOut ?? -1, 512,
                    "network process delta computes upload bytes per second")
        let resetNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 100, bytesOut: 50),
        ], now: 104)
        expect(resetNetwork.isEmpty,
               "network process delta treats counter resets as a fresh baseline")
        let staleNetwork = networkDelta.rates(from: [
            NetworkProcessSample(pid: 10, name: "Browser", bytesIn: 10_000, bytesOut: 10_000),
        ], now: 120)
        expect(staleNetwork.isEmpty,
               "network process delta treats long gaps as a fresh baseline")
        let renewedLease = NetworkProcessSamplingPolicy.renewedLease(now: 50)
        expect(NetworkProcessSamplingPolicy.leaseIsActive(expiresAt: renewedLease, now: 61.9),
               "network monitoring lease remains active before expiry")
        expect(!NetworkProcessSamplingPolicy.leaseIsActive(expiresAt: renewedLease, now: 62.0),
               "network monitoring lease expires exactly at the boundary")
        expectClose(NetworkProcessSamplingPolicy.shortenedLease(currentExpiresAt: 90, now: 50),
                    54,
                    "network monitoring stop shortens the lease instead of depending on balanced disappear events")

        expect(MonitorSamplingPolicy.sampleStride(for: .cpu, intervalSeconds: 2, foreground: false) == 1,
               "monitor CPU stays responsive in menu-bar-only mode")
        expect(MonitorSamplingPolicy.sampleStride(for: .disk, intervalSeconds: 2, foreground: false) == 5,
               "monitor disk sampling slows down in menu-bar-only mode without exceeding DiskSampler.maxGap")
        expect(MonitorSamplingPolicy.sampleStride(for: .peripheralBattery, intervalSeconds: 2, foreground: false) == 30,
               "monitor peripheral battery sampling is heavily throttled in menu-bar-only mode")
        expect(MonitorSamplingPolicy.sampleStride(for: .fanSpeed, intervalSeconds: 2, foreground: false) == 3,
               "fan speed refreshes without waking the monitor every base tick")
        expect(MonitorSamplingPolicy.sampleStride(for: .disk, intervalSeconds: 2, foreground: true) == 1,
               "monitor disk sampling stays live while the panel is open")
        expect(MonitorSamplingPolicy.shouldSample(.disk, tick: 4, intervalSeconds: 2, foreground: false) == false,
               "monitor skips heavy menu-bar-only ticks before the stride")
        expect(MonitorSamplingPolicy.shouldSample(.disk, tick: 5, intervalSeconds: 2, foreground: false),
               "monitor samples heavy menu-bar-only ticks at the stride")

        expect(MonitorSamplingPolicy.wakeTicks(for: [.cpu, .disk], intervalSeconds: 2, foreground: false) == 1,
               "monitor wakes every tick while an every-tick metric is on")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.temperature], intervalSeconds: 2, foreground: false) == 8,
               "monitor with only temperature wakes once per temperature stride")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.fanSpeed], intervalSeconds: 2, foreground: false) == 3,
               "monitor with only fan speed wakes once per fan stride")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.peripheralBattery], intervalSeconds: 2, foreground: false) == 30,
               "monitor with only peripheral battery wakes once per minute")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.disk, .peripheralBattery], intervalSeconds: 2, foreground: false) == 5,
               "monitor wake cadence is the GCD of the needed strides")
        expect(MonitorSamplingPolicy.wakeTicks(for: [.temperature], intervalSeconds: 2, foreground: true) == 1,
               "monitor wakes every tick in the foreground")
        expect(MonitorSamplingPolicy.wakeTicks(for: [], intervalSeconds: 2, foreground: false) == 1,
               "monitor wake cadence defaults to every tick with no needs")
        // Exactness invariant: the cadence always divides every needed stride,
        // so grid-aligned ticks keep hitting each stride exactly on schedule.
        let wakeKinds: [MonitorSamplingKind] = [.disk, .power, .gpuUsage, .temperature,
                                                .fanSpeed, .peripheralBattery]
        let cadence = MonitorSamplingPolicy.wakeTicks(for: wakeKinds, intervalSeconds: 2, foreground: false)
        expect(wakeKinds.allSatisfy {
            MonitorSamplingPolicy.sampleStride(for: $0, intervalSeconds: 2, foreground: false) % cadence == 0
        }, "monitor wake cadence divides every needed stride")
        expect(MonitorSamplingPolicy.alignedTick(16, wakeTicks: 8) == 16,
               "monitor tick already on the wake grid stays put")
        expect(MonitorSamplingPolicy.alignedTick(7, wakeTicks: 8) == 8,
               "monitor tick off the wake grid realigns to the next slot")
        expect(MonitorSamplingPolicy.alignedTick(9, wakeTicks: 1) == 9,
               "monitor tick needs no alignment at every-tick cadence")

        // MARK: Interface filtering

        expect(MetricFormat.includeNetworkInterface("en0"), "en0 included")
        expect(MetricFormat.includeNetworkInterface("en12"), "en12 included")
        expect(!MetricFormat.includeNetworkInterface("lo0"), "lo0 excluded")
        expect(!MetricFormat.includeNetworkInterface("awdl0"), "awdl0 excluded")
        expect(!MetricFormat.includeNetworkInterface("nan0"), "nan0 excluded")
        expect(!MetricFormat.includeNetworkInterface("utun3"), "utun3 (VPN) excluded")
        expect(!MetricFormat.includeNetworkInterface("bridge0"), "bridge0 excluded")
        expect(!MetricFormat.includeNetworkInterface(""), "empty excluded")

        // MARK: History ring buffer

        var history = MetricHistory(capacity: 3)
        history.push(1)
        history.push(2)
        expect(history.values == [1, 2], "history keeps order under capacity")
        history.push(3)
        history.push(4)
        expect(history.values == [2, 3, 4], "history drops oldest at capacity")
        expect(history.values.count == 3, "history never exceeds capacity")
        expect(history.publishedValues(whileVisible: false).isEmpty
                && history.values == [2, 3, 4]
                && history.publishedValues(whileVisible: true) == [2, 3, 4],
               "hidden graphs publish no arrays without discarding their ring")

        var single = MetricHistory(capacity: 1)
        single.push(5)
        single.push(6)
        expect(single.values == [6], "capacity 1 keeps only newest")

        // MARK: Music launch blocker

        func musicKeyData(keyCode: Int, state: Int = 10, repeatFlag: Bool = false) -> Int {
            Int((UInt32(keyCode) << 16) | (UInt32(state) << 8) | (repeatFlag ? 1 : 0))
        }
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode))),
               "play/pause arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.nextTrackKeyCode))),
               "next track arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.previousTrackKeyCode))),
               "previous track arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.fastForwardKeyCode))),
               "fast-forward arms the music-app blocker")
        expect(MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.rewindKeyCode))),
               "rewind arms the music-app blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode), state: 11)),
               "a media-key release does not arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: Int(MusicLaunchSupport.playPauseKeyCode), repeatFlag: true)),
               "auto-repeat does not re-arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: 0)),
               "volume keys do not arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(
            subtype: MusicLaunchSupport.auxiliaryControlButtonsSubtype,
            data1: musicKeyData(keyCode: 2)),
               "brightness keys do not arm the blocker")
        expect(!MusicLaunchSupport.isMusicLaunchTrigger(subtype: 1, data1: musicKeyData(keyCode: 16)),
               "other system-defined subtypes do not arm the blocker")
        expect(!MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: nil),
               "without a recent media key the music app may open")
        expect(MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: 9.5),
               "a launch in the arm window after a media key is blocked")
        expect(MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: 8.0),
               "a launch on the arm-window edge is still blocked")
        expect(!MusicLaunchSupport.shouldBlockLaunch(now: 10, lastTriggerAt: 7.9),
               "a launch after the arm window is left alone")

        // MARK: Features hub catalog

        expect(AppFeature.allCases.count == 18, "feature catalog has 18 features")
        expect(Set(AppFeature.allCases.map(\.rawValue)).count == AppFeature.allCases.count,
               "feature ids are unique")
        expect(AppFeature.allCases.map(\.rawValue) == [
            "windowLayout", "autoQuit",
            "clipboardHistory", "finderRename",
            "mixer", "soundOutputSwitcher",
            "cleaner", "uninstaller", "screenRecorder", "notchMediaControls", "fileConverter",
            "monitorCPU", "monitorGPU", "monitorMemory", "monitorNetwork", "monitorDisk", "monitorPower",
            "fanControl",
        ], "feature ids are stable (they persist inside availability keys)")
        expect(FeatureGroup.allCases.map { AppFeature.features(in: $0).count }.reduce(0, +)
                == AppFeature.allCases.count,
               "every feature belongs to exactly one group")
        expect(!FeatureGroup.allCases.contains { AppFeature.features(in: $0).isEmpty },
               "no hub group is empty")
        expect(AppPermission.allCases.map(\.rawValue) == [
            "accessibility", "screenRecording", "fullDiskAccess", "filesAndFolders", "notifications",
            "automationFinder", "audioCapture", "microphone",
        ], "permission portal contains every supported permission")
        let onboardingViewSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift",
            encoding: .utf8)) ?? ""
        let additionalPermissionsAlignment =
            #"DisclosureGroup\(isExpanded: \$showingOtherPermissions\) \{\s+"#
            + #"VStack\(alignment: \.leading, spacing: 14\)"#
        expect(onboardingViewSource.range(
            of: additionalPermissionsAlignment,
            options: .regularExpression) != nil,
               "the additional onboarding permission rows share one leading edge")
        expect(Set(FeaturePreset.essential.features.flatMap(\.onboardingPermissions))
                == [.accessibility, .screenRecording],
               "the essential first-run choice explains accessibility and screen "
               + "recording, needed by window layout, auto quit, Finder rename "
               + "and the screen recorder")
        expect(AppFeature.screenRecorder.onboardingPermissions
                == [.screenRecording, .accessibility],
               "the recorder choice explains both permissions it needs")
        expect(AppFeature.fanControl.group == .monitor
                && AppFeature.fanControl.enabledKeys.isEmpty
                && AppFeature.fanControl.permissions.isEmpty
                && AppFeature.fanControl.energyProfile == .idle
                && AppFeature.fanControl.isBeta
                && !AppFeature.monitorPower.isBeta,
               "fan control is an on-demand beta with no broad permission")

        // MARK: Hardware-gated installs

        // Availability is only ever written by the runtime that gates it, so
        // a new install surface cannot walk around the hardware check the way
        // the hub's install-all button and the first-run picker once did.
        // Two files are allowed to write the key directly, and both run where
        // the gate cannot matter: the first-run seed writes a preset holding
        // no hardware-dependent feature (pinned below), and the fan control
        // migration restores an install that already existed, which the gate
        // never revokes. A third entry here is a bug, not a new allowance.
        var availabilityWriters: Set<String> = []
        if let sources = FileManager.default.enumerator(atPath: "Sources") {
            for case let path as String in sources where path.hasSuffix(".swift") {
                let text = (try? String(contentsOfFile: "Sources/" + path, encoding: .utf8)) ?? ""
                let writes = text.split(separator: "\n").contains {
                    $0.contains(".set(") && $0.contains("availabilityKey")
                }
                if writes { availabilityWriters.insert((path as NSString).lastPathComponent) }
            }
        }
        expect(availabilityWriters == ["FeatureRuntime.swift",
                                       "FeaturePresets.swift",
                                       "Defaults.swift"],
               "feature availability is written only where the hardware gate runs, "
               + "found \(availabilityWriters.sorted())")
        expect(FeaturePreset.allCases.allSatisfy { !$0.features.contains(.fanControl) },
               "no first-run preset installs a feature whose hardware the Mac may lack")

        let featureHubSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/FeatureHubSettings.swift",
            encoding: .utf8)) ?? ""
        let onboardingFeatureSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Onboarding/OnboardingView.swift",
            encoding: .utf8)) ?? ""
        expect(featureHubSource.contains("installBlockedReason")
                && onboardingFeatureSource.contains("installBlockedReason"),
               "both feature pickers refuse an unsupported install from the same rule")
        expect(featureHubSource.contains("installableCount"),
               "the hub counts against what this Mac can install, so install-all can finish")
        expect((Defaults.registeredDefaults[DefaultsKey.panelShowFanControl] as? Bool) == true,
               "installing fan control reveals its panel section by default")

        let installerInfo: [String: Any] = [
            "images": [[
                "image-path": "/Users/test/Downloads/App.dmg",
                "system-entities": [[
                    "dev-entry": "/dev/disk9s1",
                    "mount-point": "/private/tmp/Installer Mount",
                ]],
            ]],
        ]
        // MARK: Fan Control safety policy

        expect(FanControlPolicy.coolingDuration == 15 * 60
                && FanControlPolicy.heartbeatLimit < 10,
               "the legacy session stays bounded while current control loses ownership quickly")
        expect(FanControlPolicy.isAutomaticMode(0)
                && FanControlPolicy.isAutomaticMode(3)
                && !FanControlPolicy.isAutomaticMode(1)
                && !FanControlPolicy.isAutomaticMode(2)
                && !FanControlPolicy.isAutomaticMode(.max),
               "fan ownership accepts firmware automatic modes and rejects manual or unknown modes")
        expect(FanControlPolicy.fanCount(from: 1) == 1
                && FanControlPolicy.fanCount(from: 8) == 8
                && FanControlPolicy.fanCount(from: 0) == nil
                && FanControlPolicy.fanCount(from: 9) == nil
                && FanControlPolicy.fanCount(from: 1.5) == nil
                && FanControlPolicy.fanCount(from: .nan) == nil,
               "fan discovery accepts only a small integral hardware count")
        expect(FanControlPolicy.validBounds(minimum: 1_200, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: -1, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: 5_800, maximum: 5_800)
                && !FanControlPolicy.validBounds(minimum: 1_200, maximum: 25_000),
               "fan bounds must be finite, ordered and physically sane")
        expect(FanControlPolicy.validReading(0)
                && FanControlPolicy.validReading(8_000)
                && !FanControlPolicy.validReading(-1)
                && !FanControlPolicy.validReading(.infinity),
               "fan readings stay within a safe display and verification range")
        expect(FanControlPolicy.minimumCoolingLevel == 0
                && FanControlPolicy.maximumCoolingLevel == 100
                && FanControlPolicy.defaultCoolingLevel == 100
                && FanControlPolicy.validCoolingLevel(0)
                && FanControlPolicy.validCoolingLevel(55)
                && FanControlPolicy.validCoolingLevel(100)
                && !FanControlPolicy.validCoolingLevel(-5)
                && !FanControlPolicy.validCoolingLevel(26),
               "manual cooling accepts the full bounded five-percent scale")
        expect(FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                 level: 0) == 1_200
                && FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                     level: 25) == 2_350
                && FanControlPolicy.coolingTargetRPM(minimum: 1_200, maximum: 5_800,
                                                     level: 100) == 5_800
                && FanControlPolicy.coolingTargetRPM(minimum: 5_800, maximum: 5_800,
                                                     level: 100) == nil,
               "manual targets map the full percentage scale into reported hardware bounds")
        expect(FanControlPolicy.targetRPMMatches(target: 3_121, expected: 3_121)
                && FanControlPolicy.targetRPMMatches(target: 3_122, expected: 3_121)
                && FanControlPolicy.targetRPMMatches(target: 1_201.5, expected: 1_200)
                && !FanControlPolicy.targetRPMMatches(target: 3_500, expected: 3_121)
                && !FanControlPolicy.targetRPMMatches(target: 1_205, expected: 1_200)
                && !FanControlPolicy.targetRPMMatches(target: .nan, expected: 1_200),
               "fan target verification allows a narrow tolerance and rejects stale or malformed targets")

        let defaultCurve = FanControlConfiguration.defaultCurve
        expect(FanControlPolicy.validConfiguration(.manual(level: 0))
                && FanControlPolicy.validConfiguration(.manual(level: 100))
                && FanControlPolicy.validConfiguration(.curve([defaultCurve]))
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 40) == 0
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 60) == 50
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 61) == 55
                && FanControlPolicy.interpolatedCoolingLevel(points: defaultCurve.points,
                                                             temperature: 80) == 100,
               "the default curve starts at 50 degrees, reaches maximum at 70 and rounds safely up")
        let coolingTemperature = [
            FanControlTemperatureReading(source: .hottestSoC, celsius: 59),
        ]
        expect(FanControlPolicy.curveCoolingLevel(curves: [defaultCurve],
                                                  temperatures: coolingTemperature,
                                                  previousLevel: 50) == 50
                && FanControlPolicy.curveCoolingLevel(
                    curves: [defaultCurve],
                    temperatures: [.init(source: .hottestSoC, celsius: 57)],
                    previousLevel: 50
                ) == 45,
               "a cooling curve uses two-degree hysteresis before lowering fan speed")
        let cpuCurve = FanControlCurve(
            sensor: .averageCPU,
            points: [FanControlCurvePoint(temperature: 40, coolingLevel: 0),
                     FanControlCurvePoint(temperature: 80, coolingLevel: 80)]
        )
        let curveTemperatures = [
            FanControlTemperatureReading(source: .hottestSoC, celsius: 54),
            FanControlTemperatureReading(source: .averageCPU, celsius: 70),
        ]
        expect(FanControlPolicy.curveCoolingLevel(curves: [defaultCurve, cpuCurve],
                                                  temperatures: curveTemperatures) == 60
                && FanControlPolicy.curveCoolingLevel(curves: [defaultCurve, cpuCurve],
                                                      temperatures: [curveTemperatures[0]]) == nil,
               "several temperature rules use their highest demand and require every selected sensor")
        let duplicateCurves = [defaultCurve,
                               FanControlCurve(sensor: .hottestSoC, points: cpuCurve.points)]
        let descendingCurve = FanControlCurve(
            sensor: .averageCPU,
            points: [FanControlCurvePoint(temperature: 50, coolingLevel: 80),
                     FanControlCurvePoint(temperature: 70, coolingLevel: 40)]
        )
        expect(!FanControlPolicy.validCurves(duplicateCurves)
                && !FanControlPolicy.validCurves([descendingCurve])
                && FanControlConfiguration.decodeCurves(
                    FanControlConfiguration.encodeCurves([defaultCurve]) ?? "") == [defaultCurve]
                && FanControlConfiguration.decodeCurves("not json") == nil,
               "stored curves reject duplicate sensors, unsafe slopes and malformed data")
        let addedPoints = FanControlPolicy.addingCurvePoint(to: defaultCurve.points)
        expect(FanControlPolicy.nextCurvePoint(for: defaultCurve.points) == FanControlCurvePoint(temperature: 60, coolingLevel: 50)
                && addedPoints == [
                    FanControlCurvePoint(temperature: 50, coolingLevel: 0),
                    FanControlCurvePoint(temperature: 60, coolingLevel: 50),
                    FanControlCurvePoint(temperature: 70, coolingLevel: 100),
                ]
                && FanControlPolicy.validCurve(FanControlCurve(sensor: .hottestSoC, points: addedPoints ?? [])),
               "adding a fan curve point calculates the intermediate point and produces a valid sorted curve")
        var iterativePoints = defaultCurve.points
        while let next = FanControlPolicy.addingCurvePoint(to: iterativePoints) {
            iterativePoints = next
        }
        expect(iterativePoints.count == FanControlPolicy.maximumCurvePointCount
                && FanControlPolicy.validCurve(FanControlCurve(sensor: .hottestSoC, points: iterativePoints))
                && FanControlPolicy.nextCurvePoint(for: iterativePoints) == nil
                && FanControlPolicy.addingCurvePoint(to: iterativePoints) == nil,
               "adding fan curve points fills up to the maximum point limit with strictly valid curves")
        let secondCurve = FanControlCurve(sensor: .averageCPU,
                                          points: defaultCurve.points)
        var updatedCurves = [defaultCurve, secondCurve]
        if let secondPoints = FanControlPolicy.addingCurvePoint(to: updatedCurves[1].points) {
            updatedCurves[1].points = secondPoints
        }
        let storedUpdatedCurves = FanControlConfiguration.decodeCurves(
            FanControlConfiguration.encodeCurves(updatedCurves) ?? ""
        )
        expect(updatedCurves.count == 2
                && updatedCurves.first == defaultCurve
                && updatedCurves[1].points == addedPoints
                && storedUpdatedCurves == updatedCurves,
               "adding a point to the second fan curve preserves every valid stored curve")
        let m3FanTemperatures = FanControlPolicy.aggregatedTemperatures(
            cpuReadings: [("Te05", 44), ("Tf4E", 53), ("Tf4F", 76)],
            gpuReadings: [48],
            platform: .appleM3Family
        )
        expectClose(m3FanTemperatures.first { $0.source == .hottestCPU }?.celsius ?? -1,
                    53,
                    "M3 fan curves include the hottest mapped Tf CPU core")
        expectClose(m3FanTemperatures.first { $0.source == .averageCPU }?.celsius ?? -1,
                    48.5,
                    "M3 fan curves exclude auxiliary Tf readings from the CPU average")
        let unmappedFanTemperatures = FanControlPolicy.aggregatedTemperatures(
            cpuReadings: [("Tp00", 48), ("Tp0W", 113)],
            gpuReadings: [],
            platform: .unmappedAppleSilicon
        )
        expect(unmappedFanTemperatures.isEmpty,
               "fan curves reject unknown Apple Silicon sensors instead of treating them as CPU")
        expect(FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [1_200]) == [1_200]
                && FanControlPolicy.telemetryReadings(expectedCount: 2,
                                                      readings: [1_200, 1_350]) == [1_200, 1_350],
               "fan telemetry preserves one or several ordered readings")
        expect(FanControlPolicy.telemetryReadings(expectedCount: 0, readings: []) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 2, readings: [1_200]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 2, readings: [1_200, nil]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [.infinity]) == nil
                && FanControlPolicy.telemetryReadings(expectedCount: 1, readings: [-1]) == nil,
               "fan telemetry rejects no-fan, missing and malformed sensor sets")
        expect(FanControlPolicy.menuBarValue(for: [1_249.6]) == "1250"
                && FanControlPolicy.menuBarValue(for: [1_200, 1_350]) == "1200/1350"
                && FanControlPolicy.menuBarValue(for: []) == nil
                && FanControlPolicy.menuBarValue(for: [.infinity]) == nil,
               "fan RPM menu bar text supports one or several validated fans")
        expect(FanControlPolicy.menuBarWidthUnits(fanCount: 1) == 12
                && FanControlPolicy.menuBarWidthUnits(fanCount: 2) == 18
                && FanControlPolicy.menuBarWidthUnits(fanCount: 0) == 0,
               "fan RPM menu bar width reserves one or several five-digit readings")

        let floatRPM = SMCValueCodec.encode(4_850, type: "flt ", size: 4)
        expect(floatRPM.flatMap { SMCValueCodec.decode($0, type: "flt ") } == 4_850,
               "native fan RPM floats round-trip exactly")
        let fixedRPM = SMCValueCodec.encode(4_850.25, type: "fpe2", size: 2)
        expect(fixedRPM.flatMap { SMCValueCodec.decode($0, type: "fpe2") } == 4_850.25,
               "fixed-point fan RPM values round-trip at quarter-RPM precision")
        expect(SMCValueCodec.decode([0x12, 0x34], type: "ui16") == 0x1234
                && SMCValueCodec.decode([0, 0, 1, 2], type: "ui32") == 258
                && SMCValueCodec.encode(1, type: "ui8 ", size: 1) == [1],
               "SMC integer types preserve their documented byte order")
        expect(SMCValueCodec.encode(-1, type: "flt ", size: 4) == nil
                && SMCValueCodec.encode(30_000, type: "fpe2", size: 2) == nil
                && SMCValueCodec.encode(1, type: "myst", size: 1) == nil,
               "SMC writes reject negative, overflowing and unknown encodings")

        let watchdogEnd = Date(timeIntervalSince1970: 2_000)
        expect(FanControlPolicy.restoreReason(now: watchdogEnd,
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == .timeLimit,
               "the watchdog still honors a deadline from a legacy helper request")
        expect(FanControlPolicy.restoreReason(now: watchdogEnd,
                                              endsAt: nil,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == nil,
               "current manual and curve control have no arbitrary time limit")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: FanControlPolicy.heartbeatLimit + 0.1,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == .heartbeatLost,
               "the watchdog restores when the app heartbeat stops")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: FanControlPolicy.verificationFailureLimit,
                                              thermalState: .nominal) == .hardwareChanged,
               "the watchdog restores after repeated hardware verification failures")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              temperatureFailures: FanControlPolicy.temperatureFailureLimit,
                                              thermalState: .nominal) == .temperatureUnavailable,
               "a curve returns control after repeated missing temperature readings")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .serious) == .thermalPressure,
               "the watchdog returns control to the system under thermal pressure")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .fair) == nil,
               "a fair thermal state does not cancel the user's selected control")
        expect(FanControlPolicy.restoreReason(now: Date(timeIntervalSince1970: 1_900),
                                              endsAt: watchdogEnd,
                                              heartbeatAge: 0,
                                              verificationFailures: 0,
                                              thermalState: .nominal) == nil,
               "a healthy maximum-cooling session remains active")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.fanControl(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 42 && values.allSatisfy { !$0.isEmpty },
                   "fan control has every localized field for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "fan control text uses human punctuation for \(language.rawValue)")
            expectFormat(strings.fanNameFormat, ["d"],
                         "fan name format stays valid for \(language.rawValue)")
            expectFormat(strings.rpmFormat, ["d"],
                         "fan speed format stays valid for \(language.rawValue)")
            expectFormat(strings.currentRPMFormat, ["d"],
                         "current fan speed format stays valid for \(language.rawValue)")
            expectFormat(strings.targetRPMFormat, ["d"],
                         "target fan speed format stays valid for \(language.rawValue)")
        }
        expect(FanControlFeatureStrings.ru.rpmFormat == "%d об/мин"
                && FanControlFeatureStrings.de.rpmFormat == "%d U/min"
                && FanControlFeatureStrings.fr.rpmFormat == "%d tr/min",
               "existing localized RPM units stay intact")

        let legacyFanSnapshot = Data(#"{"fans":[],"isCooling":false}"#.utf8)
        let decodedLegacyFanSnapshot = try? JSONDecoder().decode(FanControlSnapshot.self,
                                                                  from: legacyFanSnapshot)
        expect(decodedLegacyFanSnapshot != nil
                && decodedLegacyFanSnapshot?.coolingLevel == nil
                && decodedLegacyFanSnapshot?.configuration == nil
                && decodedLegacyFanSnapshot?.temperatures == nil,
               "fan snapshots remain compatible with an older installed helper")

        let fanMigrationSuite = "com.chikit.tests.fan-migration.\(UUID().uuidString)"
        if let fanMigration = UserDefaults(suiteName: fanMigrationSuite) {
            fanMigration.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            expect(fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && fanMigration.bool(forKey: AppFeature.fanControl.availabilityKey)
                    && fanMigration.object(forKey: DefaultsKey.monitorShowFanControlBeta) == nil,
                   "an old fan opt-in keeps the feature installed and visible")

            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
            fanMigration.set(false, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            expect(!fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && fanMigration.object(forKey: AppFeature.fanControl.availabilityKey) == nil,
                   "an old fan opt-out does not install the feature")

            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
            fanMigration.set(false, forKey: DefaultsKey.panelShowFanControl)
            fanMigration.set(false, forKey: AppFeature.fanControl.availabilityKey)
            fanMigration.set(true, forKey: DefaultsKey.monitorShowFanControlBeta)
            Defaults.migrateFanControlVisibility(in: fanMigration)
            expect(!fanMigration.bool(forKey: DefaultsKey.panelShowFanControl)
                    && !fanMigration.bool(forKey: AppFeature.fanControl.availabilityKey),
                   "newer fan choices win over the legacy opt-in")
            fanMigration.removePersistentDomain(forName: fanMigrationSuite)
        } else {
            expect(false, "fan visibility migration suite can be created")
        }

        func activeSet(_ permission: AppPermission,
                       available: Set<AppFeature> = Set(AppFeature.allCases),
                       on: Set<String> = [],
                       strings: [String: String] = [:]) -> Set<AppFeature> {
            Set(AppFeature.activeFeatures(using: permission,
                                          isAvailable: { available.contains($0) },
                                          boolFor: { on.contains($0) },
                                          stringFor: { strings[$0] }))
        }

        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: false,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: false,
                                                 screenRecordingIsGranted: false) == nil,
               "permissions keep no background timer without a live feature or visible surface")
        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 1,
                                                 accessibilityIsNeeded: false,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: true,
                                                 screenRecordingIsGranted: true) == 2.5,
               "a visible permission surface refreshes grants promptly")
        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: true,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: false,
                                                 screenRecordingIsGranted: true) == 2.5,
               "a live feature waiting for its grant refreshes promptly")
        expect(PermissionPollingSupport.interval(visibleSurfaceCount: 0,
                                                 accessibilityIsNeeded: true,
                                                 screenRecordingIsNeeded: false,
                                                 accessibilityIsGranted: true,
                                                 screenRecordingIsGranted: true) == 60,
               "a granted live feature keeps only the slow revocation watch")
        let windowLayoutPollingKeys = [
            DefaultsKey.windowLayoutShortcutsEnabled,
            DefaultsKey.windowGestureEnabled,
            DefaultsKey.windowEdgeSnapEnabled,
        ]
        expect(activeSet(.accessibility, on: [DefaultsKey.finderRenameEnabled]).contains(.finderRename),
               "the enabled Finder rename shortcut uses accessibility")
        expect(activeSet(.accessibility).contains(.screenRecorder),
               "the recorder uses accessibility for anonymous typing timing while active")
        expect(activeSet(.accessibility, on: [DefaultsKey.preciseVolumeRollerEnabled]).contains(.mixer),
               "mixer uses accessibility only for precise volume roller")
        expect(!activeSet(.accessibility).contains(.mixer),
               "mixer without precise volume roller does not use accessibility")

        expect(activeSet(.notifications) == [],
               "no alerts and no schedule means notifications are unused")
        expect(activeSet(.notifications, on: [DefaultsKey.monitorAlertCPUTemperature]) == [.monitorCPU],
               "a CPU temperature alert marks the CPU monitor as notifying")
        expect(activeSet(.notifications, on: [DefaultsKey.monitorAlertBatteryTemperature]) == [.monitorPower],
               "a battery temperature alert marks the power monitor as notifying")
        expect(activeSet(.notifications,
                         available: Set(AppFeature.allCases).subtracting([.monitorCPU]),
                         on: [DefaultsKey.monitorAlertCPU]) == [],
               "an alert whose metric is unavailable does not notify")
        expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "weekly"]) == [.cleaner],
               "a scheduled cleaner with notice enabled uses notifications")
        expect(activeSet(.notifications, on: [DefaultsKey.cleanerScheduleNotify],
                         strings: [DefaultsKey.cleanerScheduleFrequency: "off"]) == [],
               "an unscheduled cleaner does not use notifications")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsAutomaticEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [],
               "WhatsApp cleanup notifications stay unused until that cleaner is turned on")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsEnabled,
                              DefaultsKey.whatsAppDownloadsAutomaticEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [.cleaner],
               "WhatsApp cleanup only uses notifications for an opted-in automatic summary")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppOrganizerEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [],
               "the experimental WhatsApp organizer stays silent until that cleaner is turned on")
        expect(activeSet(.notifications,
                         on: [DefaultsKey.whatsAppDownloadsEnabled,
                              DefaultsKey.whatsAppOrganizerEnabled,
                              DefaultsKey.whatsAppDownloadsNotify]) == [.cleaner],
               "the experimental WhatsApp organizer can offer an undo notification")
        expect(activeSet(.filesAndFolders) == [],
               "WhatsApp Downloads folder access stays unused until that cleaner is turned on")
        expect(activeSet(.filesAndFolders, on: [DefaultsKey.whatsAppDownloadsEnabled]) == [.cleaner],
               "the cleaner owns WhatsApp Downloads folder access")

        expect(activeSet(.fullDiskAccess) == [.cleaner, .uninstaller],
               "cleaner and uninstaller are on-demand full disk users")
        expect(activeSet(.audioCapture) == [.mixer], "the mixer is the only audio capture user")
        expect(activeSet(.audioCapture, available: Set(AppFeature.allCases).subtracting([.mixer])) == [],
               "audio capture reads as unused once the mixer is off in the hub")
        expect(activeSet(.microphone).isEmpty
                && activeSet(.microphone, on: [DefaultsKey.recorderMicrophone]) == [.screenRecorder],
               "the recorder uses microphone access only when that optional source is on")
        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true }, boolFor: { _ in false }),
               "no alert keys means no monitor alerts")
        expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                 boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "one alert on an available metric arms the alert service")
        expect(AppFeature.anyMonitorAlertEnabled(isAvailable: { _ in true },
                                                 boolFor: {
                                                     $0 == DefaultsKey.monitorAlertBatteryTemperature
                                                 }),
               "a battery temperature alert arms the alert service")
        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .monitorPower },
                                                  boolFor: {
                                                      $0 == DefaultsKey.monitorAlertBatteryTemperature
                                                  }),
               "a battery temperature alert stays disarmed without the power metric")
        expect(!AppFeature.anyMonitorAlertEnabled(isAvailable: { $0 != .monitorDisk },
                                                  boolFor: { $0 == DefaultsKey.monitorAlertDisk }),
               "an alert with its metric off in the hub stays disarmed")

        expect(GlobalShortcutRole.activeRoles(isOn: { _ in true }).count
                == GlobalShortcutRole.allCases.count,
               "the availability-free overload keeps every enabled current role")
        let superSpace = GlobalShortcut(keyCode: Int64(kVK_Space), modifiers: .validMask)
        let customSuperSpace = GlobalShortcut(keyCode: Int64(kVK_Space),
                                              modifiers: [.control, .option, .command])
        // MARK: Super key held-key watchdog
        // The source key (F18) does not autorepeat, so a steadily-held key
        // reaches the watchdog just like a lost release. The physical key state
        // is what tells them apart.
        // MARK: Features hub strings

        for language in AppLanguage.allCases {
            let hub = FeatureStrings.hub(language)
            let values = Mirror(reflecting: hub).children.compactMap { $0.value as? String }
            expect(!values.isEmpty && values.allSatisfy { !$0.isEmpty },
                   "every hub string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible hub strings (\(language.rawValue))")
            expect(hub.activeCountFormat.contains("%1$d") && hub.activeCountFormat.contains("%2$d"),
                   "count format keeps positional specifiers (\(language.rawValue))")
        }
        for language in AppLanguage.allCases {
            let clipboard = FeatureStrings.clipboard(language)
            let values = Mirror(reflecting: clipboard).children
                .compactMap { $0.value as? String }
            expect(values.count == 54 && values.allSatisfy { !$0.isEmpty },
                   "every clipboard string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible clipboard strings (\(language.rawValue))")
            expectFormat(clipboard.deleteSelectedFormat, ["d"],
                         "\(language.rawValue) clipboard bulk-delete format")
        }
        expect(FeatureStrings.hub(.ptBR).pageTitle == "Recursos"
                && FeatureStrings.hub(.enUS).pageTitle == "Features",
               "hub page title reads naturally in the owner languages")
        // MARK: Kill Process safety
        // pid 1 -> 10 -> {20, 21} -> 30, with 40 on an unrelated branch, 50
        // its own parent and 21 <-> 22 pointing at each other.
        let processTable: [(pid: pid_t, ppid: pid_t)] = [
            (10, 1), (20, 10), (21, 10), (30, 20), (40, 1), (50, 50), (22, 21), (21, 22),
        ]
        // MARK: Hub presets and energy badges

        expect(FeaturePreset.allCases.count == 2,
               "two starting points, not another wall of decisions")
        expect(FeaturePreset.allCases.allSatisfy { !$0.features.isEmpty },
               "every preset installs something")
        expect(FeaturePreset.essential.features.contains(.mixer)
                && FeaturePreset.essential.features.contains(.windowLayout)
                && FeaturePreset.essential.features.contains(.monitorPower),
               "the essential preset covers mixer, monitor and window layout")
        expect(FeaturePreset.battery.features.allSatisfy {
                   !$0.permissions.contains(.accessibility)
               },
               "battery and quiet needs no accessibility permission at all")
        let firstRunSuiteName = "com.chikit.tests.first-run.\(UUID().uuidString)"
        if let firstRunDefaults = UserDefaults(suiteName: firstRunSuiteName) {
            firstRunDefaults.register(defaults: AppFeature.availabilityDefaults)
            FeaturePreset.prepareFirstRunAvailability(in: firstRunDefaults)
            expect(Set(AppFeature.allCases.filter {
                firstRunDefaults.bool(forKey: $0.availabilityKey)
            }) == FeaturePreset.essential.features,
            "a clean install loads only the essential feature set before onboarding")

            for feature in AppFeature.allCases {
                firstRunDefaults.set(true, forKey: feature.availabilityKey)
            }
            firstRunDefaults.set(2, forKey: DefaultsKey.onboardingStep)
            FeaturePreset.prepareFirstRunAvailability(in: firstRunDefaults)
            expect(AppFeature.allCases.allSatisfy {
                firstRunDefaults.bool(forKey: $0.availabilityKey)
            }, "an interrupted onboarding keeps the feature selection already applied")
            firstRunDefaults.removePersistentDomain(forName: firstRunSuiteName)
        } else {
            expect(false, "first-run defaults suite can be created")
        }
        for preset in FeaturePreset.allCases {
            expect(preset.enableKeys.allSatisfy { key in
                       preset.features.contains { $0.enabledKeys.contains(key) }
                   },
                   "preset enable keys belong to its own features (\(preset.rawValue))")
        }
        let previousWindowGestureEnergy = UserDefaults.standard.object(
            forKey: DefaultsKey.windowGestureEnabled
        )
        UserDefaults.standard.set(true, forKey: DefaultsKey.windowGestureEnabled)
        expect(AppFeature.windowLayout.energyProfile == .pointer,
               "window dragging reports trackpad and mouse pointer input")
        if let previousWindowGestureEnergy {
            UserDefaults.standard.set(previousWindowGestureEnergy,
                                      forKey: DefaultsKey.windowGestureEnabled)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowGestureEnabled)
        }
        let previousWindowEdgeSnapEnergy = UserDefaults.standard.object(
            forKey: DefaultsKey.windowEdgeSnapEnabled
        )
        UserDefaults.standard.set(false, forKey: DefaultsKey.windowGestureEnabled)
        UserDefaults.standard.set(true, forKey: DefaultsKey.windowEdgeSnapEnabled)
        expect(AppFeature.windowLayout.energyProfile == .pointer,
               "edge snapping reports its trackpad and mouse listener")
        if let previousWindowEdgeSnapEnergy {
            UserDefaults.standard.set(previousWindowEdgeSnapEnergy,
                                      forKey: DefaultsKey.windowEdgeSnapEnabled)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowEdgeSnapEnabled)
        }
        if let previousWindowGestureEnergy {
            UserDefaults.standard.set(previousWindowGestureEnergy,
                                      forKey: DefaultsKey.windowGestureEnabled)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.windowGestureEnabled)
        }

        // MARK: Settings page visibility

        func pageVisible(_ page: SettingsPage, available: Set<AppFeature>) -> Bool {
            FeatureVisibilitySupport.isPageVisible(page) { available.contains($0) }
        }
        let allFeatures = Set(AppFeature.allCases)
        expect(!pageVisible(.monitor, available: allFeatures.subtracting(Set(FeatureVisibilitySupport.monitorFeatures))),
               "monitor page hides with every metric off")
        expect(pageVisible(.monitor, available: [.monitorNetwork]), "one metric keeps the monitor page")
        expect(pageVisible(.general, available: []) && pageVisible(.about, available: [])
                && pageVisible(.shortcuts, available: []),
               "app pages never hide")
        expect(!pageVisible(.cleaner,
                            available: allFeatures.subtracting([.cleaner])),
               "cleaner settings, including WhatsApp downloads, follow the cleaner module")
        expect(AppFeature.allCases.allSatisfy { feature in
            let destination = feature.settingsDestination
            let gate = FeatureVisibilitySupport.features(for: destination.page)
            return gate.isEmpty || gate.contains(feature)
        }, "every feature destination is either always visible or gated by that feature")
        expect(AppFeature.allCases.allSatisfy { $0.settingsDestination.hasValidSectionAnchor },
               "every feature anchor belongs to its destination page")
        expect(Set(AppFeature.allCases.compactMap(\.settingsDestination.sectionAnchor))
                == Set(SettingsSectionAnchor.allCases),
               "every declared Settings section anchor is used by a feature destination")
        expect(AppFeature.monitorCPU.settingsDestination == FeatureSettingsDestination(.monitor)
                && AppFeature.fanControl.settingsDestination
                == FeatureSettingsDestination(.monitor, sectionAnchor: .fanControl),
               "shared monitor destinations distinguish the dedicated fan controls")
        let settingsRouter = SettingsRouter.shared
        var settingsRequestCount = 0
        var settingsRequestsPublishedReady = true
        let settingsRequestObservation = settingsRouter.$requestID
            .dropFirst()
            .sink { requestID in
                settingsRequestCount += 1
                settingsRequestsPublishedReady =
                    settingsRequestsPublishedReady
                    && settingsRouter.pendingDestinationRequest?.id == requestID
            }
        let repeatedDestination = FeatureSettingsDestination(.monitor)
        settingsRouter.request(repeatedDestination)
        let firstSettingsRequestID = settingsRouter.requestID
        settingsRouter.request(repeatedDestination)
        expect(settingsRequestCount == 2 && settingsRouter.requestID != firstSettingsRequestID,
               "repeated requests for the same Settings destination remain observable")
        expect(settingsRequestsPublishedReady,
               "a Settings request is ready to consume when its request identity is published")
        let repeatedSettingsRequestID = settingsRouter.requestID
        settingsRouter.consumeDestinationRequest(id: firstSettingsRequestID)
        expect(settingsRouter.pendingDestinationRequest?.id == repeatedSettingsRequestID,
               "consuming an older Settings request cannot clear a newer request")
        settingsRouter.consumeDestinationRequest(id: repeatedSettingsRequestID)
        expect(settingsRouter.pendingDestinationRequest == nil,
               "a handled Settings destination request is cleared")

        let featuresDestination = FeatureSettingsDestination(.features)
        settingsRouter.request(featuresDestination, targetFeature: .cleaner)
        let firstFeatureTargetRequestID = settingsRouter.requestID
        settingsRouter.request(featuresDestination, targetFeature: .cleaner)
        let secondFeatureTargetRequestID = settingsRouter.requestID
        expect(secondFeatureTargetRequestID != firstFeatureTargetRequestID
                && settingsRouter.pendingFeatureTarget?.id == secondFeatureTargetRequestID,
               "repeated requests for the same target feature remain observable")
        settingsRouter.consumeFeatureTarget(id: firstFeatureTargetRequestID)
        expect(settingsRouter.pendingFeatureTarget?.id == secondFeatureTargetRequestID,
               "consuming an older feature-target request cannot clear a newer target")
        settingsRouter.consumeFeatureTarget(id: secondFeatureTargetRequestID)
        expect(settingsRouter.pendingFeatureTarget == nil,
               "a handled feature-target request is cleared")
        settingsRouter.request(featuresDestination, targetFeature: .autoQuit)
        settingsRouter.request(repeatedDestination)
        expect(settingsRouter.pendingFeatureTarget == nil,
               "a later generic request clears any unconsumed feature target so it cannot leak into unrelated navigation")

        settingsRouter.cleanerTool = "tool-id"
        settingsRouter.request(FeatureSettingsDestination(.cleaner))
        expect(settingsRouter.page == .cleaner && settingsRouter.cleanerTool == "tool-id",
               "requesting Cleaner Settings preserves its one-shot tool hint")
        settingsRouter.consumeDestinationRequest(id: settingsRouter.requestID)
        settingsRouter.cleanerTool = nil
        settingsRouter.page = .general
        withExtendedLifetime(settingsRequestObservation) {}

        // MARK: Display brightness (DDC/CI helpers)


        let untouched: [Float] = [0.0, 0.3, 1.0]
        // Brightness keys arrive as system-defined auxiliary control events;
        // data1 packs key code, press state and the repeat bit.
        func brightnessData1(keyCode: Int, state: Int, repeated: Bool = false) -> Int {
            (keyCode << 16) | (state << 8) | (repeated ? 1 : 0)
        }
        // Keyboards other than the built-in one send brightness as a plain
        // key press, which is why the pointer never got a say on them
        // (issue #287). Codes measured against the display server.
        // Pointer routing on system-routed displays (issue #268): the system
        // only ever steps its native target, so any other display the
        // pointer picks must be stepped by the app.
        // MARK: Text snippets engine (issue #201)

        let fixedDate = Date(timeIntervalSince1970: 1_752_000_000)
        // Only a replacement that names the clipboard pays for reading it: the
        // pasteboard can hang on content nobody renders any more, and that read
        // sits on the keystroke path (issue #887).
        // Custom date patterns after a colon (issue #348)
        let enUS = Locale(identifier: "en_US")
        // Timezone-qualified date variables
        var tzTestCalendar = Calendar(identifier: .gregorian)
        tzTestCalendar.timeZone = TimeZone(identifier: "UTC")!
        let zonedDate = tzTestCalendar.date(from: DateComponents(year: 2025, month: 7, day: 1,
                                                                 hour: 12, minute: 30, second: 15))!
        // Asserted against a fixed non-UTC zone rather than the device's:
        // CI runners are UTC, where a leak and no leak look identical.
        // The likelier leak: one shared DateFormatter has to be reset back
        // to the device zone for a plain token following a zoned one.
        // Compared against the plain token's own output so it holds on
        // CI's UTC runners as well as a machine in any other zone.
        // Date variable builder logic
        // Date variable token detection
        let tokenSample = "Hi {{date:MMM d}} and {{datetime-tz(UTC):yyyy}} end"
        let insideDate = tokenSample.index(tokenSample.startIndex, offsetBy: 6)
        let insideZoned = tokenSample.range(of: "UTC")!.lowerBound
        // The detected range is what the editor later splices over, and it
        // reaches that splice as offsets so it cannot be read against a
        // string it was not measured from.
        // The editor keeps the selection as offsets recorded when the
        // selection last moved, so an edit that shortened the text since
        // leaves them past the end. They must clamp, never trap.
        let selectionText = "abcdef"
        let unknownTagText = "see {{clipboard}} here"
        let insideUnknown = unknownTagText.index(unknownTagText.startIndex, offsetBy: 6)
        let unclosedText = "start {{date:yyyy no close"
        let insideUnclosed = unclosedText.index(unclosedText.startIndex, offsetBy: 10)
        let afterFirstTag = tokenSample.range(of: "{{date:MMM d}}")!.upperBound
        let beforeFirstTag = tokenSample.range(of: "{{date:MMM d}}")!.lowerBound
        // Date variable builder support (timezone search and style matching)
        // Asserted as containment, not equality: the set of identifiers
        // comes from the OS timezone database, so a future release adding
        // another "New York" zone must not fail this.
        // A broad query matches well over a hundred zones. The obvious
        // answer has to be reachable, and near the top: an alphabetical
        // list capped for the picker used to drop it entirely.
        // "york" and the full identifier both narrow to a single match, so
        // neither can observe the ordering. "st" matches dozens, most of
        // which merely contain the letters, so only ranking puts a city
        // beginning with them at the head.
        // A built token round-trips back through detection unchanged: this is
        // exactly the path the Insert/Edit button depends on.
        // Per-snippet capitalization option (issue #304)
        let legacySnippetJSON = """
        [{"id":"1B6E2F0A-1111-4222-8333-444455556666","name":"Old","trigger":";old",\
        "replacement":"x","expansion":"afterDelimiter","enabled":true}]
        """
        // MARK: Snippet library (issue #340)

        let roleDefaults = GlobalShortcutRole.allCases.map(\.defaultShortcut)
        expect(Set(roleDefaults).count == roleDefaults.count,
               "no two shortcut roles ship the same default combination")

        // MARK: Radial menu (issue #220)

        let lossyJSON = """
        [{"kind":"media","payload":"playPause"},{"kind":"teleport","payload":"x"}]
        """
        // MARK: Radial menu profiles

        let dupID = UUID()
        let profileTestDefaults = UserDefaults(suiteName: "com.chikit.tests.radialProfiles")!
        profileTestDefaults.removePersistentDomain(forName: "com.chikit.tests.radialProfiles")
        profileTestDefaults.removePersistentDomain(forName: "com.chikit.tests.radialProfiles")

        let testImage = NSImage(size: NSSize(width: 16, height: 16))
        testImage.lockFocus()
        NSColor.red.set()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        testImage.unlockFocus()
        // The event taps read the cheap answer on every side-button event, so
        // it has to agree with the full decode, custom icons and all.
        let legacyButtonDefaults = UserDefaults(suiteName: "com.chikit.tests.radialLegacyButton")!
        legacyButtonDefaults.removePersistentDomain(forName: "com.chikit.tests.radialLegacyButton")
        legacyButtonDefaults.removePersistentDomain(forName: "com.chikit.tests.radialLegacyButton")

        // The cheap read and the full decode can disagree on a corrupt blob,
        // so only one of them may decide whether the click is passed on: once
        // the button is claimed, nothing past that point hands an event back,
        // or the down and the up split.
        let oversizedData = Data(repeating: 0xFF, count: 70_000)
        let invalidImageData = Data([0x00, 0x01, 0x02, 0x03])
        // MARK: Dock click with AX-blind apps (issue #200)

        // MARK: Dock click restore order (issue #357)

        // The AX array order is deliberately unhelpful in these cases: the
        // captured WindowServer stacking is what has to decide the outcome.
        // MARK: Quick toggles

        expect(Defaults.sanitizedDiskExclusionList(["  Backup  ", "backup", "", "  ", "Photos", "PHOTOS"])
                == ["Backup", "Photos"],
               "sanitized disk exclusion list trims and deduplicates case-insensitively")
        expect(Defaults.registeredDefaults[DefaultsKey.diskEjectExcludedVolumes] is [String],
               "disk eject exclusions are registered as an empty string array")
        expect(SettingsBackupSupport.exportKeys().contains(DefaultsKey.diskEjectExcludedVolumes),
               "disk eject exclusions travel in backups")

        // MARK: Screenshot tool

        let ownScreenshotWindows: Set<CGWindowID> = [11, 12, 13]
        let protectedScreenshotWindows: Set<CGWindowID> = [12, 99]
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotHideChikitWindows]
                as? Bool == true,
               "screenshots hide Chikit windows by default")
        expect(SettingsBackupSupport.exportKeys().contains(
            DefaultsKey.screenshotHideChikitWindows),
               "the screenshot window visibility preference travels in backups")
        expect(ScreenshotCapturePolicy.excludedWindowIDs(
            hideChikitWindows: true,
            ownWindowIDs: ownScreenshotWindows,
            protectedWindowIDs: protectedScreenshotWindows
        ) == ownScreenshotWindows,
        "screenshot hiding Chikit excludes every own window")
        expect(ScreenshotCapturePolicy.excludedWindowIDs(
            hideChikitWindows: false,
            ownWindowIDs: ownScreenshotWindows,
            protectedWindowIDs: protectedScreenshotWindows
        ) == [12],
        "screenshot keeps protected windows excluded while Chikit is visible")
        expect(ScreenshotCapturePolicy.canPickWindow(
            7,
            isOwnWindow: false,
            hideChikitWindows: true,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot can always pick an ordinary external window")
        expect(!ScreenshotCapturePolicy.canPickWindow(
            11,
            isOwnWindow: true,
            hideChikitWindows: true,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot cannot pick a Chikit window while hiding them")
        expect(ScreenshotCapturePolicy.canPickWindow(
            11,
            isOwnWindow: true,
            hideChikitWindows: false,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot can pick an ordinary Chikit window when visible")
        expect(!ScreenshotCapturePolicy.canPickWindow(
            12,
            isOwnWindow: true,
            hideChikitWindows: false,
            protectedWindowIDs: protectedScreenshotWindows
        ), "screenshot cannot pick its own protected capture UI")

        // A sheet or dialog the app stacked on the clicked window is a window
        // of its own, so a single-window capture leaves it out of a shot it is
        // plainly part of (issue #1098). Same app, in front, and lying wholly
        // inside the clicked window is the shape that describes one; anything
        // reaching past its edge is left alone, because drawing a window the
        // person did not choose is worse than leaving a dialog out.
        typealias CaptureWindow = ScreenshotCapturePolicy.CaptureWindow
        let capturedWindow = CaptureWindow(
            id: 1, ownerPID: 500, frame: CGRect(x: 100, y: 100, width: 800, height: 600))
        let sheet = CaptureWindow(
            id: 2, ownerPID: 500, frame: CGRect(x: 300, y: 100, width: 400, height: 300))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [sheet, capturedWindow])
            == ScreenshotCapturePolicy.AttachedCapturePlan(
                windowIDs: [1, 2], bounds: capturedWindow.frame),
               "a sheet on the clicked window joins its capture, the window drawn first")
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [capturedWindow, sheet]) == nil,
               "a window behind the clicked one is not stacked on it")
        let windowOfAnotherApp = CaptureWindow(
            id: 3, ownerPID: 900, frame: CGRect(x: 300, y: 100, width: 400, height: 300))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [windowOfAnotherApp, capturedWindow]) == nil,
               "another application's window over the clicked one stays out of the shot")
        // The case that decides the rule: a compose or second document window
        // of the same app, in front and overlapping, but reaching past the
        // edge. It is not what was asked for, so the ordinary capture answers.
        let composeWindow = CaptureWindow(
            id: 4, ownerPID: 500, frame: CGRect(x: 700, y: 300, width: 500, height: 400))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [composeWindow, capturedWindow]) == nil,
               "a same-app window reaching past the clicked window is not drawn into its shot")
        let detachedWindow = CaptureWindow(
            id: 5, ownerPID: 500, frame: CGRect(x: 2_000, y: 100, width: 200, height: 200))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [detachedWindow, capturedWindow]) == nil,
               "a window of the same app that does not touch the clicked one is not attached")
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [capturedWindow]) == nil,
               "a window with nothing stacked on it keeps the ordinary single-window capture")
        let captureEngineSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift",
            encoding: .utf8)) ?? ""
        // A sheet is often exactly as wide as the window it drops out of, so
        // the rule has to take one that matches an edge rather than shrink from
        // it.
        let fullWidthSheet = CaptureWindow(
            id: 6, ownerPID: 500, frame: CGRect(x: 100, y: 100, width: 800, height: 200))
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [fullWidthSheet, capturedWindow])?.windowIDs
            == [1, 6],
               "a sheet the full width of its window still joins the capture")
        // Two stacked windows are drawn in the order they are shown.
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow,
            frontToBack: [sheet, fullWidthSheet, capturedWindow])?.windowIDs == [1, 6, 2],
               "what is stacked on the window is drawn back to front")
        // A target the list does not hold cannot have anything in front of it.
        expect(ScreenshotCapturePolicy.attachedCapturePlan(
            target: capturedWindow, frontToBack: [sheet]) == nil,
               "a window missing from the list does not treat everything as stacked on it")
        expect(captureEngineSource.contains("$0.frame.intersects(plan.bounds)")
                && captureEngineSource.contains("hits.count == 1")
                && !captureEngineSource.contains(".contains(plan.bounds)"),
               "a window straddling two displays falls back to the single-window capture instead of a one-display slice")

        let geometricAttachment = ScreenshotCapturePolicy.AttachedCapturePlan(
            windowIDs: [1, 6, 2], bounds: capturedWindow.frame)
        expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: nil) == geometricAttachment,
               "missing Accessibility confirmation leaves the geometric attachment unchanged")
        expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: [2])
            == ScreenshotCapturePolicy.AttachedCapturePlan(
                windowIDs: [1, 2], bounds: capturedWindow.frame),
               "Accessibility confirmation keeps its matching attachment in capture order")
        expect(ScreenshotCapturePolicy.confirmedAttachment(
            geometricAttachment, confirmedIDs: []) == nil,
               "Accessibility confirmation with no matching attachment drops the composite plan")

        // The engine is outside the pure-helper test binary. Pin the permission
        // gate before its AX call so window capture never starts an
        // Accessibility round trip merely because geometry found a candidate.
        let screenshotCaptureEngineSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotCaptureEngine.swift",
            encoding: .utf8)) ?? ""
        let captureWindowBody = (screenshotCaptureEngineSource
            .components(separatedBy: "static func captureWindow(").last ?? "")
            .components(separatedBy: "\n    /// On-screen windows").first ?? ""
        let accessibilityGate = captureWindowBody.range(of: "if Permissions.shared.accessibility {")
        let attachmentConfirmation = captureWindowBody.range(
            of: "accessibilityAttachedWindowIDs(")
        expect(accessibilityGate != nil && attachmentConfirmation != nil
               && accessibilityGate!.lowerBound < attachmentConfirmation!.lowerBound,
               "window capture checks its existing Accessibility grant before AX confirmation")
        let accessibilityAttachedWindowIDsBody = (screenshotCaptureEngineSource
            .components(separatedBy: "private static func accessibilityAttachedWindowIDs(").last ?? "")
            .components(separatedBy: "\n    private static func accessibilityElements(").first ?? ""
        let accessibilityAttachedWindowIDsCode = accessibilityAttachedWindowIDsBody
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let unresolvedCandidatePasses = accessibilityAttachedWindowIDsCode.range(of: "guard let element = elementsByID[candidateID] else {\n                confirmed.insert(candidateID)\n                continue\n            }")
        let standardWindowFails = accessibilityAttachedWindowIDsCode.range(of: "if let subrole = accessibilityString(element, kAXSubroleAttribute as CFString),\n               subrole == (kAXStandardWindowSubrole as String) || subrole == \"AXFullScreenWindow\" {\n                continue\n            }\n            confirmed.insert(candidateID)")
        let childrenPassIsAbsent = !accessibilityAttachedWindowIDsCode.contains("kAXChildrenAttribute")
        expect(unresolvedCandidatePasses != nil && standardWindowFails != nil && childrenPassIsAbsent,
               "AX keeps unresolved candidates and excludes only identified standard windows")

        expect(ScreenshotSupport.sanitizedDelay(5) == 5
                && ScreenshotSupport.sanitizedDelay(7) == 0
                && ScreenshotSupport.sanitizedDelay(-3) == 0,
               "capture delay only accepts the offered steps")
        expect(ScreenshotSupport.scrollingCaptureMaximumDuration == 120
                && ScreenshotSupport.scrollingCaptureMaximumFrames == 512
                && ScreenshotSupport.scrollingCaptureMaximumRetainedPixels == 60_000_000
                && ScreenshotSupport.scrollingCaptureMaximumPixels == 60_000_000,
               "manual scrolling screenshots have explicit loop and memory safeguards")

        func scrollingSample(width: Int = 16,
                             height: Int = 120,
                             offset: Int) -> ScreenshotSupport.ScrollingSample {
            var pixels = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                let contentRow = row + offset
                for column in 0..<width {
                    pixels[row * width + column] = UInt8(
                        (contentRow * 17 + column * 31 + (contentRow / 7) * 13) % 251)
                }
            }
            return ScreenshotSupport.ScrollingSample(width: width,
                                                     height: height,
                                                     pixels: pixels)
        }
        let firstScrollSample = scrollingSample(offset: 0)
        let nextScrollSample = scrollingSample(offset: 76)
        let forwardScrollTransition = ScreenshotSupport.scrollingTransition(
            previous: firstScrollSample,
            current: nextScrollSample)
        expect(forwardScrollTransition
                == .advanced(overlap: 44,
                             direction: .forward,
                             contentColumns: 0..<16),
               "scrolling screenshots find the exact shared rows deterministically: \(forwardScrollTransition)")
        let backwardScrollTransition = ScreenshotSupport.scrollingTransition(
            previous: nextScrollSample,
            current: firstScrollSample)
        expect(backwardScrollTransition
                == .advanced(overlap: 44,
                             direction: .backward,
                             contentColumns: 0..<16),
               "scrolling screenshots identify backward movement without duplicating it: \(backwardScrollTransition)")
        expect(ScreenshotSupport.scrollingTransition(previous: nextScrollSample,
                                                     current: nextScrollSample) == .end,
               "an unchanged capture marks the real end of scrolling")
        expect(ScreenshotSupport.scrollingSamplesAreStable(nextScrollSample,
                                                           nextScrollSample),
               "settling recognizes two unchanged scrolling frames")
        let shortFinalScrollSample = scrollingSample(offset: 8)
        expect(ScreenshotSupport.scrollingTransition(previous: firstScrollSample,
                                                     current: shortFinalScrollSample)
                == .advanced(overlap: 112,
                             direction: .forward,
                             contentColumns: 0..<16),
               "a short final scroll is kept instead of failing the whole capture")
        func sampleWithFixedEdges(offset: Int) -> ScreenshotSupport.ScrollingSample {
            let sample = scrollingSample(offset: offset)
            var pixels = sample.pixels
            for row in 0..<12 {
                for column in 0..<sample.width {
                    pixels[row * sample.width + column] = UInt8(row * 5 + column)
                    let bottomRow = sample.height - row - 1
                    pixels[bottomRow * sample.width + column] = UInt8(row * 3 + column)
                }
            }
            return ScreenshotSupport.ScrollingSample(width: sample.width,
                                                     height: sample.height,
                                                     pixels: pixels)
        }
        expect(ScreenshotSupport.scrollingTransition(
            previous: sampleWithFixedEdges(offset: 0),
            current: sampleWithFixedEdges(offset: 50))
                == .advanced(overlap: 70,
                             direction: .forward,
                             contentColumns: 0..<16),
               "fixed page edges do not hide the shared scrolling content")
        func sampleWithFixedBottom(offset: Int,
                                   fixedBottomRows: Int = 18)
            -> ScreenshotSupport.ScrollingSample {
            let sample = scrollingSample(offset: offset)
            var pixels = sample.pixels
            for row in (sample.height - fixedBottomRows)..<sample.height {
                for column in 0..<sample.width {
                    pixels[row * sample.width + column] = UInt8(
                        (row * 29 + column * 11 + 41) % 251)
                }
            }
            return ScreenshotSupport.ScrollingSample(width: sample.width,
                                                     height: sample.height,
                                                     pixels: pixels)
        }
        let fixedBottomStart = sampleWithFixedBottom(offset: 0)
        let fixedBottomNext = sampleWithFixedBottom(offset: 42)
        expect(ScreenshotSupport.scrollingTransition(previous: fixedBottomStart,
                                                     current: fixedBottomNext)
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 0..<16),
               "a fixed footer does not hide the moving page overlap")
        expect(ScreenshotSupport.scrollingFixedBottomRows(
            previous: fixedBottomStart,
            current: fixedBottomNext,
            overlap: 78,
            contentColumns: 0..<16) == 18,
               "scrolling capture identifies a fixed footer at the bottom edge")
        expect(ScreenshotSupport.scrollingFixedBottomRows(
            previous: firstScrollSample,
            current: scrollingSample(offset: 42),
            overlap: 78,
            contentColumns: 0..<16) == 0,
               "ordinary moving content is never mistaken for a fixed footer")
        expect(ScreenshotSupport.scrollingNewContentRows(
            imageHeight: 120,
            overlap: 78,
            fixedBottomRows: 18) == 60..<102,
               "new scrolling pixels move above the fixed footer instead of copying it")
        expect(ScreenshotSupport.scrollingNewContentRows(
            imageHeight: 120,
            overlap: 78,
            fixedBottomRows: 0) == 78..<120,
               "captures without a fixed footer keep the original crop geometry")
        var scrollingStressPassed = true
        var scrollingStressFailure: ScreenshotSupport.ScrollingTransition?
        for iteration in 0..<250 {
            let offset = [8, 76][iteration % 2]
            let transition = ScreenshotSupport.scrollingTransition(
                previous: firstScrollSample,
                current: scrollingSample(offset: offset))
            let passed = transition == .advanced(overlap: 120 - offset,
                                                 direction: .forward,
                                                 contentColumns: 0..<16)
            if !passed, scrollingStressFailure == nil { scrollingStressFailure = transition }
            scrollingStressPassed = scrollingStressPassed && passed
        }
        expect(scrollingStressPassed,
               "scroll matching stays deterministic through repeated short and long advances: \(String(describing: scrollingStressFailure))")
        let retinaScrollStart = scrollingSample(width: 32, height: 900, offset: 0)
        let retinaScrollNext = scrollingSample(width: 32, height: 900, offset: 558)
        expect(ScreenshotSupport.scrollingTransition(previous: retinaScrollStart,
                                                     current: retinaScrollNext)
                == .advanced(overlap: 342,
                             direction: .forward,
                             contentColumns: 0..<32),
               "scroll matching handles a full-width sample at a realistic Retina selection height")
        func scrollingSampleWithFixedColumns(offset: Int,
                                             changesAfterScroll: Bool = false)
            -> ScreenshotSupport.ScrollingSample {
            let width = 24
            let height = 120
            var pixels = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                for column in 0..<width {
                    if column < 6 || column >= 18 {
                        pixels[row * width + column] = UInt8(
                            (row * 19 + column * 23 + (row / 5) * 11) % 251)
                    } else if changesAfterScroll && (30..<46).contains(row) {
                        pixels[row * width + column] = UInt8(
                            (row * 61 + column * 7 + 37) % 251)
                    } else {
                        let contentRow = row + offset
                        pixels[row * width + column] = UInt8(
                            (contentRow * 17 + column * 31 + (contentRow / 7) * 13) % 251)
                    }
                }
            }
            return ScreenshotSupport.ScrollingSample(width: width,
                                                     height: height,
                                                     pixels: pixels)
        }
        let fixedColumnsStart = scrollingSampleWithFixedColumns(offset: 0)
        let fixedColumnsNext = scrollingSampleWithFixedColumns(offset: 42)
        expect(ScreenshotSupport.scrollingTransition(previous: fixedColumnsStart,
                                                     current: fixedColumnsNext)
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 6..<18),
               "scroll matching isolates moving content from fixed side columns")
        let changedColumnsNext = scrollingSampleWithFixedColumns(
            offset: 42,
            changesAfterScroll: true)
        let changedColumnsTransition = ScreenshotSupport.scrollingTransition(
            previous: fixedColumnsStart,
            current: changedColumnsNext)
        expect(changedColumnsTransition
                == .advanced(overlap: 78,
                             direction: .forward,
                             contentColumns: 6..<18),
               "scroll matching survives a changed block inside moving content: \(changedColumnsTransition)")
        expect(ScreenshotSupport.scrollingPixelRange(sampleColumns: 6..<18,
                                                     sampleWidth: 24,
                                                     imageWidth: 1_920) == 480..<1_440,
               "the moving sample columns map back to the exact captured pixels")
        var unmatchedScrollPixels = [UInt8](repeating: 0, count: 16 * 120)
        for index in unmatchedScrollPixels.indices {
            unmatchedScrollPixels[index] = UInt8((index * 47 + index / 11) % 253)
        }
        let unmatchedScrollSample = ScreenshotSupport.ScrollingSample(
            width: 16, height: 120, pixels: unmatchedScrollPixels)
        expect(ScreenshotSupport.scrollingTransition(previous: firstScrollSample,
                                                     current: unmatchedScrollSample) == .unmatched,
               "ambiguous content fails instead of inventing a seam")
        expectClose(Double(ScreenshotSupport.captureScale(fromDPI: 144) ?? 0), 2,
                    "the cached screenshot restores its Retina scale from PNG metadata")
        expect(ScreenshotSupport.captureScale(fromDPI: nil) == nil
                && ScreenshotSupport.captureScale(fromDPI: 0) == nil
                && ScreenshotSupport.captureScale(fromDPI: .infinity) == nil,
               "missing or broken PNG scale metadata never opens a misleading capture")

        let dragRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 100, y: 80),
                                                       to: CGPoint(x: 40, y: 200))
        expect(dragRect == CGRect(x: 40, y: 80, width: 60, height: 120),
               "a drag in any direction normalizes to a positive rect")
        let squareRect = ScreenshotSupport.selectionRect(from: CGPoint(x: 10, y: 10),
                                                         to: CGPoint(x: 40, y: 90),
                                                         square: true)
        expect(squareRect.width == squareRect.height && squareRect.width == 80,
               "shift constrains the selection to a square")
        let centered = ScreenshotSupport.selectionRect(from: CGPoint(x: 50, y: 50),
                                                       to: CGPoint(x: 70, y: 60),
                                                       fromCenter: true)
        expect(centered == CGRect(x: 30, y: 40, width: 40, height: 20),
               "option grows the selection from the center")
        let cropBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let cropDraft = CGRect(x: 120, y: 90, width: 400, height: 300)
        expect(ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 300, y: 250), draft: cropBounds, within: cropBounds),
               "dragging inside the initial full-image crop starts a new selection")
        expect(!ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 300, y: 250), draft: cropDraft, within: cropBounds),
               "dragging inside an adjusted crop keeps moving it")
        expect(ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 700, y: 500), draft: cropDraft, within: cropBounds),
               "dragging elsewhere in the image replaces an adjusted crop")
        expect(!ScreenshotSupport.startsNewCropSelection(
                    at: CGPoint(x: 900, y: 700), draft: cropDraft, within: cropBounds),
               "a drag outside the image cannot start a crop")
        expect(ScreenshotSupport.isClick(from: CGPoint(x: 5, y: 5), to: CGPoint(x: 7, y: 8))
                && !ScreenshotSupport.isClick(from: .zero, to: CGPoint(x: 12, y: 0)),
               "a tiny drag is a click, a real drag is not")

        // The crop chrome, the loupe cross and the image applyCrop produces are
        // three drawings of one edge. They agree only while pixelSnappedCropRect
        // is the single thing deciding where that edge is.
        let snapBounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let looseDraft = CGRect(x: 100.4, y: 60.4, width: 100, height: 100)
        let snappedDraft = ScreenshotSupport.pixelSnappedCropRect(looseDraft, within: snapBounds)
        expect(snappedDraft == CGRect(x: 100, y: 60, width: 100, height: 100),
               "a crop draft rounds each edge to the nearest pixel boundary")
        expect(snappedDraft.maxX == 200,
               "a crop draft does not grow outward the way CGRect.integral would")
        expect(ScreenshotSupport.pixelSnappedCropRect(snappedDraft, within: snapBounds)
                == snappedDraft,
               "snapping a crop draft that already sits on pixels changes nothing")
        expect(ScreenshotSupport.pixelSnappedCropRect(
                    CGRect(x: 100.4, y: 60.4, width: 100.2, height: 100.2), within: snapBounds)
                == CGRect(x: 100, y: 60, width: 101, height: 101),
               "a crop edge past the halfway mark rounds to the next boundary")
        let movedDraft = ScreenshotSupport.pixelSnappedCropRect(
            ScreenshotSupport.movedRect(snappedDraft,
                                        by: CGPoint(x: 12.6, y: -4.3),
                                        within: snapBounds),
            within: snapBounds)
        expect(movedDraft.size == snappedDraft.size,
               "moving a crop draft never changes its size")
        expect(ScreenshotSupport.pixelSnappedCropRect(
                    CGRect(x: -40, y: -30, width: 100, height: 100), within: snapBounds)
                == CGRect(x: 0, y: 0, width: 60, height: 70),
               "a snapped crop draft stays inside the image")

        // An even sample side centres the edge only once the edge is whole,
        // which is what the snapping above guarantees.
        let snapImageSize = CGSize(width: 800, height: 600)
        let snappedEdge = ScreenshotSupport.Handle.left.position(in: snappedDraft)
        let snappedSample = ScreenshotSupport.cropLoupeSampleRect(around: snappedEdge,
                                                                  imageSize: snapImageSize,
                                                                  sideLength: 14,
                                                                  centredOnPixel: false)
        expect(snappedSample.midX == snappedEdge.x && snappedSample.midY == snappedEdge.y,
               "the crop loupe centres on the edge it marks once the draft sits on pixels")
        let looseEdge = ScreenshotSupport.Handle.left.position(in: looseDraft)
        let looseSample = ScreenshotSupport.cropLoupeSampleRect(around: looseEdge,
                                                                imageSize: snapImageSize,
                                                                sideLength: 14,
                                                                centredOnPixel: false)
        expect(looseSample.midX != looseEdge.x,
               "an even sample side alone does not centre a fractional crop edge")

        var patternParts = DateComponents()
        patternParts.year = 2026
        patternParts.month = 7
        patternParts.day = 24
        patternParts.hour = 15
        patternParts.minute = 4
        patternParts.second = 9
        if let patternDate = Calendar(identifier: .gregorian).date(from: patternParts) {
            expect(ScreenshotSupport.expandSaveSubfolder("%y-%mo", date: patternDate) == "26-07",
                   "short date tokens expand zero padded")
            expect(ScreenshotSupport.expandSaveSubfolder("%year/%month", date: patternDate)
                   == "2026/July",
                   "long date tokens expand before their short prefixes and nest with slashes")
            expect(ScreenshotSupport.expandSaveSubfolder("", date: patternDate) == "",
                   "an empty subfolder pattern means no subfolder")
            expect(ScreenshotSupport.expandSaveSubfolder("../up//./%y", date: patternDate)
                   == "up/26",
                   "dot, dot-dot and empty components never escape the base folder")
            expect(ScreenshotSupport.expandFileNamePattern("Shot %d at %h.%mi.%s",
                                                           date: patternDate, number: 0)
                   == "Shot 24 at 15.04.09",
                   "file name patterns expand the day and time tokens")
            expect(ScreenshotSupport.expandFileNamePattern("Shot-%#", date: patternDate, number: 7)
                   == "Shot-7",
                   "a single number token renders the sequence unpadded")
            expect(ScreenshotSupport.expandFileNamePattern("%###-%y", date: patternDate, number: 7)
                   == "007-26",
                   "a longer number token zero pads to its length")
            expect(ScreenshotSupport.fileNamePatternUsesNumber("Shot-%#")
                    && !ScreenshotSupport.fileNamePatternUsesNumber("Shot-%y"),
                   "only patterns with the number token consume the sequence")
            expect(ScreenshotSupport.expandFileNamePattern("a/b %h:%mi", date: patternDate, number: 0)
                   == "a-b 15-04",
                   "slashes and colons in a file name pattern become dashes")
        } else {
            expect(false, "gregorian calendar produced the fixed pattern date")
        }

        let cornerFrame = ScreenshotSupport.quickPreviewFrame(
            size: CGSize(width: 310, height: 210),
            anchor: .zero,
            pointer: .zero,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            position: .bottomRight)
        expect(cornerFrame == CGRect(x: 1114, y: 16, width: 310, height: 210),
               "the after-capture confirmation sits inset in the bottom-right corner")
        let previewSize = CGSize(width: 310, height: 210)
        let previewScreen = CGRect(x: -1920, y: 50, width: 1440, height: 900)
        func configuredPreviewFrame(_ position: ScreenshotSupport.QuickPreviewPosition) -> CGRect {
            ScreenshotSupport.quickPreviewFrame(
                size: previewSize,
                anchor: .zero,
                pointer: .zero,
                visibleFrame: previewScreen,
                position: position)
        }
        expect(configuredPreviewFrame(.topLeft)
                == CGRect(x: -1904, y: 724, width: 310, height: 210)
                && configuredPreviewFrame(.topRight)
                == CGRect(x: -806, y: 724, width: 310, height: 210)
                && configuredPreviewFrame(.bottomLeft)
                == CGRect(x: -1904, y: 66, width: 310, height: 210)
                && configuredPreviewFrame(.bottomRight)
                == CGRect(x: -806, y: 66, width: 310, height: 210),
               "every configured preview corner respects the display origin and inset")
        let previewScreens = [
            (frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
             visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1055)),
            (frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
             visibleFrame: CGRect(x: 0, y: 40, width: 1440, height: 860)),
            (frame: CGRect(x: 1440, y: 300, width: 1280, height: 1024),
             visibleFrame: CGRect(x: 1440, y: 300, width: 1280, height: 999)),
        ]
        expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: -900, y: 200, width: 500, height: 400),
            pointer: CGPoint(x: -500, y: 300),
            screens: previewScreens,
            fallback: .zero) == previewScreens[0].visibleFrame,
               "a capture uses the visible frame of its display in a three-display layout")
        expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: 1300, y: 500, width: 500, height: 500),
            pointer: CGPoint(x: 1700, y: 650),
            screens: previewScreens,
            fallback: .zero) == previewScreens[2].visibleFrame,
               "a capture crossing displays uses the screen containing most of it")
        expect(ScreenshotSupport.quickPreviewVisibleFrame(
            anchor: CGRect(x: 5000, y: 5000, width: 400, height: 300),
            pointer: CGPoint(x: 700, y: 500),
            screens: previewScreens,
            fallback: .zero) == previewScreens[1].visibleFrame,
               "a disconnected capture display falls back to the current pointer display")
        expect(ScreenshotSupport.QuickPreviewPosition.allCases.map(\.rawValue)
                == ["", "topLeft", "topRight", "bottomLeft", "bottomRight"]
                && ScreenshotSupport.QuickPreviewPosition(rawValue: "bogus") == nil,
               "preview positions keep stable storage values and reject unknown values")
        // A gesture that ends with more than one release, like a drag made
        // with three fingers, delivers events after the capture is over.
        expect(ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: false,
                                                              capturePending: false),
               "a live selection answers the pointer")
        expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: true,
                                                               capturePending: false),
               "a session that is over ignores the tail of a gesture")
        expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: false,
                                                               capturePending: true),
               "a capture already on its way ignores further pointer input")
        expect(!ScreenshotSupport.selectionAcceptsPointerInput(sessionIsOver: true,
                                                               capturePending: true),
               "both at once still ignores the pointer")
        let recordingOnly: Set<AppFeature> = [.screenRecorder]
        expect(ScreenCaptureTool.available(isAvailable: recordingOnly.contains) == [.recording],
               "the capture chooser hides every uninstalled mode")
        let recorderPolicy = ScreenshotSupport.unifiedCapturePolicy(
            for: .recording,
            screenshotFreeze: false,
            screenshotIncludePointer: true,
            screenshotHideChikitWindows: true)
        expect(ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: true,
                                                       selectionInProgress: false,
                                                       capturePending: false)
                && !ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: true,
                                                            selectionInProgress: true,
                                                            capturePending: false)
                && !ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: true,
                                                            selectionInProgress: false,
                                                            capturePending: true)
                && !ScreenshotSupport.captureGuideIsVisible(pointerOnDisplay: false,
                                                            selectionInProgress: false,
                                                            capturePending: false),
               "the capture chooser disappears for the whole drag and while capture is pending")
        let captureSelectionSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenshotSelectionController.swift",
            encoding: .utf8)) ?? ""
        expect(captureSelectionSource.contains(
            "override func mouseExited(with event: NSEvent) {\n        refreshPointerState()\n        refreshGuideVisibility()"),
               "system chrome cannot hide the capture chooser while the pointer remains on its display")
        expect(captureSelectionSource.contains(
            "let height: CGFloat = screenCaptureOptions != nil\n            ? 146\n            : 72")
                && captureSelectionSource.contains(
                    ".opacity(options.selectedTool == .recording ? 1 : 0)"),
               "capture modes reserve the recording controls' height so the chooser never jumps")
        expect(captureSelectionSource.contains("screenCaptureToolDidChange()")
                && captureSelectionSource.contains("!nextPolicy.sharesSource(with: capturePolicy)")
                && captureSelectionSource.contains("adoptCapturePolicy(nextPolicy)")
                && captureSelectionSource.contains("panel.update(frozenImage:")
                && captureSelectionSource.contains("screenCaptureOptions?.onSelectionChange ="),
               "a capture mode that needs other pixels gets them behind the panels, which stay on screen")
        expect(captureSelectionSource.contains("private var pointerIsInside = false")
                && !captureSelectionSource.contains("|| bounds.contains(hoverPoint)"),
               "the capture loupe draws on only the display that owns the current pointer")
        let captureServiceSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/QuickTools/ScreenCaptureService.swift",
            encoding: .utf8)) ?? ""
        expect(!captureServiceSource.contains("replaceSelection"),
               "the capture service does not cancel and recreate selection controllers when changing modes")

        let cocoa = ScreenshotSupport.cocoaRect(fromWindowServer: CGRect(x: 10, y: 30, width: 200, height: 100),
                                                mainScreenHeight: 900)
        expect(cocoa == CGRect(x: 10, y: 770, width: 200, height: 100),
               "window server rects convert to Cocoa coordinates")
        let viewRect = ScreenshotSupport.flippedViewRect(fromCocoa: cocoa,
                                                         screenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900))
        expect(viewRect == CGRect(x: 10, y: 30, width: 200, height: 100),
               "the round trip back to a flipped view restores the window server rect")
        expect(ScreenshotSupport.cocoaRect(fromFlippedView: viewRect,
                                           screenFrame: CGRect(x: 0, y: 0,
                                                               width: 1600, height: 900)) == cocoa,
               "a flipped overlay rect maps back to its Cocoa screen position")
        let pixels = ScreenshotSupport.imagePixelRect(fromView: CGRect(x: 10, y: 20, width: 30, height: 40),
                                                      viewSize: CGSize(width: 100, height: 100),
                                                      imageSize: CGSize(width: 200, height: 200))
        expect(pixels == CGRect(x: 20, y: 40, width: 60, height: 80),
               "view points scale to image pixels")
        expect(ScreenshotSupport.imagePixelRect(fromView: CGRect(x: -20, y: -20, width: 500, height: 500),
                                                viewSize: CGSize(width: 100, height: 100),
                                                imageSize: CGSize(width: 200, height: 200))
                == CGRect(x: 0, y: 0, width: 200, height: 200),
               "pixel rects clamp to the image")
        expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: 50, y: 25),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 100, y: 50),
               "the capture loupe maps its pointer to the matching source pixel")
        expect(ScreenshotSupport.imagePixelPoint(fromView: CGPoint(x: -10, y: 90),
                                                 viewSize: CGSize(width: 100, height: 50),
                                                 imageSize: CGSize(width: 200, height: 100))
                == CGPoint(x: 0, y: 100),
               "the capture loupe clamps source points at display edges")
        let editorMinimum = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 1470, height: 956))
        expect(editorMinimum == CGSize(width: 980, height: 680),
               "the screenshot editor opens on a comfortable canvas")
        let editorSmallDisplay = ScreenshotSupport.editorMinimumContentSize(
            visibleSize: CGSize(width: 700, height: 500))
        expect(editorSmallDisplay == CGSize(width: 700, height: 500),
               "the editor minimum never exceeds a compact display")
        let smallCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 180, height: 100),
            visibleSize: CGSize(width: 1470, height: 956))
        expect(smallCaptureWindow == editorMinimum,
               "a small screenshot still receives the full editing canvas")
        let largeCaptureWindow = ScreenshotSupport.editorContentSize(
            imagePointSize: CGSize(width: 2200, height: 1400),
            visibleSize: CGSize(width: 1470, height: 956))
        expect(largeCaptureWindow.width <= 1470 * 0.90
                && largeCaptureWindow.height <= 956 * 0.88,
               "a large screenshot editor stays inside the visible display")
        expect(ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 42,
                                                    editorWindowNumber: 42,
                                                    editorIsKey: true),
               "screenshot editor owns key events carrying its window number")
        expect(ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 0,
                                                    editorWindowNumber: 42,
                                                    editorIsKey: true),
               "screenshot editor owns windowless menu key equivalents while key")
        expect(!ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 0,
                                                     editorWindowNumber: 42,
                                                     editorIsKey: false),
               "inactive screenshot editor ignores windowless key events")
        expect(!ScreenshotSupport.editorOwnsKeyEvent(eventWindowNumber: 7,
                                                     editorWindowNumber: 42,
                                                     editorIsKey: true),
               "screenshot editor ignores events explicitly owned by another window")
        let previewFrame = ScreenshotSupport.quickPreviewFrame(
            size: CGSize(width: 286, height: 210),
            anchor: CGRect(x: 1100, y: 100, width: 300, height: 300),
            pointer: CGPoint(x: 1300, y: 220),
            visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 956))
        expect(CGRect(x: 10, y: 10, width: 1450, height: 936).contains(previewFrame),
               "the quick capture preview stays fully inside the visible display")

        let pickable = [ScreenshotSupport.PickableWindow(windowID: 1, frame: CGRect(x: 0, y: 0, width: 50, height: 50)),
                        ScreenshotSupport.PickableWindow(windowID: 2, frame: CGRect(x: 0, y: 0, width: 400, height: 400))]
        expect(ScreenshotSupport.window(at: CGPoint(x: 10, y: 10), in: pickable)?.windowID == 1,
               "the frontmost window wins a click")
        expect(ScreenshotSupport.window(at: CGPoint(x: 300, y: 300), in: pickable)?.windowID == 2
                && ScreenshotSupport.window(at: CGPoint(x: 900, y: 900), in: pickable) == nil,
               "clicks outside every window pick nothing")

        let fileDate = Date(timeIntervalSince1970: 1_752_486_065) // 2025-07-14 09:41:05 UTC
        let fileName = ScreenshotSupport.fileName(prefix: "Screenshot", date: fileDate)
        expect(fileName.hasPrefix("Screenshot 20") && fileName.hasSuffix(".png")
                && !fileName.contains(":") && fileName.contains(" at "),
               "file names are dated, colon free and png")
        expect(ScreenshotSupport.uniqueFileName("a.png", exists: { _ in false }) == "a.png",
               "a free name stays untouched")
        expect(ScreenshotSupport.uniqueFileName("a.png", exists: { $0 == "a.png" }) == "a 2.png",
               "a taken name gets the next numbered variant")
        expect(ScreenshotSupport.uniqueFileName("a.png",
                                                exists: { $0 == "a.png" || $0 == "a 2.png" }) == "a 3.png",
               "numbering keeps walking until a free name")
        let recentID = UUID()
        expect(ScreenshotSupport.isRecentCaptureCacheFileName("\(recentID.uuidString).png")
                && ScreenshotSupport.isRecentCaptureCacheFileName(
                    "\(recentID.uuidString)-thumbnail.png")
                && !ScreenshotSupport.isRecentCaptureCacheFileName("history.json")
                && !ScreenshotSupport.isRecentCaptureCacheFileName("../\(recentID.uuidString).png"),
               "recent capture cleanup recognizes only app-owned UUID png names")
        let dragRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotDragTests-\(UUID().uuidString)", isDirectory: true)
        let dragData = Data([0x89, 0x50, 0x4E, 0x47])
        let firstDrag = try? ScreenshotSupport.temporaryDragFile(
            data: dragData, name: "Capture.png", directory: dragRoot)
        let secondDrag = try? ScreenshotSupport.temporaryDragFile(
            data: dragData, name: "Capture.png", directory: dragRoot)
        expect(firstDrag?.lastPathComponent == "Capture.png"
                && firstDrag.flatMap { try? Data(contentsOf: $0) } == dragData,
               "a screenshot drag writes the complete payload with its file name")
        expect(firstDrag != nil && secondDrag != nil && firstDrag != secondDrag,
               "simultaneous screenshot drags receive separate temporary files")
        let unrelatedDrag = dragRoot.appendingPathComponent("ScreenshotDrag-not-owned",
                                                            isDirectory: true)
        try? FileManager.default.createDirectory(at: unrelatedDrag,
                                                 withIntermediateDirectories: true)
        ScreenshotSupport.removeTemporaryDragDirectories(directory: dragRoot)
        expect(firstDrag.map { !FileManager.default.fileExists(atPath: $0.path) } == true
                && secondDrag.map { !FileManager.default.fileExists(atPath: $0.path) } == true
                && FileManager.default.fileExists(atPath: unrelatedDrag.path),
               "temporary screenshot cleanup removes only app-owned drag directories")
        try? FileManager.default.removeItem(at: dragRoot)

        let copyRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotCopyTests-\(UUID().uuidString)", isDirectory: true)
        let staleCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "Old.png", directory: copyRoot)
        if let staleCopy {
            try? FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: 1)],
                ofItemAtPath: staleCopy.path)
        }
        let currentCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "../Capture.png", directory: copyRoot)
        let nextCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "Capture.png", directory: copyRoot)
        if let nextCopy {
            ScreenshotSupport.pruneCopiedFiles(
                in: copyRoot, preserving: nextCopy,
                now: Date(timeIntervalSince1970: 100_000))
        }
        expect(staleCopy.map { !FileManager.default.fileExists(atPath: $0.path) } == true,
               "copying a screenshot removes expired copied files")
        expect(currentCopy?.lastPathComponent == "Capture.png"
                && nextCopy?.lastPathComponent == "Capture 2.png"
                && currentCopy.flatMap { try? Data(contentsOf: $0) } == dragData,
               "copied screenshots stay as unique complete png files")
        expect(currentCopy.map { ScreenshotSupport.isCopiedScreenshot($0, in: copyRoot) } == true,
               "clipboard history recognizes a copied screenshot only inside its private cache")
        let lateStaleCopy = copyRoot.appendingPathComponent("A.png")
        let publishedCopy = copyRoot.appendingPathComponent("B.png")
        let pruneVictims = ScreenshotSupport.copiedFilePruneVictims(
            [
                .init(url: lateStaleCopy, date: Date(timeIntervalSince1970: 2), bytes: 6),
                .init(url: publishedCopy, date: Date(timeIntervalSince1970: 1), bytes: 6),
            ],
            preserving: publishedCopy,
            maximumCount: 100,
            maximumBytes: 10)
        expect(pruneVictims == [lateStaleCopy],
               "a late stale copy is pruned without evicting the published file")
        let copySymlink = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotCopyLink-\(UUID().uuidString)")
        try? FileManager.default.createSymbolicLink(at: copySymlink,
                                                     withDestinationURL: copyRoot)
        let symlinkCopy = try? ScreenshotSupport.copiedFile(
            data: dragData, name: "Linked.png", directory: copySymlink)
        expect(symlinkCopy == nil
                && currentCopy.map { FileManager.default.fileExists(atPath: $0.path) } == true,
               "copied screenshots reject a symlink cache without touching its target")
        try? FileManager.default.removeItem(at: copySymlink)
        try? FileManager.default.removeItem(at: copyRoot)

        var counterList = [
            ScreenshotSupport.Annotation(tool: .counter, number: 1),
            ScreenshotSupport.Annotation(tool: .arrow),
            ScreenshotSupport.Annotation(tool: .counter, number: 2),
            ScreenshotSupport.Annotation(tool: .counter, number: 3),
        ]
        counterList.remove(at: 0)
        let renumbered = ScreenshotSupport.renumberingCounters(counterList)
        expect(renumbered.filter { $0.tool == .counter }.map(\.number) == [1, 2],
               "deleting a counter renumbers the rest without holes")
        expect(renumbered[0].tool == .arrow || renumbered.count == 3,
               "renumbering never drops annotations")

        let layered = [
            ScreenshotSupport.Annotation(tool: .text),
            ScreenshotSupport.Annotation(tool: .rect),
            ScreenshotSupport.Annotation(tool: .arrow),
        ]
        let sentBack = ScreenshotSupport.reordering(layered, moving: layered[1].id, .backward)
        expect(sentBack.map(\.id) == [layered[1].id, layered[0].id, layered[2].id],
               "sending back swaps an annotation with the one drawn before it")
        let broughtForward = ScreenshotSupport.reordering(layered, moving: layered[1].id, .forward)
        expect(broughtForward.map(\.id) == [layered[0].id, layered[2].id, layered[1].id],
               "bringing forward swaps an annotation with the one drawn after it")
        expect(ScreenshotSupport.reordering(layered, moving: layered[0].id, .backward).map(\.id)
                == layered.map(\.id)
                && ScreenshotSupport.reordering(layered, moving: layered[2].id, .forward).map(\.id)
                == layered.map(\.id),
               "an annotation at either end of the order stays put in that direction")
        expect(ScreenshotSupport.reordering(layered, moving: UUID(), .forward).map(\.id)
                == layered.map(\.id),
               "an unknown annotation leaves the order alone")
        expect(!ScreenshotSupport.canReorder(layered, moving: layered[0].id, .backward)
                && ScreenshotSupport.canReorder(layered, moving: layered[0].id, .forward)
                && !ScreenshotSupport.canReorder(layered, moving: layered[2].id, .forward)
                && ScreenshotSupport.canReorder(layered, moving: layered[2].id, .backward),
               "each direction is offered only while the annotation can still take it")
        expect(!ScreenshotSupport.canReorder(layered, moving: UUID(), .forward)
                && !ScreenshotSupport.canReorder([], moving: layered[0].id, .backward),
               "an annotation that is not there can never be reordered")

        let resized = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .bottomRight,
                                                    to: CGPoint(x: 50, y: 60))
        expect(resized == CGRect(x: 10, y: 10, width: 40, height: 50),
               "dragging a handle resizes the rect")
        let crossed = ScreenshotSupport.resizedRect(CGRect(x: 10, y: 10, width: 100, height: 100),
                                                    dragging: .right,
                                                    to: CGPoint(x: 0, y: 0))
        expect(crossed.width == 10 && crossed.minX == 0,
               "dragging a handle across the opposite edge flips instead of going negative")
        let movedCrop = ScreenshotSupport.movedRect(
            CGRect(x: 20, y: 30, width: 80, height: 60),
            by: CGPoint(x: 50, y: -100),
            within: CGRect(x: 0, y: 0, width: 120, height: 100))
        expect(movedCrop == CGRect(x: 40, y: 0, width: 80, height: 60),
               "dragging inside a crop moves it without resizing past the image edges")
        expect(ScreenshotSupport.handle(at: CGPoint(x: 10, y: 10),
                                        rect: CGRect(x: 10, y: 10, width: 100, height: 100),
                                        tolerance: 6) == .topLeft,
               "handle hit testing finds the corner")

        let head = ScreenshotSupport.arrowHead(from: CGPoint(x: 0, y: 0),
                                               to: CGPoint(x: 100, y: 0),
                                               strokeWidth: 4)
        expect(head.left.x < 100 && head.right.x < 100 && head.left.y != head.right.y,
               "arrow heads open behind the tip")
        let shortHead = ScreenshotSupport.arrowHead(from: .zero,
                                                    to: CGPoint(x: 10, y: 0),
                                                    strokeWidth: 14)
        expect(shortHead.left.x >= 0 && shortHead.right.x >= 0,
               "a short arrow head never extends behind its tail")
        let arrowPath = ScreenshotSupport.arrowSilhouette(from: CGPoint(x: 100, y: 20),
                                                          to: CGPoint(x: 100, y: 300),
                                                          strokeWidth: 40)
        expect(arrowPath.contains(CGPoint(x: 100, y: 30),
                                  using: .winding,
                                  transform: .identity),
               "the arrow tail stays filled where its cap meets the shaft")
        expect(arrowPath.contains(CGPoint(x: 100, y: 190),
                                  using: .winding,
                                  transform: .identity),
               "the arrow stays filled where its shaft meets the head")
        expect(abs(ScreenshotSupport.distance(from: CGPoint(x: 50, y: 10),
                                              toSegment: CGPoint(x: 0, y: 0),
                                              CGPoint(x: 100, y: 0)) - 10) < 0.001,
               "segment distance measures perpendicular offset")
        expect(ScreenshotSupport.distance(from: CGPoint(x: -30, y: 0),
                                          toSegment: CGPoint(x: 0, y: 0),
                                          CGPoint(x: 100, y: 0)) == 30,
               "segment distance clamps to the endpoints")

        expect(ScreenshotSupport.pixelBlockSize(for: CGSize(width: 5500, height: 3600)) == 65
                && ScreenshotSupport.pixelBlockSize(for: CGSize(width: 200, height: 120)) == 10,
               "pixelation blocks scale with the capture and never get too fine")
        expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 2)
                == CGSize(width: 400, height: 300),
               "the 1x option halves a Retina capture")
        expect(ScreenshotSupport.downscaledSize(pixelSize: CGSize(width: 800, height: 600), scale: 1)
                == CGSize(width: 800, height: 600),
               "a 1x capture never downscales")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 100, height: 100), factor: 0.5) == 24,
               "backdrop padding keeps a floor for tiny captures")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 1)
                == (4000 * 0.175).rounded(),
               "the margin slider grows the backdrop padding")
        expect(ScreenshotSupport.backdropPadding(for: CGSize(width: 4000, height: 4000), factor: 0)
                == 140,
               "margin zero still keeps a small frame")
        expect(ScreenshotSupport.BackdropID.allCases.filter { $0 != .none }
                .allSatisfy { $0.stops.count == 2 },
               "every backdrop gradient has its two stops")
        expect(ScreenshotSupport.ColorID.sanitized("bogus") == .red
                && ScreenshotSupport.StrokeID.sanitized(nil) == .medium,
               "style choices sanitize to safe defaults")
        expect(ScreenshotSupport.StickerID.sanitized("bogus") == .check
                && ScreenshotSupport.StickerID.allCases.count == 12,
               "stickers keep a safe default and a compact built-in set")
        let stickerRect = ScreenshotSupport.stickerRect(
            centeredAt: CGPoint(x: 5, y: 5),
            side: 40,
            within: CGRect(x: 0, y: 0, width: 100, height: 80))
        expect(stickerRect == CGRect(x: 0, y: 0, width: 40, height: 40),
               "a sticker placed at an edge stays fully inside the image")

        expect(ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 0) == 0
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 1) == 180
                && ScreenshotSupport.cardCornerRadius(for: CGSize(width: 1600, height: 900), factor: 2) == 180,
               "card corner radius clamps and scales with the short side")
        expect(abs(ScreenshotSupport.backdropBlurRadius(
                    for: CGSize(width: 1600, height: 900), factor: 1) - 31.5) < 0.001
                && ScreenshotSupport.backdropBlurRadius(
                    for: CGSize(width: 1600, height: 900), factor: -1) == 0,
               "background blur scales with the canvas and clamps its slider")
        let solidStyle = ScreenshotSupport.BackdropStyle(kind: .solid, colors: [[0.2, 0.4, 0.9]],
                                                         padding: 0.3, cornerRadius: 0.2,
                                                         blur: 0.6)
        let solidRoundTrip = ScreenshotSupport.BackdropStyle.decoded(solidStyle.encoded())
        expect(solidRoundTrip == solidStyle, "a backdrop style round-trips through JSON")
        let legacyStyle = ScreenshotSupport.BackdropStyle.decoded(
            #"{"kind":"solid","colors":[[0.2,0.4,0.9]],"padding":0.3,"cornerRadius":0.2}"#)
        expect(legacyStyle.kind == .solid && legacyStyle.blur == 0,
               "backgrounds saved before blur keep decoding without changing")
        expect(ScreenshotSupport.BackdropStyle.decoded(nil).kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("").kind == .none
                && ScreenshotSupport.BackdropStyle.decoded("not json").kind == .none,
               "a missing or broken backdrop style falls back to none")
        expect(ScreenshotSupport.BackdropStyle().cornerRadius == 0,
               "the default backdrop leaves capture corners unchanged")
        let brokenSolid = ScreenshotSupport.BackdropStyle(kind: .solid, colors: nil)
        expect(brokenSolid.sanitized().kind == .none,
               "a solid style without colors demotes to none")
        let wildSliders = ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "ocean",
                                                          padding: 9, cornerRadius: -3, blur: 8)
        expect(wildSliders.sanitized().padding == 1
                && wildSliders.sanitized().cornerRadius == 0
                && wildSliders.sanitized().blur == 1,
               "backdrop sliders clamp to their range")
        expect(ScreenshotSupport.BackdropStyle(kind: .preset, presetID: "bogus").sanitized().kind == .none
                && ScreenshotSupport.BackdropStyle(kind: .image, imagePath: nil).sanitized().kind == .none,
               "unknown presets and missing image paths demote to none")
        expect(ScreenshotSupport.BackdropStyle(kind: .gradient,
                                               colors: [[0, 2, -1], [0.5, 0.5, 0.5]])
                .sanitized().colors?.first == [0, 1, 0],
               "gradient colors clamp component by component")

        let presetList = [solidStyle,
                          ScreenshotSupport.BackdropStyle(kind: .gradient,
                                                          colors: [[1, 0, 0], [0, 0, 1]])]
        let decodedPresets = ScreenshotSupport.decodedBackdropPresets(
            ScreenshotSupport.encodedBackdropPresets(presetList))
        expect(decodedPresets == presetList, "saved backdrops round-trip through JSON")
        expect(ScreenshotSupport.decodedBackdropPresets("junk").isEmpty
                && ScreenshotSupport.decodedBackdropPresets(nil).isEmpty,
               "broken preset lists decode to empty")
        let overflow = Array(repeating: solidStyle, count: 40)
        expect(ScreenshotSupport.decodedBackdropPresets(
                ScreenshotSupport.encodedBackdropPresets(overflow)).count
                == ScreenshotSupport.backdropPresetLimit,
               "saved backdrops cap at the presets limit")
        let wordBoxes = [CGRect(x: 0, y: 0, width: 40, height: 10),
                         CGRect(x: 50, y: 0, width: 40, height: 10),
                         CGRect(x: 0, y: 20, width: 40, height: 10)]
        expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 60, y: 5),
                                               boxes: wordBoxes) == [0, 1],
               "a drag across a line selects the words it crosses")
        expect(ScreenshotSupport.wordSelection(anchor: CGPoint(x: 5, y: 5),
                                               current: CGPoint(x: 10, y: 25),
                                               boxes: wordBoxes) == [0, 2],
               "a drag across lines selects into the next line")
        let recognizedWords = [
            ScreenshotSupport.RecognizedWord(text: "ola", rect: wordBoxes[0], line: 0),
            ScreenshotSupport.RecognizedWord(text: "mundo", rect: wordBoxes[1], line: 0),
            ScreenshotSupport.RecognizedWord(text: "linha", rect: wordBoxes[2], line: 1),
        ]
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [1, 0]) == "ola mundo",
               "selected words join in reading order with spaces")
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [2, 0]) == "ola\nlinha",
               "line changes become newlines")
        expect(ScreenshotSupport.joinedWords(recognizedWords, selected: [9]).isEmpty
                && ScreenshotSupport.joinedWords(recognizedWords, selected: []).isEmpty,
               "out of range or empty selections copy nothing")
        let defaultScreenshotTools = ScreenshotSupport.Tool.allCases
        expect(defaultScreenshotTools.count == 13
                && Array(defaultScreenshotTools.prefix(9))
                    == [.select, .arrow, .pixelate, .crop, .text, .sticker,
                        .rect, .highlight, .freehand],
               "the screenshot rail leads with the nine most useful numbered tools")
        let customScreenshotTools = ScreenshotSupport.Tool.ordered(
            from: "crop,arrow,arrow,invalid")
        expect(Array(customScreenshotTools.prefix(2)) == [.crop, .arrow]
                && customScreenshotTools.count == 13
                && Set(customScreenshotTools).count == 13,
               "a saved screenshot tool order drops invalid duplicates and appends missing tools")
        expect(ScreenshotSupport.Tool.shortcutTool(number: 1,
                                                   orderRaw: nil,
                                                   enabled: true) == .select
                && ScreenshotSupport.Tool.shortcutTool(number: 3,
                                                       orderRaw: nil,
                                                       enabled: true) == .pixelate
                && ScreenshotSupport.Tool.shortcutTool(number: 9,
                                                       orderRaw: nil,
                                                       enabled: true) == .freehand
                && ScreenshotSupport.Tool.shortcutTool(number: 1,
                                                       orderRaw: nil,
                                                       enabled: false) == nil
                && ScreenshotSupport.Tool.shortcutTool(number: 10,
                                                       orderRaw: nil,
                                                       enabled: true) == nil,
               "number keys 1 through 9 follow tool order and can be disabled together")
        expect(ScreenshotSupport.Tool.shortcutNumber(for: .crop,
                                                     orderRaw: "arrow,crop",
                                                     enabled: true) == 2
                && ScreenshotSupport.Tool.shortcutNumber(for: .redact,
                                                         orderRaw: nil,
                                                         enabled: true) == nil,
               "the rail exposes only the first nine configured shortcut numbers")
        let cropAssignedFirst = ScreenshotSupport.Tool.assigningShortcut(
            1, to: .crop, orderRaw: nil)
        let selectWithoutShortcut = ScreenshotSupport.Tool.assigningShortcut(
            nil, to: .select, orderRaw: nil)
        expect(cropAssignedFirst.first == .crop
                && ScreenshotSupport.Tool.shortcutNumber(
                    for: .crop,
                    orderRaw: cropAssignedFirst.map(\.rawValue).joined(separator: ","),
                    enabled: true) == 1
                && selectWithoutShortcut.firstIndex(of: .select) == 9
                && ScreenshotSupport.Tool.shortcutNumber(
                    for: .select,
                    orderRaw: selectWithoutShortcut.map(\.rawValue).joined(separator: ","),
                    enabled: true) == nil,
               "the visible shortcut menu assigns a numbered slot or removes a tool from 1 through 9")

        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 50, y: 40),
            imageSize: CGSize(width: 100, height: 80))
            == CGRect(x: 44, y: 34, width: 13, height: 13),
               "the crop loupe centers its source pixels around an inner grip")
        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 80),
            imageSize: CGSize(width: 100, height: 80))
            == CGRect(x: 87, y: 67, width: 13, height: 13),
               "the crop loupe keeps a full sample at the bottom right edge")
        // An even sample side has no middle cell. The sampled pixel then sat
        // half a cell right of and below the frame's centre, and the ring drawn
        // around it followed, which is what read as an off-centre reticle.
        for loupeZoom in [ScreenshotSupport.captureLoupeMinZoom, 1, 2,
                          ScreenshotSupport.captureLoupeMaxZoom] {
            let side = ScreenshotSupport.captureLoupeSampleSide(zoom: loupeZoom)
            let pointer = CGPoint(x: 80.4, y: 50.7)
            let image = CGSize(width: 160, height: 100)
            let sample = ScreenshotSupport.cropLoupeSampleRect(around: pointer,
                                                               imageSize: image,
                                                               sideLength: side)
            let loupeFrame = CGRect(x: 0, y: 0, width: 70, height: 70)
            let marked = ScreenshotSupport.captureLoupeTargetPixelRect(around: pointer,
                                                                       source: sample,
                                                                       frame: loupeFrame)
            expectClose(Double(marked.midX), Double(loupeFrame.midX),
                        "the loupe marks the pixel in the middle of its frame across the zoom range")
            expectClose(Double(marked.midY), Double(loupeFrame.midY),
                        "the marked pixel is as centred vertically as it is horizontally")
        }
        // The editor's crop loupe marks an edge between pixels, so it needs the
        // opposite parity: an even side puts that edge in the middle of the
        // frame, where an odd one leaves it half a cell short of centre.
        let cropEdgeSample = ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 60),
            imageSize: CGSize(width: 400, height: 300),
            sideLength: 14,
            centredOnPixel: false)
        expect(cropEdgeSample == CGRect(x: 93, y: 53, width: 14, height: 14)
                && cropEdgeSample.midX == 100 && cropEdgeSample.midY == 60,
               "the crop loupe centres its sample on the handle's edge, not on a pixel cell")
        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: CGPoint(x: 100, y: 60),
            imageSize: CGSize(width: 400, height: 300),
            sideLength: 13,
            centredOnPixel: false).width == 14,
               "an odd side grows to the next even one when the loupe centres on an edge")

        expect(ScreenshotSupport.cropLoupeSampleRect(
            around: .zero,
            imageSize: CGSize(width: 8, height: 5))
            == CGRect(x: 0, y: 0, width: 8, height: 5),
               "the crop loupe safely shrinks only for images smaller than its sample")
        expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: CGPoint(x: 50.5, y: 40.2),
            source: CGRect(x: 43, y: 33, width: 14, height: 14),
            frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 35, y: 35, width: 5, height: 5),
               "the loupe highlights one whole source pixel, not the pointer's sub-pixel position")
        expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: CGPoint(x: 100, y: 80),
            source: CGRect(x: 86, y: 66, width: 14, height: 14),
            frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 65, y: 65, width: 5, height: 5),
               "a pointer on the far display edge highlights the last pixel the picker can read")
        // The pixel the loupe marks and the pixel `confirmColor` copies come
        // from two independent expressions. Sweeping the whole overlay at
        // every zoom is what keeps them from drifting apart by one pixel.
        let sampledImageSize = CGSize(width: 160, height: 100)
        let sampledViewSize = CGSize(width: 320, height: 200)
        let sampledFrame = CGRect(x: 20, y: 30, width: 70, height: 70)
        var loupeAimFailure: String?
        for zoom in [ScreenshotSupport.captureLoupeMinZoom, 1, ScreenshotSupport.captureLoupeMaxZoom] {
            for stepX in 0...128 {
                for stepY in 0...80 {
                    let pixelPoint = ScreenshotSupport.imagePixelPoint(
                        fromView: CGPoint(x: CGFloat(stepX) * 2.5, y: CGFloat(stepY) * 2.5),
                        viewSize: sampledViewSize,
                        imageSize: sampledImageSize)
                    let source = ScreenshotSupport.cropLoupeSampleRect(
                        around: pixelPoint,
                        imageSize: sampledImageSize,
                        sideLength: ScreenshotSupport.captureLoupeSampleSide(zoom: zoom))
                    let highlight = ScreenshotSupport.captureLoupeTargetPixelRect(
                        around: pixelPoint, source: source, frame: sampledFrame)
                    let cellWidth = sampledFrame.width / source.width
                    let cellHeight = sampledFrame.height / source.height
                    let markedX = source.minX + ((highlight.minX - sampledFrame.minX) / cellWidth).rounded()
                    let markedY = source.minY + ((highlight.minY - sampledFrame.minY) / cellHeight).rounded()
                    // Copied verbatim from `confirmColor`.
                    let copiedX = CGFloat(min(max(Int(pixelPoint.x.rounded(.down)), 0),
                                              Int(sampledImageSize.width) - 1))
                    let copiedY = CGFloat(min(max(Int(pixelPoint.y.rounded(.down)), 0),
                                              Int(sampledImageSize.height) - 1))
                    if markedX != copiedX || markedY != copiedY {
                        loupeAimFailure = "at \(pixelPoint) zoom \(zoom) the loupe marks "
                            + "(\(markedX), \(markedY)) but the picker copies (\(copiedX), \(copiedY))"
                    }
                    if !sampledFrame.insetBy(dx: -0.001, dy: -0.001).contains(highlight) {
                        loupeAimFailure = "at \(pixelPoint) zoom \(zoom) the highlight leaves the loupe"
                    }
                }
            }
        }
        expect(loupeAimFailure == nil,
               loupeAimFailure ?? "the loupe highlight marks the pixel the color picker copies")
        expect(ScreenshotSupport.captureLoupeTargetPixelRect(
            around: .zero, source: .zero, frame: CGRect(x: 0, y: 0, width: 70, height: 70))
            == CGRect(x: 0, y: 0, width: 70, height: 70),
               "an empty sample leaves the loupe highlight harmless instead of dividing by zero")
        expectClose(ScreenshotSupport.captureLoupeZoom(1, adjustedBy: 1), 1.15,
                    "scrolling up zooms the capture loupe in")
        expectClose(ScreenshotSupport.captureLoupeZoom(0.5, adjustedBy: -1), 0.5,
                    "capture loupe zoom stays above its minimum")
        expectClose(ScreenshotSupport.captureLoupeZoom(10, adjustedBy: 1),
                    ScreenshotSupport.captureLoupeMaxZoom,
                    "capture loupe zoom stays below its maximum")
        expectClose(ScreenshotSupport.captureLoupeMaxZoom,
                    ScreenshotSupport.captureLoupeBaseSampleSide
                        / ScreenshotSupport.captureLoupeMinSampleSide,
                    "the zoom ceiling is derived from the smallest useful sample")
        expectClose(ScreenshotSupport.captureLoupeZoom(4, adjustedBy: 1),
                    ScreenshotSupport.captureLoupeMaxZoom,
                    "zoom reaches the three-pixel sample without a dead range above it")
        expectClose(ScreenshotSupport.captureLoupeSampleSide(zoom: 2), 7,
                    "higher capture loupe zoom samples fewer source pixels")
        expectClose(ScreenshotSupport.captureLoupeSampleSide(zoom: 0.5), 27,
                    "zooming the loupe out widens the sample")
        expectClose(ScreenshotSupport.captureLoupeSampleSide(
            zoom: ScreenshotSupport.captureLoupeMaxZoom), 3,
                    "maximum loupe zoom keeps a three pixel sample around the pointer")
        expect([0.5, 1, 2, 4, ScreenshotSupport.captureLoupeMaxZoom].allSatisfy { zoom in
            let side = ScreenshotSupport.captureLoupeSampleSide(zoom: zoom)
            return side.truncatingRemainder(dividingBy: 2) == 1
        }, "every loupe sample side is odd so an exact center pixel exists")
        expect(ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 13)
                && !ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 27)
                && !ScreenshotSupport.captureLoupeGridVisible(
                    frameSide: ScreenshotSupport.captureLoupeFrameSide, sampleSide: 0),
               "the loupe pixel grid appears only when cells are readable")
        expect(ScreenshotSupport.captureLoupeNudge(dx: 1, dy: 0, fast: false, scale: 2)
                == CGPoint(x: 0.5, y: 0),
               "an arrow nudge moves exactly one device pixel on Retina")
        expect(ScreenshotSupport.captureLoupeNudge(dx: 0, dy: -1, fast: true, scale: 2)
                == CGPoint(x: 0, y: -5),
               "a shifted nudge covers ten device pixels")
        expect(ScreenshotSupport.captureLoupeNudge(dx: -1, dy: 1, fast: false, scale: 0)
                == CGPoint(x: -1, y: 1),
               "a missing display scale falls back to whole points")

        expect(Defaults.registeredDefaults[DefaultsKey.screenshotFreeze] as? Bool == true,
               "the screen freezes during selection by default")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotShowLastRegion] as? Bool == true,
               "the previous capture outline stays visible by default, as it always was")
        expect(Defaults.registeredDefaults[DefaultsKey.screenshotLoupeStartsOn] as? Bool == false,
               "the always-on loupe is an opt-in and ships off")
        expect(ScreenshotShareDuration.allCases.map(\.rawValue) == [3_600, 21_600, 86_400],
               "temporary links allow only one, six or twenty-four hours")
        let testShareEndpoint = ScreenshotSharingSupport.endpoint(
            bundleIdentifier: ScreenshotSharingSupport.developerBundleIdentifier,
            developerOverride: "https://test.example/")
        expect(testShareEndpoint.absoluteString == "https://test.example"
                && ScreenshotSharingSupport.endpoint(
                    bundleIdentifier: "com.chikit.utils",
                    developerOverride: "https://test.example").absoluteString
                    == ScreenshotSharingSupport.productionEndpoint.absoluteString
                && ScreenshotSharingSupport.endpoint(
                    bundleIdentifier: ScreenshotSharingSupport.developerBundleIdentifier,
                    developerOverride: "http://test.example")
                    == ScreenshotSharingSupport.productionEndpoint,
               "only the Developer build accepts a valid HTTPS test endpoint")
        expect(ScreenshotSharingSupport.uploadURL(endpoint: testShareEndpoint,
                                                  duration: .sixHours)?.absoluteString
                == "https://test.example/v1/screenshots?expiresIn=21600",
               "sharing builds the fixed upload route and expiration query")
        let shareNow = Date(timeIntervalSince1970: 1_000)
        let shareResponse = ScreenshotShareResponse(
            id: String(repeating: "a", count: 32),
            viewPath: "/s/\(String(repeating: "a", count: 32))",
            expiresAt: "1970-01-01T01:16:40.125Z",
            deleteToken: String(repeating: "b", count: 43))
        expect(ScreenshotSharingSupport.record(response: shareResponse,
                                                endpoint: testShareEndpoint,
                                                now: shareNow)?.url.absoluteString
                == "https://test.example/s/\(String(repeating: "a", count: 32))",
               "a valid service response becomes an owner-held link record")
        let forgedShareResponse = ScreenshotShareResponse(
            id: "guessable",
            viewPath: "/s/guessable",
            expiresAt: "1970-01-01T01:16:40.125Z",
            deleteToken: "short")
        expect(ScreenshotSharingSupport.record(response: forgedShareResponse,
                                                endpoint: testShareEndpoint,
                                                now: shareNow) == nil,
               "guessable ids and short deletion tokens are rejected")
        let recentCaptureIDs = (0..<14).map { _ in UUID() }
        expect(ScreenshotSupport.cappedRecentCaptureIDs(recentCaptureIDs)
                == Array(recentCaptureIDs.prefix(12))
                && ScreenshotSupport.recentCaptureLimit == 12,
               "recent captures keeps only the newest bounded set")
        let oversizedCaptureIDs = Array(recentCaptureIDs.prefix(3))
        expect(ScreenshotSupport.cappedRecentCaptureIDs(
            oversizedCaptureIDs,
            screenshotBytes: [
                oversizedCaptureIDs[0]: ScreenshotSupport.recentCaptureMaximumBytes - 1,
                oversizedCaptureIDs[1]: 2,
            ]) == [oversizedCaptureIDs[0], oversizedCaptureIDs[2]],
               "recent captures keeps the latest screenshot and respects its disk budget")
        expect(ScreenshotSupport.clipboardImageScale(
            pixelSize: CGSize(width: 1200, height: 800),
            pointSize: CGSize(width: 600, height: 400)) == 2,
               "copied images preserve a consistent Retina scale")
        expect(ScreenshotSupport.clipboardImageScale(
            pixelSize: CGSize(width: 1200, height: 800),
            pointSize: CGSize(width: 600, height: 800)) == 1,
               "copied images with inconsistent metadata safely use 1x")

        // An unpinned borderless Menu claims the free width of its row on
        // macOS 15 and starves whatever shares that row (issue #569), so the
        // rule is checked for every borderless menu in the app rather than for
        // the one this fix touches. Kill Process is the one
        // deliberate exception: its row controls take a shared minimum width
        // so the Kill button and the menu beside it line up down the list.
        let borderlessMenuException = "KillProcess/KillProcessView"
        var unpinnedBorderlessMenus: [String] = []
        let uiFiles = FileManager.default
            .enumerator(atPath: "Sources/Vorssaint/UI")?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.contains(" 2") } ?? []
        for file in uiFiles.sorted() {
            let path = "Sources/Vorssaint/UI/\(file)"
            guard !file.contains(borderlessMenuException),
                  let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated()
            where line.contains(".menuStyle(.borderlessButton)") {
                // Read to the end of the menu's own modifier chain: the next
                // line that is neither a modifier nor a comment belongs to
                // something else.
                var pinned = false
                var cursor = index + 1
                while cursor < lines.count {
                    let text = lines[cursor].trimmingCharacters(in: .whitespaces)
                    guard text.hasPrefix(".") || text.hasPrefix("//") else { break }
                    if text.hasPrefix(".fixedSize()") { pinned = true; break }
                    cursor += 1
                }
                if !pinned { unpinnedBorderlessMenus.append("\(file):\(index + 1)") }
            }
        }
        // The file count is part of the rule: an enumerator that finds nothing
        // would leave the list empty and pass while checking no menu at all.
        expect(!uiFiles.isEmpty && unpinnedBorderlessMenus.isEmpty,
               "every borderless menu keeps its own size, across \(uiFiles.count) "
               + "scanned files: \(unpinnedBorderlessMenus)")

        // `waitUntilAllOperationsAreFinished` has no deadline, and the window
        // walk that used it runs on the main thread while its operations run on
        // the shared dispatch pool. Once unrelated work had taken every worker
        // in that pool, not one operation started and the wait never returned,
        // taking the whole app with it (issue #971). The call is unusable here
        // for that reason, so the rule is the absence of it rather than the one
        // caller that was found holding it.
        var unboundedOperationWaits: [String] = []
        let appSources = FileManager.default
            .enumerator(atPath: "Sources/Vorssaint")?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.contains(" 2") } ?? []
        for file in appSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            for (index, line) in source.components(separatedBy: "\n").enumerated()
            where line.contains("waitUntilAllOperationsAreFinished") {
                unboundedOperationWaits.append("\(file):\(index + 1)")
            }
        }
        expect(!appSources.isEmpty && unboundedOperationWaits.isEmpty,
               "no operation queue is waited on without a deadline: \(unboundedOperationWaits)")

        // Asking an application element for its role switches a Chromium app's
        // renderers into full accessibility mode for the rest of the process's
        // life (issue #953). It was fixed at the liveness probe, then found
        // again in the walk up an element's parents, where the chain above a
        // window is the application element — so the rule is the absence of
        // that read anywhere, rather than one grep per door somebody noticed.
        // This is a text scan, not dataflow: it knows an element is an
        // application element only when the same file names it in a `let x =
        // AXUIElementCreateApplication(...)`, and it reads the role attribute
        // and its element off one line. An application element handed to a
        // helper, stored in a property, or passed inline is still on review to
        // catch; both reads found so far were written the direct way.
        // Both scans below report real line numbers, so neither may filter its
        // array before enumerating: comments drop out in the predicate instead.
        func isCommentLine(_ line: String) -> Bool {
            line.trimmingCharacters(in: .whitespaces).hasPrefix("//")
        }
        var applicationRoleReads: [String] = []
        for file in appSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            var applicationElements: Set<String> = []
            for line in lines where line.contains("AXUIElementCreateApplication(") {
                let assigned = (line.components(separatedBy: "=").first ?? "")
                    .trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                guard assigned.count == 2, assigned[0] == "let" || assigned[0] == "var" else { continue }
                applicationElements.insert(assigned[1])
            }
            for (index, line) in lines.enumerated()
            where line.contains("kAXRoleAttribute")
                && !isCommentLine(line)
                && applicationElements.contains(where: { line.contains("(\($0), ") }) {
                applicationRoleReads.append("\(file):\(index + 1)")
            }
        }
        expect(!appSources.isEmpty && applicationRoleReads.isEmpty,
               "no application element is ever asked for its role: \(applicationRoleReads)")
        // The scan above cannot see the other way in: a walk up kAXParent asks
        // `parent` for its role, and the application element is what sits above
        // the last window, so the element it reads is never named after one.
        // Two files carried the same walk, so the rule is that anywhere doing
        // it stops at the application element first, rather than a pin per copy.
        var unguardedParentWalks: [String] = []
        for file in appSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            // Per occurrence and in order: a guard sitting anywhere in the file
            // would let a second walk go unguarded, and one written after the
            // read would let the read happen first, which is the whole failure.
            for (index, line) in lines.enumerated()
            where line.contains("role(of: parent)") && !isCommentLine(line) {
                // The window reads raw lines so the report above stays in real
                // line numbers; a commented-out guard must not count as one.
                let guarded = lines[max(0, index - 3)..<index]
                    .contains { $0.contains("isApplicationElement(parent)") && !isCommentLine($0) }
                if !guarded { unguardedParentWalks.append("\(file):\(index + 1)") }
            }
        }
        expect(!appSources.isEmpty && unguardedParentWalks.isEmpty,
               "a walk up the parent chain stops at the application element: \(unguardedParentWalks)")

        // MARK: Super key (issue #330)

        let mappingReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        100000a85   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
        )
        """
        let partiallyMappedReport = mappingReport + """

        100000a86   UserKeyMapping   (
        )
        """
        let heterogeneousUserMappingReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        100000a85   UserKeyMapping   (
        )
        """
        let ownedDifferenceReport = """
        RegistryID  Key                   Value
        100000a84   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771181;
                HIDKeyboardModifierMappingSrc = 30064771129;
            }
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        100000a85   UserKeyMapping   (
                {
                HIDKeyboardModifierMappingDst = 30064771125;
                HIDKeyboardModifierMappingSrc = 30064771172;
            }
        )
        """
        let noActionReport = """
        HIDKeyboardModifierMappingPairs = {
          HIDKeyboardModifierMappingSrc = 30064771129;
          HIDKeyboardModifierMappingDst = "-1";
        }
        """

        // MARK: Mouse app exceptions (issue #358)

        expect(Defaults.sanitizedBundleIdentifierList(["  com.example.a  ", "", "com.example.a", "com.example.b"])
                == ["com.example.a", "com.example.b"],
               "the exception list drops blanks, spaces and repeats")

        let exceptionSet: Set<String> = ["com.example.modeler"]
        // A program started from a launcher — the Java process behind a game
        // is the reported one — has no bundle identifier at all, so the file
        // being run stands in as its identity (issue #1009). An app that has
        // an identifier keeps answering only to that, so nothing already
        // listed changes meaning.
        expect(InstalledApps.name(for: "/opt/game/runtime/bin/java") == "java",
               "a listed program path is shown by its file name, not the whole path")

        // The stored path is the one the file sheet handed back and the
        // matched one is the file the running program reports, and the same
        // file arrives at the two ends under different names as soon as
        // anything on the way is a link — measured on this Mac, the sheet
        // answers /private/tmp/… for a file the running program answers
        // /tmp/… for. Both ends resolve, so they meet.
        let identityRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("chikit-identity-\(getpid())", isDirectory: true)
        let runtimeBinary = identityRoot.appendingPathComponent("runtime/bin/launcher")
        try? FileManager.default.createDirectory(at: runtimeBinary.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: runtimeBinary.path, contents: Data())
        let linkedBinary = identityRoot.appendingPathComponent("launcher")
        try? FileManager.default.createSymbolicLink(at: linkedBinary, withDestinationURL: runtimeBinary)
        // A file sheet that takes programs can be walked into a bundle, and
        // what is stored has to be what the system will report once the file
        // runs. Measured on this Mac: a bundle's own executable run straight
        // from disk is reported as com.example.withid, while a runtime shipped
        // deeper in that same bundle — the shape issue #1009 is about — is
        // reported with no identifier and stays a path. Filing that runtime
        // under the app above it would break the case this all exists for.
        func makeTestBundle(_ name: String, identifier: String?) -> URL {
            let bundle = identityRoot.appendingPathComponent("\(name).app")
            for file in ["Contents/MacOS/\(name)", "Contents/runtime/bin/java"] {
                let url = bundle.appendingPathComponent(file)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            var info: [String: Any] = ["CFBundleExecutable": name, "CFBundlePackageType": "APPL"]
            if let identifier { info["CFBundleIdentifier"] = identifier }
            if let plist = try? PropertyListSerialization.data(fromPropertyList: info,
                                                               format: .xml,
                                                               options: 0) {
                try? plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
            }
            return bundle
        }
        let namedBundle = makeTestBundle("Modeler", identifier: "com.example.modeler")
        let namelessBundle = makeTestBundle("Bare", identifier: nil)
        let bundledRuntime = namedBundle.appendingPathComponent("Contents/runtime/bin/java")
        try? FileManager.default.removeItem(at: identityRoot)

        // The list sanitizer runs over stored entries, and a file name may
        // legally end in a space: trimming a path would look for a spelling
        // the running program never reports, so only an identifier is trimmed.
        expect(Defaults.sanitizedBundleIdentifierList(["/opt/game/bin/java ", " com.example.a "])
                == ["/opt/game/bin/java ", "com.example.a"],
               "a stored path keeps its exact file name while an identifier is trimmed")

        expect(InstalledApps.location(for: "com.example.modeler") == nil,
               "a bundle identifier names its app on its own and carries no location")
        expect(InstalledApps.location(for: NSHomeDirectory() + "/runtimes/zulu-8.jre/bin/java")
                == "~/runtimes/zulu-8.jre/bin",
               "a path identity is located by its directory, spelled from home")
        expect(InstalledApps.location(for: "/opt/game/bin/java") == "/opt/game/bin",
               "a path outside home keeps its absolute directory")

        // Both ends of that agreement live outside this binary: the picker
        // stores from AppBundleList and the taps match from MouseAppExceptions.
        // An identity resolved at one end and taken raw at the other silently
        // matches nothing (issue #1009), so what each side may hand on is
        // pinned rather than the spelling it happens to use today — a second
        // way into the list, dropping a file onto it among them, has to go
        // through the same resolver as the sheet does.
        let pickerLines = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/AppBundleList.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
        var resolvedNames: Set<String> = []
        for line in pickerLines where line.contains("= InstalledApps.pickedIdentity(") {
            guard let bound = line.components(separatedBy: "let ").last?
                    .components(separatedBy: " =").first else { continue }
            resolvedNames.insert(bound.trimmingCharacters(in: .whitespaces))
        }
        var resolvedAddSites: [String] = []
        var rawAddSites: [String] = []
        for (index, line) in pickerLines.enumerated()
        where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") && line.contains("onAdd(") {
            let added = (line.components(separatedBy: "onAdd(").last?
                .components(separatedBy: ")").first ?? "").trimmingCharacters(in: .whitespaces)
            if resolvedNames.contains(added) {
                resolvedAddSites.append("AppBundleList.swift:\(index + 1)")
            } else {
                rawAddSites.append("AppBundleList.swift:\(index + 1) adds \(added)")
            }
        }
        expect(!resolvedAddSites.isEmpty && rawAddSites.isEmpty,
               "every value the picker adds is one the support enum resolved: \(rawAddSites)")

        // A list row's location caption is what tells path identities apart —
        // every bundled runtime displays as "java" (issue #1009) — and sibling
        // runtimes differ only after a long shared directory prefix, so the
        // caption must truncate from the HEAD: cutting the middle or tail
        // would hide the one component that differs. AppBundleList is not
        // compiled into this binary, so the shape is pinned here.
        var locationSites: [Int] = []
        var headTruncationSites: [Int] = []
        for (index, line) in pickerLines.enumerated()
        where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            if line.contains("InstalledApps.location(for:") { locationSites.append(index + 1) }
            if line.contains(".truncationMode(.head)") { headTruncationSites.append(index + 1) }
        }
        expect(!locationSites.isEmpty && !headTruncationSites.isEmpty,
               "a path identity row shows where its file sits and truncates from the head: "
                   + "\(locationSites) \(headTruncationSites)")

        // The leading-slash test IS the rule that tells a stored path from a
        // bundle identifier. A second spelling of it drifts the day the rule
        // learns a new shape — a ~ path, a file URL — so every file that
        // handles an identity asks isExecutablePathIdentity instead of
        // re-testing the prefix.
        var slashRuleSites: [String] = []
        let pointer = CGPoint(x: 100, y: 100)
        for language in AppLanguage.allCases {
            let strings = FeatureStrings.clipboardIgnoredApps(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 4 && values.allSatisfy { !$0.isEmpty },
                   "every clipboard skip list string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible clipboard skip list strings (\(language.rawValue))")
        }

        expect(FinderRenameSupport.acceptsFocusedRole("AXOutline")
                && !FinderRenameSupport.acceptsFocusedRole("AXTextField")
                && !FinderRenameSupport.acceptsFocusedRole("AXTextArea")
                && !FinderRenameSupport.acceptsFocusedRole(nil),
               "Finder rename only acts outside editable fields with a known focus")

        for language in AppLanguage.allCases {
            let strings = FeatureStrings.diskExclusions(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 6 && values.allSatisfy { !$0.isEmpty },
                   "every disk exclusion string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in visible disk exclusion strings (\(language.rawValue))")
        }

        for language in AppLanguage.allCases {
            let strings = WindowDirectionalStrings.localized(language)
            let values = Mirror(reflecting: strings).children.compactMap { $0.value as? String }
            expect(values.count == 2 && values.allSatisfy { !$0.isEmpty },
                   "every directional layout string is set for \(language.rawValue)")
            expect(values.allSatisfy { !$0.contains("—") },
                   "no em-dash in directional layout strings (\(language.rawValue))")
        }

        // MARK: Settings backup

        let backupKeys = SettingsBackupSupport.exportKeys()
        expect(backupKeys.contains(DefaultsKey.launchAtLoginWanted),
               "the launch at login choice travels with the settings backup")
        expect(backupKeys.contains(DefaultsKey.appearance),
               "the light or dark choice travels with the settings backup")
        expect(backupKeys.contains(DefaultsKey.finderRenameEnabled)
                && backupKeys.contains(DefaultsKey.finderRenameShortcut),
               "the Finder rename choice and shortcut travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.windowGestureEnabled)
                && backupKeys.contains(DefaultsKey.windowEdgeSnapEnabled)
                && backupKeys.contains(DefaultsKey.windowGestureModifiers)
                && backupKeys.contains(DefaultsKey.windowGestureRaiseWindow)
                && backupKeys.contains(DefaultsKey.windowLayoutShortcutPreviousDisplay)
                && backupKeys.contains(DefaultsKey.windowLayoutShortcutMarginMaximize),
               "window layout choices travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.whatsAppDownloadsEnabled)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsAutomaticEnabled)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsCategories)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsRetentionDays)
                && backupKeys.contains(DefaultsKey.whatsAppDownloadsNotify),
               "portable WhatsApp cleanup choices travel with settings backup")
        expect(backupKeys.contains(DefaultsKey.whatsAppOrganizerEnabled)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerDelayMinutes)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerCategories)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerLayout)
                && backupKeys.contains(DefaultsKey.whatsAppOrganizerDuplicateAction),
               "portable WhatsApp organizer choices travel with settings backup")
        expect(!backupKeys.contains(DefaultsKey.whatsAppDownloadsAutomaticStartDate)
                && !backupKeys.contains(DefaultsKey.whatsAppDownloadsLastCleanup)
                && !backupKeys.contains(DefaultsKey.whatsAppDownloadsExclusions)
                && !backupKeys.contains(DefaultsKey.whatsAppDownloadsAccessConfirmed),
               "machine-specific WhatsApp cleanup state never travels")
        expect(!backupKeys.contains(DefaultsKey.whatsAppOrganizerDestinationPath)
                && !backupKeys.contains(DefaultsKey.whatsAppOrganizerRecords)
                && !backupKeys.contains(DefaultsKey.whatsAppOrganizerUndoTransaction)
                && !backupKeys.contains(DefaultsKey.whatsAppOrganizerLastRun),
               "organizer paths, digests and activity never travel to another Mac")
        expect(backupKeys.contains(DefaultsKey.clipboardHistoryIgnoredApps),
               "the apps the clipboard history skips travel with the settings backup")
        expect(backupKeys.contains(DefaultsKey.panelShowFanControl)
                && backupKeys.contains(DefaultsKey.fanControlMode)
                && backupKeys.contains(DefaultsKey.fanControlCoolingLevel)
                && backupKeys.contains(DefaultsKey.fanControlCurves)
                && backupKeys.contains(DefaultsKey.menuBarFanSpeed)
                && !backupKeys.contains(DefaultsKey.fanControlRecoveryNeeded)
                && !backupKeys.contains(DefaultsKey.fanControlHelperVersion),
               "fan display and cooling preferences travel while helper recovery state stays on one Mac")
        expect(Defaults.registeredDefaults[DefaultsKey.displaysSwitchedOff] == nil,
               "a display switched off is a repair note for this machine, not a setting")
        expect(Defaults.registeredDefaults[DefaultsKey.startupDidNotFinish] == nil,
               "a start that did not finish is a note for this machine, not a setting")

        // A stored shortcut is text on disk and can arrive edited or through
        // an imported settings file, so the number is checked before it ever
        // reaches an API that takes a narrower type.
        expect(GlobalShortcut(storageValue: "command:-1") == nil,
               "a negative key code never becomes a shortcut")
        expect(GlobalShortcut(storageValue: "command:99999999") == nil,
               "a key code past the end of the range never becomes a shortcut")
        expect(GlobalShortcut(storageValue: "command:\(Int64.min)") == nil,
               "the smallest possible number never becomes a shortcut")
        expect(!GlobalShortcut(keyCode: -1, modifiers: [.command]).isValid
                && !GlobalShortcut(keyCode: 70000, modifiers: [.command]).isValid,
               "a shortcut built with a number out of range is not valid")
        expect(GlobalShortcut(keyCode: -1, modifiers: [.command]).carbonKeyCode == 0,
               "a number out of range converts to nothing instead of trapping")
        expect(GlobalShortcut(storageValue: "control+option+command:40") != nil,
               "an ordinary stored shortcut still reads back")
        expect(!backupKeys.contains(DefaultsKey.startupDidNotFinish),
               "the backup never carries a note about a start that did not finish")
        expect(backupKeys.contains(DefaultsKey.hasOnboarded)
                && backupKeys.contains(DefaultsKey.featuresOnboardingVersion)
                && backupKeys.contains(DefaultsKey.lastUpdateIntroVersion),
               "a restored Mac does not replay onboarding or the intros already seen")
        let backupPayload = SettingsBackupSupport.payload(appVersion: "test") { key in
            key == DefaultsKey.autoQuitEnabled ? true : nil
        }
        expect(backupPayload[SettingsBackupSupport.formatVersionKey] as? Int
                == SettingsBackupSupport.formatVersion,
               "backup envelope carries the format version")
        let roundTrip = SettingsBackupSupport.sanitizedSettings(from: backupPayload)
        expect(roundTrip?[DefaultsKey.autoQuitEnabled] as? Bool == true,
               "a backup round-trips its settings")
        expect(SettingsBackupSupport.sanitizedSettings(from: [SettingsBackupSupport.settingsKey: [String: Any]()]) == nil,
               "a file without the version envelope is rejected")
        let tampered: [String: Any] = [
            SettingsBackupSupport.formatVersionKey: 1,
            SettingsBackupSupport.settingsKey: ["evilKey": "x", DefaultsKey.autoQuitEnabled: true] as [String: Any],
        ]
        let filteredImport = SettingsBackupSupport.sanitizedSettings(from: tampered)
        expect(filteredImport?["evilKey"] == nil
                && filteredImport?[DefaultsKey.autoQuitEnabled] as? Bool == true,
               "unknown keys are dropped on import")
        expect(SettingsBackupSupport.sanitizedSettings(from: [
            SettingsBackupSupport.formatVersionKey: 99,
            SettingsBackupSupport.settingsKey: [String: Any](),
        ]) == nil, "a future format version is rejected")
        expect(SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: 1]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: NSNumber(value: 1)]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: "1"]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: " 1 \n"]) == 1
                && SettingsBackupSupport.formatVersion(from: [SettingsBackupSupport.formatVersionKey: "invalid"]) == nil,
               "backup format version accepts integer, NSNumber and string representations")
        // A backup file can be edited by hand, and a value of the wrong shape
        // would reach code that trusts its own settings.
        var bridgedSettings: [String: Any]?
        expect(Defaults.registeredDefaults[DefaultsKey.preciseVolumeRollerEnabled] as? Bool == false,
               "precise volume roller is opt-in")

        // MARK: Precise volume roller

        var volumeGate = PreciseVolumeRollerGate()
        expect(volumeGate.accepts(.up, at: 100.00),
               "precise volume accepts the first wheel step")
        expect(!volumeGate.accepts(.up, at: 100.01),
               "precise volume drops repeats that arrive inside the spacing window")
        expect(volumeGate.accepts(.up, at: 100.05),
               "precise volume accepts a later step in the same direction")

        var reversalGate = PreciseVolumeRollerGate()
        expect(reversalGate.accepts(.up, at: 200.00),
               "precise volume reversal setup accepts the initial direction")
        expect(!reversalGate.accepts(.down, at: 200.08),
               "precise volume ignores the first opposite pulse inside the reversal window")
        expect(!reversalGate.accepts(.down, at: 200.16),
               "precise volume waits for a stable opposite direction")
        expect(reversalGate.accepts(.down, at: 200.24),
               "precise volume accepts the confirmed opposite direction")

        var oldDirectionGate = PreciseVolumeRollerGate()
        expect(oldDirectionGate.accepts(.up, at: 300.00),
               "precise volume accepts first old-direction step")
        expect(oldDirectionGate.accepts(.down, at: 300.40),
               "precise volume accepts an opposite step after the reversal window")
        var fastStreamGate = PreciseVolumeRollerGate()
        let fastAccepted = stride(from: 400.00, through: 400.10, by: 0.02)
            .filter { fastStreamGate.accepts(.up, at: $0) }
        expect(fastAccepted.count == 3,
               "precise volume rate-limits sustained fast input instead of starving it")
        expect(PreciseVolumeMediaKey.volumeUp.rollerDirection == .up
                && PreciseVolumeMediaKey.volumeDown.rollerDirection == .down
                && PreciseVolumeMediaKey.mute.rollerDirection == nil,
               "precise volume only remaps volume up and down media keys")

        // MARK: App updates

        func caskUpdate(_ token: String, installed: String, current: String,
                        pinned: Bool = false) -> HomebrewPackageUpdate {
            HomebrewPackageUpdate(kind: .cask, name: token, installedVersions: [installed],
                                  currentVersion: current, isPinned: pinned)
        }
        let caskRecords = [
            HomebrewCaskRecord(token: "editor", displayName: "Editor",
                               installedVersion: "1.129.0", appFileNames: ["Editor.app"]),
            HomebrewCaskRecord(token: "chat", displayName: "Chat",
                               installedVersion: "0.0.374", appFileNames: ["Chat.app"]),
            HomebrewCaskRecord(token: "installer", displayName: "Installer",
                               installedVersion: "26.078", appFileNames: []),
        ]
        // The receipt says 1.129 while the app on disk already updated itself
        // to 1.130: believing the receipt would offer an update that happened.
        // Packages that install through an installer declare no app, so the
        // catalog name is tried as a bundle name before giving up.
        let exactPathRecord = HomebrewCaskRecord(token: "editor", displayName: "Editor",
                                                 installedVersion: "1.0",
                                                 appFileNames: ["Editor.app"],
                                                 appPaths: ["/Users/test/Applications/Editor.app"])
        let lookupBody = Data(#"{"resultCount":2,"results":[{"kind":"mac-software","bundleId":"a.b","version":"2.0","minimumOsVersion":"15.0","trackViewUrl":"https://x"},{"kind":"software","bundleId":"c.d","version":"9.0","minimumOsVersion":"12.0"}]}"#.utf8)
        let onlineCatalogBody = Data(#"""
        [
          {"token":"notes-stable","version":"2.0,revision","artifacts":[{"uninstall":[{"quit":"com.example.notes"}]},{"app":["Notes.app"],"target":"/Applications/Notes.app"}],"depends_on":{"macos":{">=":["14"]}}},
          {"token":"notes-preview","version":"3.0","artifacts":[{"uninstall":[{"quit":["com.example.notes.preview"]}]},{"app":["Notes.app"]}],"depends_on":{"macos":{">=":["14"]}}},
          {"token":"writer","version":"2.0","artifacts":[{"app":["Writer Source.app",{"target":"Writer.app"}],"target":"/Applications/Writer.app"}]},
          {"token":"duplicate-one","version":"2.0","artifacts":[{"uninstall":[{"quit":"com.example.one"}]},{"app":["Duplicate.app"]}]},
          {"token":"duplicate-two","version":"2.0","artifacts":[{"uninstall":[{"quit":"com.example.two"}]},{"app":["Duplicate.app"]}]},
          {"token":"future","version":"4.0","artifacts":[{"app":["Future.app"]}],"depends_on":{"macos":{">=":["26"]}}},
          {"token":"exact","version":"5.0","artifacts":[{"app":["Exact.app"]}],"depends_on":{"macos":{"==":["15"]}}},
          {"token":"rolling","version":"latest","artifacts":[{"app":["Rolling.app"]}]},
          {"token":"case-sensitive","version":"2.0","artifacts":[{"app":["Case.app"]}]},
          {"token":"older","version":"1.0","artifacts":[{"app":["Older.app"]}]},
          {"token":"own-tool","version":"9.0","artifacts":[{"app":["Own.app"]}]}
        ]
        """#.utf8)
        let discoveredPaths = InstalledApps.applicationScanPaths(
            folderPaths: ["/Applications/Editor.app",
                          "/System/Applications/System Utility.app",
                          "/Applications/Editor.app"],
            spotlightPaths: ["/Users/test/Tools/Side App.app",
                             "/Users/test/.Trash/Old.app",
                             "/Users/test/Library/Services/Helper.app",
                             "/Users/test/Projects/Sample/build/Debug.app",
                             "/Users/test/Tools/Container.app/Contents/Helper.app",
                             "/Volumes/Installer/Sample.app"],
            homeDirectory: "/Users/test")
        expect(discoveredPaths == ["/Applications/Editor.app", "/Users/test/Tools/Side App.app"],
               "shared app discovery keeps installed apps and rejects system, transient, nested and duplicate copies")

        let noon = Date(timeIntervalSince1970: 1_800_000_000)
        expect(HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew", tokens: [])?.arguments == nil
                && HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew",
                                                       tokens: ["; rm -rf /"])?.arguments == nil,
               "an upgrade with nothing valid to name builds no command")
        expect(HomebrewCommandBuilder.upgradeCasks(brewPath: "/opt/x/brew",
                                                   tokens: ["chat", "--force", "editor"])?.arguments
                == ["upgrade", "--cask", "--greedy", "chat", "editor"],
               "only real package names reach the upgrade command")
        expect(HomebrewCommandBuilder.outdatedCasksIncludingSelfUpdating(brewPath: "/opt/x/brew").arguments
                == ["outdated", "--cask", "--greedy", "--json=v2"],
               "the update check asks for the apps that carry their own updater too")
        let caskJSON = #"{"formulae":[],"casks":[{"token":"editor","name":["Editor"],"installed":"1.129.0","artifacts":[{"app":["Source.app",{"target":"Editor.app"}],"target":"/Applications/Editor.app"},{"zap":[]}]},{"token":"tapped-tool","full_token":"example/tap/tapped-tool","name":["Tapped Tool"],"installed":"1.0.0","artifacts":[{"app":["Tapped Tool.app"]}]}]}"#
        let parsedRecords = HomebrewParser.parseInstalledCaskRecords(caskJSON)
        expect(parsedRecords.count == 2 && parsedRecords[0].appFileNames == ["Editor.app"]
                && parsedRecords[0].appPaths == ["/Applications/Editor.app"]
                && parsedRecords[0].displayName == "Editor"
                && parsedRecords[0].installedVersion == "1.129.0",
               "an installed package is traced to the final app name after a rename")
        expect(parsedRecords.first { $0.token == "tapped-tool" }?.displayName == "Tapped Tool",
               "parseInstalledCaskRecords keeps the short token brew outdated reports for a cask from a tap")
        expect(HomebrewParser.parseInstalledCaskRecords("garbage").isEmpty,
               "unreadable package output yields no records")
        let managedPackage = HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Applications/Editor.app",
            installed: parsedRecords
        )
        expect(managedPackage?.name == "editor" && managedPackage?.kind == .cask,
               "the exact installed app path resolves to its package")
        expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Desktop/Editor.app",
            installed: parsedRecords
        ) == nil,
        "a same-named app outside the managed path never resolves to a package")
        let legacyRecord = HomebrewCaskRecord(token: "legacy-tool",
                                              displayName: "Legacy Tool",
                                              installedVersion: "2.0",
                                              appFileNames: ["Legacy Tool.app"])
        expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Users/test/Applications/Legacy Tool.app",
            installed: [legacyRecord]
        ) == nil,
        "package uninstall requires exact path ownership even when the catalog omits its target")
        expect(HomebrewOwnershipSupport.packageManagingApplication(
            atPath: "/Applications/Legacy Tool.app",
            installed: [legacyRecord, legacyRecord]
        ) == nil,
        "ambiguous package ownership is never used for uninstall")

        // MARK: Brightness key base (issue #370)

        let pressed = Date(timeIntervalSince1970: 1_800_000_000)
        // The step itself is unchanged; what changed is the value it starts
        // from, so the arithmetic stays pinned.
        // MARK: Command bar calculator

        // The same numbers as the owner's Mac writes them.
        // MARK: Command bar, what the person controls

        // MARK: Compact mode, what an empty field shows
        // MARK: What the bar noticed about this session
        // Five rows compete for one prefix; the least chosen is the one that
        // stops being remembered.
        // MARK: Finding a file from the bar
        let searchableDirectories: Set<String> = [
            "/Users/x/Notes", "/Users/x/Documents", "/tmp",
        ]
        let packagePaths: Set<String> = [
            "/Applications/Utility.app", "/Users/x/Notes/Archive.unknownpackage",
        ]
        // MARK: The Mac's own Settings panes
        let openablePane: [String: Any] = [
            "EXAppExtensionAttributes": [
                "SettingsExtensionAttributes": [
                    "allowsXAppleSystemPreferencesURLScheme": true,
                    "legacyPrefPaneBundleName": "Legacy.prefPane",
                ],
            ],
        ]
        // Every pane names its own groups, so all of them are read, in a fixed
        // order: one Mac and the next must produce the same words.
        let longPaneTerms = (1...45).map { ["title": "term\($0)", "index": ""] }
        let positionOffset = CGSize(width: -24.4, height: 80.6)
        let commandBarScreen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let commandBarSize = CGSize(width: 560, height: 380)
        // MARK: Command bar unit conversion

        // MARK: Command bar emoji

        // MARK: Command bar highlighting

        // MARK: Command bar wiring

        // MARK: Screen recorder wiring

        expect(Defaults.registeredDefaults[DefaultsKey.recorderShortcutEnabled] as? Bool == false,
               "the screen recorder shortcut ships off like every new feature")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderShortcut] as? String
                == "control+option+command:23",
               "the default recording shortcut sits next to the screenshot's own")
        expect(Defaults.registeredDefaults[DefaultsKey.panelUtilityScreenRecorder] as? Bool == true,
               "the screen recorder panel tile ships visible like its siblings")
        let menuPanelSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/UI/MenuPanel/MenuPanelView.swift",
            encoding: .utf8)) ?? ""
        expect(menuPanelSource.contains("ScreenRecorderService.shared.toggle()")
                && menuPanelSource.contains("DefaultsKey.panelUtilityScreenRecorder")
                && menuPanelSource.contains(
                    "systemImage: recorder.isRecording ? \"stop.circle\" : \"record.circle\""),
               "the screen recorder keeps its quick-panel tile, action and recording state")
        var windowRetention = WindowActivationRetention()
        let firstWindowNeedsPromotion = windowRetention.retain()
        let secondWindowNeedsPromotion = windowRetention.retain()
        let firstCloseNeedsDemotion = windowRetention.release()
        let lastCloseNeedsDemotion = windowRetention.release()
        let extraCloseNeedsDemotion = windowRetention.release()
        expect(firstWindowNeedsPromotion && !secondWindowNeedsPromotion
                && !firstCloseNeedsDemotion && lastCloseNeedsDemotion
                && !extraCloseNeedsDemotion && windowRetention.count == 0,
               "user-facing windows share one balanced app activation lifetime")
        let appDelegateSource = (try? String(
            contentsOfFile: "Sources/Vorssaint/App/AppDelegate.swift",
            encoding: .utf8)) ?? ""
        expect(appDelegateSource.contains("if !settingsKeepsAppRegular {")
                && appDelegateSource.contains("WindowActivationPolicy.retain()")
                && appDelegateSource.contains("WindowActivationPolicy.release()"),
               "Settings retains Command Tab presence only while its window is visible")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderSystemAudio] as? Bool == true,
               "a recording carries the sound of the Mac unless the person turns it off")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderMicrophone] as? Bool == false,
               "microphone recording is optional and ships off")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderSharingEnabled] as? Bool == true,
               "temporary recording links stay visible but do nothing until explicitly used")
        expect(Defaults.registeredDefaults[DefaultsKey.recorderQuality] as? String == "balanced"
                && Defaults.registeredDefaults[DefaultsKey.recorderFrameRate] as? Int == 60
                && Defaults.registeredDefaults[DefaultsKey.recorderCountdown] as? Int == 3
                && Defaults.registeredDefaults[DefaultsKey.recorderAutomaticZoom] as? Bool == true
                && Defaults.registeredDefaults[DefaultsKey.recorderOpenEditor] as? Bool == true,
               "the recorder ships balanced, smooth, with automatic zooms, a short countdown and the editor on")
        expect(ScreenshotSupport.countdownRingProgress(elapsed: 0) == 1
                && ScreenshotSupport.countdownRingProgress(elapsed: 0.46) == 0.5
                && ScreenshotSupport.countdownRingProgress(elapsed: 0.92) == 0,
               "the countdown ring drains smoothly across each displayed number")
        expect(ScreenshotSupport.countdownRingProgress(elapsed: -1) == 1
                && ScreenshotSupport.countdownRingProgress(elapsed: 2) == 0,
               "the countdown ring clamps delayed and early frames")
        expect(GlobalShortcutRole.availableRoles(isAvailable: { _ in true })
                .contains(.screenRecorder),
               "the restored recording shortcut is visible in the shortcut editor")
        expect(AppFeature.screenRecorder.group == .tools
                && AppFeature.screenRecorder.enabledKeys.isEmpty
                && AppFeature.screenRecorder.permissions
                    == [.screenRecording, .accessibility, .microphone],
               "the recorder keeps its optional capture permissions contextual")
        expect(AppFeature.screenRecorder.energyProfile == .idle,
               "the recorder costs nothing between recordings")
        expect(RecorderSupport.exceptedOwnWindowIDs(
            ownWindowIDs: [1, 2, 3], protectedWindowIDs: [2, 4]) == [1, 3],
               "recording keeps existing ordinary app windows but never its protected chrome")

        expect(RecordingShareDuration.allCases.map(\.rawValue) == [3_600, 21_600],
               "recording links allow only one or six hours")
        let recordingShareEndpoint = RecordingSharingSupport.endpoint(
            bundleIdentifier: RecordingSharingSupport.developerBundleIdentifier,
            developerOverride: "https://test.example/")
        expect(RecordingSharingSupport.uploadURL(endpoint: recordingShareEndpoint,
                                                 duration: .sixHours)?.absoluteString
                == "https://test.example/v1/recordings?expiresIn=21600",
               "recording sharing uses its fixed endpoint and expiration query")
        let recordingID = String(repeating: "r", count: 32)
        let recordingResponse = RecordingShareResponse(
            id: recordingID,
            viewPath: "/s/\(recordingID)",
            expiresAt: "1970-01-01T06:16:40.000Z",
            deleteToken: String(repeating: "t", count: 43))
        expect(RecordingSharingSupport.record(response: recordingResponse,
                                              endpoint: recordingShareEndpoint,
                                              now: Date(timeIntervalSince1970: 1_000))?.id
                == recordingID,
               "a valid six-hour recording response becomes an owner-held record")
        let recordingPlan = RecordingSharingSupport.encodingPlan(
            duration: 30,
            baseSize: CGSize(width: 3840, height: 2160),
            sourceFrameRate: 60,
            hasAudio: true)
        expect(recordingPlan != nil
                && max(recordingPlan!.size.width, recordingPlan!.size.height) <= 1920
                && recordingPlan!.frameRate == 30
                && recordingPlan!.audioBitRate == 128_000,
               "a large short recording gets a web-sized video and keeps its audio")
        if let recordingPlan {
            let plannedBytes = (recordingPlan.videoBitRate + recordingPlan.audioBitRate)
                * 30 / 8
            expect(plannedBytes < RecordingSharingSupport.targetUploadBytes,
                   "the first compression pass stays inside the upload budget")
        }
        expect(RecordingSharingSupport.encodingPlan(
            duration: 3_600,
            baseSize: CGSize(width: 1920, height: 1080),
            sourceFrameRate: 30,
            hasAudio: true) == nil,
               "sharing refuses a duration that cannot fit without unusable quality")
        expect(RecordingSharingSupport.retryScale(current: 1,
                                                  actualBytes: 100_000_000) ?? 1 < 1,
               "an oversized first pass retries at a lower bitrate")

        // MARK: Screen recorder geometry and policy

        let displayPixels = CGRect(x: 0, y: 0, width: 2940, height: 1912)
        let odd = RecorderSupport.snappedPixelRect(
            CGRect(x: 10.7, y: 20.2, width: 641.4, height: 401.9), in: displayPixels)
        expect(odd.width.truncatingRemainder(dividingBy: 2) == 0
                && odd.height.truncatingRemainder(dividingBy: 2) == 0,
               "a picked area is snapped to even pixels, which is what encoders accept")
        expect(odd.origin.x == 10 && odd.origin.y == 20,
               "snapping moves the origin to whole pixels without shifting the area")
        let overflowing = RecorderSupport.snappedPixelRect(
            CGRect(x: 2900, y: 1900, width: 400, height: 400), in: displayPixels)
        expect(displayPixels.contains(overflowing),
               "an area that runs off the display is brought back inside it")
        expect(overflowing.width >= RecorderSupport.minimumSide
                && overflowing.height >= RecorderSupport.minimumSide,
               "a clamped area never collapses below the smallest recordable size")
        let broken = RecorderSupport.snappedPixelRect(
            CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), in: displayPixels)
        expect(broken.width > 0 && broken.height > 0,
               "a broken rectangle falls back to the whole display instead of failing")

        expect(RecorderSupport.elapsedLabel(seconds: 0) == "0:00"
                && RecorderSupport.elapsedLabel(seconds: 7) == "0:07"
                && RecorderSupport.elapsedLabel(seconds: 754) == "12:34"
                && RecorderSupport.elapsedLabel(seconds: 3723) == "1:02:03",
               "elapsed time reads like a player position and grows an hour field only when needed")
        expect(RecorderSupport.elapsedLabel(seconds: -5) == "0:00",
               "a clock that never went forward still reads as zero")

        var pauseTimeline = RecorderPauseTimeline()
        expect(pauseTimeline.pause(at: 3) && !pauseTimeline.pause(at: 4),
               "a recording enters one pause only once")
        expect(pauseTimeline.elapsed(since: 0, at: 7) == 3
                && pauseTimeline.sampleTime(start: 5, duration: 0.01, since: 0) == nil,
               "an open pause freezes elapsed time and discards captured samples")
        expect(pauseTimeline.resume(at: 8) && !pauseTimeline.resume(at: 9),
               "a recording resumes one open pause only once")
        expect(pauseTimeline.sampleTime(start: 2, duration: 0.01, since: 0) == 2
                && pauseTimeline.sampleTime(start: 8, duration: 0.01, since: 0) == 3
                && pauseTimeline.eventTime(10, since: 0) == 5,
               "video, audio and event time close the paused gap exactly")
        expect(pauseTimeline.sampleTime(start: 2.99, duration: 0.02, since: 0) == nil,
               "an audio buffer crossing the pause edge is dropped instead of overlapping")
        expect(pauseTimeline.sampleTime(start: -0.01, duration: 0.01, since: 0) == nil,
               "a late sample from before the recording origin stays out")
        _ = pauseTimeline.pause(at: 12)
        _ = pauseTimeline.resume(at: 14)
        expect(pauseTimeline.eventTime(13, since: 0) == nil
                && pauseTimeline.elapsed(since: 0, at: 16) == 9,
               "several pauses stay excluded from every recording track")

        expect(RecorderSupport.sanitizedFrameRate(60) == 60
                && RecorderSupport.sanitizedFrameRate(30) == 30
                && RecorderSupport.sanitizedFrameRate(144) == 60,
               "an unknown frame rate falls back to the smooth default")
        expect(RecorderSupport.sanitizedQuality("high") == .high
                && RecorderSupport.sanitizedQuality("nonsense") == .balanced
                && RecorderSupport.sanitizedQuality(nil) == .balanced,
               "an unknown quality falls back to balanced")

        let smallSize = RecorderSupport.outputSize(source: CGSize(width: 2940, height: 1912),
                                                   quality: .small)
        expect(smallSize == CGSize(width: 1470, height: 956),
               "the small preset halves the picture and stays on even pixels")
        expect(RecorderSupport.outputSize(source: CGSize(width: 2940, height: 1912), quality: .high)
                == CGSize(width: 2940, height: 1912),
               "the high preset keeps every pixel")
        let highRate = RecorderSupport.averageBitRate(width: 2940, height: 1912, fps: 60,
                                                      quality: .high)
        let smallRate = RecorderSupport.averageBitRate(width: 1470, height: 956, fps: 60,
                                                       quality: .small)
        expect(highRate > smallRate,
               "a bigger picture at a higher preset asks the encoder for more")
        expect(RecorderSupport.averageBitRate(width: 64, height: 64, fps: 30, quality: .small)
                >= 800_000,
               "even a tiny area gets a usable stream")
        expect(highRate <= 60_000_000,
               "no preset asks for more than the media engine sustains")

        let now = Date(timeIntervalSince1970: 1_000_000)
        let beingEdited = UUID()
        let leftBehind = UUID()
        let beingWritten = UUID()
        let deadOnArrival = UUID()
        let takeHistory: [(id: UUID, finishedAt: Date?, createdAt: Date?)] = [
            (id: beingEdited, finishedAt: now.addingTimeInterval(-600),
             createdAt: now.addingTimeInterval(-700)),
            (id: leftBehind, finishedAt: now.addingTimeInterval(-3 * 24 * 3600),
             createdAt: now.addingTimeInterval(-3 * 24 * 3600)),
            (id: beingWritten, finishedAt: nil, createdAt: now.addingTimeInterval(-5)),
            (id: deadOnArrival, finishedAt: nil, createdAt: now.addingTimeInterval(-8 * 3600)),
        ]
        let swept = Set(RecorderSupport.orphanTakeIDs(takeHistory, now: now))
        expect(swept == [leftBehind, deadOnArrival],
               "the sweep only takes what a crash or a quit left behind")
        expect(!swept.contains(beingEdited),
               "a recording whose editor is open is never swept out from under it")
        expect(!swept.contains(beingWritten),
               "a recording being written right now has no file yet and is left alone")

        let directSaveRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("chikit-recorder-save-\(UUID().uuidString)",
                                    isDirectory: true)
        try? FileManager.default.createDirectory(at: directSaveRoot,
                                                 withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directSaveRoot) }

        let savedID = UUID()
        let savedFolder = directSaveRoot.appendingPathComponent(
            RecorderSupport.takeFolderName(id: savedID), isDirectory: true)
        try? FileManager.default.createDirectory(at: savedFolder,
                                                 withIntermediateDirectories: true)
        let savedTake = RecorderTakeStore.Take(id: savedID, folder: savedFolder)
        let masterBytes = Data("finished recording".utf8)
        try? masterBytes.write(to: savedTake.videoURL)
        let savedDestination = directSaveRoot.appendingPathComponent("saved.mov")
        do {
            try RecorderTakeStore.shared.saveDirectly(savedTake, to: savedDestination)
            expect((try? Data(contentsOf: savedDestination)) == masterBytes,
                   "direct save copies the complete recording to its destination")
            expect(!FileManager.default.fileExists(atPath: savedFolder.path),
                   "direct save removes its internal take after the copy succeeds")
        } catch {
            expect(false, "a valid direct save succeeds")
        }

        let recoverableID = UUID()
        let recoverableFolder = directSaveRoot.appendingPathComponent(
            RecorderSupport.takeFolderName(id: recoverableID), isDirectory: true)
        try? FileManager.default.createDirectory(at: recoverableFolder,
                                                 withIntermediateDirectories: true)
        let recoverableTake = RecorderTakeStore.Take(id: recoverableID, folder: recoverableFolder)
        try? masterBytes.write(to: recoverableTake.videoURL)
        let unavailableDestination = directSaveRoot
            .appendingPathComponent("missing", isDirectory: true)
            .appendingPathComponent("saved.mov")
        var directSaveFailed = false
        do {
            try RecorderTakeStore.shared.saveDirectly(recoverableTake,
                                                      to: unavailableDestination)
        } catch {
            directSaveFailed = true
        }
        expect(directSaveFailed,
               "direct save reports a destination that cannot be written")
        expect(FileManager.default.fileExists(atPath: recoverableTake.videoURL.path),
               "a failed direct save keeps the take available for recovery")

        let importSource = directSaveRoot.appendingPathComponent("source.mp4")
        try? masterBytes.write(to: importSource)
        let importedID = UUID()
        let importedFolder = directSaveRoot.appendingPathComponent(
            RecorderSupport.takeFolderName(id: importedID), isDirectory: true)
        try? FileManager.default.createDirectory(at: importedFolder,
                                                 withIntermediateDirectories: true)
        let importedTake = RecorderTakeStore.Take(id: importedID, folder: importedFolder)
        expect(RecorderTakeStore.shared.importVideo(at: importSource, into: importedTake),
               "an ordinary video is staged as an editor take")
        expect((try? Data(contentsOf: importedTake.videoURL)) == masterBytes,
               "the staged editor take keeps every source byte")
        let changedSourceBytes = Data("changed outside the editor".utf8)
        try? changedSourceBytes.write(to: importSource)
        expect((try? Data(contentsOf: importedTake.videoURL)) == masterBytes,
               "external changes to the original never alter the staged editor master")
        RecorderTakeStore.shared.delete(importedTake)
        expect((try? Data(contentsOf: importSource)) == changedSourceBytes,
               "discarding an imported take never changes the original video")

        expect(RecorderSupport.canStart(freeBytes: 10_000_000_000)
                && !RecorderSupport.canStart(freeBytes: 100_000_000),
               "a recording refuses to start when the disk is nearly full")
        expect(RecorderSupport.pendingStartIsAuthorized(requestGeneration: 4,
                                                        currentGeneration: 4,
                                                        featureIsAvailable: true)
                && !RecorderSupport.pendingStartIsAuthorized(requestGeneration: 4,
                                                             currentGeneration: 5,
                                                             featureIsAvailable: true)
                && !RecorderSupport.pendingStartIsAuthorized(requestGeneration: 4,
                                                             currentGeneration: 4,
                                                             featureIsAvailable: false),
               "a late microphone response cannot start a cancelled or uninstalled recorder")
        let recorderStartGate = RecorderStartGate()
        expect(recorderStartGate.begin() && recorderStartGate.isAuthorized,
               "recorder start gate admits one authorized capture start")
        expect(recorderStartGate.cancelAndClaimStop()
                && !recorderStartGate.claimStartFailure(),
               "stop atomically owns writer finalization when it wins the start race")
        let recorderStartFinished = DispatchSemaphore(value: 0)
        Task.detached {
            await recorderStartGate.waitUntilFinished()
            recorderStartFinished.signal()
        }
        expect(recorderStartFinished.wait(timeout: .now() + 0.05) == .timedOut,
               "recorder stop waits while capture start is suspended")
        recorderStartGate.finish()
        expect(recorderStartFinished.wait(timeout: .now() + 0.5) == .success
                && !recorderStartGate.isAuthorized,
               "recorder cancellation resumes stop only after start has unwound")
        let recorderFailureGate = RecorderStartGate()
        expect(recorderFailureGate.begin() && recorderFailureGate.claimStartFailure()
                && !recorderFailureGate.cancelAndClaimStop(),
               "start failure atomically owns writer cancellation when it wins the stop race")
        recorderFailureGate.finish()
        var captureLifecycle = RecorderCaptureLifecycle()
        expect(!captureLifecycle.acceptsSamples && captureLifecycle.beginStart()
                && captureLifecycle.acceptsSamples && !captureLifecycle.isRunning
                && captureLifecycle.didStart() && captureLifecycle.isRunning,
               "recorder capture accepts samples only while its one start is active")
        captureLifecycle.stop()
        expect(!captureLifecycle.acceptsSamples && !captureLifecycle.isRunning
                && !captureLifecycle.beginStart() && !captureLifecycle.didStart(),
               "recorder capture stays terminal after stop so queued samples cannot revive it")
        expect(RecorderSupport.shouldStopForDisk(freeBytes: 100_000_000)
                && !RecorderSupport.shouldStopForDisk(freeBytes: 10_000_000_000),
               "a recording already running stops before it fills the disk")
        expect(RecorderSupport.minimumFreeBytesToContinue < RecorderSupport.minimumFreeBytesToStart,
               "stopping a recording is allowed to get closer to full than starting one")
        expect(!RecorderTakeStore.canImport(fileSize: 600_000_000,
                                            availableBytes: 1_000_000_000)
               && RecorderTakeStore.canImport(fileSize: 600_000_000,
                                              availableBytes: 1_100_000_000),
               "video import reserves enough free disk space before copying the master")

        let wholeClip = RecorderSupport.sanitizedTrim(start: 0, end: 0, duration: 12)
        expect(wholeClip.start == 0 && wholeClip.end == 12,
               "an end of zero means the whole recording, so an untouched edit shows everything")
        let inside = RecorderSupport.sanitizedTrim(start: 2, end: 9, duration: 12)
        expect(inside.start == 2 && inside.end == 9 && inside.duration == 7,
               "a trim inside the recording is kept as it is")
        let collapsed = RecorderSupport.sanitizedTrim(start: 8, end: 8, duration: 12)
        // A hair of tolerance: the floor is added to a start time in binary
        // floating point, so the difference lands a few ulps under it.
        expect(collapsed.duration >= RecorderSupport.minimumTrimSeconds - 1e-9,
               "dragging both handles together still leaves a clip you can play")
        let past = RecorderSupport.sanitizedTrim(start: 20, end: 30, duration: 12)
        expect(past.end <= 12 && past.start >= 0 && past.duration > 0,
               "a trim past the end of the recording is brought back inside it")
        expect(RecorderSupport.sanitizedTrim(start: 0, end: 5, duration: 0).duration == 0,
               "a recording with no duration produces no clip instead of a broken one")

        expect(RecorderSupport.filmstripTimes(duration: 10, count: 4)
                == [1.25, 3.75, 6.25, 8.75],
               "filmstrip frames are sampled at the middle of each slot")
        expect(RecorderSupport.filmstripTimes(duration: 0, count: 4).isEmpty
                && RecorderSupport.filmstripTimes(duration: 10, count: 0).isEmpty,
               "an empty recording asks for no thumbnails")

        expect(RecorderSupport.gifFrameCount(duration: 10, fps: 12) == 120,
               "a GIF holds one frame per tick of its own rate")
        expect(RecorderSupport.gifFitsBudget(duration: 10, fps: 12)
                && !RecorderSupport.gifFitsBudget(duration: 120, fps: 12),
               "a GIF long enough to eat the memory of the machine is refused before it starts")
        expect(Int(RecorderSupport.maximumGIFSeconds(fps: 12)) == 25,
               "the refusal can say exactly how long a GIF may be at that rate")
        expect(RecorderSupport.gifDelay(fps: 10) == 0.1,
               "the frame delay is the reciprocal of the rate")
        let gifSize = RecorderSupport.gifOutputSize(source: CGSize(width: 2940, height: 1912),
                                                    size: .medium)
        expect(max(gifSize.width, gifSize.height) <= RecorderSupport.GIFSize.medium.longEdge
                && gifSize.width.truncatingRemainder(dividingBy: 2) == 0,
               "a GIF is scaled down to its long edge and stays on even pixels")
        expect(RecorderSupport.gifOutputSize(source: CGSize(width: 200, height: 120), size: .large)
                == CGSize(width: 200, height: 120),
               "a recording smaller than the GIF size is never blown up")
        expect(RecorderSupport.sanitizedGIFFrameRate(99) == 12
                && RecorderSupport.sanitizedGIFSize("nonsense") == .medium,
               "unknown GIF settings fall back to the middle choice")
        expect(RecorderSupport.sanitizedAudioGain(-1) == 0
                && RecorderSupport.sanitizedAudioGain(3) == 1
                && RecorderSupport.sanitizedAudioGain(.nan) == 1,
               "audio gain stays inside the editor's safe range")

        var document = RecorderEditDocument()
        expect(!document.isEdited(duration: 12) && !document.zoomsOnTyping,
               "a recording nobody touched is not treated as edited")
        document.trimStart = 3
        expect(document.isEdited(duration: 12),
               "moving a handle marks the recording as edited")
        document.trimStart = 100
        document.trimEnd = -5
        let repaired = document.sanitized(duration: 12)
        expect(repaired.trimStart >= 0 && repaired.trimEnd <= 12
                && repaired.trim(duration: 12).duration > 0,
               "a damaged edit is repaired instead of wedging the editor")
        let documentRoundTrip = RecorderEditDocument.decoded(
            RecorderEditDocument(trimStart: 1, trimEnd: 4, keepsSystemAudio: false,
                                 zoomsOnTyping: true, keepsMicrophone: false,
                                 systemAudioGain: 0.6, microphoneGain: 1.5).encoded())
        expect(documentRoundTrip.trimStart == 1 && documentRoundTrip.trimEnd == 4
                && !documentRoundTrip.keepsSystemAudio && !documentRoundTrip.keepsMicrophone
                && documentRoundTrip.systemAudioGain == 0.6
                && documentRoundTrip.microphoneGain == 1.5
                && documentRoundTrip.zoomsOnTyping,
               "an edit written next to the recording comes back exactly as it was")
        expect(RecorderEditDocument.decoded(Data("not json".utf8)).trimStart == 0,
               "an unreadable edit opens the recording untouched instead of failing")
        let click = RecorderMotion.Click(time: 3, isDown: true)
        let recoveredZooms = RecorderEditDocument(zoomEnabled: true,
                                                  zoomSegments: [],
                                                  zoomsGenerated: true)
            .restoringAutomaticZooms(clicks: [click], duration: 10)
        expect(recoveredZooms.zoomSegments.count == 1
                && recoveredZooms.zoomSegments[0].followsPointer,
               "turning automatic zoom back on recovers a click-based zoom that was deleted")
        let disabledZooms = RecorderEditDocument(zoomEnabled: false)
            .restoringAutomaticZooms(clicks: [click], duration: 10)
        expect(disabledZooms.zoomSegments.isEmpty,
               "a recording with automatic zooms off starts without zooms on its timeline")
        var intentionalZoom = RecorderTimeline.ZoomSegment(start: 2, end: 4, amount: 2.2)
        intentionalZoom.focusX = 0.2
        intentionalZoom.focusY = 0.3
        let preservedZooms = RecorderEditDocument(zoomEnabled: true,
                                                  zoomSegments: [intentionalZoom])
            .restoringAutomaticZooms(clicks: [click], duration: 10)
        expect(preservedZooms.zoomSegments == [intentionalZoom],
               "recovering automatic zoom never replaces a zoom that is still on the timeline")

        let typingTrack = RecorderTypingTrack(times: [1, 1.2])
        expect(RecorderTypingTrack.decoded(typingTrack.encoded()) == typingTrack,
               "typing timing round-trips without storing which keys were pressed")

        var styled = RecorderEditDocument(backdrop: "style", zoomAmount: 2.4,
                                          texts: [RecorderTextOverlay(text: "Keep", start: 0,
                                                                      end: 1)])
        let preset = RecorderEditPreset(name: "Demo", document: styled)
        styled.backdrop = "other"
        styled.texts.append(RecorderTextOverlay(text: "Also keep", start: 1, end: 2))
        let appliedPreset = preset.applying(to: styled)
        expect(appliedPreset.backdrop == "style" && appliedPreset.zoomAmount == 2.4
                && appliedPreset.texts.count == 2,
               "an editor preset changes the look without touching timeline edits")

        // MARK: Screen recorder motion

        let flatAlpha = RecorderMotion.onePoleAlpha(cutoff: 2, dt: 1.0 / 60)
        expect(abs(flatAlpha - 0.18899) < 0.0001,
               "the one-pole coefficient matches the closed form at 60 fps")
        expect(RecorderMotion.onePoleAlpha(cutoff: 0, dt: 1.0 / 60) == 1,
               "no smoothing at all passes the signal straight through")

        // A step is the hardest case: a causal filter lands late, a forward
        // and backward pass lands on time. That is the whole reason the
        // recording is finished before any of this runs.
        let step = (0..<120).map { $0 < 60 ? 0.0 : 1.0 }
        let filtered = RecorderMotion.filtfilt(step, alpha: 0.28)
        expect(filtered.count == step.count,
               "smoothing returns as many samples as it was given")
        expect(abs(filtered[59] - 0.5) < 0.2,
               "the smoothed step crosses halfway AT the step, not after it")
        expect(filtered[0] < 0.02 && filtered[119] > 0.98,
               "the padded ends are not dragged toward the middle of the clip")
        var monotonic = true
        for index in 1..<filtered.count where filtered[index] < filtered[index - 1] - 1e-9 {
            monotonic = false
        }
        expect(monotonic, "smoothing a step never overshoots or rings")

        let clicks = [RecorderMotion.Click(time: 1.0, isDown: true),
                      RecorderMotion.Click(time: 1.3, isDown: false)]
        expect(RecorderMotion.anchorWeight(at: 1.0, clicks: clicks) == 1,
               "at the moment of the press the pointer is exactly where it really was")
        expect(RecorderMotion.anchorWeight(at: 1.15, clicks: clicks) == 1,
               "through a drag the pointer tracks the truth, or what is dragged comes loose")
        expect(RecorderMotion.anchorWeight(at: 0.5, clicks: clicks) == 0,
               "far from a click the smoothed path is used as it is")
        expect(RecorderMotion.anchorWeight(at: 0.94, clicks: clicks) > 0
                && RecorderMotion.anchorWeight(at: 0.94, clicks: clicks) < 1,
               "the blend back to the truth eases in rather than snapping")

        let openDrag = [RecorderMotion.Click(time: 2.0, isDown: true)]
        expect(RecorderMotion.anchorWeight(at: 5.0, clicks: openDrag) == 1,
               "a recording that ended mid drag keeps tracking to the end")

        expect(RecorderMotion.smoothstep(0) == 0 && RecorderMotion.smoothstep(1) == 1
                && RecorderMotion.smoothstep(0.5) == 0.5,
               "the easing runs from nothing to everything through the middle")
        expect(RecorderMotion.smootherstep(-4) == 0 && RecorderMotion.smootherstep(9) == 1,
               "easing outside its range is clamped instead of exploding")

        // MARK: Screen recorder zoom

        let burst = [RecorderMotion.Click(time: 2.0, isDown: true),
                     RecorderMotion.Click(time: 2.4, isDown: true),
                     RecorderMotion.Click(time: 3.1, isDown: true)]
        let oneZoom = RecorderMotion.zoomSegments(clicks: burst, duration: 20)
        expect(oneZoom.count == 1,
               "a burst of clicks is one zoom that holds, not a flicker")
        expect(oneZoom.first.map { $0.start < 2.0 } == true,
               "the zoom begins BEFORE the click, which is only possible offline")
        let typingZoom = RecorderMotion.zoomSegments(
            clicks: [RecorderMotion.Click(time: 2, isDown: true)],
            typingTimes: [4, 5, 6],
            duration: 20)
        expect(typingZoom.first.map { $0.end >= 7.39 } == true,
               "typing after a click keeps that zoom on the field until writing stops")
        let delayedTypingZoom = RecorderMotion.zoomSegments(
            clicks: [RecorderMotion.Click(time: 2, isDown: true)],
            typingTimes: [9, 10],
            duration: 20)
        expect(delayedTypingZoom.first.map { $0.end >= 11.39 } == true,
               "a pause after focusing a field does not lose its typing zoom")
        expect(RecorderMotion.zoomSegments(clicks: [], typingTimes: [2, 3], duration: 20).isEmpty,
               "typing without a click never invents a place to zoom")
        let farApart = [RecorderMotion.Click(time: 2.0, isDown: true),
                        RecorderMotion.Click(time: 12.0, isDown: true)]
        expect(RecorderMotion.zoomSegments(clicks: farApart, duration: 20).count == 2,
               "clicks far apart get a zoom each")
        expect(RecorderMotion.zoomSegments(
                clicks: [RecorderMotion.Click(time: 9.6, isDown: true)], duration: 10).isEmpty,
               "the click that stopped the recording never causes a zoom")
        expect(RecorderMotion.zoomSegments(clicks: burst, duration: 20)
                .allSatisfy { $0.end <= 20 - RecorderMotion.zoomEndMargin + 0.001 },
               "no clip ends in the middle of a zoom")
        expect(RecorderMotion.zoomSegments(clicks: [], duration: 20).isEmpty,
               "a recording with no clicks has no zoom")

        let segment = RecorderMotion.ZoomSegment(start: 2, end: 6)
        expect(RecorderMotion.zoomProgress(at: 1.5, segments: [segment]) == 0,
               "before the segment the picture is untouched")
        expect(RecorderMotion.zoomProgress(at: 4, segments: [segment]) == 1,
               "in the middle of the segment the zoom is fully in")
        let rampingIn = RecorderMotion.zoomProgress(at: 2.2, segments: [segment])
        expect(rampingIn > 0 && rampingIn < 1, "the zoom eases in rather than cutting")
        let rampingOut = RecorderMotion.zoomProgress(at: 6.3, segments: [segment])
        expect(rampingOut > 0 && rampingOut < 1, "the zoom eases out rather than cutting")

        // The viewport is parameterized in its own travel range, so it cannot
        // leave the frame and never needs clamping afterwards.
        for zoomLevel in [1.2, 1.8, 2.5, 3.0] {
            for travelValue in [-1.0, 0.0, 0.37, 1.0, 2.0] {
                let origin = RecorderMotion.viewportOrigin(
                    travel: CGPoint(x: travelValue, y: travelValue), zoom: zoomLevel)
                let span = 1 / zoomLevel
                expect(origin.x >= -1e-9 && origin.x + span <= 1 + 1e-9
                        && origin.y >= -1e-9 && origin.y + span <= 1 + 1e-9,
                       "the zoomed viewport is inside the frame by construction")
            }
        }
        expect(RecorderMotion.travelParameter(focus: 0.05) == 0
                && RecorderMotion.travelParameter(focus: 0.95) == 1,
               "a pointer near an edge pins the view flush to it, so corners stay reachable")
        expect(abs(RecorderMotion.travelParameter(focus: 0.5) - 0.5) < 1e-9,
               "a pointer in the middle keeps the view centred")

        var spring = RecorderMotion.Spring(value: 0)
        for _ in 0..<400 { spring.step(toward: 1, dt: 1.0 / 240) }
        expect(abs(spring.value - 1) < 0.02,
               "the spring settles on its target instead of orbiting it")
        let springTrace = RecorderMotion.springed(
            [0, 0] + Array(repeating: 1.0, count: 40), frameRate: 60)
        expect(springTrace.first == 0 && springTrace.last ?? 0 > 0.9,
               "a springed timeline starts where it started and settles on the target")
        expect(springTrace.max() ?? 0 <= 1.2,
               "the spring is damped enough not to fly past what it was asked for")

        let cluster = RecorderMotion.focusClusters(
            [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.11, y: 0.1), CGPoint(x: 0.9, y: 0.9)],
            frameRate: 60, zoom: 2)
        expect(cluster.count >= 2,
               "a jump across the screen starts a new place to look at")
        expect(RecorderMotion.focus(at: 0, clusters: cluster) == cluster[0].center,
               "at the start the picture looks where the pointer started")

        expect(RecorderMotion.pressScale(at: 1.0, clicks: clicks) == RecorderMotion.pressPunchScale,
               "the pointer is at its smallest exactly while the button is down")
        expect(RecorderMotion.pressScale(at: 0.5, clicks: clicks) == 1,
               "away from a click the pointer is its normal size")
        expect(RecorderMotion.ringProgress(at: 1.0, clicks: clicks) == 0,
               "the ring is born at the click")
        expect(RecorderMotion.ringProgress(at: 2.0, clicks: clicks) == nil,
               "the ring is gone well before the next second")

        // The typing sampler fills an array from an NSEvent monitor callback
        // while the stop path reads it, so the append has to be under the
        // lock: an unsynchronised one races the copy-on-write buffer. The
        // recording's start time is written by `start()` and read from that
        // same callback, so it belongs under the lock too.
        let typingSampler = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Recorder/RecorderTypingTrack.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        expect(typingSampler.contains("let lock = NSLock()"),
               "the typing sampler guards its buffer the way the pointer sampler does")
        expect(typingSampler.contains("lock.withLock { startedAt = CACurrentMediaTime() }"),
               "the typing sampler writes the recording's start time under the lock")
        expect(typingSampler.contains(
            "lock.withLock { guard let time = pauseClock.eventTime(now, since: startedAt) "
            + "else { return } times.append(time) }"
        ), "the typing sampler appends a keystroke time only under the lock")
        // `RecorderSession.stop()` is nonisolated and async, so its body runs
        // off the main thread however main-actor the caller was (SE-0338).
        // Both samplers install and remove AppKit event monitors, so they are
        // started and stopped back on the main thread.
        let recorderSessionShape = ((try? String(
            contentsOfFile: "Sources/Vorssaint/Services/Recorder/ScreenRecorderService.swift",
            encoding: .utf8)) ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        expect(recorderSessionShape.contains(
            "await MainActor.run { pointer.start() typing.start() }"
        ), "the recorder installs its event monitors on the main thread")
        expect(recorderSessionShape.contains(
            "await MainActor.run { (pointer.stop(), typing.stop()) }"
        ), "the recorder removes its event monitors on the main thread")

        let uniform = RecorderMotion.resampled(
            [RecorderMotion.Sample(time: 0, point: CGPoint(x: 0, y: 0)),
             RecorderMotion.Sample(time: 1, point: CGPoint(x: 1, y: 1))],
            frameRate: 10, duration: 1)
        expect(uniform.count == 10, "the track is resampled onto the output grid")
        expect(abs(uniform[5].x - 0.5) < 0.01,
               "positions between two samples are interpolated in time")
        expect(RecorderMotion.resampled([], frameRate: 10, duration: 1).count == 10,
               "an empty track still yields a full grid instead of crashing the export")

        // MARK: Screen recorder timeline

        let cutTrim = RecorderSupport.Trim(start: 0, end: 20)
        let oneCut = [RecorderTimeline.Cut(start: 5, end: 8)]
        let kept = RecorderTimeline.keptRanges(trim: cutTrim, cuts: oneCut)
        expect(kept.count == 2 && kept[0] == 0...5 && kept[1] == 8...20,
               "a cut in the middle leaves the two pieces around it")
        expect(abs(RecorderTimeline.outputDuration(trim: cutTrim, cuts: oneCut) - 17) < 0.001,
               "the finished video is shorter by exactly what was cut")
        expect(abs(RecorderTimeline.sourceTime(forOutput: 4, trim: cutTrim, cuts: oneCut) - 4) < 0.001,
               "before the cut the two clocks agree")
        expect(abs(RecorderTimeline.sourceTime(forOutput: 6, trim: cutTrim, cuts: oneCut) - 9) < 0.001,
               "after the cut the recording is ahead of the video by the cut's length")
        expect(RecorderTimeline.outputTime(forSource: 6.5, trim: cutTrim, cuts: oneCut) == nil,
               "a moment that was cut out does not exist in the finished video")
        expect(abs((RecorderTimeline.outputTime(forSource: 12, trim: cutTrim, cuts: oneCut) ?? 0)
                    - 9) < 0.001,
               "a moment after the cut maps back to where it really lands")
        // The two clocks are inverses everywhere the moment survives.
        for step in stride(from: 0.0, through: 17.0, by: 0.37) {
            let source = RecorderTimeline.sourceTime(forOutput: step, trim: cutTrim, cuts: oneCut)
            let back = RecorderTimeline.outputTime(forSource: source, trim: cutTrim, cuts: oneCut)
            expect(abs((back ?? -99) - step) < 0.01,
                   "the recording clock and the video clock are inverses of each other")
        }
        expect(RecorderTimeline.normalized(cuts: [RecorderTimeline.Cut(start: 2, end: 6),
                                                  RecorderTimeline.Cut(start: 5, end: 9)],
                                           duration: 20)
                == [RecorderTimeline.Cut(start: 2, end: 9)],
               "two cuts that touch become one")
        expect(RecorderTimeline.normalized(cuts: [RecorderTimeline.Cut(start: 3, end: 3.02)],
                                           duration: 20).isEmpty,
               "a cut too short to see is not a cut")

        let overlapping = [
            RecorderTimeline.ZoomSegment(start: 1, end: 4, amount: 2),
            RecorderTimeline.ZoomSegment(start: 3, end: 6, amount: 2),
        ]
        let tidy = RecorderTimeline.normalized(segments: overlapping, duration: 20)
        expect(tidy.count == 2 && tidy[0].end <= tidy[1].start + 0.001,
               "two zooms that overlap are pushed apart instead of one being dropped")
        let moved = RecorderTimeline.moved(tidy[1], to: 0, among: tidy, duration: 20)
        expect(moved.start >= tidy[0].end - 0.001,
               "dragging a zoom stops at its neighbour instead of pushing it")
        expect(abs(moved.duration - tidy[1].duration) < 0.001,
               "moving a zoom never changes how long it is")
        let squeezed = RecorderTimeline.resized(tidy[0], edge: .end, to: 1.05,
                                                among: tidy, duration: 20)
        expect(squeezed.duration >= RecorderTimeline.minimumSegment - 1e-9,
               "a zoom cannot be dragged shorter than something you could grab again")
        expect(RecorderTimeline.slotForNewSegment(at: 10, existing: tidy, duration: 20) != nil,
               "there is room for a new zoom in an empty stretch")
        expect(RecorderTimeline.slotForNewSegment(at: 2, existing: tidy, duration: 20)
                .map { $0.start >= tidy[0].end - 0.001 } ?? false,
               "adding a zoom inside another one puts it after that one, never on top")

        let aimed = RecorderTimeline.ZoomSegment(start: 0, end: 3, amount: 2,
                                                 focusX: 0.9, focusY: 0.5)
        let state = RecorderTimeline.zoomState(at: 1.5, segments: [aimed])
        expect(state.progress == 1 && state.amount == 2 && state.focus != nil,
               "in the middle of a zoom it is fully in, at its own strength, aimed where it was put")
        // A hand-aimed spot near the edge must land there, not be pulled in by
        // the calming band the automatic follow uses.
        expect(abs(RecorderMotion.travelParameter(exactFocus: 0.9, zoom: 2) - 1) < 0.001,
               "a spot picked near the edge pins the view to that edge")
        expect(abs(RecorderMotion.travelParameter(exactFocus: 0.5, zoom: 2) - 0.5) < 0.001,
               "a spot picked in the middle keeps the view centred")

        // A pointer parked in a corner fades away, and is back before it
        // moves again. Both halves only work because the whole path is known.
        var parked = [CGPoint](repeating: CGPoint(x: 0.5, y: 0.5), count: 60 * 8)
        for index in (60 * 6)..<parked.count {
            parked[index] = CGPoint(x: 0.5 + Double(index - 60 * 6) * 0.01, y: 0.5)
        }
        let opacity = RecorderMotion.pointerOpacity(parked, frameRate: 60)
        expect(opacity.count == parked.count, "every frame gets an opacity")
        expect(opacity[10] > 0.95, "a pointer that just stopped is still solid")
        expect(opacity[60 * 5] < 0.05, "a pointer parked for seconds is out of the way")
        expect(opacity[60 * 6] > 0.95, "it is fully back the instant it moves, not after")
        expect(opacity.allSatisfy { $0 >= 0 && $0 <= 1 }, "opacity never leaves its range")
        let alwaysMoving = (0..<120).map { CGPoint(x: Double($0) * 0.01, y: 0.5) }
        expect(RecorderMotion.pointerOpacity(alwaysMoving, frameRate: 60).allSatisfy { $0 > 0.95 },
               "a pointer that keeps moving is never faded")

        // MARK: Screen recorder text

        let caption = RecorderTextOverlay(text: "Hello", start: 2, end: 6)
        expect(caption.opacity(at: 1.9) == 0 && caption.opacity(at: 6.1) == 0,
               "text is not there before it starts or after it ends")
        expect(caption.opacity(at: 4) == 1, "text is solid in the middle of its own time")
        expect(caption.opacity(at: 2.1) > 0 && caption.opacity(at: 2.1) < 1,
               "text eases in instead of appearing on one frame")
        expect(caption.opacity(at: 5.9) > 0 && caption.opacity(at: 5.9) < 1,
               "text eases out the same way")
        let blink = RecorderTextOverlay(text: "Hi", start: 1, end: 1.3)
        expect(blink.opacity(at: 1.15) > 0,
               "a very short caption still gets to be visible at its middle")
        expect(RecorderTextOverlay(text: "x", start: 5, end: 5.05)
                .sanitized(duration: 10) == nil,
               "a caption too short to read is not kept")
        expect(RecorderTextOverlay(text: "x", start: 9, end: 30)
                .sanitized(duration: 10)?.end == 10,
               "a caption that runs past the recording is brought back inside it")
        expect(RecorderTextOverlay(text: "x", start: 1, end: 3, size: 9)
                .sanitized(duration: 10)?.size == RecorderTextOverlay.sizeRange.upperBound,
               "an impossible text size is clamped instead of filling the frame")
        expect(RecorderTextOverlay.Anchor.bottom.unitPoint.y == 1
                && RecorderTextOverlay.Anchor.topLeading.unitPoint == CGPoint(x: 0, y: 0),
               "the nine places mean what they say, counting down from the top")

        // MARK: Screen recorder blur

        let blur = RecorderBlurRegion(start: 2, end: 6,
                                      rect: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1))
        expect(blur.covers(2) && blur.covers(4) && blur.covers(6)
                && !blur.covers(1.99) && !blur.covers(6.01),
               "a blur hides its area on every frame of its block and never eases in or out")
        expect(blur.pixelRect(in: CGSize(width: 1000, height: 500))
                == CGRect(x: 100, y: 350, width: 300, height: 50),
               "the area is counted from the top like the screen and handed over from the bottom like Core Image")
        expect(RecorderBlurRegion(start: 1, end: 1.1).sanitized(duration: 10) == nil,
               "a blur too short to matter is not kept")
        expect(RecorderBlurRegion(start: 8, end: 30).sanitized(duration: 10)?.end == 10,
               "a blur that runs past the recording is brought back inside it")
        let spilled = RecorderBlurRegion(start: 1, end: 3,
                                         rect: CGRect(x: -0.2, y: 0.9, width: 0.5, height: 0.5))
            .sanitized(duration: 10)
        expect(spilled.map { abs($0.x) < 1e-9 && abs($0.y - 0.9) < 1e-9
                && abs($0.width - 0.3) < 1e-9 && abs($0.height - 0.1) < 1e-9 } == true,
               "an area drawn past the edge is clamped to the picture instead of reaching outside it")
        expect(RecorderBlurRegion(start: 1, end: 3,
                                  rect: CGRect(x: 0.5, y: 0.5, width: 0, height: 0.2))
                .sanitized(duration: 10) == nil,
               "a line is not an area and is dropped rather than drawn")
        let backwards = RecorderBlurRegion.normalizedRect(from: CGPoint(x: 0.8, y: 0.7),
                                                          to: CGPoint(x: 0.2, y: 0.3))
        expect(backwards.map { abs($0.minX - 0.2) < 1e-9 && abs($0.minY - 0.3) < 1e-9
                && abs($0.width - 0.6) < 1e-9 && abs($0.height - 0.4) < 1e-9 } == true,
               "a drag in any direction produces the same area")
        expect(RecorderBlurRegion.normalizedRect(from: CGPoint(x: 0.5, y: 0.5),
                                                 to: CGPoint(x: 0.502, y: 0.9)) == nil,
               "a drag too thin to be seen leaves the blur where it was")
        expect(RecorderBlurRegion(start: 0, end: 5).rect == RecorderBlurRegion.defaultRect,
               "a new blur lands in the middle until its area is drawn")
        expect(RecorderSupport.blurBlockSize(for: CGSize(width: 300, height: 24)) == 8
                && RecorderSupport.blurBlockSize(for: CGSize(width: 600, height: 90)) == 30
                && RecorderSupport.blurBlockSize(for: CGSize(width: 900, height: 900)) == 48,
               "the mosaic is coarser than one line of text and never turns a big area into four squares")
        let blurredDocument = RecorderEditDocument.decoded(
            RecorderEditDocument(blurs: [blur]).encoded())
        expect(blurredDocument.blurs == [blur],
               "a blur written next to the recording comes back exactly as it was")
        expect(RecorderEditDocument().affectsPicture(blurredDocument)
                && !RecorderEditDocument().affectsTiming(blurredDocument)
                && blurredDocument.isEdited(duration: 10),
               "adding a blur redraws the preview without rebuilding the timeline, and counts as an edit")
        expect(RecorderEditDocument(blurs: [RecorderBlurRegion(start: 4, end: 4.05)])
                .sanitized(duration: 10).blurs.isEmpty,
               "a damaged blur is dropped by the same repair that fixes every other field")

        // The stage letterboxes the picture; a point on it has to come off
        // the empty bands before it means anything in the recording.
        let stagePoint = RecorderSupport.unitPoint(at: CGPoint(x: 300, y: 250),
                                                   in: CGSize(width: 500, height: 500),
                                                   sourceSize: CGSize(width: 1000, height: 500))
        expect(stagePoint.map { abs($0.x - 0.6) < 1e-9 && abs($0.y - 0.5) < 1e-9 } == true,
               "a point on the stage maps through the letterbox into the picture's own space")
        expect(RecorderSupport.unitPoint(at: CGPoint(x: 10, y: 10),
                                         in: CGSize(width: 500, height: 500),
                                         sourceSize: CGSize(width: 1000, height: 500))?.y ?? 0 < 0,
               "a point in the letterbox band comes back outside the picture rather than snapped into it")
        expect(RecorderSupport.unitPoint(at: .zero, in: .zero, sourceSize: .zero) == nil,
               "a stage with no size maps nothing")

        // MARK: Screen recorder pointer track

        let trackRoundTrip = RecorderPointerTrack.decoded(
            RecorderPointerTrack(
                samples: [RecorderMotion.Sample(time: 0.5, point: CGPoint(x: 0.25, y: 0.75))],
                clicks: [RecorderMotion.Click(time: 1.5, isDown: true)],
                systemScale: 2).encoded())
        expect(trackRoundTrip.samples.count == 1 && trackRoundTrip.clicks.count == 1
                && trackRoundTrip.systemScale == 2,
               "a pointer track survives being written and read back")
        expect(abs(trackRoundTrip.samples[0].point.x - 0.25) < 1e-6
                && trackRoundTrip.clicks[0].isDown,
               "the positions and the presses come back as they went in")
        let truncated = RecorderPointerTrack(
            samples: (0..<50).map {
                RecorderMotion.Sample(time: Double($0), point: CGPoint(x: 0.5, y: 0.5))
            }).encoded().prefix(120)
        expect(!RecorderPointerTrack.decoded(Data(truncated)).samples.isEmpty,
               "a track cut short by a crash still gives back everything it did write")
        expect(RecorderPointerTrack.decoded(Data("nonsense".utf8)).isEmpty,
               "an unrelated file is not mistaken for a pointer track")
        expect(RecorderPointerTrack.decoded(nil).isEmpty,
               "a recording with no track at all reads as no track")

        // MARK: Screen recorder canvas

        let plainCanvas = RecorderSupport.canvasSize(source: CGSize(width: 960, height: 640),
                                                     padding: 0, aspect: .original)
        expect(plainCanvas == CGSize(width: 960, height: 640),
               "with no margin and no shape the canvas is the recording itself")
        let padded = RecorderSupport.canvasSize(source: CGSize(width: 960, height: 640),
                                                padding: 0.1, aspect: .original)
        expect(padded.width > 960 && padded.height > 640,
               "a margin grows the canvas instead of shrinking the recording")
        let wide = RecorderSupport.canvasSize(source: CGSize(width: 640, height: 640),
                                              padding: 0,
                                              aspect: .wide,
                                              cropsToAspect: true)
        expect(abs(wide.width / wide.height - 16.0 / 9.0) < 0.02,
               "a shape preset gives the canvas that shape")
        expect(wide.width <= 640 && wide.height <= 640,
               "a shape without a background crops inside the source instead of adding bars")
        let framedWide = RecorderSupport.canvasSize(source: CGSize(width: 640, height: 640),
                                                    padding: 0,
                                                    aspect: .wide)
        expect(framedWide.width > 640,
               "a shape with a background grows around the source instead of cropping it")
        let huge = RecorderSupport.canvasSize(source: CGSize(width: 6000, height: 4000),
                                              padding: 0.3, aspect: .original)
        expect(max(huge.width, huge.height) <= RecorderSupport.maximumCanvasEdge,
               "no background can ask for a picture bigger than the ceiling")

        let card = RecorderSupport.cardRect(canvas: CGSize(width: 1200, height: 800),
                                            source: CGSize(width: 960, height: 640),
                                            padding: 0.1)
        expect(abs(card.width / card.height - 960.0 / 640.0) < 0.01,
               "the recording keeps its own proportions inside the canvas")
        expect(abs(card.midX - 600) < 1 && abs(card.midY - 400) < 1,
               "the recording is centred in the canvas")
        expect(card.minX >= 0 && card.maxX <= 1200 && card.minY >= 0 && card.maxY <= 800,
               "the recording never hangs off the canvas")
        let squareCrop = RecorderSupport.cardRect(canvas: CGSize(width: 640, height: 640),
                                                  source: CGSize(width: 960, height: 640),
                                                  padding: 0,
                                                  fillsCanvas: true)
        expect(squareCrop.height == 640 && squareCrop.width == 960 && squareCrop.minX == -160,
               "a centred crop covers the chosen shape and clips equal excess from both sides")
        let rotatedGeometry = RecorderSupport.videoGeometry(
            naturalSize: CGSize(width: 1920, height: 1080),
            preferredTransform: CGAffineTransform(rotationAngle: .pi / 2))
        let rotatedRect = CGRect(origin: .zero, size: CGSize(width: 1920, height: 1080))
            .applying(rotatedGeometry.transform)
        expect(rotatedGeometry.size == CGSize(width: 1080, height: 1920),
               "an imported rotated video uses its displayed portrait dimensions")
        expect(abs(rotatedRect.minX) < 0.001 && abs(rotatedRect.minY) < 0.001,
               "an imported video transform is normalized to the output origin")
        expect(RecorderSupport.videoGeometry(naturalSize: .zero,
                                             preferredTransform: .identity).size == .zero,
               "missing video dimensions stay invalid instead of becoming an artificial frame")

        expect(RecorderSupport.sanitizedZoomAmount(99) == RecorderSupport.zoomAmountRange.upperBound
                && RecorderSupport.sanitizedZoomAmount(.nan) == 1.8,
               "a broken zoom amount falls back instead of magnifying to nothing")
        let visibleTrack = RecorderPointerTrack.decoded(
            RecorderPointerTrack(samples: [
                RecorderMotion.Sample(time: 0, point: .zero, isPointerVisible: true),
                RecorderMotion.Sample(time: 1, point: .zero, isPointerVisible: false),
            ]).encoded())
        expect(visibleTrack.samples.count == 2
                && visibleTrack.samples[0].isPointerVisible
                && !visibleTrack.samples[1].isPointerVisible,
               "whether the system was showing a pointer survives the round trip")
        expect(RecorderMotion.resampledVisibility(visibleTrack.samples,
                                                  frameRate: 4, duration: 2)
                == [true, true, true, true, false, false, false, false],
               "a stretch where the system hid the pointer stays hidden in the video")

        let studio = RecorderEditDocument().applying(.studio)
        expect(studio.zoomEnabled && studio.showsPointer && !studio.backdrop.isEmpty,
               "the studio look turns on everything it promises")
        let bare = RecorderEditDocument().applying(.raw)
        expect(!bare.zoomEnabled && !bare.showsClickRing && bare.backdrop.isEmpty,
               "the raw look leaves the recording exactly as it was")
        expect(bare.showsPointer && bare.resolvedSmoothing == .off,
               "raw still draws the pointer, because the capture itself has none, but eases nothing")
        expect(RecorderEditDocument().applying(.clean).zoomEnabled
                && RecorderEditDocument().applying(.clean).backdrop.isEmpty,
               "the clean look smooths and zooms without putting anything behind it")

        let takeID = UUID()
        expect(RecorderSupport.takeID(fromFolderName: RecorderSupport.takeFolderName(id: takeID))
                == takeID,
               "a recording folder name round-trips its id")
        expect(RecorderSupport.takeID(fromFolderName: "Downloads") == nil,
               "an unrelated folder is never mistaken for a recording")

        // A translated format string whose placeholders drifted from the
        // English one does not misprint: String(format:) reads the argument
        // list by the specifiers, so a "%@" where a "%d" belongs walks off the
        // stack and takes the app with it. This is the one translation mistake
        // that is a crash rather than a typo, so it is pinned here.
        func specifiers(of format: String) -> [String] {
            var found: [String] = []
            let characters = Array(format)
            var index = 0
            while index < characters.count {
                guard characters[index] == "%" else {
                    index += 1
                    continue
                }
                var cursor = index + 1
                // Positional and width flags sit between the % and the letter.
                while cursor < characters.count,
                      "0123456789$.-+ #'lhqLzjt".contains(characters[cursor]) {
                    cursor += 1
                }
                guard cursor < characters.count else { break }
                found.append(String(characters[index...cursor]))
                index = cursor + 1
            }
            return found
        }
        var englishFormats: [String: [String]] = [:]
        // A key glyph in front of a button label reads as that button's
        // shortcut, so neither command bar action button carries one.
        for language in AppLanguage.allCases {
            let recordingShareValues = Mirror(
                reflecting: FeatureStrings.recorderShare(language)).children
                .compactMap { $0.value as? String }
            expect(recordingShareValues.count == 9
                    && recordingShareValues.allSatisfy { !$0.isEmpty },
                   "every recording share string is set for \(language.rawValue)")
            expect(recordingShareValues.allSatisfy { !$0.contains("—") },
                   "no em-dash in recording share strings (\(language.rawValue))")
        }
        expect(Set(GlobalShortcutRole.allCases.map(\.defaultShortcut)).count
                == GlobalShortcutRole.allCases.count,
               "no two shortcut roles share a default combination")

        // A heavy, rare verb stays out of the list until it is asked for, in
        // every language the app speaks.
        expect(InstalledApps.isSystemApplication(
                    at: URL(fileURLWithPath: "/System/Applications/SystemUtility.app"))
                && InstalledApps.isSystemApplication(
                    at: URL(fileURLWithPath: "/Library/Apple/SystemUtility.app"))
                && !InstalledApps.isSystemApplication(
                    at: URL(fileURLWithPath: "/Applications/UserUtility.app")),
               "app controls never offer system apps to the uninstaller")

        // MARK: Command bar search and ranking

        let firstBarPresentation = UUID()
        let secondBarPresentation = UUID()
        // One widely installed app carries a left-to-right mark in front of
        // its name, which made it stop being an exact match for the name it
        // shows and sink under every menu row that merely started with it.
        // Two rows with one id is undefined behaviour in a SwiftUI list, and
        // the list is stitched from six providers plus whatever was saved.
        // A combination tied to one row of the bar.
        let optionB = GlobalShortcut(keyCode: 11, modifiers: [.option, .command])
        let optionN = GlobalShortcut(keyCode: 45, modifiers: [.option, .command])
        let commandPeriod = GlobalShortcut(keyCode: 47, modifiers: [.command])
        var full: [String: GlobalShortcut] = [:]
        // Ends on the next declaration rather than naming a neighbour: a
        // rename would find no separator, leave the slice running to end of
        // file, and quietly restore the whole-file search.
        // Dates and places, answered by the calendar this Mac carries.
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = TimeZone(identifier: "UTC")!
        let english = Locale(identifier: "en_US")
        let tuesday = Date(timeIntervalSince1970: 1_785_240_000)   // 2026-07-28
        // The gate is the whole safety of this: anything a person might be
        // searching for that happens to carry a number must fall through.
        // The places the person saves themselves.
        // MARK: The other names macOS knows an app by
        expect(SpotlightNamesSupport.usableAlternateNames(["Legacy Planner", "Planner.app"],
                                                          displayName: "Planner",
                                                          fileName: "Planner.app")
                == ["Legacy Planner"],
               "a real alias is kept and the bundle's own file name is not")
        expect(SpotlightNamesSupport.usableAlternateNames(
                ["Preferences", "Settings", "Configuration.app", "Previous Settings",
                 "Configuration"],
                displayName: "Configuration",
                fileName: "Configuration.app")
                == ["Preferences", "Settings", "Previous Settings"],
               "an alias repeating the name under the icon teaches the search nothing")
        expect(SpotlightNamesSupport.usableAlternateNames(["ALTERNATE_NAME_1", "  ", "browser"],
                                                          displayName: "Navigator",
                                                          fileName: "Navigator.app") == ["browser"],
               "an untranslated placeholder is not a name anybody types")
        expect(SpotlightNamesSupport.usableAlternateNames(["Café", "cafe"],
                                                          displayName: "Reader",
                                                          fileName: "Reader.app") == ["Café"],
               "two aliases that differ only by accent or case are one alias")

        // The defect itself: scored against its own name, a saved search left
        // the list on the first word of the argument, which is the moment it
        // was about to run.
        // The list drops a script's own row once the answer row stands in for
        // it. That has to use the same rule that decided the script would run,
        // or a bare name shows the script twice: once as an answer and once as
        // the plain row nothing removed.
        let savedBeforeTheField = #"[{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","name":"gh","#
            + #""kind":"link","destination":"https://x"}]"#
        // MARK: Open what was typed as a URL
        let barNow: Double = 1_800_000_000
        // MARK: Capture tool shortcuts

        // The keys a tool registers have to be the ones its settings row writes.
        // Three roles once had a row and no registrar, so the key was recorded
        // and the combination did nothing (issue #708).
        expect(ScreenCaptureTool.allCases.allSatisfy { tool in
                let keys = tool.dedicatedShortcut
                return keys.role.requiredEnableKeys == [keys.enabledKey]
                    && keys.role.feature == tool.feature
               },
               "a capture tool registers exactly the keys its own settings row reads")
        // MARK: A failed removal explains itself where it failed
        // A green tick above "some items couldn't be moved to the Trash" told
        // nobody that sandboxed app data needs Full Disk Access, and the note
        // offering the permission only ever appeared before an app was picked.
        expect(UninstallerSupport.doneSymbol(hasLeftovers: false) == "checkmark.circle.fill",
               "a removal that took everything ends on a tick")
        expect(UninstallerSupport.doneSymbol(hasLeftovers: true)
                != UninstallerSupport.doneSymbol(hasLeftovers: false),
               "a removal that left something behind does not end on the same mark")
        // Both done states have to route through that decision and name what
        // survived; neither may spell a tick of its own.
        for path in ["Sources/Vorssaint/UI/Uninstall/UninstallerView.swift",
                     "Sources/Vorssaint/UI/MenuPanel/PanelUninstallerView.swift"] {
            let source = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            expect(source.contains("UninstallFailureNote(items:"),
                   "\(path) names what the removal left behind")
            expect(!source.contains("\"checkmark.circle.fill\""),
                   "\(path) takes its done symbol from UninstallerSupport")
        }
        let sharedUISource = (try? String(contentsOfFile: "Sources/Vorssaint/UI/SharedUI.swift",
                                          encoding: .utf8)) ?? ""
        expect(sharedUISource.contains("uninstallerFailedNeedsFDA"),
               "the failure note explains the permission the removal needed")

        // MARK: Private file store

        let privateRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivateFileStoreTests-\(UUID().uuidString)", isDirectory: true)
        let privateLeaf = privateRoot.appendingPathComponent("Sub", isDirectory: true)
        expect(PrivateFileStore.directoriesToTighten(from: privateLeaf, container: privateRoot)
                .map(\.lastPathComponent) == ["Sub", privateRoot.lastPathComponent],
               "tightening walks a container path up to the container itself")
        expect(PrivateFileStore.directoriesToTighten(from: privateRoot, container: privateRoot)
                .map(\.lastPathComponent) == [privateRoot.lastPathComponent],
               "the container is tightened without climbing past it")
        expect(PrivateFileStore.directoriesToTighten(
                from: privateLeaf,
                container: FileManager.default.temporaryDirectory
                    .appendingPathComponent(privateRoot.lastPathComponent + "-other",
                                            isDirectory: true)).count == 1,
               "a path outside the container tightens only itself, never a sibling's parents")

        // A container an earlier version created world readable, and a file
        // written into it, both end up owner-only.
        try? FileManager.default.createDirectory(at: privateRoot,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        let privateFile = privateLeaf.appendingPathComponent("records.json")
        let privateCreated = PrivateFileStore.createDirectory(at: privateLeaf,
                                                              container: privateRoot)
        let privateWritten = PrivateFileStore.write(Data([0x7B, 0x7D]), to: privateFile)
        func privateMode(_ url: URL) -> Int? {
            (try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions]
                .flatMap { ($0 as? NSNumber)?.intValue }
        }
        expect(privateCreated && privateMode(privateLeaf) == 0o700,
               "a created store directory is owner-only")
        expect(privateWritten
                && privateMode(privateFile) == 0o600
                && (try? Data(contentsOf: privateFile)) == Data([0x7B, 0x7D]),
               "a stored file lands complete and owner-only")
        expect(privateMode(privateRoot) == 0o700,
               "a container an earlier version left world readable is tightened on the next write")
        try? FileManager.default.removeItem(at: privateRoot)

        // MARK: Result

        // MARK: Every defaults suite stays inside a namespace build.sh sweeps
        // A UserDefaults suite leaves an empty plist in ~/Library/Preferences
        // even after `removePersistentDomain`, and cfprefsd writes that file
        // back out around the time this process exits, so the run cannot delete
        // it itself. `build.sh --test` clears them afterwards, by name prefix.
        // A suite named outside those prefixes survives every run instead.
        let testSource = (try? String(contentsOfFile: "Tests/MetricsTests.swift",
                                      encoding: .utf8)) ?? ""
        expect(!testSource.isEmpty, "the test file reads back for its own source checks")
        // The prefixes are read out of the sweep itself, so the check and the
        // thing it guards cannot drift apart.
        let buildScript = (try? String(contentsOfFile: "build.sh", encoding: .utf8)) ?? ""
        let sweepBody = buildScript.components(separatedBy: "discard_test_preferences() {")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        let sweptNamespaces = sweepBody.components(separatedBy: "\"")
            .enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
            .filter { $0.hasSuffix(".") }
        expect(!sweptNamespaces.isEmpty, "the swept namespaces read back out of build.sh")
        expect(sweepBody.contains("rm -f \"$preferences\"/$name*.plist(N)"),
               "the defaults preference sweep tolerates an already-empty namespace")
        // Split so this needle is not itself a match in the text it scans.
        let suiteCall = "UserDefaults(suiteName" + ": "
        let suiteArguments = testSource.components(separatedBy: suiteCall)
            .dropFirst()
            .map { String($0.prefix { $0 != ")" && $0 != "," && !$0.isNewline }) }
        expect(!suiteArguments.isEmpty, "the namespace check finds the suites it guards")
        for argument in Set(suiteArguments) {
            let name: String?
            if argument.hasPrefix("\"") {
                name = String(argument.dropFirst().prefix { $0 != "\"" })
            } else {
                name = testSource.components(separatedBy: "let \(argument) = \"")
                    .dropFirst().first
                    .map { String($0.prefix { $0 != "\"" }) }
            }
            expect(name.map { value in sweptNamespaces.contains { value.hasPrefix($0) } } == true,
                   "defaults suite \(argument) is named inside a namespace build.sh sweeps")
        }

        // MARK: Every temp dir build.sh stages in is swept when the script ends
        // `mktemp -d` lands outside the repo, so a dir the script does not
        // remove survives the run — a successful one as much as a failed one.
        // The sweep is therefore a trap, and a staging dir added later leaks on
        // every build until it is named in cleanup(). The names are read out of
        // the script so the two cannot drift apart.
        // The trap has to be installed before the first dir exists: a failure
        // between `mktemp -d` and a later `trap` leaks exactly as before.
        let sweepInstalled = buildScript.range(of: "trap cleanup EXIT")?.lowerBound
        let firstStaged = buildScript.range(of: "mktemp -d")?.lowerBound
        expect(sweepInstalled != nil && firstStaged != nil && sweepInstalled! < firstStaged!,
               "build.sh installs the temp dir sweep before it stages the first dir")
        // zsh runs the EXIT trap on HUP but not on INT or TERM, so the signals
        // have to reach it through `exit` or Ctrl-C leaks the staged bundle.
        let signalsRouted = buildScript.range(of: "trap 'exit 1' INT TERM HUP")?.lowerBound
        expect(signalsRouted != nil && firstStaged != nil && signalsRouted! < firstStaged!,
               "build.sh routes interrupts through the sweep before it stages the first dir")
        let cleanupBody = buildScript.components(separatedBy: "cleanup() {")
            .dropFirst().first?.components(separatedBy: "\n}").first ?? ""
        let stagedTempDirs = buildScript.components(separatedBy: "=\"$(mktemp -d)\"")
            .dropLast()
            .compactMap {
                $0.split(whereSeparator: { $0.isNewline || $0 == " " || $0 == "\t" })
                    .last.map(String.init)
            }
        expect(!stagedTempDirs.isEmpty, "the staged temp dirs read back out of build.sh")
        // A dir reached through a path suffix — `X="$(mktemp -d)/name"` — puts
        // the parent in no variable at all, which is how the bundle staging dir
        // leaked. Every call has to be captured whole to be sweepable.
        expect(buildScript.components(separatedBy: "mktemp -d").count - 1 == stagedTempDirs.count,
               "every mktemp -d in build.sh is a whole capture — no path suffix, no other spelling")
        for variable in Set(stagedTempDirs) {
            expect(cleanupBody.contains("\"$\(variable)\""),
                   "temp dir \(variable) is swept by build.sh cleanup()")
            // The sweep runs under `set -u` before the dir is staged: an entry
            // whose variable is not empty first aborts cleanup() at that line,
            // leaving everything listed below it unswept and the exit status
            // untouched. The empty assignment is the third line of the pattern.
            // The leading newline keeps ICON_TMP off STAGE_ICON_TMP.
            let initialized = buildScript.range(of: "\n\(variable)=\"\"")?.lowerBound
            expect(initialized != nil && sweepInstalled != nil && initialized! < sweepInstalled!,
                   "temp dir \(variable) is empty before the sweep is installed")
        }

        // MARK: An identity-less Developer build creates its stable signing identity
        // An ad-hoc signature changes hash on every build, so macOS orphans
        // Accessibility and Screen Recording grants on each rebuild while
        // System Settings keeps showing them as granted. build.sh therefore
        // routes identity-less --dev builds through Tools/setup-signing.sh
        // before signing. The needle is the invocation at the start of a
        // command line: the ad-hoc fallback's advice string also names the
        // script, and must not satisfy this check.
        let runsSigningSetup = buildScript.components(separatedBy: "\n").contains {
            $0.range(of: #"^\s*(if\s+!?\s*)?\./Tools/setup-signing\.sh"#,
                     options: .regularExpression) != nil
        }
        expect(runsSigningSetup,
               "an identity-less Developer build invokes Tools/setup-signing.sh itself")
        // The setup script must run against the stock /usr/bin/openssl, which
        // is LibreSSL: it rejects OpenSSL 3's -legacy flag outright, and the
        // script once died on exactly that with its stderr discarded. The
        // portable spelling names the PBE algorithms instead of the flag.
        let signingSetup = (try? String(contentsOfFile: "Tools/setup-signing.sh",
                                         encoding: .utf8)) ?? ""
        expect(!signingSetup.isEmpty, "the signing setup script reads back for its shape check")
        let signingSetupCode = signingSetup.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: "\n")
        expect(!signingSetupCode.contains("-legacy"),
               "setup-signing.sh avoids the -legacy flag the stock LibreSSL openssl rejects")

        // MARK: Modifying mouse taps are handed back across a session switch
        // The tap owners cannot be reached from this list (they need the event
        // chain), so the wiring is pinned as text: each service follows the
        // session and asks before re-arming a tap the window server disabled.
        // Comments are stripped so prose naming the API cannot answer for it.
        let sessionActivitySource = (try? String(
            contentsOfFile: "Sources/Vorssaint/Services/SessionActivity.swift",
            encoding: .utf8)) ?? ""
        expect(sessionActivitySource.contains("sessionDidResignActiveNotification")
                && sessionActivitySource.contains("sessionDidBecomeActiveNotification"),
               "the session watcher follows both halves of a fast user switch")
        // Disabling a tap and dropping the last Swift reference does not hand
        // the port back: CGGetEventTapList still reports the tap against this
        // process, one more per start/stop cycle, for the life of the process.
        // Only CFMachPortInvalidate deregisters it. Counted per tap rather than
        // per file, because BrightnessService and SuperKeyService own two taps
        // each and WindowLayoutService three, and on comment-stripped source,
        // as in the per-service check above, so prose naming the API cannot
        // answer for a missing call. A margin does not cover a tap added later:
        // tap. The owners reached are counted too, because a file with no
        // literal CGEvent.tapCreate is skipped, so moving the call behind a
        // helper would otherwise leave a sweep that passes having read nothing.
        var tapOwnersWithoutInvalidate: [String] = []
        var tapOwners = 0
        let tapOwnerSources = FileManager.default
            .enumerator(atPath: "Sources/Vorssaint")?
            .compactMap { $0 as? String }
            .filter { $0.hasSuffix(".swift") && !$0.contains(" 2") } ?? []
        for file in tapOwnerSources.sorted() {
            guard let source = try? String(contentsOfFile: "Sources/Vorssaint/\(file)",
                                           encoding: .utf8) else { continue }
            let code = source.components(separatedBy: "\n")
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            let taps = code.components(separatedBy: "CGEvent.tapCreate").count - 1
            guard taps > 0 else { continue }
            tapOwners += 1
            let invalidations = code.components(separatedBy: "CFMachPortInvalidate").count - 1
            if invalidations < taps {
                tapOwnersWithoutInvalidate.append("\(file) (\(taps) taps, \(invalidations) invalidated)")
            }
        }
        expect(tapOwners > 0 && tapOwnersWithoutInvalidate.isEmpty,
               "every event tap owner invalidates its port on teardown, across "
               + "\(tapOwners) scanned owners: \(tapOwnersWithoutInvalidate)")

        // MARK: Uninstallation paths stay aligned across SelfUninstall and Tools/uninstall.sh
        let selfUninstallSource = (try? String(contentsOfFile: "Sources/Vorssaint/Services/SelfUninstall.swift",
                                              encoding: .utf8)) ?? ""
        let uninstallScriptSource = (try? String(contentsOfFile: "Tools/uninstall.sh",
                                                encoding: .utf8)) ?? ""
        expect(!selfUninstallSource.isEmpty && !uninstallScriptSource.isEmpty,
               "uninstall sources read back for uninstallation alignment check")
        let requiredSubpaths = ["Library/Application Support", "Library/Caches", "Library/HTTPStorages"]
        for subpath in requiredSubpaths {
            expect(selfUninstallSource.contains(subpath) && uninstallScriptSource.contains(subpath),
                   "both in-app and script uninstall sweep \(subpath)")
        }
        expect(uninstallScriptSource.contains("Library/Preferences/ByHost"),
               "script uninstall sweeps ByHost preferences")
        // Restoring sleep used to be fired and forgotten at both exits. A
        // failure there leaves `pmset disablesleep 1` set system-wide, and
        // removal deletes the flag that launch-time recovery reads before it
        // reads the setting, so nothing repairs it afterwards — a reinstall
        // included.
        let uninstallerSource = (try? String(contentsOfFile: "Sources/Vorssaint/Support/Uninstaller.swift",
                                             encoding: .utf8)) ?? ""
        expect(!uninstallerSource.isEmpty,
               "uninstaller entry point reads back for the sleep restore check")
        expect(!selfUninstallSource.contains("_ = Sudoers.pmsetDisableSleep")
                && !uninstallerSource.contains("_ = Sudoers.pmsetDisableSleep"),
               "neither uninstall path discards the result of restoring sleep")
        expect(selfUninstallSource.contains("guard detachFromSystem() else")
                && selfUninstallSource.contains("guard FanControlService.restoreAndUnregisterForRemoval() else"),
               "in-app uninstall aborts unless fans are restored before removal")

        // MARK: Detached command reruns (counted last, so a late rerun still fails)
        // The `||` form reran the whole installer — as root — on every non-zero
        // payload exit. Counting here rather than after a fixed wait leaves the
        // check no window a second run can arrive behind.
        let detachedRuns = detachedRunCount()
        expect(detachedRuns == 1,
               "a detached command runs its payload once whatever the payload exits with "
               + "(ran \(detachedRuns) time(s))")
        try? FileManager.default.removeItem(at: detachRoot)

        // MARK: A dropped identifier
        let diskExclusionsListCode = ((try? String(
            contentsOfFile: "Sources/Vorssaint/UI/Settings/DiskExclusionsList.swift",
            encoding: .utf8)) ?? "").components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        // MARK: Cleaner / Uninstaller — bundle identifier matching

        do {
            let identity = UninstallerSupport.identity(
                primaryBundleID: "com.maker.editor",
                bundleIDs: ["com.maker.editor"],
                displayNames: ["Editor"])
            expect(UninstallerSupport.leftoverMatch("com.maker.editor.plist", identity: identity) == .exact,
                   "an exact bundle id match (with a stripped payload suffix) is exact confidence")
            expect(UninstallerSupport.leftoverMatch("com.maker.editor.helper", identity: identity) == .related,
                   "a sub-identifier of an owned bundle id is related, not exact")
            expect(UninstallerSupport.leftoverMatch("com.other.vendor", identity: identity) == .none,
                   "an unrelated reverse-DNS identifier never matches by display name fragments")
            expect(UninstallerSupport.leftoverMatch("Editor Preferences", identity: identity) == .related,
                   "a display name fragment long enough to be specific matches as related, never exact")
            expect(UninstallerSupport.leftoverMatch("com.mymaker.editorpro", identity: identity) == .none,
                   "a look-alike bundle id is never claimed by a shorter owned id's dot-prefix rule")
        }

        do {
            let groupIdentity = UninstallerSupport.Identity(
                bundleIDs: [], nameTokens: [], teamIDs: [],
                groupIDs: ["group.com.maker.suite"])
            expect(UninstallerSupport.leftoverMatch("group.com.maker.suite", identity: groupIdentity) == .exact,
                   "a signed group container id is exact confidence even with no bundle id evidence")
            expect(UninstallerSupport.leftoverMatch("group.com.other.suite", identity: groupIdentity) == .none,
                   "an unsigned group id never matches just by looking similar")
        }

        expectEqual(CleanerSupport.bundleIDCandidate(fromEntryName: "com.maker.Editor.savedState") ?? "?",
                    "com.maker.Editor", "bundleIDCandidate strips a known payload suffix")
        expectEqual(CleanerSupport.bundleIDCandidate(fromEntryName: "group.com.maker.Editor") ?? "?",
                    "com.maker.Editor", "bundleIDCandidate strips the group. shared-container wrapper")
        expect(CleanerSupport.bundleIDCandidate(fromEntryName: "SomeVendor") == nil,
               "bundleIDCandidate refuses a plain vendor folder name with no dot-separated shape")
        expect(CleanerSupport.bundleIDCandidate(
                fromEntryName: "com.4C2E9C1A-1B2C-4D5E-8F9A-0B1C2D3E4F5A.maker") == nil,
               "bundleIDCandidate refuses a name whose remainder still carries a mid-name UUID component")

        expect(CleanerSupport.isOwned(candidate: "com.maker.editor.helper", byInstalled: ["com.maker.editor"]),
               "isOwned treats an embedded helper as owned by its parent bundle id")
        expect(CleanerSupport.isOwned(candidate: "com.maker.editor", byInstalled: ["com.maker.editor.suite"]),
               "isOwned also matches the other direction: an installed id nested under the candidate")
        expect(!CleanerSupport.isOwned(candidate: "com.maker.editorpro", byInstalled: ["com.maker.editor"]),
               "isOwned never matches on a bare string prefix without the dot boundary")
        expect(CleanerSupport.sharesVendorNamespace(candidate: "com.maker.updater",
                                                     withInstalled: ["com.maker.editor"]),
               "sharesVendorNamespace keeps a sibling identifier alive under the same vendor namespace")
        expect(!CleanerSupport.sharesVendorNamespace(candidate: "com.github.someproject",
                                                      withInstalled: ["com.github.otherproject"]),
               "sharesVendorNamespace excludes hosting namespaces like github, where the vendor is not the owner")
        expect(!CleanerSupport.isProtectedBundleID("com.maker.editor"),
               "an ordinary third-party id is not protected")
        expect(CleanerSupport.isProtectedBundleID("com.apple.dock"),
               "an Apple domain id is always protected")

        // MARK: Cleaner — user exclusion whitelist

        do {
            let previousPaths = UserDefaults.standard.object(forKey: DefaultsKey.cleanerExcludedPaths)
            let previousOwners = UserDefaults.standard.object(forKey: DefaultsKey.cleanerExcludedBundleIDs)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.cleanerExcludedPaths)
            UserDefaults.standard.removeObject(forKey: DefaultsKey.cleanerExcludedBundleIDs)
            defer {
                if let previousPaths { UserDefaults.standard.set(previousPaths, forKey: DefaultsKey.cleanerExcludedPaths) }
                else { UserDefaults.standard.removeObject(forKey: DefaultsKey.cleanerExcludedPaths) }
                if let previousOwners { UserDefaults.standard.set(previousOwners, forKey: DefaultsKey.cleanerExcludedBundleIDs) }
                else { UserDefaults.standard.removeObject(forKey: DefaultsKey.cleanerExcludedBundleIDs) }
            }

            expect(!CleanerExclusions.isExcluded(path: "/Users/x/Library/Caches/com.maker.editor", owner: nil),
                   "nothing is excluded before the whitelist has any entries")

            CleanerExclusions.excludePath("/Users/x/Library/Caches/com.maker.editor")
            expect(CleanerExclusions.isExcluded(path: "/Users/x/Library/Caches/com.maker.editor", owner: nil),
                   "an excluded exact path is reported excluded")
            expect(CleanerExclusions.isExcluded(path: "/Users/x/Library/Caches/com.maker.editor/sub/file", owner: nil),
                   "a path nested inside an excluded folder is excluded too")
            expect(!CleanerExclusions.isExcluded(path: "/Users/x/Library/Caches/com.maker.editorpro", owner: nil),
                   "a sibling path that merely shares a prefix string is not excluded")

            CleanerExclusions.excludeOwner("com.maker.editor")
            expect(CleanerExclusions.isExcluded(path: "/Users/x/Library/Application Support/com.maker.editor",
                                                owner: "com.maker.editor"),
                   "an excluded leftover owner is reported excluded regardless of its path")
            expect(CleanerExclusions.isExcluded(path: "/anything", owner: "COM.MAKER.EDITOR"),
                   "owner exclusion is case-insensitive")

            CleanerExclusions.removePath("/Users/x/Library/Caches/com.maker.editor")
            CleanerExclusions.removeOwner("com.maker.editor")
            expect(!CleanerExclusions.isExcluded(path: "/Users/x/Library/Caches/com.maker.editor", owner: "com.maker.editor"),
                   "removing a path and an owner takes them back out of the whitelist")
        }

        // MARK: Notch media controls
        expect(NotchMediaSupport.hasNotch(topSafeAreaInset: 32),
               "a non-zero top safe-area inset reads as a notched display")
        expect(!NotchMediaSupport.hasNotch(topSafeAreaInset: 0),
               "a zero top safe-area inset (external display, pre-notch MacBook) reads as no notch")
        expect(NotchMediaSupport.snapshot(info: [:], isPlaying: false,
                                          appBundleIdentifier: nil, appPID: 0) == nil,
               "an empty info dictionary with nothing playing and no app identity yields no snapshot")
        if let idleAppOnly = NotchMediaSupport.snapshot(info: [:], isPlaying: false,
                                                        appBundleIdentifier: "com.apple.Music", appPID: 0) {
            expect(idleAppOnly.title == nil && idleAppOnly.isPlaying == false,
                   "an app identity alone (paused, no title) still yields a session, just an untitled one")
        } else {
            expect(false, "a bundle identifier alone is enough app identity for a snapshot")
        }
        let notchNowPlayingInfo: [String: Any] = [
            NotchMediaSupport.titleKey: "Song Title",
            NotchMediaSupport.artistKey: "Artist Name",
            NotchMediaSupport.albumKey: "Album Name",
            NotchMediaSupport.elapsedTimeKey: NSNumber(value: 30.0),
            NotchMediaSupport.durationKey: NSNumber(value: 180.0),
            NotchMediaSupport.playbackRateKey: NSNumber(value: 1.0),
        ]
        if let playing = NotchMediaSupport.snapshot(info: notchNowPlayingInfo, isPlaying: true,
                                                     appBundleIdentifier: "com.spotify.client", appPID: 42) {
            expectEqual(playing.title ?? "", "Song Title", "notch snapshot title")
            expectEqual(playing.artist ?? "", "Artist Name", "notch snapshot artist")
            expectClose(playing.elapsed, 30, "notch snapshot elapsed")
            expectClose(playing.duration ?? -1, 180, "notch snapshot duration")
            expect(playing.isPlaying, "notch snapshot carries the playing flag it was given")
        } else {
            expect(false, "a populated now-playing dictionary with an app identity yields a snapshot")
        }
        // Control characters and newlines are stripped the same way the
        // radial menu's now-playing sanitizer strips them, so a malformed
        // title can never break the pill's layout or accessibility label.
        if let sanitized = NotchMediaSupport.snapshot(
            info: [NotchMediaSupport.titleKey: "Line one\nLine two\u{0007}"],
            isPlaying: true, appBundleIdentifier: nil, appPID: 7) {
            expectEqual(sanitized.title ?? "", "Line oneLine two", "notch snapshot strips control characters and newlines")
        } else {
            expect(false, "a title needing sanitization should still produce a snapshot")
        }
        // MARK: Notch media elapsed-time interpolation
        let baseSnapshot = NotchMediaSnapshot(title: "T", artist: nil, album: nil, artworkData: nil,
                                              appBundleIdentifier: nil, appPID: nil, isPlaying: true,
                                              elapsed: 10, duration: 100,
                                              timestamp: Date(timeIntervalSince1970: 1000),
                                              playbackRate: 1)
        expectClose(NotchMediaSupport.interpolatedElapsed(
            baseSnapshot, at: Date(timeIntervalSince1970: 1005)), 15,
            "playing elapsed time advances at the playback rate between polls")
        expectClose(NotchMediaSupport.interpolatedElapsed(
            baseSnapshot, at: Date(timeIntervalSince1970: 1200)), 100,
            "interpolated elapsed time clamps to the track's duration")
        let pausedSnapshot = NotchMediaSnapshot(title: "T", artist: nil, album: nil, artworkData: nil,
                                                appBundleIdentifier: nil, appPID: nil, isPlaying: false,
                                                elapsed: 42, duration: 100,
                                                timestamp: Date(timeIntervalSince1970: 1000),
                                                playbackRate: 0)
        expectClose(NotchMediaSupport.interpolatedElapsed(
            pausedSnapshot, at: Date(timeIntervalSince1970: 1050)), 42,
            "a paused snapshot's elapsed time holds still regardless of how much wall time passes")

        if failures.isEmpty {
            print("TESTS OK (\(checks) checks)")
            exit(0)
        } else {
            print("TESTS FAILED (\(failures.count) of \(checks)):")
            failures.forEach { print("  - \($0)") }
            exit(1)
        }
    }

    private static func formatSpecifiers(in format: String) -> [String] {
        var specifiers: [String] = []
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                index = format.index(after: index)
                continue
            }
            index = format.index(after: index)
            if index < format.endIndex, format[index] == "%" {
                index = format.index(after: index)
                continue
            }
            while index < format.endIndex {
                let character = format[index]
                if character.isLetter || character == "@" {
                    specifiers.append(String(character))
                    index = format.index(after: index)
                    break
                }
                index = format.index(after: index)
            }
        }
        return specifiers
    }

}
