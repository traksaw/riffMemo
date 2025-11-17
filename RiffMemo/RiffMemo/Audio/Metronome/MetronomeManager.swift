//
//  MetronomeManager.swift
//  RiffMemo
//
//

import Foundation
import AVFoundation
import Combine

/// Manages metronome playback with precise timing
@MainActor
class MetronomeManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isPlaying = false
    @Published var currentBeat = 0
    @Published var bpm: Double = 120
    @Published var timeSignature: TimeSignature = .fourFour

    // MARK: - Configuration

    private let minBPM: Double = 30
    private let maxBPM: Double = 300

    // MARK: - Audio Components

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var mixer: AVAudioMixerNode?

    // Audio buffers for click sounds
    private var accentBuffer: AVAudioPCMBuffer?
    private var regularBuffer: AVAudioPCMBuffer?

    // Timing
    private var timer: Timer?
    private var nextBeatTime: TimeInterval = 0

    // MARK: - Time Signatures

    enum TimeSignature: String, CaseIterable {
        case twoFour = "2/4"
        case threeFour = "3/4"
        case fourFour = "4/4"
        case fiveFour = "5/4"
        case sixEight = "6/8"
        case sevenEight = "7/8"

        var beatsPerMeasure: Int {
            switch self {
            case .twoFour: return 2
            case .threeFour: return 3
            case .fourFour: return 4
            case .fiveFour: return 5
            case .sixEight: return 6
            case .sevenEight: return 7
            }
        }
    }

    // MARK: - Public Methods

    func start() {
        guard !isPlaying else { return }

        do {
            try setupAudioSession()
            try setupAudioEngine()
            generateClickSounds()

            isPlaying = true
            currentBeat = 0
            nextBeatTime = 0

            startTimer()
            playBeat()

            Logger.info("Metronome started at \(bpm) BPM", category: Logger.audio)
        } catch {
            Logger.error("Failed to start metronome: \(error)", category: Logger.audio)
        }
    }

    func stop() {
        guard isPlaying else { return }

        timer?.invalidate()
        timer = nil

        playerNode?.stop()
        audioEngine?.stop()

        isPlaying = false
        currentBeat = 0

        Logger.info("Metronome stopped", category: Logger.audio)
    }

    func setBPM(_ newBPM: Double) {
        let clampedBPM = min(max(newBPM, minBPM), maxBPM)
        bpm = clampedBPM

        if isPlaying {
            // Restart with new tempo
            stop()
            start()
        }
    }

    func incrementBPM(_ amount: Double) {
        setBPM(bpm + amount)
    }

    func tapTempo() {
        // TODO: Implement tap tempo functionality
        // Store tap times and calculate average interval
    }

    // MARK: - Private Methods

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    private func setupAudioEngine() throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let mixer = engine.mainMixerNode

        // Create format for stereo audio
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else {
            throw MetronomeError.setupFailed
        }

        engine.attach(player)
        engine.connect(player, to: mixer, format: format)

        try engine.start()

        self.audioEngine = engine
        self.playerNode = player
        self.mixer = mixer
    }

    private func generateClickSounds() {
        let sampleRate = 44100.0
        let duration = 0.05 // 50ms click

        // Generate accent click (higher pitch)
        accentBuffer = generateClickBuffer(frequency: 1200, duration: duration, sampleRate: sampleRate)

        // Generate regular click (lower pitch)
        regularBuffer = generateClickBuffer(frequency: 800, duration: duration, sampleRate: sampleRate)
    }

    private func generateClickBuffer(frequency: Double, duration: TimeInterval, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        // Create stereo buffer to match engine format
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }

        buffer.frameLength = frameCount

        guard let channelData = buffer.floatChannelData else { return nil }

        // Generate sine wave with envelope for both channels (stereo)
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let amplitude = Float(1.0 - (time / duration)) // Decay envelope
            let sineValue = Float(sin(2.0 * Double.pi * frequency * time))
            let sample = sineValue * amplitude * 0.5

            // Write to both left and right channels
            channelData[0][frame] = sample // Left
            channelData[1][frame] = sample // Right
        }

        return buffer
    }

    private func startTimer() {
        let interval = 60.0 / bpm / 4.0 // Check 4 times per beat for accuracy

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkAndPlayBeat()
            }
        }

        // Use high priority for better timing
        timer?.tolerance = interval * 0.1
    }

    private func checkAndPlayBeat() {
        let now = audioEngine?.outputNode.lastRenderTime?.sampleTime ?? 0
        let sampleRate = audioEngine?.outputNode.outputFormat(forBus: 0).sampleRate ?? 44100

        let currentTime = Double(now) / sampleRate

        if nextBeatTime == 0 || currentTime >= nextBeatTime {
            playBeat()

            let beatDuration = 60.0 / bpm
            nextBeatTime = currentTime + beatDuration
        }
    }

    private func playBeat() {
        guard let playerNode = playerNode else { return }

        // Determine if this is an accented beat (first beat of measure)
        let isAccent = currentBeat == 0

        let buffer = isAccent ? accentBuffer : regularBuffer

        guard let clickBuffer = buffer else { return }

        // Schedule the click
        playerNode.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)

        if !playerNode.isPlaying {
            playerNode.play()
        }

        // Update beat counter
        currentBeat = (currentBeat + 1) % timeSignature.beatsPerMeasure

        // Haptic feedback
        if isAccent {
            HapticManager.shared.mediumTap()
        } else {
            HapticManager.shared.lightTap()
        }
    }
}

// MARK: - MetronomeError

enum MetronomeError: LocalizedError {
    case setupFailed
    case audioEngineError

    var errorDescription: String? {
        switch self {
        case .setupFailed:
            return "Failed to setup metronome audio"
        case .audioEngineError:
            return "Audio engine error"
        }
    }
}
