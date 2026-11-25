// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Combine

/// Owns the menu bar presence: the black hole glyph, the optional countdown
/// title and the tooltip. Click handling is delegated back to the AppDelegate.
final class StatusItemController {
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onMetricClick: ((MenuBarMetric, NSStatusBarButton) -> Void)?

    private(set) var statusItem: NSStatusItem!
    private var metricStatusItems: [String: NSStatusItem] = [:]
    private var metricStatusItemFocus: [String: MenuBarMetric] = [:]
    private var cancellables = Set<AnyCancellable>()
    private var titleTimer: Timer?
    private var defaultsObserver: NSObjectProtocol?
    /// Last combination applied by updateIconAppearance, so refresh ticks
    /// don't re-render an unchanged icon every 2 seconds.
    private var lastIconStateKey = ""
    /// A settings reply already waiting for the next turn of the run loop.
    private var settingsSyncScheduled = false
    /// How many readings in a row each metric has failed to render, so an
    /// item is kept through a hiccup but not forever.
    private var metricEmptyRenders: [String: Int] = [:]
    /// How many metric items are actually showing a reading. An item kept
    /// through a hiccup shows nothing, so it must not be what makes the main
    /// item step aside: that would leave the menu bar with nothing to click.
    private var renderedMetricItemCount = 0
    /// True while a refresh is running. Anything the menu bar announces back
    /// to us in the middle of one is a consequence of that same work, so it
    /// is answered once afterwards rather than on top of it.
    private var isRefreshing = false
    private var refreshRequestedWhileRunning = false
    private static let mainAutosaveName = "ChikitMenuBarItem"
    private static let metricAutosavePrefix = "ChikitMetric"
    private static let maxPlacementGeneration = 10_000
    private static let emptyStatusImage = NSImage()

    private struct MetricStatusGroup {
        let id: String
        let metrics: [MenuBarMetric]
        let focusMetric: MenuBarMetric
        let title: String
    }

    var button: NSStatusBarButton? { statusItem.button }

    func containsStatusItem(at screenPoint: NSPoint) -> Bool {
        let buttons = ([statusItem?.button] + metricStatusItems.values.map(\.button)).compactMap { $0 }
        // Bound once for the whole scan: a default argument is evaluated per
        // call, so leaving it to the default would rebuild this per button.
        let screenFrames = NSScreen.screens.map(\.frame)
        return buttons.contains { button in
            guard let frame = button.window?.frame,
                  StatusItemAnchorSupport.isTrustworthyStatusFrame(frame, screenFrames: screenFrames)
            else { return false }
            return frame.insetBy(dx: -4, dy: -8).contains(screenPoint)
        }
    }

    init() {
        installStatusItem()
        bind()
    }

    /// Creates the status item and configures its button. The menu bar item is the
    /// app's only entry point, so an empty behavior set keeps it from being dragged
    /// off the bar (reordering still works), and forcing isVisible undoes any hidden
    /// state macOS may have persisted. If it ever goes missing, re-opening the app
    /// recovers access (see applicationShouldHandleReopen) and the "Show menu bar
    /// icon" button in Settings rebuilds it.
    private func installStatusItem() {
        StatusItemPlacementSupport.sanitizeStalePlacement(in: .standard)
        // A fresh NSStatusItem starts blank; the memoized icon state belongs
        // to the previous instance and must not suppress the first apply.
        lastIconStateKey = ""
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // A stable identity so macOS remembers the item's position across launches
        // and across rebuilds, instead of re-placing it at the crowded default spot.
        statusItem.autosaveName = StatusItemPlacementSupport.mainAutosaveName(in: .standard)
        statusItem.behavior = []
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.image = BlackHoleGlyph.image()
            button.font = MenuBarRenderer.statusFont(stacked: false)
            button.alignment = .left
            button.cell?.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = false
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        refresh()
        syncMonitorMode()
        updateIconAppearance()
    }

