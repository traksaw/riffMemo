//
//  WaveformViewModelTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-100: first ViewModel test coverage for `WaveformViewModel`'s three-tier cache
/// (memory -> SwiftData -> regenerate) using a protocol-mocked `WaveformGenerator`.
@MainActor
final class WaveformViewModelTests: XCTestCase {

    // Xcode 26.1.1/Swift 6.2.1 toolchain crashes (libmalloc corruption) when a @MainActor
    // class from the app module (WaveformViewModel, which holds a SwiftData `Recording`)
    // deinits synchronously inside a non-`async` test method in this test target. Leaking
    // the instances here sidesteps the deinit rather than working around app code.
    // See memory: swiftdata-repo-deinit-crash.
    private static var leakedToAvoidToolchainDeinitCrash: [Any] = []

    private func makeRecording(waveformData: Data? = nil) -> Recording {
        Recording(
            title: "Test Recording",
            duration: 10,
            audioFileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".caf"),
            waveformData: waveformData
        )
    }

    private func makeViewModel(recording: Recording) -> (WaveformViewModel, MockWaveformGenerator) {
        let generator = MockWaveformGenerator()
        let viewModel = WaveformViewModel(recording: recording, waveformGenerator: generator)
        return (viewModel, generator)
    }

    func testLoadWaveformSkipsGenerationWhenSamplesAlreadyInMemory() async {
        let (viewModel, generator) = makeViewModel(recording: makeRecording())
        viewModel.samples = [0.9, 0.8]

        await viewModel.loadWaveform()

        XCTAssertEqual(viewModel.samples, [0.9, 0.8], "Tier 1 (memory) must short-circuit before touching the generator")
        XCTAssertEqual(generator.generateWaveformCallCount, 0)
        XCTAssertEqual(generator.decodeWaveformCallCount, 0)
    }

    func testLoadWaveformDecodesFromSwiftDataCacheWhenAvailable() async {
        let recording = makeRecording(waveformData: Data([0xAA]))
        let (viewModel, generator) = makeViewModel(recording: recording)
        generator.decodedWaveformToReturn = [0.11, 0.22, 0.33]

        await viewModel.loadWaveform()

        XCTAssertEqual(viewModel.samples, [0.11, 0.22, 0.33], "Tier 2 (SwiftData cache) should decode the persisted data")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(generator.decodeWaveformCallCount, 1)
        XCTAssertEqual(generator.generateWaveformCallCount, 0, "A cached waveform must never trigger regeneration")
    }

    func testLoadWaveformGeneratesAndCachesWhenNoDataAvailable() async {
        let recording = makeRecording(waveformData: nil)
        let (viewModel, generator) = makeViewModel(recording: recording)
        generator.waveformToReturn = [0.5, 0.6]
        generator.waveformDataToReturn = Data([0x01, 0x02, 0x03])

        await viewModel.loadWaveform()

        XCTAssertEqual(viewModel.samples, [0.5, 0.6], "Tier 3 (regenerate) result should populate samples")
        XCTAssertEqual(recording.waveformData, Data([0x01, 0x02, 0x03]), "Regenerated waveform must be written back to the Recording for future Tier-2 hits")
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.loadError)
        XCTAssertEqual(generator.generateWaveformCallCount, 1)
        XCTAssertEqual(generator.generateWaveformDataCallCount, 1)
    }

    func testLoadWaveformSetsLoadErrorWhenGenerationFails() async {
        let recording = makeRecording(waveformData: nil)
        let (viewModel, generator) = makeViewModel(recording: recording)
        generator.generateWaveformError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "decode failed"])

        await viewModel.loadWaveform()

        XCTAssertTrue(viewModel.samples.isEmpty)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.loadError, "Failed to load waveform: decode failed")
        XCTAssertNil(recording.waveformData, "A failed generation must not write partial/stale data back to the Recording")
    }

    func testClearCacheResetsSamplesAndPersistedData() {
        let recording = makeRecording(waveformData: Data([0xFF]))
        let (viewModel, generator) = makeViewModel(recording: recording)
        viewModel.samples = [0.1, 0.2]

        viewModel.clearCache()

        XCTAssertTrue(viewModel.samples.isEmpty)
        XCTAssertNil(recording.waveformData)

        // Avoid the toolchain deinit crash described above (only reproduces on this
        // synchronous test method, not the `async` ones elsewhere in this file).
        Self.leakedToAvoidToolchainDeinitCrash.append(viewModel)
        Self.leakedToAvoidToolchainDeinitCrash.append(recording)
        Self.leakedToAvoidToolchainDeinitCrash.append(generator)
    }

    func testRegenerateDiscardsMemoryCacheAndFetchesFreshSamples() async {
        let recording = makeRecording(waveformData: nil)
        let (viewModel, generator) = makeViewModel(recording: recording)
        generator.waveformToReturn = [0.1]
        await viewModel.loadWaveform()
        XCTAssertEqual(viewModel.samples, [0.1])

        generator.waveformToReturn = [0.2, 0.3]
        await viewModel.regenerate()

        XCTAssertEqual(viewModel.samples, [0.2, 0.3], "regenerate() must ignore the Tier 1 memory cache from the first load")
        XCTAssertEqual(generator.generateWaveformCallCount, 2)
    }
}
