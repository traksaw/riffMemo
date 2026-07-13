# WAS-59: Stop Views Bypassing ViewModels — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close four MVVM leaks so every View routes data mutation and business logic through a ViewModel instead of touching repositories/generators/singletons/local shadow state directly.

**Architecture:** Each of the four screens gets a narrow, targeted fix that matches the pattern already used elsewhere in the app (`@Observable @MainActor` ViewModel classes, `@State` held by the View, private dependencies). No new abstractions beyond what each screen already needs.

**Tech Stack:** Swift 6.2 / SwiftUI / SwiftData / XCTest, iOS app target `RiffMemo`, test target `RiffMemoTests`.

---

## Task 1: LibraryViewModel — move bulk-delete and rename off the View, make `repository` private

**Files:**
- Modify: `RiffMemo/RiffMemo/Features/Library/LibraryViewModel.swift`
- Modify: `RiffMemo/RiffMemo/Features/Library/LibraryView.swift:250-265,271-366` (`deleteSelectedRecordings`, `RecordingRow`)
- Test: `RiffMemo/RiffMemoTests/LibraryViewModelTests.swift` (new)

**Step 1: Add `deleteRecordings(withIDs:)` and `renameRecording(_:to:)` to `LibraryViewModel`, make `repository` private**

In `LibraryViewModel.swift`, change:
```swift
let repository: RecordingRepository
```
to:
```swift
/// Private so a View can never reach past the ViewModel to mutate persistence
/// directly (WAS-59) — the `private` keyword is the enforcement: any View code
/// that writes `viewModel.repository...` fails to compile. Route all data
/// operations through ViewModel methods instead.
private let repository: RecordingRepository
```

Refactor `deleteAllRecordings()` to share logic with the new bulk-delete method:
```swift
func deleteAllRecordings() async {
    guard !recordings.isEmpty else { return }
    Logger.info("Deleting all \(recordings.count) recordings", category: Logger.data)
    await deleteRecordings(recordings)
    Logger.info("Deleted all recordings", category: Logger.data)
}

/// Deletes the recordings whose id is in `ids`. Used by the Library's
/// multi-select "Delete" action; kept separate from `deleteAllRecordings`
/// only because the two log different messages.
func deleteRecordings(withIDs ids: Set<Recording.ID>) async {
    let recordingsToDelete = recordings.filter { ids.contains($0.id) }
    guard !recordingsToDelete.isEmpty else { return }
    Logger.info("Deleting \(recordingsToDelete.count) selected recordings", category: Logger.data)
    await deleteRecordings(recordingsToDelete)
    Logger.info("Deleted selected recordings", category: Logger.data)
}

private func deleteRecordings(_ recordingsToDelete: [Recording]) async {
    for recording in recordingsToDelete {
        do {
            try await repository.delete(recording)
        } catch {
            Logger.error("Failed to delete recording \(recording.title): \(error)", category: Logger.data)
        }
    }
    await loadRecordings()
}

/// Renames a recording through the repository (not a direct `recording.title =`
/// mutation from a View) so the change is persisted via the same path CloudKit
/// sync relies on (WAS-51).
func renameRecording(_ recording: Recording, to newTitle: String) async {
    guard !newTitle.isEmpty else { return }
    recording.title = newTitle
    do {
        try await repository.update(recording)
        Logger.info("Renamed recording to: \(newTitle)", category: Logger.data)
    } catch {
        Logger.error("Failed to rename recording: \(error)", category: Logger.data)
    }
}
```

**Step 2: Update `LibraryView.swift` to use the new methods and stop touching `repository`/`recording.title` directly**

Delete the private `deleteSelectedRecordings()` method (`LibraryView.swift:249-266`) entirely and replace its call site:
```swift
Button("Delete \(selectedRecordings.count)", role: .destructive) {
    Task {
        await viewModel.deleteRecordings(withIDs: selectedRecordings)
        HapticManager.shared.success()
        editMode = .inactive
        selectedRecordings.removeAll()
    }
}
```

