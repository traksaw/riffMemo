//
//  AudioRecovery.swift
//  RiffMemo
//

import Foundation
import UniformTypeIdentifiers

/// WAS-121: finds the raw audio files on disk so they can be exported even when the
/// SwiftData store can't be opened. Audio lives as plain files in Documents (see
/// `AudioRecordingManager` / `Recording.audioFileURL`), independent of the store,
/// so this deliberately does not consult `Recording` rows at all.
///
/// `nonisolated` because the target defaults to MainActor isolation, and staging a
/// large library with the copy fallback must run off the main thread.
nonisolated enum AudioRecovery {
    /// Result of staging an export. Partial success is the normal failure mode:
    /// one unreadable take must not cost the user every other take.
    struct StagedExport: Sendable {
        /// Everything to hand to the document picker: audio first, then the library backup.
        var files: [URL] = []
        var audioCount = 0
        var includesLibraryBackup = false
        /// Original filenames that couldn't be staged.
        var skippedFiles: [String] = []
    }

    static let libraryBackupBaseName = "RiffMemo Library Backup"

    static var defaultAudioDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var defaultStagingDirectory: URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioRecoveryExport", isDirectory: true)
    }

    /// Every audio file directly inside `directory`, sorted by name.
    static func audioFiles(in directory: URL = defaultAudioDirectory) throws -> [URL] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        return contents
            .filter { url in
                let isRegularFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false
                let isAudio = UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false
                return isRegularFile && isAudio
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The SQLite store plus its `-wal`/`-shm` sidecars, whichever exist. The WAL
    /// holds the most recent writes, so a backup without it can silently miss them.
    static func libraryStoreFiles(storeURL: URL) -> [URL] {
        ["", "-wal", "-shm"]
            .map { URL(fileURLWithPath: storeURL.path + $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Prepares audio (and optionally the library database) for export under
    /// human-readable names. On disk takes are `recording_<UUID>.caf` and their titles
    /// live in the store that just failed to open, so the recording date is the best
    /// label left to tell takes apart. The raw store is included so titles, notes and
    /// analysis can still be recovered later instead of being lost with the app.
    ///
    /// Each entry is a hard link where possible: it shares the original's bytes, so
    /// staging costs no extra space (a full disk is one reason the store fails to
    /// open). Falls back to a real copy if linking isn't possible, and skips (rather
    /// than aborts on) any file that can't be staged at all. Originals are never moved
    /// or modified.
    static func stageForExport(
        audioFiles: [URL],
        libraryFiles: [URL] = [],
        in stagingDirectory: URL = defaultStagingDirectory,
        timeZone: TimeZone = .current
    ) throws -> StagedExport {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: stagingDirectory)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        // Dots, not colons: colons aren't allowed in Files/Finder filenames.
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"

        var result = StagedExport()
        var usedNames = Set<String>()

        for source in audioFiles {
            let values = try? source.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let baseName: String
            if let date = values?.creationDate ?? values?.contentModificationDate {
                baseName = "RiffMemo \(formatter.string(from: date))"
            } else {
                baseName = source.deletingPathExtension().lastPathComponent
            }

            let fileName = uniqueFileName(baseName, extension: source.pathExtension, avoiding: &usedNames)
            if let staged = stage(source, as: fileName, in: stagingDirectory) {
                result.files.append(staged)
                result.audioCount += 1
            } else {
                result.skippedFiles.append(source.lastPathComponent)
            }
        }

        // Sidecar names must keep the store's base name + suffix pairing
        // ("X.store", "X.store-wal", "X.store-shm") or SQLite won't reopen them together.
        var stagedLibraryFiles: [URL] = []
        for source in libraryFiles {
            let storeBaseName = libraryFiles[0].deletingPathExtension().lastPathComponent
            let suffix = source.lastPathComponent.dropFirst(storeBaseName.count)
            if let staged = stage(source, as: libraryBackupBaseName + suffix, in: stagingDirectory) {
                stagedLibraryFiles.append(staged)
            } else {
                stagedLibraryFiles.removeAll()
                result.skippedFiles.append(source.lastPathComponent)
                break  // A store without its WAL is a misleading backup; ship all or none.
            }
        }
        result.files += stagedLibraryFiles
        result.includesLibraryBackup = !stagedLibraryFiles.isEmpty
        return result
    }

    /// Removes staged entries once the picker has finished copying them out. Only
    /// matters for the copy fallback; hard links free nothing but cost nothing either.
    static func clearStaging(in stagingDirectory: URL = defaultStagingDirectory) {
        try? FileManager.default.removeItem(at: stagingDirectory)
    }

    private static func stage(_ source: URL, as fileName: String, in stagingDirectory: URL) -> URL? {
        let destination = stagingDirectory.appendingPathComponent(fileName)
        do {
            try FileManager.default.linkItem(at: source, to: destination)
            return destination
        } catch {
            do {
                try FileManager.default.copyItem(at: source, to: destination)
                return destination
            } catch {
                // Not logged here: `Logger` is MainActor-isolated and this runs off-main.
                // The caller surfaces every skipped filename to the user instead.
                return nil
            }
        }
    }

    /// Two takes recorded in the same second would otherwise collide; suffix with " (2)", " (3)"…
    private static func uniqueFileName(_ baseName: String, extension ext: String, avoiding usedNames: inout Set<String>) -> String {
        var candidate = "\(baseName).\(ext)"
        var counter = 2
        while usedNames.contains(candidate.lowercased()) {
            candidate = "\(baseName) (\(counter)).\(ext)"
            counter += 1
        }
        usedNames.insert(candidate.lowercased())
        return candidate
    }
}
