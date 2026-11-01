//
//  LibraryRecoveryView.swift
//  RiffMemo
//

import SwiftUI
import UIKit

/// WAS-121: shown instead of the app when the library store can't be opened.
/// Offers Retry and a raw-audio export so takes are never held hostage by a
/// broken database. Nothing here deletes or resets the store.
struct LibraryRecoveryView: View {
    let error: any Error
    /// Retries that have already failed; non-zero means Retry ran and the store still won't open.
    let failedRetryCount: Int
    let onRetry: () -> Void

    @State private var filesToExport: [URL] = []
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
                    prepareExport()
                } label: {
                    Label("Export my audio", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
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
            }

            Spacer()

            Text(error.localizedDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
        }
        .padding(24)
        .sheet(isPresented: $isExporting) {
            AudioExportPicker(urls: filesToExport) { exportedCount in
                isExporting = false
                if let exportedCount {
                    exportMessage = String(localized: "Exported \(exportedCount) of \(filesToExport.count) audio files.")
                }
            }
            .ignoresSafeArea()
        }
    }

    private func prepareExport() {
        do {
            let files = try AudioRecovery.audioFiles()
            guard !files.isEmpty else {
                exportMessage = String(localized: "No audio files were found on this device.")
                return
            }
            filesToExport = try AudioRecovery.stageForExport(files)
            isExporting = true
        } catch {
            exportMessage = String(localized: "Couldn't prepare your audio for export: \(error.localizedDescription)")
        }
    }
}

/// Copies the given files to a user-chosen Files location. `asCopy: true` means
/// the originals stay in place; the export never moves or removes anything.
private struct AudioExportPicker: UIViewControllerRepresentable {
    let urls: [URL]
    /// Called with the number of files exported, or `nil` if the user cancelled.
    let onFinish: (Int?) -> Void

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
        let onFinish: (Int?) -> Void

        init(onFinish: @escaping (Int?) -> Void) {
            self.onFinish = onFinish
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onFinish(urls.count)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onFinish(nil)
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
