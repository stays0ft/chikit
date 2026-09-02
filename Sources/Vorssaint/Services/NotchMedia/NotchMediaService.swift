// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Darwin
import Foundation
import SwiftUI

/// A Dynamic-Island-style now-playing widget anchored at the MacBook notch.
///
/// Now-playing data source: this reads Now Playing through the MediaRemote
/// private framework, the same technique `RadialNowPlayingService` already
/// uses for the radial menu's now-playing card (dlopen + dlsym, so a missing
/// symbol degrades to "nothing playing" instead of crashing). That approach
/// was chosen over shelling out to a `nowplaying-cli`-style helper because it
/// needs no bundled binary, gives push notifications instead of polling, and
/// this is a personal, unpublished fork where private-API use carries no App
/// Store risk. macOS asks for no permission for either technique.
///
/// Windowing follows the same borderless `NSPanel` pattern as
/// `ShelfService`'s docked shelf and `RadialNowPlayingService`'s card: no new
/// window management, just another panel anchored either at the notch (when
/// `NSScreen.safeAreaInsets.top` is non-zero) or, on a notch-less/external
/// display, docked under the menu bar icon the same way the shelf is.
final class NotchMediaService: ObservableObject {
    static let shared = NotchMediaService()

    @Published private(set) var state = NotchMediaState.idle
    @Published private(set) var isExpanded = false

    /// Screen frame of the app's menu bar icon, set by the AppDelegate, used
    /// only as the anchor when no notch is present.
    var statusItemFrameProvider: (() -> NSRect?)?

    private let bridge = NotchMediaRemoteBridge()
    private var isObserving = false
    private var isFetching = false
    private var notificationObservers: [NSObjectProtocol] = []
    private var tickTimer: Timer?
    private var collapseWork: DispatchWorkItem?
    private var panel: NSPanel?
    private var eventMonitors: [Any] = []
    private var activationObserver: NSObjectProtocol?

    private init() {}

    // MARK: - Lifecycle

    /// The one entry point `FeatureRuntime` calls whenever availability or
    /// the feature's own enable key changes. Turning the feature off tears
    /// everything down immediately: no more MediaRemote observation, no
    /// timer, no window.
    func syncWithPreferences() {
        let wanted = AppFeature.notchMediaControls.isAvailable
            && UserDefaults.standard.bool(forKey: DefaultsKey.notchMediaControlsEnabled)
        if wanted {
            startObserving()
        } else {
            stopObserving()
        }
    }

    private func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        bridge.registerForNotifications()
        let center = NotificationCenter.default
        notificationObservers = NotchMediaRemoteBridge.changeNotificationNames.map { name in
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
        startTick()
    }

    private func stopObserving() {
        collapseWork?.cancel()
        collapseWork = nil
        stopTick()
        notificationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        notificationObservers = []
        removeEventMonitors()
        isObserving = false
        isExpanded = false
        state = .idle
        panel?.orderOut(nil)
        // Fully released, not just hidden, so a disabled feature leaves
        // nothing behind: the next enable builds a fresh panel and view.
        panel = nil
    }