    /// Tears the status item down and builds a fresh one. When recovery is explicit,
    /// reset the saved placement too; otherwise macOS can restore the new item to
    /// the same hidden/crowded position that made it unreachable.
    func recreateStatusItem(resetPlacement: Bool = false) {
        if resetPlacement {
            StatusItemPlacementSupport.bumpPlacementGeneration(in: .standard)
        }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        installStatusItem()
    }

    private func bind() {
        L10n.shared.$language
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        SystemMonitor.shared.$snapshot
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard MenuBarMetric.anyEnabled(in: .standard) else { return }
                self?.refresh()
            }
            .store(in: &cancellables)

        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil,
                                                                  queue: .main) { [weak self] _ in
            // Showing a status item writes its own remembered position into
            // this same domain and announces it right there on the stack, so
            // reacting immediately would call back into the work that is
            // still running. The reply waits for the next turn of the run
            // loop, and a burst of writes collapses into one.
            self?.scheduleSettingsSync()
        }
    }

    private func scheduleSettingsSync() {
        guard !settingsSyncScheduled else { return }
        settingsSyncScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settingsSyncScheduled = false
            self.syncMonitorMode()
            self.updateIconAppearance()
            self.refresh()
        }
    }

    deinit {
        // The controller lives for the whole process today, but tear down cleanly
        // so a future "recreate the status item" path can't leak a firing timer or
        // a block observer that outlives this instance.
        titleTimer?.invalidate()
        if let defaultsObserver { NotificationCenter.default.removeObserver(defaultsObserver) }
        for item in metricStatusItems.values {
            NSStatusBar.system.removeStatusItem(item)
        }
    }

    /// Keeps the background sampler in step with the menu bar settings: it runs
    /// continuously only while at least one metric is pinned to the menu bar.
    private func syncMonitorMode() {
        let defaults = UserDefaults.standard
        let interval = Defaults.sanitizedMonitorInterval(defaults.integer(forKey: DefaultsKey.monitorInterval))
        SystemMonitor.shared.setInterval(seconds: interval)
        SystemMonitor.shared.setMenuBarActive(MenuBarMetric.anyEnabled(in: defaults))
    }

    /// Reflects an available update in the icon with the blue attention
    /// glyph. The glyph can also hide entirely while metrics render in the
    /// title (user option); the decision reads the button's actual title, so
    /// it must run AFTER refresh() writes it — refresh() calls this at its
    /// end.
    private func updateIconAppearance() {
        guard let button = statusItem?.button else { return }
        let defaults = UserDefaults.standard
        let optionEnabled = defaults.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics)
        let separateMetrics = defaults.bool(forKey: DefaultsKey.menuBarSeparateMetrics)
        let hidden = MenuBarSpacingSupport.shouldHideStatusIcon(
            optionEnabled: optionEnabled,
            separateMetrics: separateMetrics,
            metricsEnabled: MenuBarMetric.anyEnabled(in: defaults),
            renderedTitleLength: button.attributedTitle.length,
            mustShowForSignal: false)
        // In the separate-items mode the metrics are their own clickable
        // items, so hiding means the whole main item steps aside instead of
        // just its image (which is all that item has).
        let mainItemHidden = MenuBarSpacingSupport.shouldHideMainStatusItem(
            optionEnabled: optionEnabled,
            separateMetrics: separateMetrics,
            metricItemsShown: renderedMetricItemCount,
            renderedTitleLength: button.attributedTitle.length,
            mustShowForSignal: false)

        // refresh() runs on every monitor tick and lands here; re-rendering
        // the same image every 2 seconds would be wasted composition, so the
        // image is only touched when some ingredient actually changed.
        let stateKey = [String(hidden), String(mainItemHidden)].joined(separator: "|")
        guard stateKey != lastIconStateKey else { return }
        lastIconStateKey = stateKey

        statusItem.isVisible = !mainItemHidden

        guard !hidden else {
            // A non-nil image lets macOS apply the inactive-display appearance
            // to the title while keeping the glyph visually absent.
            button.image = Self.emptyStatusImage
            return
        }
        button.image = BlackHoleGlyph.image()
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
        } else {
            onLeftClick?()
        }
    }

    /// Updates the countdown title and tooltip from the current session state.
    func refresh() {
        guard !isRefreshing else {
            refreshRequestedWhileRunning = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if refreshRequestedWhileRunning {
                refreshRequestedWhileRunning = false
                DispatchQueue.main.async { [weak self] in self?.refresh() }
            }
        }
        performRefresh()
    }

    private func performRefresh() {
        guard let button = statusItem?.button else { return }
        let strings = L10n.shared.s
        let defaults = UserDefaults.standard
        let snapshot = SystemMonitor.shared.snapshot
        let metrics = MenuBarMetric.enabled(in: defaults)
        let separateMetrics = defaults.bool(forKey: DefaultsKey.menuBarSeparateMetrics)

        // Compose the title from the pinned live metrics. Built attributed so
        // the memory pressure dot can carry its green/yellow/red color; all
        // other runs stay adaptive.
        let title = NSMutableAttributedString()
        let includesCountdown = false
        if separateMetrics {
            refreshMetricStatusItems(metrics: metrics, snapshot: snapshot, strings: strings)
        } else {
            removeMetricStatusItems(except: Set<String>())
            renderedMetricItemCount = 0
        }
        if !separateMetrics, !metrics.isEmpty {
            let metricsTitle = MenuBarRenderer.attributed(for: snapshot,
                                                          metrics: metrics,
                                                          allowStacked: !includesCountdown,
                                                          linePrefix: " ")
            if metricsTitle.length > 0 {
                if title.length > 0 { title.append(NSAttributedString(string: "  ")) }
                title.append(metricsTitle)
            }
        }

        // Every write below invalidates the button's layout and redraws the
        // status window even when the value is identical — and this runs on
        // every monitor tick and defaults change. Rounded metric strings
        // repeat most ticks, so skipping no-op writes skips that churn.
        if statusItem.length != NSStatusItem.variableLength {
            statusItem.length = NSStatusItem.variableLength
        }

        if title.length == 0 {
            if button.attributedTitle.length != 0 {
                button.attributedTitle = NSAttributedString(string: "")
            }
            if button.imagePosition != .imageOnly {
                button.imagePosition = .imageOnly
            }
        } else {
            // The leading space separates the glyph from the text; with the
            // glyph hidden by the metrics-only option it would be pure dead
            // padding on the item's left edge. Same decision inputs as
            // updateIconAppearance, with a sentinel length: the title is
            // known non-empty on this branch.
            let glyphHidden = MenuBarSpacingSupport.shouldHideStatusIcon(
                optionEnabled: defaults.bool(forKey: DefaultsKey.menuBarHideIconWithMetrics),
                separateMetrics: separateMetrics,
                metricsEnabled: !metrics.isEmpty,
                renderedTitleLength: 1,
                mustShowForSignal: false)
            let full = NSMutableAttributedString(string: glyphHidden ? "" : " ")
            full.append(title)
            let stacked = full.string.contains("\n")
            let font = MenuBarRenderer.statusFont(stacked: stacked)
            full.addAttribute(.font, value: font, range: NSRange(location: 0, length: full.length))
            if stacked {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .left
                paragraph.lineBreakMode = .byClipping
                paragraph.minimumLineHeight = MenuBarRenderer.statusLineHeight(stacked: true)
                paragraph.maximumLineHeight = MenuBarRenderer.statusLineHeight(stacked: true)
                full.addAttribute(.paragraphStyle,
                                  value: paragraph,
                                  range: NSRange(location: 0, length: full.length))
                full.addAttribute(.baselineOffset,
                                  value: -0.4,
                                  range: NSRange(location: 0, length: full.length))
            }
            if !full.isEqual(to: button.attributedTitle) {
                button.font = font
                button.attributedTitle = full
            }
            if button.imagePosition != .imageLeading {
                button.imagePosition = .imageLeading
            }
        }

        let toolTip = strings.statusIdleTooltip
        if button.toolTip != toolTip {
            button.toolTip = toolTip
        }

        // The icon decision depends on the title just written (the glyph may
        // hide only while metrics actually render), so it re-runs here — the
        // one place where title and icon can never get out of step.
        updateIconAppearance()
    }

    private func refreshMetricStatusItems(metrics: [MenuBarMetric],
                                          snapshot: SystemSnapshot,
                                          strings: Strings) {
        let groups = metricStatusGroups(for: metrics, strings: strings)
        let wanted = Set(groups.map(\.id))
        removeMetricStatusItems(except: wanted)
        var rendered = 0
        defer { renderedMetricItemCount = rendered }

        for group in groups {
            let title = MenuBarRenderer.attributed(for: snapshot,
                                                   metrics: group.metrics,
                                                   allowStacked: false)
            let empties = title.length > 0 ? 0 : (metricEmptyRenders[group.id] ?? 0) + 1
            metricEmptyRenders[group.id] = empties
            guard MenuBarSpacingSupport.keepsMetricStatusItem(
                hasRenderedTitle: title.length > 0,
                itemExists: metricStatusItems[group.id] != nil,
                consecutiveEmptyRenders: empties) else {
                // The reading has been gone long enough to call it gone.
                removeMetricStatusItem(for: group.id)
                continue
            }
            if title.length > 0 { rendered += 1 }

            metricStatusItemFocus[group.id] = group.focusMetric
            let item = metricStatusItems[group.id] ?? installMetricStatusItem(for: group)
            if item.length != NSStatusItem.variableLength {
                item.length = NSStatusItem.variableLength
            }
            guard let button = item.button else { continue }

            let full = NSMutableAttributedString(attributedString: title)
            let font = MenuBarRenderer.statusFont(stacked: false)
            full.addAttribute(.font,
                              value: font,
                              range: NSRange(location: 0, length: full.length))
            if button.font?.isEqual(font) != true {
                button.font = font
            }
            if !full.isEqual(to: button.attributedTitle) {
                button.attributedTitle = full
            }
            if button.image !== Self.emptyStatusImage {
                button.image = Self.emptyStatusImage
            }
            if button.imagePosition != .noImage {
                button.imagePosition = .noImage
            }
            if button.toolTip != group.title {
                button.toolTip = group.title
            }
        }
    }

    private func metricStatusGroups(for metrics: [MenuBarMetric], strings: Strings) -> [MetricStatusGroup] {
        guard MenuBarMetricAppearance.current.allowsCombinedTemperatures,
              UserDefaults.standard.bool(forKey: DefaultsKey.menuBarCombineTemperatures) else {
            return metrics.map {
                MetricStatusGroup(id: $0.rawValue, metrics: [$0], focusMetric: $0, title: $0.title(strings))
            }
        }

        let enabled = Set(metrics)
        var emittedIDs = Set<String>()
        var groups: [MetricStatusGroup] = []

        func appendComponentGroup(id: String,
                                  primary: MenuBarMetric,
                                  temperature: MenuBarMetric,
                                  primaryTitle: String) {
            guard emittedIDs.insert(id).inserted else { return }
            var groupedMetrics: [MenuBarMetric] = []
            if enabled.contains(primary) { groupedMetrics.append(primary) }
            if enabled.contains(temperature) { groupedMetrics.append(temperature) }
            guard let focusMetric = groupedMetrics.first else { return }
            let title = groupedMetrics.count > 1 ? primaryTitle : focusMetric.title(strings)
            groups.append(MetricStatusGroup(id: id,
                                            metrics: groupedMetrics,
                                            focusMetric: focusMetric,
                                            title: title))
        }

        for metric in metrics {
            switch metric {
            case .cpu, .cpuTemperature:
                appendComponentGroup(id: "cpu",
                                     primary: .cpu,
                                     temperature: .cpuTemperature,
                                     primaryTitle: strings.monitorShowCPU)
            case .gpu, .gpuTemperature:
                appendComponentGroup(id: "gpu",
                                     primary: .gpu,
                                     temperature: .gpuTemperature,
                                     primaryTitle: strings.monitorShowGPU)
            case .battery, .batteryTemperature:
                appendComponentGroup(id: "battery",
                                     primary: .battery,
                                     temperature: .batteryTemperature,
                                     primaryTitle: strings.batteryLabel)
            case .memory, .network, .diskUsage, .diskActivity, .batteryTime, .peripheralBattery, .power,
                 .fanSpeed:
                let id = metric.rawValue
                guard emittedIDs.insert(id).inserted else { continue }
                groups.append(MetricStatusGroup(id: id,
                                                metrics: [metric],
                                                focusMetric: metric,
                                                title: metric.title(strings)))
            }
        }

        return groups
    }

    private func installMetricStatusItem(for group: MetricStatusGroup) -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "\(Self.metricAutosavePrefix).\(group.id)"
        item.behavior = []
        // Registered before it is shown: showing it writes its remembered
        // position and announces that write while this call is still on the
        // stack, and an unregistered item would be built all over again by
        // whoever answers that announcement.
        metricStatusItems[group.id] = item
        metricStatusItemFocus[group.id] = group.focusMetric
        item.isVisible = true
        if let button = item.button {
            button.font = MenuBarRenderer.statusFont(stacked: false)
            button.alignment = .left
            button.cell?.lineBreakMode = .byClipping
            button.cell?.usesSingleLineMode = true
            button.target = self
            button.action = #selector(metricClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.identifier = NSUserInterfaceItemIdentifier("\(Self.metricAutosavePrefix).\(group.id)")
        }
        return item
    }

    @objc private func metricClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            onRightClick?()
            return
        }
        guard let metric = focusMetric(from: sender) else {
            onLeftClick?()
            return
        }
        onMetricClick?(metric, sender)
    }

    private func focusMetric(from button: NSStatusBarButton) -> MenuBarMetric? {
        let prefix = "\(Self.metricAutosavePrefix)."
        guard let identifier = button.identifier?.rawValue,
              identifier.hasPrefix(prefix) else { return nil }
        return metricStatusItemFocus[String(identifier.dropFirst(prefix.count))]
    }

    private func removeMetricStatusItems(except wanted: Set<String>) {
        let staleMetrics = metricStatusItems.keys.filter { !wanted.contains($0) }
        for id in staleMetrics {
            removeMetricStatusItem(for: id)
        }
    }

    private func removeMetricStatusItem(for id: String) {
        metricStatusItemFocus.removeValue(forKey: id)
        metricEmptyRenders.removeValue(forKey: id)
        guard let item = metricStatusItems.removeValue(forKey: id) else { return }
        NSStatusBar.system.removeStatusItem(item)
    }
}

