// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import SwiftUI

/// Standalone Convert window, opened by the Finder "Convert with Chikit"
/// service so a right-click on files lands straight in the converter.
final class ConverterWindowController: NSObject, NSWindowDelegate {
    static let shared = ConverterWindowController()
    private var window: NSWindow?

    func show(urls: [URL]) {
        guard AppFeature.fileConverter.isAvailable else { return }
        // A running batch keeps its window; new files wait for the next call.
        if ConverterService.shared.isRunning, let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        window?.close()
        ConverterService.shared.reset()
        let host = NSHostingController(rootView:
            PanelConverterView(initialURLs: urls) { [weak self] in self?.window?.close() }
                .padding(14)
                .frame(width: 380))
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.title = "Convert"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if ConverterService.shared.isRunning { ConverterService.shared.stop() }
        window = nil
    }

    /// Target of the NSServices entry in Info.plist ("Convert with Chikit").
    @objc func convertFiles(_ pasteboard: NSPasteboard, userData: String,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self],
                                           options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return }
        DispatchQueue.main.async { self.show(urls: urls) }
    }
}
