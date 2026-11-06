# Device testing log

A running record of what was tested on a real iPhone, what worked, and
device-setup facts that are easy to forget. Add new entries at the top.

## Setup facts

### Two RiffMemo apps on the phone (old and new bundle ID)

The phone has two RiffMemo icons. They are two different apps to iOS.

| Icon | Bundle ID | Where it came from |
| --- | --- | --- |
| Old | `traksaw.RiffMemo.waskar` | Xcode builds before WAS-110 (Oct 31, 2026) |
| New | `com.traksaw.riffmemo` | Xcode builds and TestFlight after WAS-110 |

- iOS keys each app by bundle ID. A new bundle ID installs a new app. It does
  not replace the old one.
- Each app has its own sandbox. Recordings in the old app do not appear in
  the new app.
- The iCloud containers are separate too. The old container does not sync to
  `iCloud.com.traksaw.riffmemo`.
- Before you test, confirm which icon you opened. The old app runs old code.
- Delete the old app when it holds nothing you want to keep. Deleting it
  deletes its recordings.

Status: the old app was deleted from the phone on 2026-11-03. Only the
TestFlight app (orange dot before the name) is installed now.

## Test entries

### 2026-11-05 — WAS-118: keep recording through lock, background, calls, and kills

- Build: Debug cable install of branch `waskarpaulino/was-118-...`, launched
  from the Mac with `devicectl --console` so each event shows in the log.
- **1. Lock mid-take:** pass. Recorded, locked the phone, unlocked, stopped:
  the take is 1:03 with no gap.
- **2. Background mid-take:** pass. The take is 0:32, the whole time away.
- **3. A call mid-take:** pass. The log shows `interruptionBegan` at
  21:35:50 and the take saved at 0:45, 0.55 s after the cut. The Record tab
  showed "A call stopped your recording" with "SAVED 0:45". Play and
  "Continue as a new take" worked. Found: the card's second line truncated
  ("Nothing wa…"); fixed to wrap.
- **4. Force quit mid-take:** pass. A take started at 21:38:05, and the app
  was killed at about 21:38:27. On the next launch the log showed
  `Recovered an orphan take: …, 21.900000s`. The take appeared as
  "Recovered Recording" and was analyzed.
- **5. Upgrade over an existing library:** pass. The new `wasInterrupted`
  field migrated lightweight; all 20 recordings loaded.
- Gotcha: `devicectl device process launch` waits silently while the phone is
  locked. Unlock first, or the launch never prints anything.
- Side finding, not WAS-118: one call logged "ready to resume playback" 19
  times. The Library builds a playback view model for every row up front, and
  each one listens for audio session events.

### 2026-11-05 — WAS-177: the click plays after the count-in

- Build: Debug installs of branch `waskarpaulino/was-177-...`, opened from the
  Home Screen. Tests 1 and 2 ran on a Wi-Fi install. Test 3 ran on a cable install.
- **1. Standalone click for 1 minute:** pass on the speaker and on AirPods.
  Every beat plays.
- **2. Click through a recording after the count-in:** pass.
- **3. Step from count-in beat 4 to beat 1 (WAS-117 test D):** first run
  "a bit iffy": a gap between the count-in and the recording beats. The
  console log (cable launch with `devicectl --console`) showed the timer fire
  recording beat 1 at 630.61 s, but the delayed task set `state = .recording`
  only at 630.70 s. Beat 1 went to the count-in path, whose guard dropped it
  silently. Fixed: the count-in ends when `preCountRemaining` reaches 0, not
  when the state changes. Re-test on a cable install: **pass**, an even tempo
  into beat 1.
- **4. Follow-up fixes, cable install:** all pass.
  - Stop right after count-in beat 4, then start the click again: it starts
    normally. Before, the delayed task marked the stopped click as recording.
  - Drag the tempo slider during the count-in: the recording still starts.
    Before, `setBPM` restarted the click and reset the count-in, so the
    recording never started.
  - Drag the tempo slider during a recording: the tempo changes with no
    stutter. Before, every slider step restarted the audio engine.
  - Subdivisions on: the step from count-in beat 4 into beat 1 is even.
- Gotcha: `Logger.debug` lines do not appear in `devicectl --console`. Only
  `info` and higher, plus `print`, show up there.
