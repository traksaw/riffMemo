# riffMemo

<img width="1100" height="398" alt="image" src="https://github.com/user-attachments/assets/93f12627-0a02-4238-a7e7-823a8c5b7c8e" />

A modern iOS app that replicates and enhances the core experience of Apple's discontinued Music Memos app. Built for musicians who need to quickly capture, organize, and develop musical ideas.

## Overview

This app provides a friction-free way for musicians to:
- Record musical ideas with one tap
- Automatically detect tempo and key
- Organize recordings with tags and search
- Share and export to other music apps
- Sync across devices via iCloud

## Tech Stack

- **Platform**: iOS 17+ (native Swift)
- **UI Framework**: SwiftUI
- **Architecture**: MVVM + Coordinator Pattern
- **Audio Engine**: AVFoundation + Core Audio
- **Storage**: SwiftData + CloudKit
- **Package Manager**: Swift Package Manager

## Project Structure

```
musicProject/
├── RiffMemo/                  # Main Xcode project
│   ├── App/                   # App lifecycle, entry point
│   ├── Core/                  # Core utilities, extensions
│   ├── Features/              # Feature modules
│   │   ├── Recording/         # Recording feature
│   │   ├── Library/           # Library/organization feature
│   │   ├── Playback/          # Playback feature
│   │   └── Settings/          # Settings feature
│   ├── Audio/                 # Audio engine layer
│   │   ├── Recording/         # Recording manager
│   │   ├── Playback/          # Playback manager
│   │   ├── Analysis/          # Pitch, tempo, key detection
│   │   └── Waveform/          # Waveform rendering
│   ├── Data/                  # Data layer
│   │   ├── Models/            # SwiftData models
│   │   ├── Repositories/      # Data repositories
│   │   └── Storage/           # File storage utilities
│   └── Resources/             # Assets, localization
└── README.md
```

## Development Roadmap

### MVP (v1.0) - Target: 14-16 weeks
- [x] Project setup
- [ ] Core recording engine (AVAudioEngine)
- [ ] Basic UI (recording, library, playback screens)
- [ ] Waveform visualization
- [ ] Organization (tags, search, favorites)
- [ ] Audio analysis (tempo, key detection)
- [ ] iCloud sync
- [ ] Sharing and export

### Future Features (v1.1+)
- [ ] Instrument detection
- [ ] Auto-accompaniment (bass/drums)
- [ ] Project grouping
- [ ] Chord detection
- [ ] Multi-track recording
- [ ] GarageBand export

## Getting Started

### Prerequisites
- Xcode 15.0+
- iOS 17.0+ SDK
- macOS 14.0+ (Sonoma)
- Apple Developer account (for device testing)

### Setup
1. Clone this repository
2. Open `RiffMemo.xcodeproj` in Xcode
3. Select your development team in signing settings
4. Build and run on simulator or device

### Dependencies
Managed via Swift Package Manager:
- AudioKit (planned - for pitch detection)
- Other dependencies TBD

## Architecture

### MVVM + Coordinator
- **Views**: SwiftUI views (presentation)
- **ViewModels**: Business logic, state management (@Observable)
- **Coordinators**: Navigation flow
- **Repositories**: Data abstraction layer
- **Audio Engine**: Isolated audio processing layer

### Key Design Patterns
- Repository pattern for data access
- Factory pattern for audio processors
- Observer pattern for real-time updates
- Strategy pattern for instrument-specific processing

## Contributing

This is currently a solo project. Contribution guidelines will be added once the MVP is complete.

## License

MIT License. See [LICENSE](LICENSE) for details.

## Acknowledgments

Inspired by Apple's Music Memos (2016-2021)

---

**Status**: 🚧 In active development
**Started**: November 2024
