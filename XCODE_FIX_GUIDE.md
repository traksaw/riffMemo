# Xcode Project Fix Guide

Follow these steps carefully to add all the new files to your Xcode project.

## Step 1: Open Project in Xcode

1. Open `RiffMemo.xcodeproj` in Xcode
2. You should see the Project Navigator on the left

## Step 2: Clean Up Missing Files

You'll likely see some files in **red** (Xcode can't find them). We moved these files.

1. Look for these **red files** in the Project Navigator:
   - `RiffMemoApp.swift`
   - `ContentView.swift`
   - `Persistence.swift`
   - `Assets.xcassets`
   - `RiffMemo.xcdatamodeld`

2. For each red file:
   - Right-click on it
   - Choose **"Delete"**
   - Select **"Remove Reference"** (NOT "Move to Trash")

## Step 3: Add Folders with New Structure

Now we'll add all the files back in their new organized structure.

### 3a. Add the App Folder

1. Right-click on **"RiffMemo"** folder (the yellow one at the top)
2. Choose **"Add Files to 'RiffMemo'..."**
3. Navigate to: `RiffMemo/RiffMemo/App/`
4. Select the **App** folder
5. **Important checkboxes:**
   - ✅ **"Create groups"** (should be selected)
   - ✅ **"Add to targets: RiffMemo"** (check this!)
   - ❌ **"Copy items if needed"** (uncheck - files are already there)
6. Click **"Add"**

### 3b. Add the Core Folder

1. Right-click on **"RiffMemo"** folder again
2. Choose **"Add Files to 'RiffMemo'..."**
3. Navigate to: `RiffMemo/RiffMemo/Core/`
4. Select the **Core** folder
5. Same checkboxes as above:
   - ✅ "Create groups"
   - ✅ "Add to targets: RiffMemo"
   - ❌ "Copy items if needed"
6. Click **"Add"**

### 3c. Add the Features Folder

1. Right-click on **"RiffMemo"** folder
2. Choose **"Add Files to 'RiffMemo'..."**
3. Navigate to: `RiffMemo/RiffMemo/Features/`
4. Select the **Features** folder
5. Same checkboxes:
   - ✅ "Create groups"
   - ✅ "Add to targets: RiffMemo"
6. Click **"Add"**

### 3d. Add the Audio Folder

1. Right-click on **"RiffMemo"** folder
2. Choose **"Add Files to 'RiffMemo'..."**
3. Navigate to: `RiffMemo/RiffMemo/Audio/`
4. Select the **Audio** folder
5. Same checkboxes:
   - ✅ "Create groups"
   - ✅ "Add to targets: RiffMemo"
6. Click **"Add"**

### 3e. Add the Data Folder

1. Right-click on **"RiffMemo"** folder
2. Choose **"Add Files to 'RiffMemo'..."**
3. Navigate to: `RiffMemo/RiffMemo/Data/`
4. Select the **Data** folder
5. Same checkboxes:
   - ✅ "Create groups"
   - ✅ "Add to targets: RiffMemo"
6. Click **"Add"**

## Step 4: Verify Structure

Your Project Navigator should now look like this:

```
RiffMemo
├── App/
│   ├── AppCoordinator.swift
│   ├── RiffMemoApp.swift
│   └── Assets.xcassets
├── Core/
│   ├── Extensions/
│   │   ├── Date+Extensions.swift
│   │   └── TimeInterval+Extensions.swift
│   └── Utilities/
│       ├── Coordinator.swift
│       └── Logger.swift
├── Features/
│   ├── Recording/
│   │   ├── RecordingCoordinator.swift
│   │   └── RecordingViewModel.swift
│   ├── Library/
│   │   ├── LibraryCoordinator.swift
│   │   └── LibraryViewModel.swift
│   ├── Playback/ (empty)
│   ├── Settings/ (empty)
│   └── ContentView.swift
├── Audio/
│   ├── Recording/
│   │   └── AudioRecordingManager.swift
│   ├── Playback/ (empty)
│   ├── Analysis/ (empty)
│   └── Waveform/ (empty)
├── Data/
│   ├── Models/
│   │   ├── Recording.swift
│   │   └── RiffMemo.xcdatamodeld
│   ├── Repositories/
│   │   └── RecordingRepository.swift
│   └── Storage/
│       └── Persistence.swift
├── RiffMemoTests/
└── RiffMemoUITests/
```

## Step 5: Try Building

1. Select **iPhone 15 Pro** simulator (or any recent simulator)
2. Press **Cmd + B** to build
3. You might get some **compilation errors** - this is normal! The files reference each other but some pieces are missing.

## Common Build Errors (Expected)

You'll likely see errors like:
- `Cannot find type 'RecordingRepository'` - This is OK, we'll fix it
- `Cannot find 'Logger'` - This is OK
- Missing imports - We'll add these next

## Step 6: Return to Claude Code

Once you've added all the folders to Xcode, come back to this terminal and let me know!

I'll then:
- Help fix any compilation errors
- Add missing imports
- Create a simple test build to verify everything works

---

**Time estimate**: 5-10 minutes

**Stuck?** Take a screenshot and show me where you're stuck!
