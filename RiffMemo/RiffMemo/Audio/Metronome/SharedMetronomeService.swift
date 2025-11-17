//
//  SharedMetronomeService.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import Foundation
import AVFoundation
import Combine

/// Shared metronome service for use across the app
/// Can be used both in standalone metronome and as click track during recording
@MainActor
class SharedMetronomeService: ObservableObject {

    // MARK: - Singleton

    static let shared = SharedMetronomeService()

    // MARK: - Published Properties

    @Published var isPlaying = false
    @Published var currentBeat = 0  // Internal counter (incremented after play)
    @Published var displayBeat = 0  // The beat currently being played (for UI sync)
    @Published var bpm: Double = 120
    @Published var timeSignature: TimeSignature = .fourFour
    @Published var volume: Float = 0.5 // 0.0 to 1.0
    @Published var preCountRemaining: Int = 0 // Countdown for pre-count (0 = not in pre-count)
    @Published var preCountDisplayNumber: Int = 0 // The count number shown in UI (set BEFORE playing)
    @Published var tapCount: Int = 0 // Number of taps recorded
    @Published var calculatedBPM: Double? = nil // Live BPM calculation from taps

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

    // Sample-accurate scheduling
    private var nextBeatSampleTime: AVAudioFramePosition = 0
    private var isFirstBeatScheduled = false

    // Pre-count
    private var preCountCompletionHandler: (() -> Void)?

    // MARK: - Metronome State

    enum MetronomeState {
        case idle           // Not playing
        case preCount       // Counting down before recording (4, 3, 2, 1)
        case recording      // Main metronome during recording
        case standalone     // Standalone metronome (no recording)
    }

    private var state: MetronomeState = .idle

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

    // MARK: - Initialization

