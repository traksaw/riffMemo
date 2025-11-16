# Setup Guide - Creating the Xcode Project

Follow these steps to create the Xcode project for RiffMemo.

## Step 1: Open Xcode

1. Launch **Xcode** (make sure you have Xcode 15.0 or later)

## Step 2: Create New Project

1. Click **"Create New Project"** (or File > New > Project)
2. Select **iOS** tab at the top
3. Choose **"App"** template
4. Click **Next**

## Step 3: Configure Project Settings

Enter the following details:

- **Product Name**: `RiffMemo`
- **Team**: Select your Apple Developer team (or "Add Team" if needed)
- **Organization Identifier**: `com.yourname` (e.g., `com.waskar`)
  - This creates Bundle ID: `com.yourname.RiffMemo`
- **Interface**: **SwiftUI** ⚠️ Important!
- **Language**: **Swift** ⚠️ Important!
- **Storage**: **SwiftData** ⚠️ Important!
- **Include Tests**: ✅ Checked (both Unit and UI)

Click **Next**

## Step 4: Save Location

⚠️ **CRITICAL**:
- Navigate to: `/Users/waskarpaulino/Desktop/Personal/projects/musicProject`
- **UNCHECK** "Create Git repository" (we already have one!)
- Click **Create**

## Step 5: Initial Build Test

1. Select **iPhone 15 Pro** simulator (or any recent iPhone)
2. Click **Run** button (▶️) or press `Cmd + R`
3. Wait for build to complete
4. You should see "Hello, world!" on the simulator
5. Stop the app (⏹ or `Cmd + .`)

## Step 6: Project Structure Setup

Now let's organize the project properly:

1. In Xcode's Project Navigator (left sidebar), right-click on "RiffMemo" folder (the blue one)
2. Create the following folder structure (New Group):

```
RiffMemo/
├── App/
├── Core/
├── Features/
│   ├── Recording/
│   ├── Library/
│   ├── Playback/
│   └── Settings/
├── Audio/
│   ├── Recording/
│   ├── Playback/
│   ├── Analysis/
│   └── Waveform/
├── Data/
│   ├── Models/
│   ├── Repositories/
│   └── Storage/
└── Resources/
```

3. Move the existing files:
   - Drag `RiffMemoApp.swift` into **App/** folder
   - Drag `ContentView.swift` into **Features/** folder
   - Drag `Assets.xcassets` into **Resources/** folder
   - Drag `Preview Content` into **Resources/** folder

## Step 7: Configure Capabilities

1. Click on **RiffMemo** project in Project Navigator (the very top blue icon)
2. Select **RiffMemo** target
3. Go to **"Signing & Capabilities"** tab
4. Add the following capabilities (click + button):
   - **iCloud** → Check "CloudKit" and "iCloud Documents"
   - **Background Modes** → Check "Audio, AirPlay, and Picture in Picture"

## Step 8: Privacy Settings

1. Click on **Info** tab
2. Add the following privacy keys (right-click > Add Row):
   - **Privacy - Microphone Usage Description**
     - Value: `"RiffMemo needs microphone access to record your musical ideas"`

## Step 9: Build Settings (Optional but Recommended)

1. Go to **Build Settings** tab
2. Search for "Swift Language Version"
3. Ensure it's set to **Swift 5** or later

## Step 10: Return to Terminal

Once complete, come back to the terminal where Claude Code is running and let me know!

I'll then:
- Verify the project structure
- Create the initial commit
- Set up the foundational code architecture

---

**Time estimate**: 5-10 minutes

**Stuck?** Let me know which step you're on and I can help troubleshoot!
