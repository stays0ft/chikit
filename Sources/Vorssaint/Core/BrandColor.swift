// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The app's fixed brand tint. Chikit paints its own accent rather than
/// following the Mac's System Settings accent color, so every control that
/// used to read SwiftUI's `Color.accentColor` reads this instead — a vivid
/// indigo-violet (#6749F6) matched to the app icon's gradient.
extension Color {
    static let chikitAccent = Color(red: 0.404, green: 0.286, blue: 0.965)
}
