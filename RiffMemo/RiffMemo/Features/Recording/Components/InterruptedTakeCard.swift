//
//  InterruptedTakeCard.swift
//  RiffMemo
//

import SwiftUI

/// WAS-118: the "Recording interrupted" board. Shown on the Record screen after a call (or
/// Siri, or an alarm) cut a take. The take is already saved up to the cut.
///
/// Colors are the DESIGN.md tokens (surface, raised, text, text-secondary, warning). They
/// are not in the asset catalog yet, so they live here until the token work moves them.
struct InterruptedTakeCard: View {
    let take: Recording
    let onContinue: () -> Void
    let onPlay: () -> Void

    private static let surface = Color(red: 0x17 / 255, green: 0x17 / 255, blue: 0x1C / 255)
    private static let raised = Color(red: 0x21 / 255, green: 0x21 / 255, blue: 0x28 / 255)
    private static let text = Color(red: 0xED / 255, green: 0xED / 255, blue: 0xF0 / 255)
    private static let textSecondary = Color(red: 0x9A / 255, green: 0x9A / 255, blue: 0xA3 / 255)
    private static let warning = Color(red: 0xFF / 255, green: 0xB3 / 255, blue: 0x40 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "phone")
                    .font(.title3)
                    .foregroundStyle(Self.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("A call stopped your recording")
                        .font(.headline)
                        .foregroundStyle(Self.text)
                    Text("Everything up to the call is saved. Nothing was lost.")
                        .font(.subheadline)
                        .foregroundStyle(Self.textSecondary)
                        // Wrap instead of truncating "Nothing wa…" (seen on device).
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .foregroundStyle(Self.text)
                    .accessibilityHidden(true)
                Text(take.createdDate, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(Self.text)
                Spacer()
                Text("SAVED \(take.duration.formattedDuration())")
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Self.textSecondary)
            }
            .padding(14)
            .background(Self.raised, in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)

            HStack(spacing: 10) {
                Button(action: onContinue) {
                    Text("Continue as a new take")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .foregroundStyle(Color.black)
                        .background(Self.text, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("continueAsNewTakeButton")

                Button(action: onPlay) {
                    Text("Play")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 50)
                        .foregroundStyle(Self.text)
                        .overlay(Capsule().stroke(Color.white.opacity(0.20)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("playInterruptedTakeButton")
            }
        }
        .padding(18)
        .background(Self.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Self.warning.opacity(0.4))
        )
        .accessibilityIdentifier("interruptedTakeCard")
    }
}
