# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Users

Songwriters and band musicians who capture musical ideas on an iPhone. The typical moment: mid-practice, a guitar in their hands, an idea arriving that will be gone in a minute. They need to catch it in one tap, find it again later inside the song it belongs to, and pass it to a bandmate.

## Product Purpose

Never lose an idea. RiffMemo captures an idea in one tap, keeps it in its song (and an optional section), and sends it to a bandmate who adds a layer from their own phone. Success for 1.0: a musician records a riff, it lands in the song with its key and tempo, they send it, and a bass line comes back in time on a second phone.

## Positioning

The Music Memos replacement. Apple discontinued Music Memos in 2021 with no direct successor. RiffMemo detects tempo and key on the device and never sends an unreleased song to a server.

## Operating Context

- One-handed use, often with an instrument in the other hand or on the lap. Low light (rehearsal rooms, bedrooms at night).
- Short sessions: record, stop, name later. Review happens in batches ("3 ideas to listen back to").
- Pre-flight tools (click track with count-in, tuner) open as sheets from Home. They are 10-second checks, not destinations.
- Bandmates exchange ideas asynchronously through CloudKit private sharing.

## Capabilities and Constraints

- **Stack:** native SwiftUI, SwiftData, AVFoundation. CloudKit for Send an idea (M6). No server.
- **Terminology:** idea → take → layer. An idea belongs to a song and optionally a section. "Send an idea" is the sharing feature. "Loose ideas" are ideas not in a song.
- **Roadmap:** 1.0 ships free after milestones M0–M7 (M7 Submit). Pro (one-time purchase) comes in v1.1 and gates only v1.1 features: Practice mode, light mode, the iPad layout, batch export. Nothing that ships in 1.0 is ever gated.
- **Appearance:** 1.0 is dark only. Light mode is a v1.1 feature.
- **Analysis gate:** key and BPM detection are not featured in marketing until the accuracy target in WAS-163 is met.
- **Privacy:** all analysis on the device. Logs keep song titles and file paths private.
- **Undecided:** iCloud sync across a person's own devices (v1.1 epic WAS-176) and the Sessions v2 scope (M8, WAS-156).

## Brand Commitments

- Name: RiffMemo (kept after WAS-83).
- Promise line: "Never lose an idea."
- Launch demo line: "Your idea. Their part. Two phones."
- App icon: shipped in default, dark and tinted variants (`docs/design/app-icon/`).

## Evidence on Hand

- Design canvas with 43 boards: https://claude.ai/artifact/9qMfxvGLxzCS8SmzMMMgqq (PNG copies in `~/Downloads/RiffMemo-canvas-boards/`; Linear document "RiffMemo 1.0 design boards").
- No users, testimonials, reviews, download counts or benchmarks exist yet. Do not invent them. The M2 gate (5–10 musicians for 14 days) will produce the first real usage.

## Product Principles

1. **Capture beats everything.** One tap to record, from any state. Nothing stands between the idea and the record button.
2. **Say no to everything that isn't the idea.** Tools are sheets, not tabs. Settings stay small.
3. **The song is the unit.** Ideas, takes and layers live inside songs; organizing never forces a choice at capture time.
4. **On the device, private by default.** Analysis runs locally. Sharing is always an explicit send.
5. **Free core forever.** What ships in 1.0 is never put behind Pro.

## Accessibility & Inclusion

- Every control is at least 44 × 44 pt.
- Dynamic Type through the largest accessibility sizes (the "Largest text size" board).
- Reduce Motion is gentler, not zero: zooms and slides become fades, haptics stay.
- VoiceOver labels on every icon-only control (the boards label each one).
