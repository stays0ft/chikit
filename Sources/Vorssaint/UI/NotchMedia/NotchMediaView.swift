// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// Root content of the notch media panel: a slim pill while collapsed, a
/// full playback card once hovered/clicked open. Mirrors the shelf's own
/// collapsed-pill/expanded-card split (`ShelfService.dockedExpanded`).
struct NotchMediaWidgetView: View {
    @EnvironmentObject private var service: NotchMediaService

    var body: some View {
        Group {
            switch service.state {
            case .idle, .loading:
                Color.clear.frame(width: 1, height: 1)
            case let .session(snapshot):
                if service.isExpanded {
                    NotchMediaExpandedView(snapshot: snapshot)
                } else {
                    NotchMediaPillView(snapshot: snapshot)
                }
            }
        }
        .onHover { inside in
            if inside {
                service.expand()
            } else {
                service.scheduleCollapse()
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: service.isExpanded)
    }
}

/// The idle/collapsed state: a small "something is playing" indicator, the
/// Dynamic Island's collapsed pill translated to a MacBook notch. Hidden
/// entirely (the panel itself is ordered out) whenever nothing is playing.
private struct NotchMediaPillView: View {
    let snapshot: NotchMediaSnapshot
    @State private var barPhase = false

    var body: some View {
        HStack(spacing: 6) {
            artwork
            NotchAudioBarsView(isPlaying: snapshot.isPlaying)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.001)))
        .background(HUDBackdrop(cornerRadius: 20, contrast: .high))
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture { NotchMediaService.shared.expand() }
        .accessibilityLabel(snapshot.title ?? NotchMediaApplication.name(for: snapshot) ?? "")
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = snapshot.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 16, height: 16)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

/// Three tiny animated bars, the collapsed pill's "audio playing" tell.
struct NotchAudioBarsView: View {
    let isPlaying: Bool
    @State private var animate = false

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.primary.opacity(0.85))
                    .frame(width: 2.5, height: barHeight(index))
            }
        }
        .frame(width: 14, height: 14, alignment: .center)
        .onAppear { animate = isPlaying }
        .onChange(of: isPlaying) { _, playing in animate = playing }
        .animation(
            isPlaying
                ? .easeInOut(duration: 0.4).repeatForever(autoreverses: true)
                : .default,
            value: animate)
    }

    private func barHeight(_ index: Int) -> CGFloat {
        guard animate else { return 4 }
        let base: [CGFloat] = [7, 13, 9]
        return base[index % base.count]
    }
}

/// The expanded card: artwork, title/artist, transport controls and a
/// best-effort scrubber. Styled after `RadialNowPlayingCard`.
private struct NotchMediaExpandedView: View {
    let snapshot: NotchMediaSnapshot

    @ObservedObject private var l10n = L10n.shared
    @State private var dragElapsed: Double?

    private var text: NotchMediaFeatureStrings { FeatureStrings.notchMedia(l10n.language) }
    private var appName: String { NotchMediaApplication.name(for: snapshot) ?? text.nowPlayingFallback }
    private var title: String { snapshot.title ?? appName }
    private var duration: Double { max(snapshot.duration ?? 0, 1) }
    private var liveElapsed: Double {
        dragElapsed ?? min(NotchMediaSupport.interpolatedElapsed(snapshot, at: Date()), duration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if let artist = snapshot.artist {
                        Text(artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if let album = snapshot.album {
                        Text(album)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    NotchMediaService.shared.collapse()
                    NotchMediaApplication.open(snapshot)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(format: text.openAppFormat, appName))
            }

            if snapshot.duration != nil {
                scrubber
            }

            HStack(spacing: 22) {
                Spacer(minLength: 0)
                transportButton(systemName: "backward.fill") {
                    NotchMediaService.shared.send(.previousTrack)
                }
                transportButton(systemName: snapshot.isPlaying ? "pause.fill" : "play.fill", large: true) {
                    NotchMediaService.shared.send(.playPause)
                }
                transportButton(systemName: "forward.fill") {
                    NotchMediaService.shared.send(.nextTrack)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(HUDBackdrop(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var artwork: some View {
        if let data = snapshot.artworkData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Theme.spaceGradient)
                .frame(width: 56, height: 56)
                .overlay {
                    if let icon = NotchMediaApplication.icon(for: snapshot) {
                        Image(nsImage: icon).resizable().interpolation(.high).frame(width: 30, height: 30)
                    } else {
                        Image(systemName: "music.note")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
        }
    }

    private var scrubber: some View {
        VStack(spacing: 3) {
            Slider(value: Binding(
                get: { liveElapsed },
                set: { dragElapsed = $0 }
            ), in: 0...duration, onEditingChanged: { editing in
                if !editing, let value = dragElapsed {
                    NotchMediaService.shared.send(.seek(to: value))
                    dragElapsed = nil
                }
            })
            .controlSize(.mini)
            HStack {
                Text(NotchMediaTimeFormat.string(liveElapsed))
                Spacer()
                Text(NotchMediaTimeFormat.string(duration))
            }
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(.secondary)
        }
    }

    private func transportButton(systemName: String, large: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: large ? 17 : 13, weight: .semibold))
                .frame(width: large ? 30 : 22, height: large ? 30 : 22)
        }
        .buttonStyle(.plain)
    }
}

enum NotchMediaTimeFormat {
    static func string(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
