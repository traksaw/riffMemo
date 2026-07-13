//
//  AudioQualityAnalyzerTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-55 regression coverage: calculateDynamicRange used to hardcode a 44.1kHz window
/// ("windowSize = 44100 // 1 second at 44.1kHz") regardless of the recording's actual sample
/// rate. At 48kHz that misaligns every window with 1-second boundaries, blending adjacent
/// loud/quiet content together and understating the measured dynamic range. This is only
/// verified indirectly elsewhere (the shared-load regression test fixture is 44.1kHz, where the
/// old hardcoded value happened to be correct) — this test targets the fix directly at a
/// non-44.1kHz rate.
final class AudioQualityAnalyzerTests: XCTestCase {

    private func makeTone(frequency: Double, amplitude: Float, sampleRate: Double, sampleCount: Int) -> [Float] {
        (0..<sampleCount).map { i in
            Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate)) * amplitude
        }
    }

    func testDynamicRangeUsesTheRecordingsActualSampleRate() async {
        let sampleRate = 48000.0

        // One clean loud second followed by one clean quiet second, each exactly one window
        // at 48kHz. If the window size were still hardcoded to 44100, neither 48000-sample
        // half would line up with a window boundary, blending loud and quiet content together
        // within the same window and understating the measured range.
        let loudSecond = makeTone(frequency: 440.0, amplitude: 0.5, sampleRate: sampleRate, sampleCount: 48000)
        let quietSecond = makeTone(frequency: 440.0, amplitude: 0.02, sampleRate: sampleRate, sampleCount: 48000)
        let samples = loudSecond + quietSecond

        let metrics = await AudioQualityAnalyzer().analyze(samples: samples, sampleRate: sampleRate)

        // RMS of a sine wave is amplitude/sqrt(2), so the dynamic range between two clean
        // windows reduces to 20*log10(loudAmplitude / quietAmplitude) = 20*log10(0.5/0.02).
        let expectedDynamicRange = 20 * log10(0.5 / 0.02)
        XCTAssertEqual(metrics.dynamicRange, expectedDynamicRange, accuracy: 0.5)
    }
}
