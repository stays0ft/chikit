// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import CoreGraphics
import Foundation

/// A now-playing snapshot for the notch widget. Distinct from
/// `RadialNowPlayingSnapshot` (the radial menu's own, simpler card) because
/// this widget also drives a scrubber and needs elapsed/duration/rate to
/// interpolate playback position between fetches.
struct NotchMediaSnapshot: Equatable {
    let title: String?
    let artist: String?
    let album: String?
    let artworkData: Data?
    let appBundleIdentifier: String?
    let appPID: Int32?
    let isPlaying: Bool
    /// Elapsed playback position, in seconds, as of `timestamp`.
    let elapsed: Double
    /// Track duration in seconds; nil when the source never reported one
    /// (radio streams, some browser tabs).
    let duration: Double?
    /// When `elapsed` was read, so the UI can interpolate a moving position
    /// between polls instead of visibly stepping once a second.
    let timestamp: Date
    let playbackRate: Double

    var hasIdentity: Bool {
        title != nil || appBundleIdentifier != nil || appPID != nil
    }
}

enum NotchMediaState: Equatable {
    case idle
    case loading
    case session(NotchMediaSnapshot)
}

/// Which physical/simulated control a tap or key should send.
enum NotchMediaCommand: Equatable {
    case playPause
    case nextTrack
    case previousTrack
    /// Best-effort: not every now-playing source honors an external seek.
    case seek(to: Double)
}

/// Pure logic for the notch widget: notch detection, snapshot parsing and
/// elapsed-time interpolation. Kept free of AppKit/MediaRemote types so it
/// can be exercised by the standalone unit-test harness.
enum NotchMediaSupport {
    static let titleKey = "kMRMediaRemoteNowPlayingInfoTitle"
    static let artistKey = "kMRMediaRemoteNowPlayingInfoArtist"
    static let albumKey = "kMRMediaRemoteNowPlayingInfoAlbum"
    static let artworkDataKey = "kMRMediaRemoteNowPlayingInfoArtworkData"
    static let playbackRateKey = "kMRMediaRemoteNowPlayingInfoPlaybackRate"
    static let elapsedTimeKey = "kMRMediaRemoteNowPlayingInfoElapsedTime"
    static let durationKey = "kMRMediaRemoteNowPlayingInfoDuration"
    static let timestampKey = "kMRMediaRemoteNowPlayingInfoTimestamp"

    private static let forbiddenScalars = CharacterSet.controlCharacters.union(.newlines)
    private static let maximumArtworkBytes = 12 * 1_024 * 1_024

    /// A notched display reports a non-zero top safe-area inset; every other
    /// display (including external monitors and pre-notch MacBooks) reports
    /// zero. This is the entire detection rule — no model sniffing.
    static func hasNotch(topSafeAreaInset: CGFloat) -> Bool {
        topSafeAreaInset > 0
    }

    static func playbackIsActive(remoteIsPlaying: Bool?, info: [String: Any]) -> Bool {
        if let remoteIsPlaying { return remoteIsPlaying }
        return (info[playbackRateKey] as? NSNumber)?.doubleValue ?? 0 > 0
    }

    static func snapshot(info: [String: Any],
                         isPlaying: Bool,
                         appBundleIdentifier: String?,
                         appPID: Int32,
                         now: Date = Date()) -> NotchMediaSnapshot? {
        let title = sanitizedText(info[titleKey])
        let artist = sanitizedText(info[artistKey])
        let album = sanitizedText(info[albumKey])
        let bundleIdentifier = sanitizedBundleIdentifier(appBundleIdentifier)
        let pid = appPID > 0 ? appPID : nil
        let artworkData = sanitizedArtworkData(info[artworkDataKey])
        let elapsed = (info[elapsedTimeKey] as? NSNumber)?.doubleValue ?? 0
        let duration = (info[durationKey] as? NSNumber)?.doubleValue
        let rate = (info[playbackRateKey] as? NSNumber)?.doubleValue ?? (isPlaying ? 1 : 0)
        let timestamp = (info[timestampKey] as? Date) ?? now
        guard title != nil || bundleIdentifier != nil || pid != nil else { return nil }
        return NotchMediaSnapshot(title: title,
                                  artist: artist,
                                  album: album,
                                  artworkData: artworkData,
                                  appBundleIdentifier: bundleIdentifier,
                                  appPID: pid,
                                  isPlaying: isPlaying,
                                  elapsed: max(0, elapsed),
                                  duration: duration.flatMap { $0 > 0 ? $0 : nil },
                                  timestamp: timestamp,
                                  playbackRate: rate)
    }

    /// Interpolates a moving playback position between polls: while playing,
    /// time keeps advancing at `playbackRate` past the last known elapsed
    /// reading; while paused, it holds still. Clamped to duration so a stale
    /// snapshot can never scrub past the end of the track.
    static func interpolatedElapsed(_ snapshot: NotchMediaSnapshot, at now: Date) -> Double {
        guard snapshot.isPlaying else { return snapshot.elapsed }
        let delta = now.timeIntervalSince(snapshot.timestamp)
        let projected = snapshot.elapsed + max(0, delta) * snapshot.playbackRate
        guard let duration = snapshot.duration else { return max(0, projected) }
        return min(max(0, projected), duration)
    }

    private static func sanitizedText(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clean = String(String.UnicodeScalarView(
            trimmed.unicodeScalars.filter { !forbiddenScalars.contains($0) }))
        return clean.isEmpty ? nil : String(clean.prefix(300))
    }

    private static func sanitizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count < 255 else { return nil }
        return trimmed
    }

    private static func sanitizedArtworkData(_ value: Any?) -> Data? {
        guard let data = value as? Data, !data.isEmpty, data.count <= maximumArtworkBytes else { return nil }
        return data
    }
}
