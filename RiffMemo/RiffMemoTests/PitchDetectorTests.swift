//
//  PitchDetectorTests.swift
//  RiffMemoTests
//

import XCTest
@testable import RiffMemo

/// WAS-55 follow-up: the DoD asked for a by-ear spot-check that pitch-detection sensitivity is
/// consistent across quiet and loud input. An automated, repeatable synthesized-tone test is a
/// stronger substitute than a one-off subjective listen — it also regression-guards the noise-floor
/// bug the WAS-55 code review caught (energy-normalizing the correlation threshold made sensitivity
/// amplitude-independent, which accidentally let ambient/silent noise cross it just as easily as a
/// loud clean tone).
@MainActor
final class PitchDetectorTests: XCTestCase {

    private let sampleRate = 44100.0
    private let frameCount = 4096

    private func makeTone(frequency: Double, amplitude: Float) -> [Float] {
        (0..<frameCount).map { i in
            Float(sin(2.0 * .pi * frequency * Double(i) / sampleRate)) * amplitude
        }
    }

    func testQuietAndLoudTonesDetectTheSameFrequency() {
        let quietTone = makeTone(frequency: 440.0, amplitude: 0.02)
        let loudTone = makeTone(frequency: 440.0, amplitude: 0.8)

        let quietFrequency = PitchDetector.detectPitch(samples: quietTone, sampleRate: sampleRate)
        let loudFrequency = PitchDetector.detectPitch(samples: loudTone, sampleRate: sampleRate)

        let quietUnwrapped = try? XCTUnwrap(quietFrequency, "Quiet tone should still be detected")
        let loudUnwrapped = try? XCTUnwrap(loudFrequency, "Loud tone should be detected")

        XCTAssertEqual(quietUnwrapped ?? -1, 440.0, accuracy: 5.0)
        XCTAssertEqual(loudUnwrapped ?? -1, 440.0, accuracy: 5.0)
    }

    func testSilenceDoesNotProduceAPitch() {
        let silence = [Float](repeating: 0, count: frameCount)

        XCTAssertNil(PitchDetector.detectPitch(samples: silence, sampleRate: sampleRate))
    }

    func testVeryQuietAmbientNoiseDoesNotProduceAPitch() {
        // Amplitude chosen so average energy falls below PitchDetector's noise floor —
        // representative of mic self-noise/room noise rather than an actual played note.
        // Regression guard: before the noise-floor fix, energy-normalizing the correlation
        // threshold made it amplitude-independent, so noise like this could cross the 0.1
        // cutoff just as easily as a loud clean tone.
        let noise = makeTone(frequency: 300.0, amplitude: 0.0005)

        XCTAssertNil(PitchDetector.detectPitch(samples: noise, sampleRate: sampleRate))
    }

    func testQuietTonePassesTheNoiseFloor() {
        // Sanity check on the floor threshold itself: a real quiet note must not be caught by
        // the same gate that rejects ambient noise above.
        let quietTone = makeTone(frequency: 440.0, amplitude: 0.02)

        XCTAssertNotNil(PitchDetector.detectPitch(samples: quietTone, sampleRate: sampleRate))
    }
}
