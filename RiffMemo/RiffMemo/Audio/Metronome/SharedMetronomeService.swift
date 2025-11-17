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
    @Published var errorMessage: String? = nil // Error message to display to user
    @Published var showError: Bool = false // Whether to show error alert

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
    private var dispatchTimer: DispatchSourceTimer?
    private var nextBeatTime: TimeInterval = 0
    private var subdivisionCounter: Int = 0 // Tracks subdivision position (0 to clicksPerBeat-1)

    // Sample-accurate scheduling using AVAudioTime
    private var nextBeatSampleTime: AVAudioFramePosition = 0
    private var isFirstBeatScheduled = false
    private var startSampleTime: AVAudioFramePosition = 0

    // Pre-count
    private var preCountCompletionHandler: (() -> Void)?

    // MARK: - Metronome State

    enum MetronomeState: Equatable {
        case idle           // Not playing
        case preCount       // Counting down before recording (4, 3, 2, 1)
        case recording      // Main metronome during recording
        case standalone     // Standalone metronome (no recording)
    }

    @Published var state: MetronomeState = .idle

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

    // MARK: - Subdivisions

    enum Subdivision: String, CaseIterable {
        case none = "None"
        case eighth = "8th Notes"
        case sixteenth = "16th Notes"
        case triplet = "Triplets"

        var clicksPerBeat: Int {
            switch self {
            case .none: return 1
            case .eighth: return 2
            case .sixteenth: return 4
            case .triplet: return 3
            }
        }

        var displayName: String { rawValue }
    }

    // MARK: - Click Sounds

    enum ClickSound: String, CaseIterable {
        case digital = "Digital"
        case woodblock = "Woodblock"
        case cowbell = "Cowbell"
        case stick = "Stick"

        var displayName: String { rawValue }
    }

    // MARK: - Advanced Settings

    @Published var subdivision: Subdivision = .none
    @Published var clickSound: ClickSound = .digital
    @Published var visualOnlyMode: Bool = false
    @Published var tempoRampEnabled: Bool = false
    @Published var tempoRampStartBPM: Double = 60
    @Published var tempoRampTargetBPM: Double = 120
    @Published var tempoRampDuration: TimeInterval = 60 // seconds

    private var tempoRampStartTime: Date?
    private var subdivisionBuffer: AVAudioPCMBuffer? // Quieter click for subdivisions

    // Sound generation types
    private enum SoundType {
        case sine           // Pure sine wave
        case woodblock      // Filtered noise
        case cowbell        // Multiple harmonics
        case stick          // Short impulse
    }

    // MARK: - Initialization

    private init() {
        loadSettings()

        // Debug: Log visual-only mode state
        #if DEBUG
        Logger.info("Metronome initialized - Visual Only: \(visualOnlyMode), Volume: \(volume)", category: Logger.audio)
        #endif
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
            subdivisionCounter = 0
            preCountRemaining = 0
            state = .standalone  // Standalone metronome mode

            // Reset sample-accurate scheduling for precise timing
            nextBeatSampleTime = 0
            startSampleTime = 0
            isFirstBeatScheduled = false

            // Initialize nextBeatTime to trigger first beat immediately
            nextBeatTime = Date().timeIntervalSince1970

            startTimer()

            Logger.info("Shared metronome started (standalone) at \(bpm) BPM - Using sample-accurate timing", category: Logger.audio)
        } catch {
            Logger.error("Failed to start metronome: \(error)", category: Logger.audio)
            errorMessage = "Failed to start metronome: \(error.localizedDescription)"
            showError = true
            isPlaying = false
            state = .idle
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
            subdivisionCounter = 0
            // Pre-count matches time signature (4 beats for 4/4, 6 beats for 6/8, etc.)
            preCountRemaining = timeSignature.beatsPerMeasure
            preCountDisplayNumber = timeSignature.beatsPerMeasure // Initialize to show beat 1 immediately
            preCountCompletionHandler = completion
            state = .preCount  // Pre-count mode

            // Reset sample-accurate scheduling for precise timing
            nextBeatSampleTime = 0
            startSampleTime = 0
            isFirstBeatScheduled = false

            // Set next beat time with a small delay to give SwiftUI time to render beat 1
            // This ensures the user sees "1" before the first click plays
            nextBeatTime = Date().timeIntervalSince1970 + 0.05  // 50ms delay for UI rendering

            startTimer()
            // Don't call playBeat() manually - let the timer handle all beats consistently

            Logger.info("Shared metronome started with \(timeSignature.beatsPerMeasure)-beat pre-count at \(bpm) BPM - Using sample-accurate timing", category: Logger.audio)
        } catch {
            Logger.error("Failed to start metronome with pre-count: \(error)", category: Logger.audio)
            errorMessage = "Failed to start metronome: \(error.localizedDescription)"
            showError = true
            isPlaying = false
            state = .idle
        }
    }

    func stop() {
        guard isPlaying else { return }

        timer?.invalidate()
        timer = nil

        dispatchTimer?.cancel()
        dispatchTimer = nil

        playerNode?.stop()
        audioEngine?.stop()

        isPlaying = false
        currentBeat = 0
        subdivisionCounter = 0
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

    // MARK: - Advanced Feature Setters

    func setSubdivision(_ newSubdivision: Subdivision) {
        subdivision = newSubdivision
        saveSettings()
    }

    func setClickSound(_ newSound: ClickSound) {
        clickSound = newSound
        // Regenerate click sounds with new sound type
        generateClickSounds()
        saveSettings()
    }

    func setVisualOnlyMode(_ enabled: Bool) {
        visualOnlyMode = enabled
        saveSettings()
    }

    func setTempoRampEnabled(_ enabled: Bool) {
        tempoRampEnabled = enabled
        if enabled {
            tempoRampStartTime = Date()
            tempoRampStartBPM = bpm
        } else {
            tempoRampStartTime = nil
        }
        saveSettings()
    }

    func setTempoRampSettings(startBPM: Double, targetBPM: Double, duration: TimeInterval) {
        tempoRampStartBPM = startBPM
        tempoRampTargetBPM = targetBPM
        tempoRampDuration = duration
        saveSettings()
    }

    // MARK: - Settings Persistence

    private func saveSettings() {
        UserDefaults.standard.set(bpm, forKey: "metronome_bpm")
        UserDefaults.standard.set(timeSignature.rawValue, forKey: "metronome_timeSignature")
        UserDefaults.standard.set(volume, forKey: "metronome_volume")
        UserDefaults.standard.set(subdivision.rawValue, forKey: "metronome_subdivision")
        UserDefaults.standard.set(clickSound.rawValue, forKey: "metronome_clickSound")
        UserDefaults.standard.set(visualOnlyMode, forKey: "metronome_visualOnly")
        UserDefaults.standard.set(tempoRampEnabled, forKey: "metronome_tempoRampEnabled")
        UserDefaults.standard.set(tempoRampStartBPM, forKey: "metronome_tempoRampStart")
        UserDefaults.standard.set(tempoRampTargetBPM, forKey: "metronome_tempoRampTarget")
        UserDefaults.standard.set(tempoRampDuration, forKey: "metronome_tempoRampDuration")
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

        if let savedSubdivision = UserDefaults.standard.string(forKey: "metronome_subdivision"),
           let sub = Subdivision(rawValue: savedSubdivision) {
            subdivision = sub
        }

        if let savedSound = UserDefaults.standard.string(forKey: "metronome_clickSound"),
           let sound = ClickSound(rawValue: savedSound) {
            clickSound = sound
        }

        if let savedVisualOnly = UserDefaults.standard.object(forKey: "metronome_visualOnly") as? Bool {
            visualOnlyMode = savedVisualOnly
        }

        if let savedRampEnabled = UserDefaults.standard.object(forKey: "metronome_tempoRampEnabled") as? Bool {
            tempoRampEnabled = savedRampEnabled
        }

        if let savedRampStart = UserDefaults.standard.object(forKey: "metronome_tempoRampStart") as? Double {
            tempoRampStartBPM = savedRampStart
        }

        if let savedRampTarget = UserDefaults.standard.object(forKey: "metronome_tempoRampTarget") as? Double {
            tempoRampTargetBPM = savedRampTarget
        }

        if let savedRampDuration = UserDefaults.standard.object(forKey: "metronome_tempoRampDuration") as? TimeInterval {
            tempoRampDuration = savedRampDuration
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

        // Use the mixer's output format instead of creating custom format
        // This avoids format conversion issues
        let format = mixer.outputFormat(forBus: 0)

        engine.attach(player)
        engine.connect(player, to: mixer, format: format)

        try engine.start()

        // Start the player node immediately
        player.play()

        self.audioEngine = engine
        self.playerNode = player
        self.mixer = mixer

        Logger.info("Audio engine started - sampleRate: \(format.sampleRate), channels: \(format.channelCount)", category: Logger.audio)
    }

    private func generateClickSounds() {
        // Use the actual sample rate from the audio engine's format
        let sampleRate = audioEngine?.mainMixerNode.outputFormat(forBus: 0).sampleRate ?? 44100.0

        switch clickSound {
        case .digital:
            // Original sine wave clicks
            accentBuffer = generateClickBuffer(
                frequency: 2000, duration: 0.08, amplitude: 0.8,
                soundType: .sine, sampleRate: sampleRate
            )
            regularBuffer = generateClickBuffer(
                frequency: 600, duration: 0.06, amplitude: 0.5,
                soundType: .sine, sampleRate: sampleRate
            )
            subdivisionBuffer = generateClickBuffer(
                frequency: 400, duration: 0.04, amplitude: 0.3,
                soundType: .sine, sampleRate: sampleRate
            )

        case .woodblock:
            // Woodblock: filtered noise burst
            accentBuffer = generateClickBuffer(
                frequency: 800, duration: 0.05, amplitude: 0.85,
                soundType: .woodblock, sampleRate: sampleRate
            )
            regularBuffer = generateClickBuffer(
                frequency: 500, duration: 0.04, amplitude: 0.55,
                soundType: .woodblock, sampleRate: sampleRate
            )
            subdivisionBuffer = generateClickBuffer(
                frequency: 300, duration: 0.03, amplitude: 0.35,
                soundType: .woodblock, sampleRate: sampleRate
            )

        case .cowbell:
            // Cowbell: multiple sine waves (metallic)
            accentBuffer = generateClickBuffer(
                frequency: 800, duration: 0.12, amplitude: 0.75,
                soundType: .cowbell, sampleRate: sampleRate
            )
            regularBuffer = generateClickBuffer(
                frequency: 500, duration: 0.10, amplitude: 0.50,
                soundType: .cowbell, sampleRate: sampleRate
            )
            subdivisionBuffer = generateClickBuffer(
                frequency: 350, duration: 0.08, amplitude: 0.30,
                soundType: .cowbell, sampleRate: sampleRate
            )

        case .stick:
            // Stick: short noise burst
            accentBuffer = generateClickBuffer(
                frequency: 1000, duration: 0.03, amplitude: 0.90,
                soundType: .stick, sampleRate: sampleRate
            )
            regularBuffer = generateClickBuffer(
                frequency: 600, duration: 0.02, amplitude: 0.60,
                soundType: .stick, sampleRate: sampleRate
            )
            subdivisionBuffer = generateClickBuffer(
                frequency: 400, duration: 0.02, amplitude: 0.35,
                soundType: .stick, sampleRate: sampleRate
            )
        }

        Logger.info("Click sounds generated: \(clickSound.rawValue) style with subdivisions", category: Logger.audio)
    }

    private func generateClickBuffer(frequency: Double, duration: TimeInterval, amplitude: Float, soundType: SoundType, sampleRate: Double) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)

        // Use the EXACT format from the audio engine to avoid format conversion
        guard let engineFormat = audioEngine?.mainMixerNode.outputFormat(forBus: 0),
              let buffer = AVAudioPCMBuffer(pcmFormat: engineFormat, frameCapacity: frameCount) else {
            Logger.error("Failed to create buffer with engine format", category: Logger.audio)
            return nil
        }

        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData else { return nil }

        // Generate waveform based on sound type
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let envelopeProgress = time / duration
            let envelope = Float(pow(1.0 - envelopeProgress, 2.5))

            var sample: Float = 0

            switch soundType {
            case .sine:
                // Pure sine wave
                let sineValue = Float(sin(2.0 * Double.pi * frequency * time))
                sample = sineValue * envelope * amplitude

            case .woodblock:
                // Bandpass filtered noise for woody sound
                let noise = Float.random(in: -1...1)
                let bandpass = Float(sin(2.0 * Double.pi * frequency * time))
                sample = noise * bandpass * envelope * amplitude * 1.2

            case .cowbell:
                // Multiple harmonics for metallic sound
                let fundamental = Float(sin(2.0 * Double.pi * frequency * time))
                let harmonic2 = Float(sin(2.0 * Double.pi * frequency * 1.5 * time)) * 0.6
                let harmonic3 = Float(sin(2.0 * Double.pi * frequency * 2.0 * time)) * 0.4
                sample = (fundamental + harmonic2 + harmonic3) * envelope * amplitude * 0.5

            case .stick:
                // Very short impulse with quick decay
                let quickDecay = Float(pow(1.0 - envelopeProgress, 5.0))
                let noise = Float.random(in: -1...1)
                sample = noise * quickDecay * amplitude
            }

            // Write to all channels (mono or stereo)
            let channelCount = Int(engineFormat.channelCount)
            for channel in 0..<channelCount {
                channelData[channel][frame] = sample
            }
        }

        return buffer
    }

    private func startTimer() {
        // Calculate interval based on subdivisions for higher accuracy
        let clicksPerBeat = subdivision.clicksPerBeat
        let interval = 60.0 / bpm / Double(clicksPerBeat) / 4.0 // Check 4x per subdivision

        // Use DispatchSourceTimer for more reliable timing
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(10))

        timer.setEventHandler { [weak self] in
            self?.checkAndPlayBeat()
        }

        timer.resume()
        dispatchTimer = timer

        Logger.info("Timer started with interval: \(interval)s", category: Logger.audio)
    }

    private func checkAndPlayBeat() {
        // Update BPM if tempo ramping is enabled
        if tempoRampEnabled, let startTime = tempoRampStartTime {
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed < tempoRampDuration {
                let progress = elapsed / tempoRampDuration
                bpm = tempoRampStartBPM + (tempoRampTargetBPM - tempoRampStartBPM) * progress
            } else {
                // Ramping complete
                bpm = tempoRampTargetBPM
                tempoRampEnabled = false
                tempoRampStartTime = nil
            }
        }

        // Check player and engine state
        #if DEBUG
        let engineRunning = audioEngine?.isRunning ?? false
        let playerPlaying = playerNode?.isPlaying ?? false
        print("🔔 Timer fired - Engine: \(engineRunning), Player: \(playerPlaying)")
        #endif

        // Use Date-based timing instead of audio render time for more reliability
        let currentTime = Date().timeIntervalSince1970

        if currentTime >= nextBeatTime {
            #if DEBUG
            print("✅ Time to play beat!")
            #endif

            playBeat()

            // Calculate next beat/subdivision time
            // During pre-count, always use full beat intervals (ignore subdivisions)
            let clicksPerBeat = state == .preCount ? 1 : subdivision.clicksPerBeat
            let subdivisionDuration = 60.0 / bpm / Double(clicksPerBeat)

            // Add duration to previous time to avoid drift
            nextBeatTime += subdivisionDuration

            #if DEBUG
            print("⏭️ Next beat at: \(nextBeatTime) (in \(subdivisionDuration)s)")
            #endif
        }
    }

    private func playBeat() {
        guard let playerNode = playerNode else { return }

        // Apply volume (0 for visual-only mode)
        playerNode.volume = visualOnlyMode ? 0.0 : volume

        // Route to appropriate handler based on state
        // Each handler will schedule buffers and manage player state
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

        // Guard: Stop playing if pre-count has finished (prevents going negative)
        guard preCountRemaining > 0 else {
            #if DEBUG
            Logger.debug("Pre-count already complete, skipping beat", category: Logger.audio)
            #endif
            return
        }

        // Update display number BEFORE playing sound (for UI synchronization)
        preCountDisplayNumber = preCountRemaining

        // Beat 1 of the measure (when counter == beatsPerMeasure) gets accent, just like recording
        let isDownbeat = preCountRemaining == timeSignature.beatsPerMeasure
        let buffer = isDownbeat ? accentBuffer : regularBuffer

        guard let clickBuffer = buffer else { return }

        // Schedule buffer FIRST
        playerNode.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)

        // Then ensure player is running
        if !playerNode.isPlaying {
            playerNode.play()
        }

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

            // Delay state transition so the last countdown number stays visible
            // for the full beat duration before the overlay hides
            Task { @MainActor in
                // Wait one full beat duration before transitioning
                let beatDuration = 60.0 / self.bpm
                try? await Task.sleep(nanoseconds: UInt64(beatDuration * 1_000_000_000))

                self.state = .recording
                self.currentBeat = 0  // Reset to 0 so next beat will be the accent downbeat

                Logger.info("Pre-count complete → transitioned to recording", category: Logger.audio)
            }

            // Don't increment currentBeat - we want to start recording on beat 0 (accent)
            return
        }

        // Increment beat counter for pre-count (only if we haven't transitioned)
        currentBeat = (currentBeat + 1) % timeSignature.beatsPerMeasure
    }

    // MARK: - Recording/Standalone Beat Logic

    /// Plays a beat during recording or standalone metronome
    /// Supports subdivisions (8th notes, 16th notes, triplets)
    /// Pattern: ACCENT on beat 1, regular on other beats, subdivision clicks in between
    private func playRecordingBeat() {
        guard let playerNode = playerNode else { return }

        // Determine if this is a main beat (subdivision 0) or a subdivision
        let clicksPerBeat = subdivision.clicksPerBeat
        let isMainBeat = subdivisionCounter == 0
        let isDownbeat = isMainBeat && currentBeat == 0

        // Update displayBeat BEFORE playing so UI is in sync (only on main beats)
        if isMainBeat {
            displayBeat = currentBeat
        }

        // Choose appropriate buffer
        let buffer: AVAudioPCMBuffer?
        if isDownbeat {
            buffer = accentBuffer // Downbeat (beat 1)
        } else if isMainBeat {
            buffer = regularBuffer // Other main beats
        } else {
            buffer = subdivisionBuffer // Subdivisions
        }

        guard let clickBuffer = buffer else {
            #if DEBUG
            print("❌ ERROR: Buffer is nil!")
            #endif
            return
        }

        #if DEBUG
        print("🎵 Scheduling buffer - isPlaying: \(playerNode.isPlaying), volume: \(playerNode.volume)")
        #endif

        // Get sample rate for timing calculations
        guard let sampleRate = audioEngine?.mainMixerNode.outputFormat(forBus: 0).sampleRate else {
            Logger.error("Cannot get sample rate for timing", category: Logger.audio)
            return
        }

        // Calculate sample-accurate timing (use clicksPerBeat already calculated above)
        let beatDuration = 60.0 / bpm
        let subdivisionDuration = beatDuration / Double(clicksPerBeat)
        let samplesToNextBeat = AVAudioFramePosition(subdivisionDuration * sampleRate)

        // Get current audio time
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            // First beat - schedule immediately
            playerNode.scheduleBuffer(clickBuffer, at: nil, options: [], completionHandler: nil)

            if !playerNode.isPlaying {
                playerNode.play()
            }

            // Store starting sample time for future scheduling
            if let now = audioEngine?.outputNode.lastRenderTime {
                startSampleTime = now.sampleTime
                nextBeatSampleTime = now.sampleTime + samplesToNextBeat
            }

            #if DEBUG
            print("✓ First beat scheduled immediately")
            #endif
            return
        }

        // Schedule at precise sample time for sample-accurate timing
        let scheduleTime = AVAudioTime(sampleTime: nextBeatSampleTime, atRate: sampleRate)

        playerNode.scheduleBuffer(clickBuffer, at: scheduleTime, options: [], completionHandler: { [weak self] in
            #if DEBUG
            DispatchQueue.main.async {
                print("🎵 Buffer completed at sample time: \(self?.nextBeatSampleTime ?? 0)")
            }
            #endif
        })

        // Update next beat time using sample-accurate calculation
        nextBeatSampleTime += samplesToNextBeat

        // Ensure player is running
        if !playerNode.isPlaying {
            #if DEBUG
            print("▶️ Starting player node")
            #endif
            playerNode.play()
        }

        #if DEBUG
        print("✓ Buffer scheduled at sample time: \(nextBeatSampleTime) (+\(samplesToNextBeat) samples)")
        #endif

        // Debug logging
        #if DEBUG
        let beatNumber = currentBeat + 1
        let stateLabel = state == .recording ? "Recording" : "Standalone"
        let clickType = isDownbeat ? "ACCENT/DOWNBEAT" : (isMainBeat ? "regular beat" : "subdivision \(subdivisionCounter)")
        Logger.debug("\(stateLabel) Beat \(beatNumber).\(subdivisionCounter): \(clickType)", category: Logger.audio)
        #endif

        // Haptic feedback (always provide, even in visual-only mode)
        if isDownbeat {
            HapticManager.shared.mediumTap()  // Medium tap on downbeat
        } else if isMainBeat {
            HapticManager.shared.lightTap()   // Light tap on main beats
        } else {
            // Very subtle tap for subdivisions (or skip to reduce battery usage)
            // HapticManager.shared.lightTap()
        }

        // Update subdivision counter
        subdivisionCounter = (subdivisionCounter + 1) % clicksPerBeat

        // Update beat counter only when subdivisions complete
        if subdivisionCounter == 0 {
            currentBeat = (currentBeat + 1) % timeSignature.beatsPerMeasure
        }
    }
}
