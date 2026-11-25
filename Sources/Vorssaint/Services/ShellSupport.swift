// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import CoreServices
import Darwin

enum Shell {
    /// A command that stops answering must not keep a thread forever. Nothing
    /// here asks a question that is worth more than a few seconds, and a tool
    /// waiting on a damaged disk or a share that went away can wait for good.
    static let defaultTimeout: TimeInterval = 5

    @discardableResult
    static func run(_ path: String,
                    _ args: [String],
                    timeout: TimeInterval = defaultTimeout,
                    maxOutputBytes: Int = 4 * 1024 * 1024)
        -> (status: Int32, output: String) {
        let result = BoundedProcessRunner.run(path, args,
                                              timeout: timeout,
                                              maxOutputBytes: maxOutputBytes)
        return (result.status, String(decoding: result.output, as: UTF8.self))
    }
}

/// Sends Apple Events to another app IN-PROCESS (via NSAppleScript) instead of
/// spawning `osascript`. The Automation consent is then attributed to THIS app —
/// so it stays granted across updates, is re-requested if it was lost, and the
/// first-run consent prompt is never killed by a watchdog. It is the same
/// per-target Automation permission the features already required; nothing new is
/// requested. Call these OFF the main thread, so a slow target never blocks the
/// UI or the event taps (the calls block their thread until the target replies).
enum AppleScriptRunner {
    /// True when this app may script `bundleID`. Undetermined → shows the system
    /// prompt (attributed to this app); granted → returns at once; denied →
    /// false without nagging.
    @discardableResult
    static func consentToAutomate(bundleID: String) -> Bool {
        var target = AEAddressDesc()
        let created = bundleID.withCString { ptr in
            AECreateDesc(typeApplicationBundleID, ptr, bundleID.utf8.count, &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, true) == noErr
    }

    /// Runs the AppleScript in this process. Returns whether it succeeded and the
    /// result string (or the error message on failure). Sending the event in
    /// process itself triggers the Automation prompt when consent is undetermined.
    @discardableResult
    static func run(_ source: String) -> (ok: Bool, output: String) {
        let result = runDetailed(source)
        return (result.ok, result.ok ? result.output : result.message)
    }

    /// Same as `run`, keeping the AppleScript error number so callers can tell
    /// a declined Automation consent (-1743/-1744) apart from a real failure.
    @discardableResult
    static func runDetailed(_ source: String) -> (ok: Bool, errorNumber: Int?, message: String, output: String) {
        guard let script = NSAppleScript(source: source) else { return (false, nil, "", "") }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return (false,
                    error[NSAppleScript.errorNumber] as? Int,
                    (error[NSAppleScript.errorMessage] as? String) ?? "",
                    "")
        }
        return (true, nil, "", result.stringValue ?? "")
    }

    /// Escapes a value for embedding inside an AppleScript double-quoted string.
    static func literal(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
