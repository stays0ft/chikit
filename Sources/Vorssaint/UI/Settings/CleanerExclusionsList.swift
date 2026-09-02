// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import SwiftUI

/// The cleaner's whitelist: paths and app bundle identifiers excluded from
/// every future scan, added from a result row's context menu ("Never scan
/// this again") and removable here. Sits quietly collapsed as a single row
/// when empty, exactly like the other exclusion lists in Settings.
struct CleanerExclusionsList: View {
    @ObservedObject private var l10n = L10n.shared
    @State private var paths: [String] = Self.savedPaths
    @State private var owners: [String] = Self.savedOwners
    @State private var isExpanded: Bool

    private var strings: CleanerExclusionStrings {
        FeatureStrings.cleanerExclusions(l10n.language)
    }

    init() {
        _isExpanded = State(initialValue: !(Self.savedPaths.isEmpty && Self.savedOwners.isEmpty))
    }

    private var totalCount: Int { paths.count + owners.count }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if !owners.isEmpty {
                Text(strings.appsHeader)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(owners, id: \.self) { bundleID in
                    row(icon: "app.badge", text: bundleID) {
                        CleanerExclusions.removeOwner(bundleID)
                        owners = Self.savedOwners
                    }
                }
            }
            if !paths.isEmpty {
                Text(strings.pathsHeader)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(paths, id: \.self) { path in
                    row(icon: "folder", text: prettyPath(path)) {
                        CleanerExclusions.removePath(path)
                        paths = Self.savedPaths
                    }
                }
            }
            Text(strings.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            HStack {
                Text(strings.listTitle)
                Spacer()
                if totalCount > 0 {
                    Text("\(totalCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .onAppear {
            paths = Self.savedPaths
            owners = Self.savedOwners
        }
    }

    private func row(icon: String, text: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(strings.removeButton)
        }
    }

    private func prettyPath(_ path: String) -> String {
        path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private static var savedPaths: [String] {
        (UserDefaults.standard.stringArray(forKey: DefaultsKey.cleanerExcludedPaths) ?? []).sorted()
    }

    private static var savedOwners: [String] {
        (UserDefaults.standard.stringArray(forKey: DefaultsKey.cleanerExcludedBundleIDs) ?? []).sorted()
    }
}