Give `RecordingRow` an `onRename` closure instead of mutating `recording.title` itself:
```swift
struct RecordingRow: View {
    let recording: Recording
    let onRename: (String) -> Void
    @State private var isEditing = false
    @State private var editedTitle = ""
    ...
    .onSubmit {
        if !editedTitle.isEmpty {
            onRename(editedTitle)
        }
        isEditing = false
    }
```

Update both call sites in `LibraryView.body` to pass the closure:
```swift
RecordingRow(recording: recording, onRename: { newTitle in
    Task { await viewModel.renameRecording(recording, to: newTitle) }
})
```
(one inside the `isSelectionMode` branch, one inside the `NavigationLink` label — both currently at `LibraryView.swift:48` and `61`.)

**Step 3: Build to confirm no other code reaches `viewModel.repository`**

Run: `xcodebuild -project RiffMemo/RiffMemo.xcodeproj -scheme RiffMemo -destination "generic/platform=iOS Simulator" build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED. (If anything outside `LibraryViewModel.swift` referenced `.repository`, this fails with "'repository' is inaccessible due to 'private' protection level" — confirms the compiler guard works.)

**Step 4: Write tests for the new ViewModel methods**

Create `RiffMemo/RiffMemoTests/LibraryViewModelTests.swift`. Follow the leaked-container pattern from `RecordingRepositoryDeleteTests.swift` (deiniting a `@MainActor` app-module class holding a `ModelContext` crashes on this toolchain — see `swiftdata_repo_deinit_crash` memory).

```swift
//
//  LibraryViewModelTests.swift
//  RiffMemoTests
//

import XCTest
import SwiftData
@testable import RiffMemo

/// WAS-59: LibraryViewModel now owns bulk-delete and rename so LibraryView can't
/// reach past it into the repository or mutate `recording.title` directly.
@MainActor
final class LibraryViewModelTests: XCTestCase {

    private static var leakedToAvoidToolchainDeinitCrash: [Any] = []

    var viewModel: LibraryViewModel!
    var createdFileURLs: [URL] = []

    override func setUpWithError() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Recording.self, configurations: configuration)
        let repository = SwiftDataRecordingRepository(modelContext: container.mainContext)
        let viewModel = LibraryViewModel(repository: repository)
        Self.leakedToAvoidToolchainDeinitCrash.append(container)
        Self.leakedToAvoidToolchainDeinitCrash.append(repository)
        Self.leakedToAvoidToolchainDeinitCrash.append(viewModel)
        self.viewModel = viewModel
        createdFileURLs = []
    }

    override func tearDownWithError() throws {
        for url in createdFileURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func makeRecordingWithFile(title: String = "Test") throws -> Recording {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WAS59-\(UUID().uuidString).caf")
        try Data("fake audio".utf8).write(to: url)
        createdFileURLs.append(url)
        return Recording(title: title, duration: 1, audioFileURL: url)
    }

    func testDeleteRecordingsWithIDsOnlyDeletesSelected() async throws {
        let keep = try makeRecordingWithFile(title: "Keep")
        let remove = try makeRecordingWithFile(title: "Remove")
        try await viewModel.saveForTest(keep)
        try await viewModel.saveForTest(remove)
        await viewModel.loadRecordings()

        await viewModel.deleteRecordings(withIDs: [remove.id])
        await viewModel.loadRecordings()

        XCTAssertEqual(viewModel.recordings.map(\.title), ["Keep"])
    }

    func testDeleteRecordingsWithEmptyIDsIsNoOp() async throws {
        let recording = try makeRecordingWithFile()
        try await viewModel.saveForTest(recording)
        await viewModel.loadRecordings()

        await viewModel.deleteRecordings(withIDs: [])
        await viewModel.loadRecordings()

        XCTAssertEqual(viewModel.recordings.count, 1)
    }

    func testRenameRecordingUpdatesTitle() async throws {
        let recording = try makeRecordingWithFile(title: "Old Title")
        try await viewModel.saveForTest(recording)

        await viewModel.renameRecording(recording, to: "New Title")

        XCTAssertEqual(recording.title, "New Title")
    }

    func testRenameRecordingIgnoresEmptyTitle() async throws {
        let recording = try makeRecordingWithFile(title: "Keep Me")

        await viewModel.renameRecording(recording, to: "")

        XCTAssertEqual(recording.title, "Keep Me")
    }
}
```

This test needs a way to save a recording through the ViewModel's own repository without exposing `repository` outside the type. Add a `#if DEBUG`-gated test hook to `LibraryViewModel` right under the `private let repository` declaration:
```swift
#if DEBUG
    /// Test-only seam: lets `LibraryViewModelTests` save fixtures without
    /// making `repository` non-private for production code.
    func saveForTest(_ recording: Recording) async throws {
        try await repository.save(recording)
    }
#endif
```

