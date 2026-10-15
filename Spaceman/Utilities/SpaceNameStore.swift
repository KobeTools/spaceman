//
//  SpaceNameStore.swift
//  Spaceman
//
//  Created by René Uittenbogaard on 2025-09-16.
//  Co-author: ChatGPT
//

import Foundation

/// Centralizes reading and writing the per-space name information that is persisted in UserDefaults.
///
/// Historically the code touched `UserDefaults.standard` from multiple call sites, each performing their
/// own decode/encode cycle. Aside from duplicating work, that pattern made it easy to miss error handling
/// and complicated future changes to the storage format. `SpaceNameStore` wraps the persistence details in
/// one place and serializes access so callers can work with value-type dictionaries safely.
final class SpaceNameStore {
    static let shared = SpaceNameStore()

    private let defaults: UserDefaults
    private let key = "spaceNames"
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    private let queue = DispatchQueue(label: "dev.ruittenb.Spaceman.SpaceNameStore", attributes: .concurrent)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the complete dictionary of saved names. Callers get a value copy that they can mutate freely.
    func loadAll() -> [String: SpaceNameInfo] {
        queue.sync {
            loadUnlocked()
        }
    }

    /// Persists the given dictionary, replacing any existing stored data.
    func save(_ newValue: [String: SpaceNameInfo]) {
        queue.sync(flags: .barrier) {
            write(newValue, replacing: loadUnlocked())
        }
    }

    /// Loads the current dictionary, passes an inout copy to the mutating closure, and writes the result back.
    func update(_ mutate: (inout [String: SpaceNameInfo]) -> Void) {
        queue.sync(flags: .barrier) {
            let before = loadUnlocked()
            var names = before
            mutate(&names)
            write(names, replacing: before)
        }
    }

    /// Convenience for reading an entry for a single space.
    func nameInfo(for spaceID: String) -> SpaceNameInfo? {
        queue.sync {
            loadUnlocked()[spaceID]
        }
    }

    /// Convenience for saving or clearing a single entry.
    func setName(_ info: SpaceNameInfo?, for spaceID: String) {
        update { names in
            names[spaceID] = info
        }
    }

    // MARK: - Private helpers

    private func loadUnlocked() -> [String: SpaceNameInfo] {
        // Re-read what another process wrote (`defaults import`, a settings restore) while Spaceman runs.
        // Without this the running app kept its cached copy and saved it back over the restore (KobeTools fork).
        if defaults == .standard { CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication) }
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? decoder.decode([String: SpaceNameInfo].self, from: data)) ?? [:]
    }

    private func write(_ names: [String: SpaceNameInfo], replacing before: [String: SpaceNameInfo]) {
        guard let data = try? encoder.encode(names) else { return }
        defaults.set(data, forKey: key)
        if defaults == .standard { SpaceNameHistory.record(names, previous: before) }
    }
}

/// A dated copy of the names and colours in ~/.spaceman/space-names/ each time they change (the last 50),
/// so a mix-up can be undone: `defaults write dev.ruittenb.Spaceman spaceNames -data …` or
/// `defaults import`, with Spaceman quit (KobeTools fork).
enum SpaceNameHistory {
    static let directory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".spaceman/space-names", isDirectory: true)
    static let keep = 50

    /// What a person set: names (not the "---" placeholder) and colours, by space.
    static func userData(_ names: [String: SpaceNameInfo]) -> [String: String] {
        names.filter { $0.value.hasUserData }.mapValues { "\($0.spaceName)|\($0.colorHex ?? "")" }
    }

    static func record(_ names: [String: SpaceNameInfo], previous: [String: SpaceNameInfo]) {
        guard userData(names) != userData(previous) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        if let data = try? encoder.encode(names) {
            try? data.write(to: directory.appendingPathComponent("space-names-\(stamp).plist"), options: .atomic)
        }
        let files = (try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let old = files.filter { $0.lastPathComponent.hasPrefix("space-names-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .dropLast(keep)
        for url in old { try? fm.removeItem(at: url) }
    }
}
