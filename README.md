# RiffMemo

[![iOS Build](https://github.com/traksaw/riffMemo/actions/workflows/ios-build.yml/badge.svg)](https://github.com/traksaw/riffMemo/actions/workflows/ios-build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A native iOS app for musicians to capture, analyze, and organize musical ideas — inspired by Apple's discontinued Music Memos. Built with SwiftUI and AVFoundation, with an on-device audio analysis pipeline for tempo, key, and pitch detection.

## Features

- **One-tap recording** with a live waveform and frequency spectrum view
- **On-device audio analysis** — BPM detection, key detection, pitch detection, and recording quality scoring
- **Built-in metronome and tuner**
- **Library management** — search, organize, and review past recordings with waveform thumbnails
- **Export** — single and batch export with configurable options
- **iCloud sync** via SwiftData + CloudKit

## Screenshots

| Recording | Library | Tuner | Metronome |
|:---:|:---:|:---:|:---:|
| <img src="Screenshots/recording-active.png" width="200" alt="Recording a riff with live waveform"> | <img src="Screenshots/library.png" width="200" alt="Library with BPM and key detected per recording"> | <img src="Screenshots/tuner.png" width="200" alt="Chromatic tuner"> | <img src="Screenshots/metronome.png" width="200" alt="Metronome with tap tempo"> |

## Engineering Highlights

- **Custom on-device DSP** — BPM, key, and pitch detection are implemented from scratch (`Audio/Analysis/`) rather than pulled from a third-party library, running entirely on-device with no network round-trip.
- **Testable core flows** — `RecordingViewModel` and `LibraryViewModel` depend on protocol-mocked audio/data interfaces (`AudioRecorderProtocol`, `RecordingRepository`), so their state-machine and race-condition logic is unit-tested with `XCTest` without touching AVFoundation or a simulator's microphone; the remaining view models don't yet have dedicated test coverage.
- **Clear separation of concerns** — MVVM throughout: views own presentation, `@Observable` view models own state. No feature reaches into another feature's internals.
- **CI on every change** — GitHub Actions builds and runs the test suite on every push and pull request against `main`, catching regressions before merge.

## Tech Stack

- **Platform**: iOS (Swift, SwiftUI)
- **Architecture**: MVVM
- **Audio**: AVFoundation / AVAudioEngine for recording and playback, custom DSP for BPM/key/pitch detection
- **Persistence**: SwiftData with CloudKit sync
- **CI**: GitHub Actions — automated build and test on every push/PR ([workflow](.github/workflows))
- **Testing**: XCTest (unit + UI)

## Architecture

```
RiffMemo/
├── App/                    # App entry point, tab navigation (MainTabView)
├── Core/                   # Shared utilities, extensions, logging, sharing, haptics
├── Features/                # SwiftUI views + view models, one folder per feature
│   ├── Recording/          # Recording flow, live waveform, spectrum visualization
│   ├── Library/             # Browse, search, organize recordings
│   ├── Playback/            # Recording detail + playback controls
│   ├── Waveform/            # Waveform rendering and thumbnails
│   ├── Analysis/             # Analysis results UI
│   ├── Metronome/           # Metronome
│   ├── Tuner/                # Instrument tuner
│   ├── Export/               # Single + batch export
│   └── Settings/
├── Audio/                   # Audio engine layer, isolated from UI
│   ├── Recording/           # AVAudioEngine-based recording manager
│   ├── Playback/             # Playback manager
│   ├── Analysis/             # BPM, key, and pitch detectors; quality analyzer
│   ├── Metronome/            # Metronome timing engine
│   └── Export/                # Audio export engine
├── Data/
│   ├── Models/                # SwiftData models
│   ├── Repositories/          # Data access layer
│   └── Storage/               # File + persistence utilities
└── Resources/                 # Assets, localization
```

Each feature follows the same shape: a SwiftUI `View` and an `@Observable` `ViewModel` for state and business logic; navigation is handled directly with SwiftUI's `TabView`/`NavigationStack`/sheets rather than a dedicated Coordinator layer. The audio engine and data layers are isolated behind repositories/managers so the UI never talks to AVFoundation or SwiftData directly — `RecordingViewModel` and `LibraryViewModel` in particular are unit-tested against protocol mocks rather than the real engine.

## Getting Started

### Prerequisites
- Xcode 15+
- iOS 17+ SDK
- macOS 14+ (Sonoma)
- Apple Developer account (for on-device testing)

### Setup
```bash
git clone https://github.com/traksaw/riffMemo.git
cd riffMemo/RiffMemo
open RiffMemo.xcodeproj
```
Select your development team under signing settings, then build and run. See [SETUP_GUIDE.md](SETUP_GUIDE.md) for a walkthrough and [XCODE_FIX_GUIDE.md](XCODE_FIX_GUIDE.md) for common project-setup issues.

### Running tests
```bash
cd RiffMemo
xcodebuild test -project RiffMemo.xcodeproj -scheme RiffMemo \
  -destination 'generic/platform=iOS Simulator'
```
The same build-and-test job runs in CI on every push and pull request against `main`.

## Roadmap

- [ ] Instrument detection
- [ ] Chord detection
- [ ] Multi-track recording
- [ ] Auto-accompaniment (bass/drums)
- [ ] GarageBand export

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Inspired by Apple's Music Memos (2016–2021).

## Contact

**Waskar Paulino**
[GitHub](https://github.com/traksaw) · [LinkedIn](https://www.linkedin.com/in/waskar-m-paulino/) · [workwithwaskar@gmail.com](mailto:workwithwaskar@gmail.com)

---

**Status**: In active development
**Started**: November 2025
