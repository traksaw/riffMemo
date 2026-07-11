//
//  AudioBufferSafety.swift
//  RiffMemo
//

import AVFoundation

/// Shared guard against corrupted/implausible audio file lengths.
///
/// `AVAudioPCMBuffer(pcmFormat:frameCapacity:)` computes its internal byte size as
/// `frameCount * bytesPerFrame` using unsigned 32-bit arithmetic. If that overflows,
/// it doesn't return nil — it throws a C++ exception that Swift can't catch, which
/// aborts the whole process. Every analyzer that reads `frameCount` from a file's
/// reported length must check it here before allocating.
enum AudioBufferSafety {
    /// Sane upper bound on a single PCM buffer allocation, well below where the
    /// internal size math would overflow.
    static let maxBufferBytes: UInt64 = 512 * 1024 * 1024

    static func exceedsMaxBufferSize(frameCount: AVAudioFrameCount, format: AVAudioFormat) -> Bool {
        let bytesPerFrame = UInt64(format.streamDescription.pointee.mBytesPerFrame)
        return UInt64(frameCount) * bytesPerFrame >= maxBufferBytes
    }
}