**Step 5: Run the new tests**

Run: `xcodebuild test -project RiffMemo/RiffMemo.xcodeproj -scheme RiffMemo -destination "platform=iOS Simulator,name=iPhone 16" -only-testing:RiffMemoTests/LibraryViewModelTests 2>&1 | tail -60`
Expected: all 4 tests pass.

**Step 6: Commit**
```bash
git add RiffMemo/RiffMemo/Features/Library/LibraryViewModel.swift RiffMemo/RiffMemo/Features/Library/LibraryView.swift RiffMemo/RiffMemoTests/LibraryViewModelTests.swift
git commit -m "fix(library): WAS-59 — route bulk-delete and rename through LibraryViewModel"
```

---

## Task 2: WaveformThumbnail — delete its private cache, use `WaveformViewModel`

**Files:**
- Modify: `RiffMemo/RiffMemo/Features/Waveform/WaveformThumbnail.swift:1-80`

**Context:** `WaveformThumbnail` currently instantiates its own `WaveformGenerator`, keeps its own `samples`/`isLoading` `@State`, and writes `recording.waveformData` itself — a second, independent implementation of the exact caching `WaveformViewModel` already does (used by `RecordingDetailView`). `WaveformViewModel` already takes a configurable `targetSamples` (default 300; thumbnails need 100).

**Step 1: Replace the local state with a `WaveformViewModel` instance**

```swift
struct WaveformThumbnail: View {
    let recording: Recording
    let height: CGFloat

    @State private var viewModel: WaveformViewModel

    init(recording: Recording, height: CGFloat = 40) {
        self.recording = recording
        self.height = height
        self._viewModel = State(initialValue: WaveformViewModel(recording: recording, targetSamples: 100))
    }

    var body: some View {
        Group {
            if viewModel.isLoading {
                WaveformSkeleton()
                    .frame(height: height)
            } else if !viewModel.samples.isEmpty {
                WaveformView(
                    samples: viewModel.samples,
                    configuration: .thumbnail
                )
                .frame(height: height)
            } else {
                WaveformPlaceholder(compact: true)
                    .frame(height: height)
            }
        }
        .task {
            await viewModel.loadWaveform()
        }
    }
}
```

Delete the old `loadWaveform()` private method entirely — `WaveformViewModel.loadWaveform()` replaces it. The `WaveformSkeleton`, `WaveformPlaceholder` extension, and previews below stay unchanged.

**Step 2: Build**

Run: `xcodebuild -project RiffMemo/RiffMemo.xcodeproj -scheme RiffMemo -destination "generic/platform=iOS Simulator" build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**
```bash
git add RiffMemo/RiffMemo/Features/Waveform/WaveformThumbnail.swift
git commit -m "fix(waveform): WAS-59 — WaveformThumbnail reuses WaveformViewModel's cache"
```

---

## Task 3: TunerView — bind directly to `pitchDetector.isDetecting`

**Files:**
- Modify: `RiffMemo/RiffMemo/Features/Tuner/TunerView.swift:10-140`

**Step 1: Remove the local `isActive` state and every reference to it**

Delete `@State private var isActive = false` (line 12).

Replace every `isActive` read in `body` with `pitchDetector.isDetecting`:
```swift
Image(systemName: pitchDetector.isDetecting ? "stop.circle.fill" : "play.circle.fill")
    .font(.title2)

Text(pitchDetector.isDetecting ? "Stop" : "Start Tuner")
    .font(.title3)
    .fontWeight(.semibold)
