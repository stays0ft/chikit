// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import ApplicationServices

/// Window-server queries and requests around Spaces, resolved at runtime so a
/// macOS that drops a symbol degrades to the previous behavior (windows on
/// other Spaces stay invisible and unreachable) instead of failing to launch.
///
/// Accessibility cannot describe a window parked on a Space that is not
/// visible: the app's window list omits it and direct element access is
/// refused (measured on macOS 26 and 27). The window server is the only
/// witness that such a window exists, and the only reliable tell between a
/// real parked window and a stale leftover surface: real windows normally
/// belong to at least one Space, leftovers belong to none. Some auxiliary
/// surfaces share a Space with a real window but explicitly opt out of window
/// cycling, so their window-server tag is checked separately.
enum SpaceWindowBridge {
    private typealias ConnectionID = UInt32

    private static func symbol(_ name: String) -> UnsafeMutableRawPointer? {
        dlsym(UnsafeMutableRawPointer(bitPattern: -2) /* RTLD_DEFAULT */, name)
    }

    private static let connection: ConnectionID = {
        typealias Function = @convention(c) () -> ConnectionID
        guard let symbol = symbol("CGSMainConnectionID") else { return 0 }
        return unsafeBitCast(symbol, to: Function.self)()
    }()

    private typealias GetWindowTagsFunction =
        @convention(c) (ConnectionID, CGWindowID, UnsafeMutablePointer<UInt32>, Int) -> CGError
    private static let getWindowTags: GetWindowTagsFunction? = {
        guard let symbol = symbol("CGSGetWindowTags") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowTagsFunction.self)
    }()

    // MARK: - Space membership

    private typealias CopySpacesFunction =
        @convention(c) (ConnectionID, Int32, CFArray) -> Unmanaged<CFArray>?
    private static let copySpacesForWindows: CopySpacesFunction? = {
        guard let symbol = symbol("CGSCopySpacesForWindows") else { return nil }
        return unsafeBitCast(symbol, to: CopySpacesFunction.self)
    }()

    /// Whether `spaces(of:)` can actually answer in this session. Callers use
    /// it to tell "this surface belongs to no Space" (the leftover signature)
    /// apart from "the Space queries are unavailable here", so a macOS that
    /// drops the private symbol keeps the pre-existing behavior instead of
    /// misreading every window as a leftover (issue #807).
    static var canResolveSpaces: Bool {
        connection != 0 && copySpacesForWindows != nil
    }

    /// Every Space (user desktops and fullscreen Spaces alike) containing the
    /// window. Empty for leftover surfaces, and when the query is unavailable.
    static func spaces(of windowID: CGWindowID) -> [UInt64] {
        guard connection != 0, let copySpacesForWindows else { return [] }
        let mask: Int32 = 0x7
        guard let array = copySpacesForWindows(connection, mask,
                                               [NSNumber(value: windowID)] as CFArray)?
            .takeRetainedValue() as? [NSNumber]
        else { return [] }
        return array.map(\.uint64Value)
    }

    // MARK: - Display topology

    private typealias CopyDisplaySpacesFunction = @convention(c) (ConnectionID) -> Unmanaged<CFArray>?
    private static let copyManagedDisplaySpaces: CopyDisplaySpacesFunction? = {
        guard let symbol = symbol("CGSCopyManagedDisplaySpaces") else { return nil }
        return unsafeBitCast(symbol, to: CopyDisplaySpacesFunction.self)
    }()

    struct Topology {
        struct DisplayInfo {
            let displayID: CGDirectDisplayID?
            let spaces: [UInt64]
            let fullscreenSpaces: Set<UInt64>
            let currentSpace: UInt64?
        }

        /// Displays in order.
        let displays: [DisplayInfo]
        /// Space ids in left-to-right order, one row per display.
        var orderedSpacesPerDisplay: [[UInt64]] { displays.map(\.spaces) }
        /// The Space currently showing on each display.
        var visibleSpaces: Set<UInt64> { Set(displays.compactMap(\.currentSpace)) }
        /// Native fullscreen Spaces. Managed-display dictionaries use type 4
        /// for these and type 0 for ordinary desktops on current macOS.
        var fullscreenSpaces: Set<UInt64> {
            displays.reduce(into: []) { $0.formUnion($1.fullscreenSpaces) }
        }
    }

    /// Captures AppKit's display identity while the caller is on main. The
    /// resulting values are safe to carry to window-enumeration workers.
    static func displayIDsByUUID() -> [String: CGDirectDisplayID] {
        var map: [String: CGDirectDisplayID] = [:]
        for screen in NSScreen.screens {
            guard let screenNum = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(screenNum)?.takeRetainedValue(),
                  let uuidStr = CFUUIDCreateString(nil, uuid) as String?
            else { continue }
            map[uuidStr] = screenNum
        }
        return map
    }

    /// Main-thread callers can keep using the AppKit-backed display mapping.
    static func topology() -> Topology? {
        topology(displayIDsByUUID: displayIDsByUUID())
    }

    /// Resolves Space topology using display values captured by the caller.
    /// This overload does not access AppKit and is safe for worker queues.
    static func topology(displayIDsByUUID: [String: CGDirectDisplayID]) -> Topology? {
        guard connection != 0, let copyManagedDisplaySpaces,
              let displayDicts = copyManagedDisplaySpaces(connection)?
                .takeRetainedValue() as? [[String: Any]],
              !displayDicts.isEmpty
        else { return nil }

        var displays: [Topology.DisplayInfo] = []
        for display in displayDicts {
            let spaceDictionaries = display["Spaces"] as? [[String: Any]] ?? []
            let row = spaceDictionaries
                .compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
            guard !row.isEmpty else { continue }
            let fullscreenSpaces = Set(spaceDictionaries.compactMap { space -> UInt64? in
                guard (space["type"] as? NSNumber)?.intValue == 4 else { return nil }
                return (space["id64"] as? NSNumber)?.uint64Value
            })
            let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber
            let uuidStr = display["Display Identifier"] as? String
            let displayID = uuidStr.flatMap { displayIDsByUUID[$0] }
            displays.append(Topology.DisplayInfo(displayID: displayID,
                                                 spaces: row,
                                                 fullscreenSpaces: fullscreenSpaces,
                                                 currentSpace: current?.uint64Value))
        }
        guard !displays.isEmpty else { return nil }
        return Topology(displays: displays)
    }

    private typealias MoveWindowsToSpaceFunction =
        @convention(c) (ConnectionID, CFArray, UInt64) -> Void
    private static let moveWindowsToManagedSpace: MoveWindowsToSpaceFunction? = {
        guard let symbol = symbol("CGSMoveWindowsToManagedSpace") else { return nil }
        return unsafeBitCast(symbol, to: MoveWindowsToSpaceFunction.self)
    }()

    /// Whether the window sits on at least one Space and none of them is
    /// visible. False when the Space queries are unavailable, so every caller
    /// falls back to the pre-existing behavior.
    static func isParkedOnHiddenSpace(_ windowID: CGWindowID, visibleSpaces: Set<UInt64>? = nil) -> Bool {
        guard let visible = visibleSpaces ?? topology()?.visibleSpaces else { return false }
        return SpaceHopSupport.isParkedOnHiddenSpace(windowSpaces: spaces(of: windowID),
                                                     visibleSpaces: visible)
    }

    /// False when the private query is unavailable, preserving the existing
    /// cross-Space behavior instead of hiding a legitimate window on a guess.
    static func isExcludedFromWindowCycle(_ windowID: CGWindowID) -> Bool {
        guard connection != 0, let getWindowTags else { return false }
        var tags = [UInt32](repeating: 0, count: 2)
        return tags.withUnsafeMutableBufferPointer { buffer in
            guard let base = buffer.baseAddress,
                  getWindowTags(connection, windowID, base,
                                MemoryLayout<UnsafeRawPointer>.size * 8) == .success
            else { return false }
            return SpaceHopSupport.isExcludedFromWindowCycle(windowTagsLow: buffer[0])
        }
    }

    // MARK: - Fronting a specific window

    private typealias SetFrontFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, CGWindowID, UInt32) -> CGError
    private static let setFrontProcess: SetFrontFunction? = {
        guard let symbol = symbol("_SLPSSetFrontProcessWithOptions") else { return nil }
        return unsafeBitCast(symbol, to: SetFrontFunction.self)
    }()

    private typealias PostEventRecordFunction =
        @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> CGError
    private static let postEventRecord: PostEventRecordFunction? = {
        guard let symbol = symbol("SLPSPostEventRecordTo") else { return nil }
        return unsafeBitCast(symbol, to: PostEventRecordFunction.self)
    }()

    private typealias ProcessForPIDFunction =
        @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> OSStatus
    private static let processForPID: ProcessForPIDFunction? = {
        guard let symbol = symbol("GetProcessForPID") else { return nil }
        return unsafeBitCast(symbol, to: ProcessForPIDFunction.self)
    }()

    // MARK: - The user's "move a space" shortcut

    private typealias HotKeyValueFunction =
        @convention(c) (Int32, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>) -> CGError
    private static let symbolicHotKeyValue: HotKeyValueFunction? = {
        guard let symbol = symbol("CGSGetSymbolicHotKeyValue") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyValueFunction.self)
    }()

    private typealias HotKeyEnabledFunction = @convention(c) (Int32) -> Bool
    private static let symbolicHotKeyEnabled: HotKeyEnabledFunction? = {
        guard let symbol = symbol("CGSIsSymbolicHotKeyEnabled") else { return nil }
        return unsafeBitCast(symbol, to: HotKeyEnabledFunction.self)
    }()

    struct SpaceShortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private static func registeredShortcut(_ hotKeyID: Int32) -> SpaceShortcut? {
        guard let symbolicHotKeyValue, let symbolicHotKeyEnabled,
              symbolicHotKeyEnabled(hotKeyID) else { return nil }
        var options: UInt32 = 0
        var keyCode: UInt32 = 0
        var modifiers: UInt32 = 0
        guard symbolicHotKeyValue(hotKeyID, &options, &keyCode, &modifiers) == .success,
              keyCode != 0
        else { return nil }
        return SpaceShortcut(keyCode: CGKeyCode(keyCode),
                             flags: SpaceHopSupport.eventFlags(fromCarbonModifiers: modifiers))
    }

}
