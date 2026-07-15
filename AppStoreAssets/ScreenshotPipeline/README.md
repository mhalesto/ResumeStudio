# App Store screenshot pipeline

Regenerates the marketing screenshots in `AppStoreAssets/screenshots/`
(1284 × 2778 PNG, accepted for the iPhone 6.5"/6.7" slot, no alpha channel).

The pipeline has two stages: capture real app screens in the simulator, then
composite them onto branded canvases with headlines and a device frame.

## 1. Capture raw screens

`MarketingScreenshotCapture.swift` is an XCTest that runs inside the app on a
simulator. It seeds every store with a realistic fictional job search (Avery
Sample's pipeline, interviews, voice practice, coach chat), hosts each screen
in a `UIWindow`, and writes full-resolution PNGs.

1. Copy `MarketingScreenshotCapture.swift` into `ResumeStudioTests/`
   (the folder is file-synchronized, so it joins the target automatically).
2. Update `outputDirectory` at the top of the file to a writable folder.
3. Run it on a 6.9" simulator (raw captures are 1320 × 2868 @3x):

   ```sh
   xcodebuild test -project ResumeStudio.xcodeproj -scheme ResumeStudio \
     -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
     -only-testing:ResumeStudioTests/MarketingScreenshotCapture
   ```

4. Delete the file from `ResumeStudioTests/` again — it is tooling,
   not part of the test suite.

Seeding notes: applications are added without `deadline` values and interviews
with `reminderEnabled: false`, otherwise `CareerReminderService` triggers the
notification-permission dialog mid-capture.

## 2. Compose the marketing shots

`compose_screenshots.swift` is a macOS script (AppKit/CoreText, no
dependencies). It draws the brand background (Theme paper/ink + accent glows),
the New York serif headline, a device frame with Dynamic Island, status bar
and side buttons, then writes flattened RGB PNGs.

1. Update `scratch`/`rawDir` at the top to the folder holding the raw captures.
2. Run:

   ```sh
   swift compose_screenshots.swift [output-dir]
   ```

   Output defaults to `AppStoreAssets/screenshots/`.

Captions live in the `specs` array. Keep claims aligned with
`AppStoreAssets/Metadata/en-US.md` (no invented scores, unwatermarked free
exports, privacy positioning).

Raw captures `11-interviews` and `12-privacy` are spares — captured but not
part of the published ten.