...
.background(pitchDetector.isDetecting ? Color.red : Color.blue)
```

Replace `onDisappear`:
```swift
.onDisappear {
    Task {
        await pitchDetector.stopDetection()
    }
}
```
(`stopDetection()` already guards on `isDetecting` internally, so this is safe to call unconditionally.)

Replace `toggleTuner()`:
```swift
private func toggleTuner() {
    Task {
        if pitchDetector.isDetecting {
            await pitchDetector.stopDetection()
            HapticManager.shared.lightTap()
        } else {
            do {
                try await pitchDetector.startDetection()
                HapticManager.shared.mediumTap()
            } catch {
                Logger.error("Failed to start tuner: \(error)", category: Logger.audio)
            }
        }
    }
}
```

**Step 2: Build**

Run: `xcodebuild -project RiffMemo/RiffMemo.xcodeproj -scheme RiffMemo -destination "generic/platform=iOS Simulator" build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

**Step 3: Commit**
```bash
git add RiffMemo/RiffMemo/Features/Tuner/TunerView.swift
git commit -m "fix(tuner): WAS-59 — bind Start/Stop directly to pitchDetector.isDetecting"
```

---

## Task 4: Export/Analysis — add ViewModels

**Files:**
- Create: `RiffMemo/RiffMemo/Features/Export/ExportViewModel.swift`
- Create: `RiffMemo/RiffMemo/Features/Analysis/AnalysisViewModel.swift`
- Modify: `RiffMemo/RiffMemo/Features/Export/ExportOptionsView.swift:11-157`
- Modify: `RiffMemo/RiffMemo/Features/Export/BatchExportView.swift:11-173`
- Modify: `RiffMemo/RiffMemo/Features/Analysis/AnalysisResultsView.swift:218-250` (`AnalyzeButton`)

**Step 1: Create `ExportViewModel`**

```swift
//
//  ExportViewModel.swift
//  RiffMemo
//

import Foundation
import Observation

/// ViewModel for the export screens (single-recording and batch)
@MainActor
@Observable
class ExportViewModel {

    // MARK: - Published State

    var isExporting: Bool = false
    var exportProgress: Double = 0

    // MARK: - Dependencies

    private let shareManager: ShareManager

    // MARK: - Initialization

    init(shareManager: ShareManager = .shared) {
        self.shareManager = shareManager
    }

    // MARK: - Actions

    func exportAndShare(
        _ recording: Recording,
        format: AudioFormat,
        quality: ExportQuality,
        includeMetadata: Bool
    ) async {
        isExporting = true

        let settings = ExportSettings(
            format: format,
            quality: quality,
            includeMetadata: includeMetadata,
            metadata: includeMetadata ? ExportMetadata.from(recording) : nil
        )
        await shareManager.shareRecording(recording, settings: settings)

        isExporting = false
    }

    func exportAll(
        _ recordings: [Recording],
        format: AudioFormat,
        quality: ExportQuality,
        includeMetadata: Bool
    ) async {
        isExporting = true
        exportProgress = 0

        let settings = ExportSettings(
            format: format,
            quality: quality,
            includeMetadata: includeMetadata,
            metadata: nil
        )
        await shareManager.shareMultipleRecordings(recordings, settings: settings)

        isExporting = false
    }
}
```

**Step 2: Create `AnalysisViewModel`**

```swift
//
//  AnalysisViewModel.swift
//  RiffMemo
//

import Foundation
import Observation

/// ViewModel for triggering audio analysis from the UI
@MainActor
@Observable
class AnalysisViewModel {

    // MARK: - Published State

    var isAnalyzing: Bool = false

    // MARK: - Dependencies

    private let analysisManager: AudioAnalysisManager

    // MARK: - Initialization

    init(analysisManager: AudioAnalysisManager = .shared) {
        self.analysisManager = analysisManager
    }

    // MARK: - Actions

    func analyze(_ recording: Recording) async {
        isAnalyzing = true
        _ = await analysisManager.analyzeRecording(recording)
        isAnalyzing = false
    }
}
```

**Step 3: Wire `ExportOptionsView` to `ExportViewModel`**

