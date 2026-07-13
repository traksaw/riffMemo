//
//  AudioRecorderProtocol.swift
//  RiffMemo
//

import Foundation

/// Abstraction over `AudioRecordingManager` so `RecordingViewModel` can be tested with a mock
/// instead of a real `AVAudioEngine`/microphone. See the "FUTURE IMPROVEMENTS" note this was
/// planned in `RecordingViewModelTests.swift`.
protocol AudioRecorderProtocol: AnyObject {
    var onAudioLevel: (@Sendable (Float) -> Void)? { get set }
    var onFrequencyData: (@Sendable ([Float]) -> Void)? { get set }
    var onWaveformSample: (@Sendable (Float) -> Void)? { get set }
    var onRecordingFailed: (@Sendable (Error) -> Void)? { get set }

    func startRecording() async throws
    func stopRecording(duration: TimeInterval, recordedWithBPM: Int?, recordedWithTimeSignature: String?) async throws -> Recording
}

extension AudioRecordingManager: AudioRecorderProtocol {}
