//
//  AudioAnalysisSharedLoadRegressionTests.swift
//  RiffMemoTests
//

import XCTest
import AVFoundation
@testable import RiffMemo

/// Regression coverage for WAS-57: BPMDetector/KeyDetector/AudioQualityAnalyzer/WaveformGenerator
/// used to each independently open and decode the recording. AudioAnalysisManager now decodes once
/// via AudioSampleLoader and shares the samples across all three detectors. This proves that path
/// produces byte-identical results to each detector decoding the file on its own — i.e. the refactor
/// changed how the file is decoded, not what the decoded samples or analysis results are.
final class AudioAnalysisSharedLoadRegressionTests: XCTestCase {

    /// Synthesizes a deterministic 3s recording: a continuous 440Hz (A4) tone so key detection has
    /// a clear pitch class to lock onto, with a periodic amplitude step every 0.5s so BPM's
    /// spectral-flux onset detection has transients to lock onto (~120 BPM).
    ///
    /// Written into the Documents directory (not temp) because `Recording.audioFileURL` is a
    /// computed property that reconstructs `documentsDirectory/audioFilename` — it ignores
    /// whatever URL was passed to `init`, so the file must actually live there for
    /// AudioAnalysisManager's `recording.audioFileURL`-based load to find it.
    private func makeToneRecording() throws -> URL {
        let sampleRate = 44100.0
        let duration = 3.0
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documentsPath.appendingPathComponent(UUID().uuidString + ".caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        let toneFrequency = 440.0
        let clickIntervalSeconds = 0.5

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let tone = sin(2.0 * .pi * toneFrequency * t)
            let phase = t.truncatingRemainder(dividingBy: clickIntervalSeconds)
            let envelope = phase < 0.05 ? 1.0 : 0.05
            channel[i] = Float(tone * envelope * 0.8)
        }

        try file.write(from: buffer)
        return url
    }

    @MainActor
    func testSharedLoadProducesIdenticalResultsToPerDetectorDecode() async throws {
        let url = try makeToneRecording()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        // New path: AudioAnalysisManager decodes once and shares samples across all three detectors.
        let recording = Recording(title: "Regression", duration: 3.0, audioFileURL: url)
        let sharedResults = await AudioAnalysisManager.shared.analyzeRecording(recording)

        // Reference path: each detector independently opens and decodes the file, exactly as
        // the pre-refactor code did for every call.
        let referenceBPM = try await BPMDetector().detectBPM(from: url)
        let referenceKey = try await KeyDetector().detectKey(from: url)
        let referenceQuality = try await AudioQualityAnalyzer().analyze(from: url)

        XCTAssertEqual(sharedResults.bpm, referenceBPM)
        XCTAssertEqual(sharedResults.key, referenceKey)
        XCTAssertEqual(sharedResults.quality?.peakLevel, referenceQuality.peakLevel)
        XCTAssertEqual(sharedResults.quality?.rmsLevel, referenceQuality.rmsLevel)
        XCTAssertEqual(sharedResults.quality?.dynamicRange, referenceQuality.dynamicRange)
        XCTAssertEqual(sharedResults.quality?.crestFactor, referenceQuality.crestFactor)
        XCTAssertEqual(sharedResults.quality?.silenceRatio, referenceQuality.silenceRatio)
        XCTAssertEqual(sharedResults.quality?.clippingDetected, referenceQuality.clippingDetected)
        XCTAssertEqual(sharedResults.quality?.quality, referenceQuality.quality)

        // Sanity: the fixture actually produced analyzable signal, not nils across the board —
        // guards against a vacuous pass if the synthetic tone failed to trigger detection at all.
        XCTAssertNotNil(sharedResults.bpm)
        XCTAssertNotNil(sharedResults.key)
        XCTAssertNotNil(sharedResults.quality)
    }

    /// WaveformGenerator is a separate, UI-driven pipeline (not part of AudioAnalysisManager's
    /// pass) but shares the same AudioSampleLoader — confirm it still decodes and downsamples
    /// correctly through the shared loader.
    func testWaveformGeneratorStillProducesNormalizedSamples() async throws {
        let url = try makeToneRecording()
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let waveform = try await WaveformGenerator().generateWaveform(from: url, targetSamples: 100)

        XCTAssertEqual(waveform.count, 100)
        XCTAssertTrue(waveform.contains { $0 > 0 })
        XCTAssertTrue(waveform.allSatisfy { $0 >= 0 && $0 <= 1.0 })
    }
}
