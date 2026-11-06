//
//  MetronomeClickSchedulingTests.swift
//  RiffMemoTests
//

import AVFoundation
import Testing
@testable import RiffMemo

/// WAS-177: a click scheduled at a sample time that has already passed plays nothing.
/// Every click must land on the player's own clock, ahead of where the player is now.
struct MetronomeClickSchedulingTests {

    private let lead: AVAudioFramePosition = 1_000

    @Test func firstClickAnchorsAheadOfThePlayer() {
        let time = SharedMetronomeService.clickSampleTime(planned: nil, playerNow: 96_000, lead: lead)

        #expect(time == 97_000)
    }

    @Test func plannedClickAheadOfThePlayerKeepsTheGrid() {
        let time = SharedMetronomeService.clickSampleTime(planned: 120_000, playerNow: 96_000, lead: lead)

        #expect(time == 120_000)
    }

    /// The bug: after a 2 s count-in the player is at 96 000, but the app scheduled at 0.
    @Test func plannedClickThatAlreadyPassedReanchorsInsteadOfGoingSilent() {
        let time = SharedMetronomeService.clickSampleTime(planned: 0, playerNow: 96_000, lead: lead)

        #expect(time == 97_000)
    }

    @Test func leadCoversTheTimerCheckIntervalPlusRenderMargin() {
        // At 120 BPM in quarter notes, the timer checks every 0.125 s. A click can be due
        // up to one check late, so the lead must cover that, plus the render margin.
        let frames = SharedMetronomeService.schedulingLead(checkInterval: 0.125, sampleRate: 48_000)

        #expect(frames == AVAudioFramePosition((0.125 + 0.03) * 48_000))
    }
}

/// WAS-177 test 3: the timer can fire recording beat 1 before the delayed task flips the state
/// to `.recording`. That click must still play as a main beat, at the main-beat interval.
@MainActor
struct MetronomeCountInHandoverTests {

    @Test func countInBeatsStillPlayAsCountIn() {
        #expect(SharedMetronomeService.isCountInClick(state: .preCount, preCountRemaining: 4))
        #expect(SharedMetronomeService.isCountInClick(state: .preCount, preCountRemaining: 1))
    }

    /// The bug: state is still `.preCount`, but the count-in is over. Routing it to the
    /// count-in path dropped beat 1 and left a gap.
    @Test func firstBeatAfterTheCountInPlaysAsAMainBeat() {
        #expect(!SharedMetronomeService.isCountInClick(state: .preCount, preCountRemaining: 0))
    }

    @Test func recordingAndStandaloneBeatsAreNotCountIn() {
        #expect(!SharedMetronomeService.isCountInClick(state: .recording, preCountRemaining: 0))
        #expect(!SharedMetronomeService.isCountInClick(state: .standalone, preCountRemaining: 0))
    }
}

/// WAS-177 follow-ups, driven through the real shared metronome on the simulator.
/// The bugs are about timing between real tasks, so pure helpers cannot show them.
@MainActor
@Suite(.serialized)
struct MetronomeCountInLifecycleTests {

    private let metronome = SharedMetronomeService.shared

    /// Polls until `condition` is true or `timeout` passes. Returns the final value.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// Stop inside the beat between the last count-in click and the switch to recording.
    /// The delayed switch must not run after stop() and mark an idle click as recording.
    @Test func stopDuringTheHandoverStaysIdle() async throws {
        let savedBPM = metronome.bpm
        defer { metronome.stop(); metronome.setBPM(savedBPM) }
        metronome.setBPM(240)  // 0.25 s beats keep the test short

        metronome.startWithPreCount {}
        try #require(metronome.isPlaying)
        let countInDone = await waitUntil(timeout: 3) { metronome.preCountRemaining == 0 }
        try #require(countInDone)
        #expect(metronome.state == .preCount)  // still inside the handover beat

        metronome.stop()
        try? await Task.sleep(nanoseconds: 500_000_000)  // past the end of the handover beat

        #expect(metronome.state == .idle)
        #expect(metronome.preCountRemaining == 0)
    }

    /// The bug: a tempo change during the count-in restarted the click as standalone, so the
    /// count never reached 0 and the recording never started.
    @Test func tempoChangeDuringTheCountInStillStartsTheRecording() async throws {
        let savedBPM = metronome.bpm
        defer { metronome.stop(); metronome.setBPM(savedBPM) }
        metronome.setBPM(240)

        var recordingStarted = false
        metronome.startWithPreCount { recordingStarted = true }
        try #require(metronome.isPlaying)
        let firstBeatPlayed = await waitUntil(timeout: 2) { metronome.preCountRemaining < 4 }
        try #require(firstBeatPlayed)

        metronome.setBPM(250)

        #expect(metronome.state == .preCount)
        #expect(metronome.preCountRemaining > 0)
        #expect(await waitUntil(timeout: 3) { recordingStarted })
        #expect(await waitUntil(timeout: 2) { metronome.state == .recording })
    }

    /// A tempo change during a recording changes the tempo in place. It keeps the state.
    @Test func tempoChangeDuringARecordingKeepsRecording() async throws {
        let savedBPM = metronome.bpm
        defer { metronome.stop(); metronome.setBPM(savedBPM) }
        metronome.setBPM(240)

        metronome.startWithPreCount {}
        try #require(metronome.isPlaying)
        try #require(await waitUntil(timeout: 4) { metronome.state == .recording })

        metronome.setBPM(200)

        #expect(metronome.isPlaying)
        #expect(metronome.state == .recording)
        #expect(metronome.bpm == 200)
    }
}