Replace:
```swift
@State private var isExporting = false
```
with:
```swift
@State private var viewModel = ExportViewModel()
```

Replace every `isExporting` read (the `Share` button's `ProgressView`/`disabled`) with `viewModel.isExporting`.

Replace `exportAndShare()`:
```swift
private func exportAndShare() {
    HapticManager.shared.mediumTap()
    Task {
        await viewModel.exportAndShare(
            recording,
            format: selectedFormat,
            quality: selectedQuality,
            includeMetadata: includeMetadata
        )
        dismiss()
    }
}
```

**Step 4: Wire `BatchExportView` to `ExportViewModel`**

Replace:
```swift
@State private var isExporting = false
@State private var exportProgress: Double = 0
```
with:
```swift
@State private var viewModel = ExportViewModel()
```

Replace every `isExporting`/`exportProgress` read (the progress banner, toolbar buttons) with `viewModel.isExporting` / `viewModel.exportProgress`.

Replace `exportAll()`:
```swift
private func exportAll() {
    HapticManager.shared.mediumTap()
    Task {
        await viewModel.exportAll(
            recordings,
            format: selectedFormat,
            quality: selectedQuality,
            includeMetadata: includeMetadata
        )
        HapticManager.shared.success()
        dismiss()
    }
}
```

**Step 5: Wire `AnalyzeButton` to `AnalysisViewModel`**

In `AnalysisResultsView.swift`, replace:
```swift
struct AnalyzeButton: View {
    let recording: Recording
    @State private var isAnalyzing = false

    var body: some View {
        Button(action: {
            isAnalyzing = true
            Task {
                _ = await AudioAnalysisManager.shared.analyzeRecording(recording)
                isAnalyzing = false
                HapticManager.shared.success()
            }
        }) {
            HStack {
                if isAnalyzing {
```
with:
```swift
struct AnalyzeButton: View {
    let recording: Recording
    @State private var viewModel = AnalysisViewModel()

    var body: some View {
        Button(action: {
            Task {
                await viewModel.analyze(recording)
                HapticManager.shared.success()
            }
        }) {
            HStack {
                if viewModel.isAnalyzing {
```
and update the remaining two `isAnalyzing` reads (`Text(isAnalyzing ? ...)`, `.disabled(isAnalyzing)`) to `viewModel.isAnalyzing`.

**Step 6: Build**

Run: `xcodebuild -project RiffMemo/RiffMemo.xcodeproj -scheme RiffMemo -destination "generic/platform=iOS Simulator" build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

**Step 7: Commit**
```bash
git add RiffMemo/RiffMemo/Features/Export/ExportViewModel.swift RiffMemo/RiffMemo/Features/Export/ExportOptionsView.swift RiffMemo/RiffMemo/Features/Export/BatchExportView.swift RiffMemo/RiffMemo/Features/Analysis/AnalysisViewModel.swift RiffMemo/RiffMemo/Features/Analysis/AnalysisResultsView.swift
git commit -m "feat(export,analysis): WAS-59 — add ExportViewModel and AnalysisViewModel"
```

---

## Task 5: Full validation pass

**Step 1: Full build**

Run: `xcodebuild -project RiffMemo/RiffMemo.xcodeproj -scheme RiffMemo -destination "generic/platform=iOS Simulator" build 2>&1 | tail -40`
Expected: BUILD SUCCEEDED.

**Step 2: Full test suite**

Run: `xcodebuild test -project RiffMemo/RiffMemo.xcodeproj -scheme RiffMemo -destination "platform=iOS Simulator,name=iPhone 16" 2>&1 | tail -80`
Expected: all tests pass, including the new `LibraryViewModelTests`.

**Step 3: Check off the Linear DoD checklist**

- [ ] `LibraryViewModel.repository` is private; no View touches it directly. (Task 1)
- [ ] Only one waveform-caching implementation exists. (Task 2)
- [ ] Tuner never shows "Stop" while nothing is running. (Task 3)
- [ ] Export/Analysis screens have ViewModels consistent with the rest of the app. (Task 4)
- [ ] Lesson saved in `LibraryViewModel` doc comment on `repository`. (Task 1, Step 1)
