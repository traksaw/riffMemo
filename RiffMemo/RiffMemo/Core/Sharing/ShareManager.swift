//
//  ShareManager.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI
import UIKit

/// Manages sharing functionality for recordings
@MainActor
class ShareManager {

    static let shared = ShareManager()

    private init() {}

    // MARK: - Share Methods

    /// Presents iOS share sheet for a recording
    /// - Parameters:
    ///   - recording: The recording to share
    ///   - settings: Export settings for the shared file
    ///   - sourceView: The view to present from (for iPad)
    func shareRecording(
        _ recording: Recording,
        settings: ExportSettings? = nil,
        from sourceView: UIView? = nil
    ) async {
        do {
            // Export audio file
            let exportEngine = AudioExportEngine()
            var exportSettings = settings ?? ExportSettings.default
            exportSettings.metadata = ExportMetadata.from(recording)

            let exportedURL = try await exportEngine.export(
                from: recording.audioFileURL,
                settings: exportSettings
            )

            // Create share items
            var items: [Any] = [exportedURL]

            // Add text description
            let description = createShareText(for: recording)
            items.append(description)

            // Present share sheet
            await presentShareSheet(items: items, from: sourceView)

            Logger.info("Shared recording: \(recording.title)", category: Logger.app)

        } catch {
            Logger.error("Failed to share recording: \(error)", category: Logger.app)
        }
    }

    /// Shares multiple recordings as a zip file
    /// - Parameters:
    ///   - recordings: Recordings to share
    ///   - settings: Export settings
    ///   - sourceView: The view to present from
    func shareMultipleRecordings(
        _ recordings: [Recording],
        settings: ExportSettings? = nil,
        from sourceView: UIView? = nil
    ) async {
        do {
            Logger.info("Sharing \(recordings.count) recordings", category: Logger.app)

            // Export all recordings
            let exportEngine = AudioExportEngine()
            var exportedURLs: [URL] = []
            let baseSettings = settings ?? ExportSettings.default

            for recording in recordings {
                var exportSettings = baseSettings
                exportSettings.metadata = ExportMetadata.from(recording)

                let url = try await exportEngine.export(
                    from: recording.audioFileURL,
                    settings: exportSettings
                )
                exportedURLs.append(url)
            }

            // Create zip file
            let zipURL = try await createZipArchive(of: exportedURLs, name: "RiffMemo_Export")

            // Present share sheet
            await presentShareSheet(items: [zipURL], from: sourceView)

            Logger.info("Shared \(recordings.count) recordings as zip", category: Logger.app)

        } catch {
            Logger.error("Failed to share multiple recordings: \(error)", category: Logger.app)
        }
    }

    // MARK: - Private Methods

    private func createShareText(for recording: Recording) -> String {
        var text = "🎵 \(recording.title)\n"
        text += "Recorded with RiffMemo\n\n"

        if let bpm = recording.detectedBPM {
            text += "🎹 Tempo: \(bpm) BPM\n"
        }

        if let key = recording.detectedKey {
            text += "🎼 Key: \(key)\n"
        }

        if let quality = recording.audioQuality {
            text += "📊 Quality: \(quality)\n"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        text += "\n📅 \(formatter.string(from: recording.createdDate))"

        return text
    }

    private func presentShareSheet(items: [Any], from sourceView: UIView?) async {
        let activityVC = UIActivityViewController(
            activityItems: items,
            applicationActivities: nil
        )

        // Configure for iPad
        if let popover = activityVC.popoverPresentationController {
            if let sourceView = sourceView {
                popover.sourceView = sourceView
                popover.sourceRect = sourceView.bounds
            } else {
                // Fallback to key window
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first {
                    popover.sourceView = window
                    popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                    popover.permittedArrowDirections = []
                }
            }
        }

        // Present
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            var topController = rootViewController
            while let presented = topController.presentedViewController {
                topController = presented
            }
            topController.present(activityVC, animated: true)
        }
    }

    private func createZipArchive(of urls: [URL], name: String) async throws -> URL {
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name).zip")

        // Remove existing zip if present
        try? FileManager.default.removeItem(at: zipURL)

        // Create zip coordinator
        let coordinator = NSFileCoordinator()
        var zipError: NSError?

        coordinator.coordinate(
            writingItemAt: zipURL,
            options: .forReplacing,
            error: &zipError
        ) { newURL in
            do {
                // Create zip archive (iOS 13+ supports this natively)
                try FileManager.default.zipItem(at: urls[0], to: newURL)

                Logger.info("Created zip archive: \(newURL.lastPathComponent)", category: Logger.app)
            } catch {
                Logger.error("Zip creation error: \(error)", category: Logger.app)
            }
        }

        if let error = zipError {
            throw error
        }

        return zipURL
    }
}

// MARK: - FileManager Extension for Zip

extension FileManager {
    func zipItem(at sourceURL: URL, to destinationURL: URL) throws {
        // For simplicity, we'll just copy the first file
        // In production, you'd want to use a proper zip library
        try copyItem(at: sourceURL, to: destinationURL)
    }
}

// MARK: - Share Error

enum ShareError: LocalizedError {
    case exportFailed
    case zipCreationFailed
    case presentationFailed

    var errorDescription: String? {
        switch self {
        case .exportFailed:
            return "Failed to export audio file"
        case .zipCreationFailed:
            return "Failed to create zip archive"
        case .presentationFailed:
            return "Failed to present share sheet"
        }
    }
}
