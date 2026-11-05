//
//  AudioSessionCoordinator.swift
//  RiffMemo
//

import AVFoundation
import Combine
import OSLog

/// The one owner of the app's `AVAudioSession` (WAS-117).
///
/// iOS gives an app a single audio session. Recording, playback, the tuner and the click
/// used to set its category themselves, so the newest caller won: AirPods dropped to the
/// speaker, the click glitched when playback started, and nothing ever deactivated the
/// session, so Music never resumed after RiffMemo stopped.
///
/// Features now *ask* for what they need. Each one calls `acquire(_:)` when it starts and
/// `release(_:)` when it stops. The coordinator applies one configuration that covers
/// every demand still active, and deactivates the session (letting other apps resume)
/// when the last demand is released.
@MainActor
final class AudioSessionCoordinator {

    /// What a feature needs from the session.
    nonisolated enum Demand: Sendable, CustomStringConvertible {
        case record
        case play
        case tune
        case click

        /// Whether this demand needs the `.playAndRecord` configuration.
        ///
        /// `.click` counts even though it only plays: a musician starts the click and then
        /// records over it. Changing the category under a running click resets the route and
        /// glitches it (see the old comment in `SharedMetronomeService.setupAudioSession`), so
        /// the click starts in the configuration recording will need.
        var needsInputRoute: Bool {
            switch self {
            case .record, .tune, .click: return true
            case .play: return false
            }
        }

        var description: String {
            switch self {
            case .record: return "record"
            case .play: return "play"
            case .tune: return "tune"
            case .click: return "click"
            }
        }
    }

    /// Proof of one active demand. Pass it back to `release(_:)` exactly once.
    nonisolated struct Token: Hashable, Sendable {
        fileprivate let id = UUID()
        let demand: Demand
    }

    /// Typed session events, parsed once here instead of in every view model.
    nonisolated enum Event: Sendable, Equatable {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        /// The device that was playing or recording went away (headphones unplugged,
        /// Bluetooth disconnected).
        case audioDeviceLost
        case audioDeviceAdded
    }

    /// The configuration the coordinator applies. Exposed for tests.
    nonisolated struct Configuration: Equatable, Sendable {
        let category: AVAudioSession.Category
        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions

        /// Mic and output together. `.allowBluetoothA2DP` keeps AirPods as the output
        /// (A2DP is output-only, so the built-in mic still records at full quality).
        /// `.measurement` turns off the system's voice processing, which would color an
        /// instrument recording and the tuner's pitch reading.
        static let input = Configuration(
            category: .playAndRecord,
            mode: .measurement,
            options: [.defaultToSpeaker, .allowBluetoothA2DP]
        )

        static let playbackOnly = Configuration(category: .playback, mode: .default, options: [])
    }

    static let shared = AudioSessionCoordinator(session: AVAudioSession.sharedInstance())

    /// Session events for any feature that must react (pause playback, stop recording).
    var events: AnyPublisher<Event, Never> { eventSubject.eraseToAnyPublisher() }

    private let session: AudioSessionControlling
    private let notificationCenter: NotificationCenter
    private var active: Set<Token> = []
    private var applied: Configuration?
    private let eventSubject = PassthroughSubject<Event, Never>()
    private var cancellables = Set<AnyCancellable>()

    init(session: AudioSessionControlling, notificationCenter: NotificationCenter = .default) {
        self.session = session
        self.notificationCenter = notificationCenter
        observeSession()
    }

    /// The demands currently holding the session. Exposed for tests.
    var activeDemands: [Demand] { active.map(\.demand) }

    /// The configuration the active demands need, or `nil` when none are active.
    var requiredConfiguration: Configuration? {
        guard !active.isEmpty else { return nil }
        return active.contains { $0.demand.needsInputRoute } ? .input : .playbackOnly
    }

    // MARK: - Acquire and release