    private func startTick() {
        stopTick()
        // Fires purely to redraw the scrubber via interpolation; it never
        // re-fetches MediaRemote. A slower re-fetch beneath it catches
        // changes (seeks, track swaps) that a notification was missed for.
        var tickCount = 0
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.objectWillChange.send()
            tickCount += 1
            if tickCount % 5 == 0 { self.refresh() }
        }
        tickTimer?.tolerance = 0.2
    }

    private func stopTick() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: - Fetching

    private func refresh() {
        guard isObserving, !isFetching else { return }
        isFetching = true
        bridge.fetchSnapshot { [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetching = false
                guard self.isObserving else { return }
                self.apply(snapshot)
            }
        }
    }

    private func apply(_ snapshot: NotchMediaSnapshot?) {
        if let snapshot, snapshot.hasIdentity {
            state = .session(snapshot)
        } else {
            state = .idle
            isExpanded = false
        }
        updateWidget()
    }

    // MARK: - Commands

    func send(_ command: NotchMediaCommand) {
        bridge.send(command)
        // Optimistic flip for play/pause so the button feels instant; the
        // real state reconciles a moment later from MediaRemote's own
        // notification (or the follow-up refresh below, if that notification
        // never arrives for this source).
        if case .playPause = command, case let .session(snapshot) = state {
            state = .session(NotchMediaSnapshot(
                title: snapshot.title, artist: snapshot.artist, album: snapshot.album,
                artworkData: snapshot.artworkData, appBundleIdentifier: snapshot.appBundleIdentifier,
                appPID: snapshot.appPID, isPlaying: !snapshot.isPlaying,
                elapsed: NotchMediaSupport.interpolatedElapsed(snapshot, at: Date()),
                duration: snapshot.duration, timestamp: Date(),
                playbackRate: snapshot.isPlaying ? 0 : 1))
            updateWidget()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.refresh() }
    }

    // MARK: - Expand / collapse

    func expand() {
        collapseWork?.cancel()
        collapseWork = nil
        guard !isExpanded else { return }
        isExpanded = true
        updateWidget()
        installOutsideClickMonitor()
    }

    func collapse() {
        collapseWork?.cancel()
        collapseWork = nil
        guard isExpanded else { return }
        isExpanded = false
        removeEventMonitors()
        updateWidget()
    }

    func scheduleCollapse(after delay: TimeInterval = 0.5) {
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.collapse() }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: - Window

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { NotchMediaSupport.hasNotch(topSafeAreaInset: $0.safeAreaInsets.top) }
    }

    private func updateWidget() {
        guard isObserving else { return }
        let shouldShow: Bool
        switch state {
        case .idle, .loading:
            shouldShow = false
        case let .session(snapshot):
            let showIdlePill = UserDefaults.standard.bool(forKey: DefaultsKey.notchMediaControlsShowIdlePill)
            shouldShow = isExpanded || (snapshot.isPlaying && showIdlePill)
        }
        guard shouldShow else {
            panel?.orderOut(nil)
            return
        }
        let panel = ensurePanel()
        if panel.contentViewController == nil {
            let host = NSHostingController(rootView: NotchMediaWidgetView().environmentObject(self))
            host.sizingOptions = .preferredContentSize
            panel.contentViewController = host
        }
        positionWidget(panel)
        panel.orderFrontRegardless()
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.title = "Notch Media Controls"
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.panel = panel
        return panel
    }

    /// Anchors under the notch when the current display has one; otherwise
    /// falls back to hanging under the menu bar icon, exactly like the
    /// shelf's docked panel does on a screen with no room for it elsewhere.
    private func positionWidget(_ panel: NSPanel) {
        guard let view = panel.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        if let screen = notchScreen() {
            let frame = screen.frame
            let x = frame.midX - size.width / 2
            let y = frame.maxY - size.height
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        } else {
            let anchor = statusItemFrameProvider?()
            let visible = (anchor.flatMap { rect in
                NSScreen.screens.first { $0.frame.intersects(rect) }
            } ?? NSScreen.withMouse)?.visibleFrame ?? NSScreen.pointerVisibleFrame
            var x = anchor.map { $0.midX - size.width / 2 } ?? (visible.maxX - size.width - 12)
            x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
            let top = visible.maxY - 2
            panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        }
    }

    private func installOutsideClickMonitor() {
        removeEventMonitors()
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            if event.window !== panel { self.scheduleCollapse(after: 0) }
            return event
        }) { eventMonitors.append(monitor) }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] _ in
            self?.scheduleCollapse(after: 0)
        }) { eventMonitors.append(monitor) }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleCollapse(after: 0)
        }
    }

    private func removeEventMonitors() {
        eventMonitors.forEach { NSEvent.removeMonitor($0) }
        eventMonitors = []
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }
    }
}

