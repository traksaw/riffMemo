//
//  AudioSessionCoordinatorTests.swift
//  RiffMemoTests
//

import AVFoundation
import Testing
@testable import RiffMemo

/// WAS-117: one owner applies the union of active demands, changes the category only when
/// it must, and deactivates (so Music resumes) when the last demand is released.
@MainActor
struct AudioSessionCoordinatorTests {

    private func makeCoordinator() -> (AudioSessionCoordinator, FakeAudioSession) {
        let session = FakeAudioSession()
        // A private center, so these tests never see real system notifications.
        let coordinator = AudioSessionCoordinator(session: session, notificationCenter: NotificationCenter())
        return (coordinator, session)
    }

    // MARK: - Configuration

    @Test func playbackAloneUsesPlaybackOnly() throws {
        let (coordinator, session) = makeCoordinator()

        try coordinator.acquire(.play)

        #expect(session.categoryCalls == [.playbackOnly])
        #expect(session.activeCalls.last?.active == true)
    }

    @Test func clickUsesTheInputConfigurationSoRecordingNeedsNoChange() throws {
        let (coordinator, session) = makeCoordinator()

        try coordinator.acquire(.click)
        try coordinator.acquire(.record)

        // One setCategory for both: starting a take over a running click must not
        // reconfigure the session, because that glitches the click.
        #expect(session.categoryCalls == [.input])
    }

    @Test func playingATakeOverTheClickKeepsTheInputConfiguration() throws {
        let (coordinator, session) = makeCoordinator()

        try coordinator.acquire(.click)
        try coordinator.acquire(.play)

        #expect(session.categoryCalls == [.input])
        #expect(coordinator.requiredConfiguration == .input)
    }

    @Test func inputConfigurationKeepsAirPodsAndAvoidsVoiceProcessing() {
        let input = AudioSessionCoordinator.Configuration.input

        #expect(input.category == .playAndRecord)
        #expect(input.mode == .measurement)
        #expect(input.options.contains(.allowBluetoothA2DP))
        #expect(input.options.contains(.defaultToSpeaker))
    }

    // MARK: - Release

    @Test func releasingTheLastDemandDeactivatesAndNotifiesOthers() throws {
        let (coordinator, session) = makeCoordinator()
        let token = try coordinator.acquire(.play)

        coordinator.release(token)

        #expect(coordinator.activeDemands.isEmpty)
        let last = try #require(session.activeCalls.last)
        #expect(last.active == false)
        #expect(last.options.contains(.notifyOthersOnDeactivation))
    }

    @Test func releasingRecordWhilePlayingNarrowsToPlaybackOnly() throws {
        let (coordinator, session) = makeCoordinator()
        let record = try coordinator.acquire(.record)
        try coordinator.acquire(.play)

        coordinator.release(record)

        #expect(session.categoryCalls == [.input, .playbackOnly])
        let stayedActive = session.activeCalls.allSatisfy(\.active)
        #expect(stayedActive)
    }

    @Test func releasingTwiceDoesNothingTheSecondTime() throws {
        let (coordinator, session) = makeCoordinator()
        let token = try coordinator.acquire(.tune)

        coordinator.release(token)
        let callsAfterFirstRelease = session.activeCalls.count
        coordinator.release(token)

        #expect(session.activeCalls.count == callsAfterFirstRelease)
    }

    @Test func acquiringAgainAfterDeactivationReappliesTheCategory() throws {
        let (coordinator, session) = makeCoordinator()
        coordinator.release(try coordinator.acquire(.play))

        try coordinator.acquire(.play)

        #expect(session.categoryCalls == [.playbackOnly, .playbackOnly])
    }

    @Test func failedAcquireKeepsNoDemand() {
        let (coordinator, session) = makeCoordinator()
        session.setActiveError = FakeAudioSession.Failure()

        #expect(throws: FakeAudioSession.Failure.self) {
            try coordinator.acquire(.record)
        }
        #expect(coordinator.activeDemands.isEmpty)
    }

    // MARK: - Event parsing

    @Test func parsesInterruptionBeganAndEnded() {
        let began: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue
        ]
        let endedResume: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
            AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
        ]
        let endedNoOptions: [AnyHashable: Any] = [
            AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue
        ]

        #expect(AudioSessionCoordinator.interruptionEvent(from: began) == .interruptionBegan)
        #expect(AudioSessionCoordinator.interruptionEvent(from: endedResume) == .interruptionEnded(shouldResume: true))
        #expect(AudioSessionCoordinator.interruptionEvent(from: endedNoOptions) == .interruptionEnded(shouldResume: false))
        #expect(AudioSessionCoordinator.interruptionEvent(from: nil) == nil)
    }

    @Test func parsesOnlyTheRouteChangesFeaturesActOn() {
        func info(_ reason: AVAudioSession.RouteChangeReason) -> [AnyHashable: Any] {
            [AVAudioSessionRouteChangeReasonKey: reason.rawValue]
        }

        #expect(AudioSessionCoordinator.routeChangeEvent(from: info(.oldDeviceUnavailable)) == .audioDeviceLost)
        #expect(AudioSessionCoordinator.routeChangeEvent(from: info(.newDeviceAvailable)) == .audioDeviceAdded)
        // Our own setCategory calls post .categoryChange; features must not react to them.
        #expect(AudioSessionCoordinator.routeChangeEvent(from: info(.categoryChange)) == nil)
        #expect(AudioSessionCoordinator.routeChangeEvent(from: nil) == nil)
    }
}

// MARK: - Fake session

@MainActor
private final class FakeAudioSession: AudioSessionControlling {
    struct Failure: Error {}
    struct ActiveCall { let active: Bool; let options: AVAudioSession.SetActiveOptions }

    private(set) var categoryCalls: [AudioSessionCoordinator.Configuration] = []
    private(set) var activeCalls: [ActiveCall] = []
    var setActiveError: Error?

    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws {
        categoryCalls.append(.init(category: category, mode: mode, options: options))
    }

    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws {
        if let setActiveError { throw setActiveError }
        activeCalls.append(.init(active: active, options: options))
    }
}