    /// Registers a demand and makes sure the session covers it.
    ///
    /// If configuring the session fails, the demand is not kept, so a failed start never
    /// leaves the session held.
    @discardableResult
    func acquire(_ demand: Demand) throws -> Token {
        let token = Token(demand: demand)
        active.insert(token)
        do {
            try apply()
        } catch {
            active.remove(token)
            Logger.audio.error("Audio session acquire failed for \(demand, privacy: .public): [\(error.logCode, privacy: .public)] \(error)")
            throw error
        }
        Logger.audio.info("Audio session acquired for \(demand, privacy: .public); active: \(self.active.count)")
        return token
    }

    /// Ends a demand. Releasing a token twice, or one that was never acquired, does nothing.
    func release(_ token: Token) {
        guard active.remove(token) != nil else { return }
        Logger.audio.info("Audio session released for \(token.demand, privacy: .public); active: \(self.active.count)")

        if active.isEmpty {
            deactivate()
        } else {
            // A smaller set of demands may need less (for example, recording stopped but
            // playback continues). A failure here keeps the current, wider configuration,
            // which still covers every remaining demand.
            do {
                try apply()
            } catch {
                Logger.audio.error("Audio session reconfigure after release failed: [\(error.logCode, privacy: .public)] \(error)")
            }
        }
    }

    // MARK: - Private

    private func apply() throws {
        guard let required = requiredConfiguration else { return }

        // Every setCategory call can reset the audio route and glitch a running engine,
        // so only change the session when the configuration actually differs.
        if applied != required {
            try session.setCategory(required.category, mode: required.mode, options: required.options)
            applied = required
        }
        try session.setActive(true, options: [])
    }

    private func deactivate() {
        do {
            // Lets Music or a podcast resume after RiffMemo stops making sound.
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation fails while any audio I/O is still running. The next acquire
            // reactivates the session, so this is logged, not thrown.
            Logger.audio.error("Audio session deactivate failed: [\(error.logCode, privacy: .public)] \(error)")
        }
        applied = nil
    }

    private func observeSession() {
        notificationCenter
            .publisher(for: AVAudioSession.interruptionNotification)
            .compactMap { Self.interruptionEvent(from: $0.userInfo) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.publish(event) }
            .store(in: &cancellables)

        notificationCenter
            .publisher(for: AVAudioSession.routeChangeNotification)
            .compactMap { Self.routeChangeEvent(from: $0.userInfo) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in self?.publish(event) }
            .store(in: &cancellables)
    }

    private func publish(_ event: Event) {
        Logger.audio.info("Audio session event: \(String(describing: event), privacy: .public)")
        eventSubject.send(event)
    }

    // MARK: - Parsing (nonisolated so tests can call them directly)

    nonisolated static func interruptionEvent(from userInfo: [AnyHashable: Any]?) -> Event? {
        guard let typeValue = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return nil
        }
        switch type {
        case .began:
            return .interruptionBegan
        case .ended:
            let optionsValue = userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            return .interruptionEnded(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }

    nonisolated static func routeChangeEvent(from userInfo: [AnyHashable: Any]?) -> Event? {
        guard let reasonValue = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return nil
        }
        switch reason {
        case .oldDeviceUnavailable:
            return .audioDeviceLost
        case .newDeviceAvailable:
            return .audioDeviceAdded
        case .routeConfigurationChange, .categoryChange, .override, .wakeFromSleep,
             .noSuitableRouteForCategory, .unknown:
            return nil
        @unknown default:
            return nil
        }
    }
}

// MARK: - Session seam

/// The slice of `AVAudioSession` the coordinator uses, so tests can use a fake.
protocol AudioSessionControlling: AnyObject {
    func setCategory(_ category: AVAudioSession.Category,
                     mode: AVAudioSession.Mode,
                     options: AVAudioSession.CategoryOptions) throws
    func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions) throws
}

extension AVAudioSession: AudioSessionControlling {}
