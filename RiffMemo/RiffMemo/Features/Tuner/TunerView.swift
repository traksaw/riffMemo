//
//  TunerView.swift
//  RiffMemo
//
//  Created by Claude Code on 11/16/25.
//

import SwiftUI

struct TunerView: View {
    @StateObject private var pitchDetector = PitchDetector()
    @State private var isActive = false

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 40) {
                    Spacer()

                    // Note Display
                    VStack(spacing: 12) {
                        Text(pitchDetector.note.isEmpty ? "—" : pitchDetector.note)
                            .font(.system(size: 80, weight: .bold, design: .rounded))
                            .foregroundStyle(tuningColor)
                            .animation(.easeInOut(duration: 0.2), value: pitchDetector.note)

                        Text(String(format: "%.1f Hz", pitchDetector.frequency))
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    // Needle Indicator
                    TunerNeedle(cents: pitchDetector.cents)
                        .frame(height: 200)
                        .padding(.horizontal, 40)

                    // Cents Display
                    Text(centsDisplay)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(tuningColor)
                        .monospacedDigit()

                    // In-Tune Indicator
                    if abs(pitchDetector.cents) < 5 && !pitchDetector.note.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("In Tune")
                        }
                        .font(.headline)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                    }

                    Spacer()

                    // Start/Stop Button
                    Button(action: {
                        toggleTuner()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: isActive ? "stop.circle.fill" : "play.circle.fill")
                                .font(.title2)

                            Text(isActive ? "Stop" : "Start Tuner")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: 300)
                        .padding()
                        .background(isActive ? Color.red : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                        .shadow(radius: 8)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                        .frame(height: 40)
                }
            }
            .navigationTitle("Tuner")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onDisappear {
            if isActive {
                Task {
                    await pitchDetector.stopDetection()
                }
            }
        }
    }

    private var tuningColor: Color {
        guard !pitchDetector.note.isEmpty else { return .secondary }

        let cents = abs(pitchDetector.cents)

        if cents < 5 {
            return .green
        } else if cents < 15 {
            return .yellow
        } else {
            return .orange
        }
    }

    private var centsDisplay: String {
        guard !pitchDetector.note.isEmpty else { return "—" }

        let sign = pitchDetector.cents >= 0 ? "+" : ""
        return "\(sign)\(Int(pitchDetector.cents))¢"
    }

    private func toggleTuner() {
        Task {
            if isActive {
                await pitchDetector.stopDetection()
                isActive = false
                HapticManager.shared.lightTap()
            } else {
                do {
                    try await pitchDetector.startDetection()
                    isActive = true
                    HapticManager.shared.mediumTap()
                } catch {
                    Logger.error("Failed to start tuner: \(error)", category: Logger.audio)
                }
            }
        }
    }
}

// MARK: - Tuner Needle

struct TunerNeedle: View {
    let cents: Double

    private let maxCents: Double = 50

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background arc
                TunerArc()
                    .stroke(Color.gray.opacity(0.3), lineWidth: 3)

                // Tick marks
                ForEach(Array(stride(from: -50, through: 50, by: 10)), id: \.self) { tick in
                    TickMark(cents: Double(tick), size: geometry.size)
                }

                // Center line
                Rectangle()
                    .fill(Color.green)
                    .frame(width: 2, height: 30)
                    .offset(y: -geometry.size.height / 2 + 15)

                // Needle
                Needle(angle: needleAngle)
                    .stroke(needleColor, lineWidth: 4)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: cents)

                // Center dot
                Circle()
                    .fill(needleColor)
                    .frame(width: 12, height: 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var needleAngle: Double {
        let clampedCents = min(max(cents, -maxCents), maxCents)
        return (clampedCents / maxCents) * 45 // -45° to +45°
    }

    private var needleColor: Color {
        let absCents = abs(cents)

        if absCents < 5 {
            return .green
        } else if absCents < 15 {
            return .yellow
        } else {
            return .orange
        }
    }
}

struct TunerArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let radius = min(rect.width, rect.height * 2) / 2

        path.addArc(
            center: center,
            radius: radius - 20,
            startAngle: .degrees(180 + 45),
            endAngle: .degrees(360 - 45),
            clockwise: false
        )

        return path
    }
}

struct Needle: Shape {
    var angle: Double // -45 to +45 degrees

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let center = CGPoint(x: rect.midX, y: rect.maxY)
        let length = min(rect.width, rect.height * 2) / 2 - 30

        let angleRadians = CGFloat((angle - 90) * .pi / 180)
        let endPoint = CGPoint(
            x: center.x + length * CGFloat(cos(angleRadians)),
            y: center.y + length * CGFloat(sin(angleRadians))
        )

        path.move(to: center)
        path.addLine(to: endPoint)

        return path
    }
}

struct TickMark: View {
    let cents: Double
    let size: CGSize

    var body: some View {
        let center = CGPoint(x: size.width / 2, y: size.height)
        let radius = min(size.width, size.height * 2) / 2 - 20
        let angle = (cents / 50) * 45 + 180 // Convert cents to angle

        let angleRadians = CGFloat(angle * .pi / 180)
        let startRadius = radius - 10
        let endRadius = radius - 25

        let startPoint = CGPoint(
            x: center.x + startRadius * CGFloat(cos(angleRadians)),
            y: center.y + startRadius * CGFloat(sin(angleRadians))
        )

        let endPoint = CGPoint(
            x: center.x + endRadius * CGFloat(cos(angleRadians)),
            y: center.y + endRadius * CGFloat(sin(angleRadians))
        )

        return Path { path in
            path.move(to: startPoint)
            path.addLine(to: endPoint)
        }
        .stroke(cents == 0 ? Color.green : Color.gray.opacity(0.5), lineWidth: cents == 0 ? 3 : 2)
    }
}

#Preview {
    TunerView()
}