/// App identity helpers for a `NotchMediaSnapshot`, mirroring
/// `RadialNowPlayingApplication` but keyed off this feature's own snapshot
/// type.
enum NotchMediaApplication {
    private static var icons: [String: NSImage] = [:]

    static func runningApplication(for snapshot: NotchMediaSnapshot) -> NSRunningApplication? {
        if let bundleIdentifier = snapshot.appBundleIdentifier,
           let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier).first(where: { !$0.isTerminated }) {
            return application
        }
        if let pid = snapshot.appPID {
            return NSRunningApplication(processIdentifier: pid_t(pid))
        }
        return nil
    }

    static func name(for snapshot: NotchMediaSnapshot) -> String? {
        if let name = runningApplication(for: snapshot)?.localizedName, !name.isEmpty { return name }
        guard let identifier = snapshot.appBundleIdentifier else { return nil }
        return identifier.split(separator: ".").last.map(String.init)
    }

    static func icon(for snapshot: NotchMediaSnapshot) -> NSImage? {
        let key = snapshot.appBundleIdentifier ?? snapshot.appPID.map { "pid:\($0)" } ?? ""
        if let icon = icons[key] { return icon }
        let icon: NSImage?
        if let runningIcon = runningApplication(for: snapshot)?.icon {
            icon = runningIcon
        } else if let identifier = snapshot.appBundleIdentifier,
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            icon = nil
        }
        if let icon { icons[key] = icon }
        return icon
    }

    static func open(_ snapshot: NotchMediaSnapshot) {
        if let application = runningApplication(for: snapshot) {
            application.activate(options: [.activateAllWindows])
            return
        }
        guard let identifier = snapshot.appBundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// dlopen/dlsym bridge to the MediaRemote private framework: fetches Now
/// Playing info the same way Control Center does, pushes change
/// notifications instead of requiring a poll loop, and sends playback
/// commands. Every symbol is resolved dynamically, so a missing or
/// resigned framework degrades to "nothing playing" / commands that no-op,
/// never a crash.
private final class NotchMediaRemoteBridge {
    private typealias InfoCallback = @convention(block) (NSDictionary?) -> Void
    private typealias InfoFunction = @convention(c) (DispatchQueue, @escaping InfoCallback) -> Void
    private typealias PIDCallback = @convention(block) (Int32) -> Void
    private typealias PIDFunction = @convention(c) (DispatchQueue, @escaping PIDCallback) -> Void
    private typealias DisplayIDCallback = @convention(block) (NSString?) -> Void
    private typealias DisplayIDFunction = @convention(c) (DispatchQueue, @escaping DisplayIDCallback) -> Void
    private typealias IsPlayingCallback = @convention(block) (Bool) -> Void
    private typealias IsPlayingFunction = @convention(c) (DispatchQueue, @escaping IsPlayingCallback) -> Void
    private typealias SendCommandFunction = @convention(c) (Int32, NSDictionary?) -> UInt8
    private typealias RegisterFunction = @convention(c) (DispatchQueue) -> Void

    /// MRMediaRemoteCommand values this widget uses; the rest of the enum
    /// (stop, shuffle, rating, bookmarking, …) is left unused.
    private enum Command: Int32 {
        case togglePlayPause = 2
        case nextTrack = 4
        case previousTrack = 5
        case seekToPlaybackPosition = 16
    }

    static let changeNotificationNames = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    ]

    private let queue = DispatchQueue(label: "com.vorssaint.utils.notch-now-playing", qos: .userInitiated)
    private let handle: UnsafeMutableRawPointer?
    private let getInfo: InfoFunction?
    private let getPID: PIDFunction?
    private let getDisplayID: DisplayIDFunction?
    private let getIsPlaying: IsPlayingFunction?
    private let sendCommand: SendCommandFunction?
    private let register: RegisterFunction?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
        self.handle = handle
        getInfo = Self.function(handle, "MRMediaRemoteGetNowPlayingInfo", as: InfoFunction.self)
        getPID = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationPID", as: PIDFunction.self)
        getDisplayID = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationDisplayID",
                                     as: DisplayIDFunction.self)
        getIsPlaying = Self.function(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying",
                                     as: IsPlayingFunction.self)
        sendCommand = Self.function(handle, "MRMediaRemoteSendCommand", as: SendCommandFunction.self)
        register = Self.function(handle, "MRMediaRemoteRegisterForNowPlayingNotifications",
                                 as: RegisterFunction.self)
    }

    deinit {
        if let handle { dlclose(handle) }
    }

    func registerForNotifications() {
        register?(queue)
    }

    func send(_ command: NotchMediaCommand) {
        guard let sendCommand else { return }
        switch command {
        case .playPause:
            _ = sendCommand(Command.togglePlayPause.rawValue, nil)
        case .nextTrack:
            _ = sendCommand(Command.nextTrack.rawValue, nil)
        case .previousTrack:
            _ = sendCommand(Command.previousTrack.rawValue, nil)
        case let .seek(to: position):
            // Best-effort: not every now-playing source honors an external
            // seek command, unlike play/pause/skip which are near-universal.
            let userInfo: NSDictionary = ["kMRMediaRemoteOptionElapsedTime": position]
            _ = sendCommand(Command.seekToPlaybackPosition.rawValue, userInfo)
        }
    }

    func fetchSnapshot(completion: @escaping (NotchMediaSnapshot?) -> Void) {
        guard let getInfo else {
            completion(nil)
            return
        }
        let result = FetchResult(completion: completion)
        let group = DispatchGroup()

        group.enter()
        getInfo(queue) { info in
            result.setInfo(info as? [String: Any] ?? [:])
            group.leave()
        }
        if let getPID {
            group.enter()
            getPID(queue) { pid in
                result.setPID(pid)
                group.leave()
            }
        }
        if let getDisplayID {
            group.enter()
            getDisplayID(queue) { identifier in
                result.setDisplayID(identifier as String?)
                group.leave()
            }
        }
        if let getIsPlaying {
            group.enter()
            getIsPlaying(queue) { isPlaying in
                result.setRemoteIsPlaying(isPlaying)
                group.leave()
            }
        }

        group.notify(queue: queue) { result.finish() }
        queue.asyncAfter(deadline: .now() + 0.75) { result.finish() }
    }

    private static func function<T>(_ handle: UnsafeMutableRawPointer?,
                                    _ name: String,
                                    as type: T.Type) -> T? {
        guard let handle, let symbol = dlsym(handle, name) else { return nil }
        return unsafeBitCast(symbol, to: type)
    }

    private final class FetchResult {
        private let lock = NSLock()
        private var info: [String: Any] = [:]
        private var pid: Int32 = 0
        private var displayID: String?
        private var remoteIsPlaying: Bool?
        private var finished = false
        private let completion: (NotchMediaSnapshot?) -> Void

        init(completion: @escaping (NotchMediaSnapshot?) -> Void) {
            self.completion = completion
        }

        func setInfo(_ info: [String: Any]) { lock.withLock { self.info = info } }
        func setPID(_ pid: Int32) { lock.withLock { self.pid = pid } }
        func setDisplayID(_ displayID: String?) { lock.withLock { self.displayID = displayID } }
        func setRemoteIsPlaying(_ remoteIsPlaying: Bool) { lock.withLock { self.remoteIsPlaying = remoteIsPlaying } }

        func finish() {
            let values: ([String: Any], Int32, String?, Bool?)? = lock.withLock {
                guard !finished else { return nil }
                finished = true
                return (info, pid, displayID, remoteIsPlaying)
            }
            guard let (info, pid, displayID, remoteIsPlaying) = values else { return }
            let isPlaying = NotchMediaSupport.playbackIsActive(remoteIsPlaying: remoteIsPlaying, info: info)
            completion(NotchMediaSupport.snapshot(info: info,
                                                  isPlaying: isPlaying,
                                                  appBundleIdentifier: displayID,
                                                  appPID: pid))
        }
    }
}
