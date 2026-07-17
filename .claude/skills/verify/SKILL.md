---
name: verify
description: Drive ResumeStudio in the iOS Simulator with real clicks and screenshots to verify a change end-to-end.
---

# Verifying ResumeStudio in the Simulator

## Build, install, launch

```sh
SIM=$(xcrun simctl list devices available | grep "iPhone 17 (" | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot $SIM; open -a Simulator; sleep 14
xcodebuild -project ResumeStudio.xcodeproj -scheme ResumeStudio \
  -destination "platform=iOS Simulator,id=$SIM" build
APP=~/Library/Developer/Xcode/DerivedData/ResumeStudio-*/Build/Products/Debug-iphonesimulator/ResumeStudio.app
xcrun simctl install $SIM $APP
xcrun simctl launch $SIM com.halalisanimbanjwa.ResumeStudio
```

## Screenshots

`xcrun simctl io $SIM screenshot out.png` — 1206×2622 px = 402×874 device points (÷3).

## Real taps via AppleScript

System Events "click at" works (accessibility permission is granted for the
terminal). The Simulator's iOS accessibility tree is NOT visible to System
Events, and hosted-XCTest accessibility activation finds no SwiftUI elements —
coordinate clicks are the only working path.

- Window frame at (101, 62), size 456×972 → device content is 1:1 points at
  offset (+27, +80): **screen = (128 + deviceX, 142 + deviceY)**. If the frame
  differs, recalibrate with two landmarks between a simctl screenshot and a
  `screencapture -R` of the window (the window draws a bezel; content is 1:1).
- **Always focus first** or clicks are swallowed by macOS click-through:

```applescript
tell application "System Events" to tell process "Simulator" to set frontmost to true
delay 0.4
tell application "System Events" to click at {X, Y}
```

## Scrolling and drags

CGEvent scroll-wheel events do NOT scroll SwiftUI Lists in the Simulator —
synthesize a mouse **drag** instead (down → dragged steps → up). Start drags on
the left side of the screen: the floating Career Coach button (bottom-right)
and the ATS checker's TextEditor both eat touches. A Python one-shot works:
Quartz `kCGEventLeftMouseDown/Dragged/Up` with ~24 interpolated steps.

## Driving against the Firebase emulator

`firebase emulators:start` (functions 5001, firestore 8480, storage 9399;
needs `functions/.secret.local` with any OPENAI_API_KEY value). Point the sim
app at it with `SIMCTL_CHILD_AI_SERVICE_BASE_URL="http://127.0.0.1:5001/resumestudio-4addf/europe-west1/api" xcrun simctl launch …`.
The SmartLink client skips App Check when that override is set; other services
still 403 on simulators whose App Check debug token isn't console-registered.
App state can be pre-seeded/inspected in
`$(xcrun simctl get_app_container <dev> com.halalisanimbanjwa.ResumeStudio data)/Library/Application Support/ResumeStudio/`
— reading files the app wrote is often sturdier proof than fighting taps.

## Gotchas

- A fresh simulator shows a **"Sign in to Apple Account"** system dialog over
  the app on each app launch (iCloud sync asks for ubiquity), and they QUEUE —
  several identical prompts can stack, respawning as you cancel. Prevent them
  instead: `xcrun simctl spawn <dev> defaults write
  com.halalisanimbanjwa.ResumeStudio iCloudSyncEnabled -bool false` **before
  the app's first launch**. Cancel sits at device point (127, 379) with the
  keyboard up, (127, 529) without.
- **Window position is not stable** — re-read it before every click batch, and
  `tell application "Simulator" to activate` first (clicks otherwise land in
  whatever app is frontmost, e.g. VS Code). If clicks still don't register
  (field-focus probe fails), screenshot the mac-side region with
  `screencapture -R` to confirm the Simulator actually owns those pixels.
- Test runs on "Clone N of iPhone 17" shut down the booted device afterwards —
  reboot before installing.
- The app persists its draft: after the first "Start with an example", later
  launches land on Home; the preview is behind Home's "Ready to export" row at
  click {328, 646}, and the Preview chip is top-right at {474, 226}.
- Attachments from hosted render tests: `xcrun xcresulttool export attachments
  --path r.xcresult --output-path dir` (manifest.json maps names).
