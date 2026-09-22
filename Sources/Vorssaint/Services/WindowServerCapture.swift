// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// The window-server capture path shared by every tool that photographs one
/// window directly (the screen-region selector's window-click capture).
/// Resolved at runtime so a future macOS that drops the private symbol
/// degrades to whatever fallback the caller already has instead of failing
/// to launch.
enum WindowServerCapture {
    private typealias CGSConnectionID = UInt32
    private typealias CGSCaptureFunction =
        @convention(c) (CGSConnectionID, UnsafeMutablePointer<UInt32>, UInt32, UInt32) -> Unmanaged<CFArray>?

    /// `CGSHWCaptureWindowList` — resolved at runtime so a future macOS that
    /// drops the symbol degrades to the caller's own fallback path instead of
    /// failing to launch.
    private static let windowServerCapture: CGSCaptureFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSHWCaptureWindowList")
        else { return nil }
        return unsafeBitCast(symbol, to: CGSCaptureFunction.self)
    }()

    private static let windowServerConnection: CGSConnectionID = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGSMainConnectionID")
        else { return 0 }
        typealias ConnectionFunction = @convention(c) () -> CGSConnectionID
        return unsafeBitCast(symbol, to: ConnectionFunction.self)()
    }()

    /// Best resolution + ignore the global clip shape, so parked, minimized and
    /// other-Space windows come back as their real, untransformed content.
    private static let windowServerCaptureOptions: UInt32 = (1 << 8) | (1 << 11)

    static func captureViaWindowServer(_ windowID: CGWindowID) -> CGImage? {
        guard windowServerConnection != 0, let capture = windowServerCapture else { return nil }
        var id = UInt32(windowID)
        guard let array = capture(windowServerConnection, &id, 1, windowServerCaptureOptions)?
            .takeRetainedValue(),
            CFArrayGetCount(array) > 0,
            let value = CFArrayGetValueAtIndex(array, 0)
        else { return nil }
        let candidate = unsafeBitCast(value, to: CFTypeRef.self)
        guard CFGetTypeID(candidate) == CGImage.typeID else { return nil }
        let image = unsafeBitCast(candidate, to: CGImage.self)
        guard image.width > 1, image.height > 1 else { return nil }
        return image
    }

    /// Whether a captured image's aspect ratio still matches the window it
    /// was captured from, within tolerance. A window-server capture of a
    /// window on another Space can come back a clipped strip instead of the
    /// full frame; this tells that apart from a legitimate capture.
    static let captureCoverageTolerance = 0.02

    static func captureCoversWindow(imageWidth: Int,
                                    imageHeight: Int,
                                    windowSize: CGSize,
                                    tolerance: Double = captureCoverageTolerance) -> Bool {
        guard windowSize.width.isFinite, windowSize.height.isFinite,
              windowSize.width > 1, windowSize.height > 1
        else { return true }
        let horizontal = Double(imageWidth) / Double(windowSize.width)
        let vertical = Double(imageHeight) / Double(windowSize.height)
        guard horizontal > 0, vertical > 0 else { return true }
        return max(horizontal, vertical) / min(horizontal, vertical) <= 1 + tolerance
    }
}
