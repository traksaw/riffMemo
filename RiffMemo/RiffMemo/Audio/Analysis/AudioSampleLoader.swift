//
//  AudioSampleLoader.swift
//  RiffMemo
//

import Foundation
import AVFoundation

/// Shared "open file → allocate buffer → read → extract `[Float]`" sequence used by every
/// analyzer that needs raw, unnormalized, first-channel samples from a recording.
enum AudioSampleLoader {
    struct LoadedAudioSamples {
        let samples: [Float]
        let sampleRate: Double
    }

    /// Loads raw samples from the first channel of `url`'s native processing format.
    /// No resampling, no downmixing of additional channels, no normalization —
    /// callers that need those apply them on top of the returned samples.
    static func load(from url: URL) throws -> LoadedAudioSamples {
        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let frameCount = AVAudioFrameCount(audioFile.length)

        guard frameCount > 0 else {
            throw AudioDecodeError.emptyFile
        }

        guard !AudioBufferSafety.exceedsMaxBufferSize(frameCount: frameCount, format: format) else {
            throw AudioDecodeError.frameCountTooLarge
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioDecodeError.bufferAllocationFailed
        }

        try audioFile.read(into: buffer)

        guard let channelData = buffer.floatChannelData else {
            throw AudioDecodeError.noChannelData
        }

        let samples = extractSamples(from: channelData[0], frameCount: Int(buffer.frameLength))

        return LoadedAudioSamples(samples: samples, sampleRate: format.sampleRate)
    }

    private static func extractSamples(from channelData: UnsafeMutablePointer<Float>, frameCount: Int) -> [Float] {
        var samples = [Float](repeating: 0, count: frameCount)
        for i in 0..<frameCount {
            samples[i] = channelData[i]
        }
        return samples
    }
}

// MARK: - Audio Decode Error

enum AudioDecodeError: LocalizedError {
    case emptyFile
    case bufferAllocationFailed
    case noChannelData
    case frameCountTooLarge

    var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "Audio file is empty"
        case .bufferAllocationFailed:
            return "Failed to allocate audio buffer"
        case .noChannelData:
            return "No channel data available"
        case .frameCountTooLarge:
            return "Audio file length is too large to process"
        }
    }
}