    private init() {
        loadSettings()
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
            preCountRemaining = 0
            state = .standalone  // Standalone metronome mode

            // Reset sample-accurate scheduling
            nextBeatSampleTime = 0
            isFirstBeatScheduled = false

            startTimer()
            playBeat()

            Logger.info("Shared metronome started (standalone) at \(bpm) BPM", category: Logger.audio)
        } catch {
            Logger.error("Failed to start metronome: \(error)", category: Logger.audio)
        }
    }

    /// Start with a pre-count (one full measure) before regular playback
    /// - Parameter completion: Called after pre-count completes (on beat 1 of actual playback)
    func startWithPreCount(completion: @escaping () -> Void) {
        guard !isPlaying else { return }

        do {
            try setupAudioSession()
            try setupAudioEngine()
            generateClickSounds()

            isPlaying = true
            currentBeat = 0
            nextBeatTime = 0
            // Pre-count matches time signature (4 beats for 4/4, 6 beats for 6/8, etc.)
            preCountRemaining = timeSignature.beatsPerMeasure
            preCountDisplayNumber = 0 // Will be set on first beat
            preCountCompletionHandler = completion
            state = .preCount  // Pre-count mode

            // Reset sample-accurate scheduling
            nextBeatSampleTime = 0
            isFirstBeatScheduled = false

            startTimer()
            playBeat()

            Logger.info("Shared metronome started with \(timeSignature.beatsPerMeasure)-beat pre-count at \(bpm) BPM", category: Logger.audio)
        } catch {
            Logger.error("Failed to start metronome with pre-count: \(error)", category: Logger.audio)
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
        state = .idle

        // Reset sample-accurate scheduling state
        nextBeatSampleTime = 0
        isFirstBeatScheduled = false

        Logger.info("Shared metronome stopped", category: Logger.audio)
    }

    func setBPM(_ newBPM: Double) {
        let clampedBPM = min(max(newBPM, minBPM), maxBPM)
        bpm = clampedBPM
        saveSettings()

        if isPlaying {
            // Restart with new tempo
            stop()
            start()
        }
    }

    func incrementBPM(_ amount: Double) {
        setBPM(bpm + amount)
    }

    func setTimeSignature(_ signature: TimeSignature) {
        timeSignature = signature
        currentBeat = 0
        saveSettings()
    }

    func setVolume(_ newVolume: Float) {
        volume = min(max(newVolume, 0.0), 1.0)
        saveSettings()
    }

    // MARK: - Settings Persistence

    private func saveSettings() {
        UserDefaults.standard.set(bpm, forKey: "metronome_bpm")
        UserDefaults.standard.set(timeSignature.rawValue, forKey: "metronome_timeSignature")
        UserDefaults.standard.set(volume, forKey: "metronome_volume")
    }

    private func loadSettings() {
        if let savedBPM = UserDefaults.standard.object(forKey: "metronome_bpm") as? Double {
            bpm = savedBPM
        }

        if let savedTimeSig = UserDefaults.standard.string(forKey: "metronome_timeSignature"),
           let timeSig = TimeSignature(rawValue: savedTimeSig) {
            timeSignature = timeSig
        }

        if let savedVolume = UserDefaults.standard.object(forKey: "metronome_volume") as? Float {
            volume = savedVolume
        }
    }

    // MARK: - Tap Tempo

    private var tapTimes: [Date] = []
    private let tapTempoWindow: TimeInterval = 3.0 // 3 seconds

    func tapTempo() {
        let now = Date()

        // Remove taps older than window
        tapTimes = tapTimes.filter { now.timeIntervalSince($0) < tapTempoWindow }

        // Add current tap
        tapTimes.append(now)

        // Update tap count
        tapCount = tapTimes.count

        // Need at least 2 taps to calculate tempo
        guard tapTimes.count >= 2 else {
            calculatedBPM = nil
            HapticManager.shared.lightTap()
            return
        }

        // Calculate average interval between taps
        var intervals: [TimeInterval] = []
        for i in 1..<tapTimes.count {
            intervals.append(tapTimes[i].timeIntervalSince(tapTimes[i-1]))
        }

        let averageInterval = intervals.reduce(0, +) / Double(intervals.count)

        // Convert to BPM (60 seconds / interval = BPM)
        let tempoBPM = 60.0 / averageInterval

        // Update calculated BPM for display
        calculatedBPM = tempoBPM

        // Apply the BPM if it's within valid range
        if tempoBPM >= minBPM && tempoBPM <= maxBPM {
            setBPM(tempoBPM)
            HapticManager.shared.lightTap()
        }
    }

    func resetTapTempo() {
        tapTimes.removeAll()
        tapCount = 0
        calculatedBPM = nil
    }

    // MARK: - Private Methods

    private func setupAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Use EXACT same configuration as AudioRecordingManager to prevent reconfiguration glitches
        // Mode .measurement is optimized for low-latency recording
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
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

        // Generate accent click: higher pitch, louder, longer duration
        // Using traditional metronome frequencies for maximum distinction
        accentBuffer = generateClickBuffer(
            frequency: 2000,      // High woodblock sound
            duration: 0.08,       // 80ms for clear pitch perception
            amplitude: 0.8,       // Louder
            sampleRate: sampleRate
        )

        // Generate regular click: lower pitch, softer, shorter duration
        regularBuffer = generateClickBuffer(
            frequency: 600,       // Low woodblock sound
            duration: 0.06,       // 60ms
            amplitude: 0.5,       // Softer
            sampleRate: sampleRate
        )

        Logger.info("Click sounds generated: Accent=2000Hz/80ms/0.8vol, Regular=600Hz/60ms/0.5vol", category: Logger.audio)
    }

    private func generateClickBuffer(frequency: Double, duration: TimeInterval, amplitude: Float, sampleRate: Double) -> AVAudioPCMBuffer? {
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

            // Exponential decay envelope for sharper attack
            let envelopeProgress = time / duration
            let envelope = Float(pow(1.0 - envelopeProgress, 2.0))

            let sineValue = Float(sin(2.0 * Double.pi * frequency * time))
            let sample = sineValue * envelope * amplitude

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

        // Apply volume
        playerNode.volume = volume

        // Ensure player is running
        if !playerNode.isPlaying {
            playerNode.play()
        }

        // Route to appropriate handler based on state
        switch state {
        case .idle:
            return

        case .preCount:
            playPreCountBeat()

        case .recording, .standalone:
            playRecordingBeat()
        }
    }

    // MARK: - Pre-Count Beat Logic

    /// Plays a beat during the pre-count phase
    /// Pre-count is one full measure matching the time signature
    /// Pattern: ACCENT (beat 1), regular (beats 2-N) - just like the actual recording will sound
    /// For 4/4: counts "4, 3, 2, 1" playing ACCENT, regular, regular, regular
    /// For 6/8: counts "6, 5, 4, 3, 2, 1" playing ACCENT, regular, regular, regular, regular, regular
    private func playPreCountBeat() {
        guard let playerNode = playerNode else { return }

        // Update display number BEFORE playing sound (for UI synchronization)
        preCountDisplayNumber = preCountRemaining

        // Beat 1 of the measure (when counter == beatsPerMeasure) gets accent, just like recording
        let isDownbeat = preCountRemaining == timeSignature.beatsPerMeasure
        let buffer = isDownbeat ? accentBuffer : regularBuffer

        guard let clickBuffer = buffer else { return }

        // Schedule buffer
        playerNode.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)

        // Haptic feedback
        if isDownbeat {
            HapticManager.shared.heavyTap()  // Heavy tap on downbeat (beat 1)
        } else {
            HapticManager.shared.lightTap()
        }

        // Debug logging
        #if DEBUG
        Logger.debug("Pre-count \(preCountDisplayNumber): \(isDownbeat ? "ACCENT/DOWNBEAT (2000Hz/LOUD)" : "regular (600Hz/soft)") - beat \(timeSignature.beatsPerMeasure - preCountRemaining + 1) of \(timeSignature.beatsPerMeasure)", category: Logger.audio)
        #endif

        // Decrement counter AFTER playing
        preCountRemaining -= 1

        // Transition to recording when pre-count finishes
        if preCountRemaining == 0 {
            // Call completion handler to start recording
            if let completion = preCountCompletionHandler {
                Task { @MainActor in
                    completion()
                }
                preCountCompletionHandler = nil
            }

            // Transition to recording state
            state = .recording
            currentBeat = 0  // Reset to 0 so next beat will be the accent downbeat
            preCountDisplayNumber = 0 // Clear display

            Logger.info("Pre-count complete → transitioning to recording", category: Logger.audio)

            // Don't increment currentBeat - we want to start recording on beat 0 (accent)
            return
        }

        // Increment beat counter for pre-count (only if we haven't transitioned)
        currentBeat = (currentBeat + 1) % timeSignature.beatsPerMeasure
    }

    // MARK: - Recording/Standalone Beat Logic

    /// Plays a beat during recording or standalone metronome
    /// Pattern: ACCENT, regular, regular, regular (1, 2, 3, 4)
    /// First beat (1) is accented as the downbeat
    private func playRecordingBeat() {
        guard let playerNode = playerNode else { return }

        // Update displayBeat BEFORE playing so UI is in sync
        displayBeat = currentBeat

        // Beat 1 (downbeat) gets accent
        let isAccent = currentBeat == 0
        let buffer = isAccent ? accentBuffer : regularBuffer

        guard let clickBuffer = buffer else { return }

        // Schedule buffer
        playerNode.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)

        // Debug logging
        #if DEBUG
        let beatNumber = currentBeat + 1  // Display as 1-4 instead of 0-3
        let stateLabel = state == .recording ? "Recording" : "Standalone"
        Logger.debug("\(stateLabel) Beat \(beatNumber): \(isAccent ? "ACCENT (2000Hz/LOUD)" : "regular (600Hz/soft)") - isPlaying: \(playerNode.isPlaying)", category: Logger.audio)
        #endif

        // Haptic feedback
        if isAccent {
            HapticManager.shared.mediumTap()  // Medium tap on downbeat
        } else {
            HapticManager.shared.lightTap()
        }

        // Update beat counter AFTER playing
        currentBeat = (currentBeat + 1) % timeSignature.beatsPerMeasure
    }
}
