//
//  PlaybackProgressStore.swift
//  NookPlay
//
//  Created by Codex on 2026/03/19.
//

import Foundation

actor PlaybackProgressStore {
    private let fileManager: FileManager
    private let fileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = appSupportURL.appendingPathComponent("NookPlay", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("resume-progress.json")
    }

    func loadResumeEntry(for itemID: PlaybackItemID) -> ResumeEntry? {
        let allEntries = loadAllEntries()
        return allEntries[itemID.storageKey]
    }

    func saveResumeEntry(_ entry: ResumeEntry) {
        var allEntries = loadAllEntries()
        allEntries[entry.itemID.storageKey] = entry
        persist(allEntries)
    }

    func removeResumeEntry(for itemID: PlaybackItemID) {
        var allEntries = loadAllEntries()
        allEntries.removeValue(forKey: itemID.storageKey)
        persist(allEntries)
    }

    private func loadAllEntries() -> [String: ResumeEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return [:]
        }

        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode([String: ResumeEntry].self, from: data)
        } catch {
            return [:]
        }
    }

    private func persist(_ entries: [String: ResumeEntry]) {
        do {
            let directoryURL = fileURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to persist playback progress: \(error.localizedDescription)")
        }
    }
}