/// The official mark, bundled as a template image so the idle state adapts to
/// light and dark menu bars.
enum BlackHoleGlyph {
    /// Logical size of the glyph in the menu bar, in points. Wide because the
    /// mark is ~1.97:1 and sized from its height. Tools/MakeIcon.swift writes
    /// the bundled PNGs at this size; `--selftest` checks the two still agree.
    static let pointSize = NSSize(width: 26, height: 20)

    /// Both scale representations go into one NSImage — loading the 1x file
    /// alone would render blurry on Retina menu bars.
    private static let base: NSImage? = {
        let image = NSImage(size: pointSize)
        for resource in ["MenuBarIcon", "MenuBarIcon@2x"] {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "png"),
                  let data = try? Data(contentsOf: url),
                  let rep = NSBitmapImageRep(data: data)
            else { continue }
            rep.size = pointSize
            image.addRepresentation(rep)
        }
        guard !image.representations.isEmpty else { return nil }
        image.isTemplate = true
        return image
    }()

    static func image() -> NSImage? {
        base ?? fallback()
    }

    /// Keeps a recognizable presence if the bundled asset is ever missing
    /// (e.g. running the bare binary from build/).
    private static func fallback() -> NSImage? {
        if let symbol = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: AppInfo.name)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular)) {
            symbol.isTemplate = true
            return symbol
        }
        // Guaranteed last resort: draw a filled circle so the button always has a
        // visible, clickable image and can never become a zero-width, invisible item.
        let drawn = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 2, dy: 2)).fill()
            return true
        }
        drawn.isTemplate = true
        return drawn
    }
}
