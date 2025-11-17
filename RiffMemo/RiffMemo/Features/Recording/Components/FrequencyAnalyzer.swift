//
//  FrequencyAnalyzer.swift
//  RiffMemo
//
//  Real-time frequency analysis using FFT
//

import Foundation
import Accelerate
import AVFoundation

/// Analyzes audio frequency spectrum using FFT
class FrequencyAnalyzer {

    private let bandCount: Int
    private var fftSetup: vDSP_DFT_Setup?
    private let bufferSize: Int = 2048
    private var window: [Float]
    private(set) var frequencyMagnitudes: [Float]

    init(bandCount: Int = 32) {
        self.bandCount = bandCount
        self.frequencyMagnitudes = Array(repeating: 0.0, count: bandCount)

        // Create Hann window
        self.window = [Float](repeating: 0, count: bufferSize)
        vDSP_hann_window(&self.window, vDSP_Length(bufferSize), Int32(vDSP_HANN_NORM))

        // Setup FFT
        self.fftSetup = vDSP_DFT_zop_CreateSetup(
            nil,
            vDSP_Length(bufferSize),
            vDSP_DFT_Direction.FORWARD
        )
    }

    deinit {
        if let setup = fftSetup {
            vDSP_DFT_DestroySetup(setup)
        }
    }

    /// Analyzes audio buffer and updates frequency magnitudes
    func analyze(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0],
              let setup = fftSetup else {
            return
        }

        let frameCount = Int(buffer.frameLength)
        let sampleCount = min(frameCount, bufferSize)

        // Apply window
        var windowedSamples = [Float](repeating: 0, count: sampleCount)
        vDSP_vmul(channelData, 1, window, 1, &windowedSamples, 1, vDSP_Length(sampleCount))

        // FFT - use separate input and output arrays to avoid exclusive access violation
        var realPartIn = [Float](repeating: 0, count: bufferSize)
        var imaginaryPartIn = [Float](repeating: 0, count: bufferSize)
        var realPartOut = [Float](repeating: 0, count: bufferSize)
        var imaginaryPartOut = [Float](repeating: 0, count: bufferSize)
        realPartIn.replaceSubrange(0..<sampleCount, with: windowedSamples)

        vDSP_DFT_Execute(setup, &realPartIn, &imaginaryPartIn, &realPartOut, &imaginaryPartOut)

        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: bufferSize / 2)
        realPartOut.withUnsafeMutableBufferPointer { realPtr in
            imaginaryPartOut.withUnsafeMutableBufferPointer { imagPtr in
                var complexBuffer = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                vDSP_zvabs(&complexBuffer, 1, &magnitudes, 1, vDSP_Length(bufferSize / 2))
            }
        }

        // Normalize
        var normalizedMagnitudes = [Float](repeating: 0, count: bufferSize / 2)
        var scaleFactor = Float(2.0 / Float(bufferSize))
        vDSP_vsmul(magnitudes, 1, &scaleFactor, &normalizedMagnitudes, 1, vDSP_Length(bufferSize / 2))

        updateFrequencyBands(magnitudes: normalizedMagnitudes, sampleRate: Float(buffer.format.sampleRate))
    }

    private func updateFrequencyBands(magnitudes: [Float], sampleRate: Float) {
        let nyquistFrequency = sampleRate / 2.0
        let frequencyResolution = nyquistFrequency / Float(magnitudes.count)
        let minFreq: Float = 20.0
        let maxFreq: Float = min(nyquistFrequency, 20000.0)

        var newMagnitudes = [Float](repeating: 0, count: bandCount)

        for i in 0..<bandCount {
            let bandPosition = Float(i) / Float(bandCount - 1)
            let frequency = minFreq * pow(maxFreq / minFreq, bandPosition)
            let binIndex = Int(frequency / frequencyResolution)

            if binIndex < magnitudes.count {
                let avgRange = max(1, bandCount / 8)
                var sum: Float = 0
                var count = 0

                for j in max(0, binIndex - avgRange)...min(magnitudes.count - 1, binIndex + avgRange) {
                    sum += magnitudes[j]
                    count += 1
                }

                let avgMagnitude = sum / Float(count)
                let db = 20 * log10(max(avgMagnitude, 1e-7))
                let normalizedValue = (db + 80) / 80
                newMagnitudes[i] = max(0, min(1, normalizedValue))
            }
        }

        // Smooth transitions
        for i in 0..<bandCount {
            let smoothingFactor: Float = 0.3
            frequencyMagnitudes[i] = frequencyMagnitudes[i] * (1 - smoothingFactor) + newMagnitudes[i] * smoothingFactor
        }
    }

    /// Returns color category for band
    func colorForBand(at index: Int) -> BandColor {
        let bandPosition = Float(index) / Float(bandCount - 1)
        let minFreq: Float = 20.0
        let maxFreq: Float = 20000.0
        let frequency = minFreq * pow(maxFreq / minFreq, bandPosition)

        if frequency < 250 { return .bass }
        else if frequency < 500 { return .lowMid }
        else if frequency < 2000 { return .mid }
        else if frequency < 6000 { return .highMid }
        else { return .high }
    }
}

enum BandColor {
    case bass, lowMid, mid, highMid, high
}
