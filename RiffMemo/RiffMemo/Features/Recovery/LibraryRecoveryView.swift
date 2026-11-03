//
//  LibraryRecoveryView.swift
//  RiffMemo
//

import SwiftUI
import UIKit
import OSLog

/// WAS-121: shown instead of the app when the library store can't be opened.
/// Offers Retry and a raw-audio export so takes are never held hostage by a
/// broken database. Nothing here deletes or resets the store.
struct LibraryRecoveryView: View {
    let error: any Error
    /// Retries that have already failed; non-zero means Retry ran and the store still won't open.
    let failedRetryCount: Int
    let onRetry: () -> Void

    @State private var stagedExport: AudioRecovery.StagedExport?
    @State private var isPreparingExport = false
    @State private var isExporting = false
    @State private var exportMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Can't open library")
                    .font(.title2.bold())
                Text("RiffMemo couldn't open your recordings library. Your audio files are still on this device. Export them to Files to keep them safe, then try again.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    onRetry()
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("libraryRecovery.retry")

                Button {
                    Task { await prepareExport() }
                } label: {
                    HStack {
                        if isPreparingExport {
                            ProgressView()
                        }
                        Label("Export my audio", systemImage: "square.and.arrow.up")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isPreparingExport || isExporting)
                .accessibilityIdentifier("libraryRecovery.export")
            }
            .controlSize(.large)

            if failedRetryCount > 0 {
                Text("Still can't open the library (tried \(failedRetryCount) time\(failedRetryCount == 1 ? "" : "s")). Exporting your audio is the safest next step.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("libraryRecovery.retryFailed")
            }

            if let exportMessage {
                Text(exportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("libraryRecovery.exportMessage")
            }

            Spacer()

            Text(error.localizedDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(24)
        .sheet(isPresented: $isExporting, onDismiss: finishExport) {
            AudioExportPicker(urls: stagedExport?.files ?? []) { didExport in
                if didExport, let stagedExport {
                    exportMessage = Self.exportSummary(for: stagedExport)
                }
                isExporting = false
            }
            .ignoresSafeArea()
        }
    }

    private func prepareExport() async {
        isPreparingExport = true
        exportMessage = nil
        defer { isPreparingExport = false }

        let storeURL = LibraryStore.defaultStoreURL
        // Off the main thread: the copy fallback can take a while on a big library.
        let result = await Task.detached(priority: .userInitiated) {
            Result {
                try AudioRecovery.stageForExport(
                    audioFiles: AudioRecovery.audioFiles(),
                    libraryFiles: AudioRecovery.libraryStoreFiles(storeURL: storeURL)
                )
            }
        }.value

        if case .success(let staged) = result, !staged.skippedFiles.isEmpty {
            Logger.data.error("Recovery export skipped unreadable files: \(staged.skippedFiles)")
        }

        switch result {
        case .success(let staged) where staged.audioCount == 0 && staged.skippedFiles.isEmpty:
            exportMessage = String(localized: "No audio files were found on this device.")
            AudioRecovery.clearStaging()
        case .success(let staged) where staged.files.isEmpty:
            exportMessage = Self.exportSummary(for: staged)
            AudioRecovery.clearStaging()
        case .success(let staged):
            stagedExport = staged
            isExporting = true
        case .failure(let error):
            exportMessage = String(localized: "Couldn't prepare your audio for export: \(error.localizedDescription)")
        }
    }

    /// Runs however the picker goes away (export, cancel, or swipe-down).
    private func finishExport() {
        stagedExport = nil
        AudioRecovery.clearStaging()
    }

    static func exportSummary(for staged: AudioRecovery.StagedExport) -> String {
        var lines = [String(localized: "Exported \(staged.audioCount) audio takes, named by recording date.")]
        if staged.includesLibraryBackup {
            lines.append(String(localized: "Also saved \"\(AudioRecovery.libraryBackupBaseName)\" files, which hold your titles and notes. Keep them together."))
        }
        if !staged.skippedFiles.isEmpty {
            lines.append(String(localized: "\(staged.skippedFiles.count) files couldn't be read: \(staged.skippedFiles.joined(separator: ", "))"))
        }
        return lines.joined(separator: "\n")
    }
}

/// Copies the given files to a user-chosen Files location. `asCopy: true` means
/// the originals stay in place; the export never moves or removes anything.
private struct AudioExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    /// Called with `true` once the files are exported, `false` if the user cancelled.
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onFinish: (Bool) -> Void

        init(onFinish: @escaping (Bool) -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(false)
        }
    }
}

#Preview {
    LibraryRecoveryView(
        error: CocoaError(.fileReadCorruptFile),
        failedRetryCount: 1,
        onRetry: {}
    )
}