- Cause, proved with an offline `AVAudioPlayerNode` probe: a click scheduled at
  a sample time the player's clock has already passed plays nothing. The app
  scheduled main beats from 0 (after the count-in) or from the engine output
  clock (standalone), never from the player's own clock.

### 2026-11-04 — WAS-117: the audio session coordinator

- Build: Debug cable install of commit `aa7ff5f` (branch
  `waskarpaulino/was-117-...`), opened from the Home Screen with no debugger.
- **A. Music resumes after the click stops:** pass.
- **B. Music resumes after a take plays to its end:** pass. Found a bug: the
  play button stayed on "pause" after the take ended. Fixed in `41e6d53`.
- **C. AirPods keep the sound across click, tuner, and playback:** pass.
- **D. No stutter when recording starts over the click:** not tested. The
  click is silent after the count-in (see below).
- **Silent click after the count-in.** The count-in plays. No beats play
  after it, in the standalone click or under a recording, on the speaker or
  AirPods. The `main` build `b934efc` (before WAS-117) does the same, so
  WAS-117 did not cause it. Likely cause, not yet proved: the main beats are
  scheduled at a sample time that is already in the past
  (`SharedMetronomeService.playRecordingBeat`, from WAS-53). Filed as
  WAS-177, which also takes over test D.

### 2026-11-03 — WAS-113: TestFlight 1.0 (9) skips the compliance hold

- Build: TestFlight 1.0 (9), from the WAS-113 branch (`main` plus the
  `ExportComplianceTests`). First build uploaded with
  `ITSAppUsesNonExemptEncryption = NO`, from PR #47.
- Result: App Store Connect showed build 9 as **Ready to Submit** in the
  Internal group, with no **Missing Compliance** and no **Manage** button.
  Nobody answered the export question. Builds 4, 6, 7, and 8 had all stopped
  there.
- Guard: `ExportComplianceTests` fails CI if the key disappears, or if app
  source starts calling encryption APIs, which would make `NO` untrue.

### 2026-11-03 — TestFlight 1.0 (8) installed after a compliance hold

- Build: TestFlight 1.0 (8), from `main` at `6b2861a` (the WAS-165 merge).
  Installed with **Update** in TestFlight. It replaced the cable-installed
  branch build, and the orange dot came back. Recordings stayed.
- Gotcha: build 8 uploaded fine but never reached the phone. App Store
  Connect held it in **Missing Compliance**, because the app did not declare
  `ITSAppUsesNonExemptEncryption`. Builds 4, 6, and 7 were stuck the same way.
  Fix for build 8: App Store Connect → TestFlight → build → **Manage** →
  "None of the algorithms mentioned above" → Save. PR #47 sets the key to
  `NO`, so later builds skip the question.
- Note: build numbers come from `github.run_number`, so they skip numbers
  (5, then 8). That is fine; they only need to go up.

### 2026-11-03 — WAS-165: titles are `<private>` in device logs

- Build: Release build of the WAS-165 branch, installed over cable with
  `xcrun devicectl device install app`. Launched from the home screen, with
  no debugger attached. This replaced TestFlight build 5 on the phone.
- Result: Console showed `Analysis complete for: <private>`. The song title
  is hidden. `Key detected: F# Major` and `Quality: Poor` stay readable.
- How to check: Console app → select the iPhone → Start → filter
  `subsystem:com.traksaw.riffmemo`. Turn on Action → Include Info Messages,
  or most app lines stay hidden.
- Gotcha: launching from Xcode attaches a debugger, and then private values
  show in plain text. The simulator shows them too. Only a device with no
  debugger proves redaction.
- Gotcha: after a cable install, TestFlight shows **Open**, not **Install**.
  It only checks the bundle ID, so it can't tell the Xcode copy from build 5.
  Getting build 5 back means deleting the app, which deletes its recordings.
  Wait for the next TestFlight build instead: it shows **Update**.

### 2026-11-03 — Playback works on device

- Recorded singing, then played it back. Playback works.
- Build: TestFlight 1.0 (5), new app (`com.traksaw.riffmemo`). Released
  Nov 2, 2026. Expires Jan 31, 2027.
- How to check the build: open the TestFlight app, then tap RiffMemo. The
  screen shows the version, build number, and expiry date.
