// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import Foundation

/// The user's own whitelist for the cleaner: exact paths and leftover-owner
/// bundle identifiers that are kept out of every future scan, on top of the
/// built-in safety rules in `CleanerPolicy`. Nothing here weakens those
/// rules — this only ever removes items the scan would otherwise show, and
/// an excluded owner never removes the protection `CleanerSupport` already
/// gives Apple's own domains, this app, or shared infrastructure.
enum CleanerExclusions {
    static var excludedPaths: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: DefaultsKey.cleanerExcludedPaths) ?? [])
    }

    static var excludedOwners: Set<String> {
        Set((UserDefaults.standard.stringArray(forKey: DefaultsKey.cleanerExcludedBundleIDs) ?? [])
            .map { $0.lowercased() })
    }

    static func excludePath(_ path: String) {
        var paths = excludedPaths
        paths.insert(path)
        write(paths, key: DefaultsKey.cleanerExcludedPaths)
    }

    static func removePath(_ path: String) {
        var paths = excludedPaths
        paths.remove(path)
        write(paths, key: DefaultsKey.cleanerExcludedPaths)
    }

    static func excludeOwner(_ bundleID: String) {
        var owners = excludedOwners
        owners.insert(bundleID.lowercased())
        write(owners, key: DefaultsKey.cleanerExcludedBundleIDs)
    }

    static func removeOwner(_ bundleID: String) {
        var owners = excludedOwners
        owners.remove(bundleID.lowercased())
        write(owners, key: DefaultsKey.cleanerExcludedBundleIDs)
    }

    /// Whether a scanned find should be hidden: its exact path was excluded,
    /// it lives inside an excluded folder, or (leftovers only) its owning
    /// bundle identifier is on the whitelist.
    static func isExcluded(path: String, owner: String?) -> Bool {
        if let owner, !owner.isEmpty, excludedOwners.contains(owner.lowercased()) {
            return true
        }
        let paths = excludedPaths
        if paths.contains(path) { return true }
        return paths.contains { path.hasPrefix($0 + "/") }
    }

    private static func write(_ values: Set<String>, key: String) {
        UserDefaults.standard.set(values.sorted(), forKey: key)
    }
}
