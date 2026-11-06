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
