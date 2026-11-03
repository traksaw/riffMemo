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
