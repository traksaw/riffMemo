//
//  HapticManager.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import UIKit

/// Manages haptic feedback throughout the app
@MainActor
class HapticManager {

    static let shared = HapticManager()

    private init() {}

    // MARK: - Impact Feedback

    /// Triggers impact haptic feedback
    /// - Parameter style: The intensity of the impact
    func impact(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    // MARK: - Selection Feedback

    /// Triggers selection change haptic feedback
    func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    // MARK: - Notification Feedback

    /// Triggers notification haptic feedback
    /// - Parameter type: The type of notification
    func notification(type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }

    // MARK: - Convenience Methods

    /// Light tap feedback for minor interactions
    func lightTap() {
        impact(style: .light)
    }

    /// Medium tap feedback for standard interactions
    func mediumTap() {
        impact(style: .medium)
    }

    /// Heavy tap feedback for important interactions
    func heavyTap() {
        impact(style: .heavy)
    }

    /// Success feedback (soft impact + success notification)
    func success() {
        impact(style: .soft)
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            notification(type: .success)
        }
    }

    /// Warning feedback
    func warning() {
        notification(type: .warning)
    }

    /// Error feedback
    func error() {
        notification(type: .error)
    }
}
