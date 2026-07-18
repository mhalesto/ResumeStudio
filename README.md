# ResumeStudio

ResumeStudio is a native SwiftUI app for building polished, export-ready resumes on iPhone and iPad.

![ResumeStudio home screen](docs/screenshots/home.png)

## Features

- Structured editing for personal details, profile, competencies, experience, education, and references
- AI profile writing, competency suggestions, experience-bullet rewrites, job-match review, and reviewed résumé tailoring
- AI-generated cover letters grounded in the existing résumé and pasted job description
- Fifty-five editable, searchable-PDF cover-letter templates, with coordinated designs drawn to match résumé templates
- Multiple named résumé versions with duplication and non-destructive AI tailoring
- Side-by-side version comparison with per-section restore into the active résumé
- A Layout Studio with font, scale, line spacing, margins, paper size, custom headings, section order, and one- or two-page auto-fit
- Market localization for A4/US Letter conventions, localized headings, market photo guidance, and evidence-preserving AI translation
- Account-free iCloud sync for résumé versions, applications, and cover letters
- Application tracker with saved, applied, interview, offer, and rejected stages
- Live ATS coaching with a readiness score, matched and missing job-language evidence, and links back to the exact résumé section
- A Recruiter Scan that replays the eye-tracking research's 7.4-second first pass on the rendered page — an animated gaze spotlight adapted to the template's layout, a dwell-time heatmap, a first-impression score weighted by gaze share with low, medium, and high strictness, and what the recruiter left with versus looked for and never found — computed entirely on device
- Trackable résumé links: send a hosted link instead of an attachment and know when it is opened — per-viewer opens, honest visible-tab reading time, PDF-save flags, privacy-safe daily trends with 7/30/90/all ranges and bar/line/area views, link filters, engagement insights, refresh-driven alerts, a Today-queue follow-up nudge, and one-tap revoke; the viewer page states plainly that opens are visible to the sender, and viewers are never identified
- A role-, seniority-, market-, portrait-, page-, plan-, and ATS-aware Template Finder with favorites, recent styles, and three-way comparison
- Per-application packets that keep the selected résumé, cover letter, application email, follow-up email, notes, and interview checklist together
- Outcome analytics for application-to-interview and interview-to-offer conversion, response time, source performance, and résumé-version performance
- A private Outcome Learning Loop with one-minute stage debriefs, exact résumé/packet attribution, a ranked next recommendation, free on-device drafting, optional connected drafting for paid plans, and review-before-apply improvement versions
- A complete interview workspace with a graphical calendar, upcoming and past interviews, outcomes, reflections, and local day-before reminders
- AI interview plans and eight-question résumé-based quizzes, unlocked at 90% résumé completion
- AI marking with saved totals, percentages, strengths, knowledge gaps, per-question feedback, focus plans, and attempt history
- A floating animated Career Coach grounded in the saved résumé, applications, interview reflections,
  assessment history, and cover-letter target, with a strict work and job-search scope
- On-device PDF, scanned-PDF, image, DOCX, text, and LinkedIn data-export import, including private Vision OCR
- Goal-first onboarding, a real weekly campaign, due relationship follow-ups, and a ranked Today queue
- Projects, certifications, languages, awards, volunteering, publications, and custom sections
- Automatic local draft persistence
- Reordering and deletion of repeatable sections
- One hundred and thirty-one distinct résumé PDF templates, thirty of them photo-led
- Fifty-one structural templates that rearrange the page rather than the letterhead: sidebar columns for contact, skills and education; a dated timeline rail; dates hung in the margin; card-per-entry; two-column splits; a ticked skills matrix; and a skills-first order
- Contact icons, skill pills and a skills matrix drawn as real text, so a two-column page stays searchable and selectable
- An optional profile photo on every template: the photo-led styles build their header around it, the rest close the space up without one
- An ATS check that warns when a template puts content in a second column, because some parsers read columns out of order
- Fourteen accurately previewed accent colours: four free originals and ten premium Signature and Atelier tones
- Calendar deadline/interview export, Mail handoff, App Shortcuts, a Career Momentum widget, and explicit-action Safari application autofill backed by the private app group
- Data-driven, automatically paginated PDF generation
- Live PDFKit preview
- Searchable PDF and editable DOCX export, Files export, and iOS share-sheet support
- Built-in fictional example and blank-resume starting points
- Versioned sample-data migration so legacy development data is not retained

## Architecture

- `Models/ResumeDocument.swift`: platform-neutral, Codable resume data
- `Models/CoverLetterDocument.swift`: locally persisted cover-letter content and its styles
- `Models/TemplatePlan.swift`: what a template does with the *page* — the second column, the timeline rail, the margin dates — as opposed to what it does with the letterhead
- `Services/ResumeAIService.swift`: plan-aware routing between Apple Foundation Models and redacted Firebase AI requests
- `Services/CoverLetterPDFRenderer.swift`: searchable, automatically paginated letter PDFs
- `Services/ResumePDFRenderer.swift`: reusable PDF layout and pagination engine
- `Services/ResumeStore.swift`: versioned local résumé-library persistence
- `Services/ApplicationStore.swift`: local application-tracker persistence
- `Services/ResumeAnalysisServices.swift`: on-device job-advert and ATS checks
- `Services/RecruiterScanService.swift`: the recruiter first-pass simulation — fixation audit and template-aware gaze path
- `Services/SmartLinkService.swift` and `Services/SmartLinkStore.swift`: hosted trackable-link publishing, activity polling, and view alerts
- `Services/ProductivityServices.swift`: template recommendations, packet export, analytics, auto-fit, and market localization
- `Services/PlatformIntegrationService.swift`: Calendar, Mail, widget, Shortcut, and Safari-profile bridges
- `Services/ResumeDocumentInterchange.swift`: DOCX export and local document import
- `Services/ICloudSyncService.swift`: private iCloud Documents workspace sync
- `Views/`: SwiftUI editor and PDF preview flows
- `Support/`: file export and share-sheet adapters

The renderer is intentionally separated from the editor so additional templates can be added without changing how resume data is stored.

## AI architecture

The OpenAI API key is never included in the iOS app. Lightweight extraction, rewriting, summarisation and classification can use Apple's Foundation Models framework on supported Apple Intelligence devices. Free routes these supported tasks on device first and transparently falls back to the metered server path when necessary. Go and Pro route to the connected quality model first, using on-device intelligence mainly as an offline or temporary-service fallback. Complex tailoring, interview plans, translation and Career Coach work always use the structured server path.

The connected path calls a Firebase Cloud Function in the registered `resumestudio-4addf` project. That function:

- verifies Firebase App Check in production;
- rate-limits individual installations;
- strips the client down to a fixed set of supported actions;
- calls the OpenAI Responses API with `store: false` and strict JSON schemas;
- returns suggestions for review instead of silently editing a draft.

The client sends a redacted resume snapshot. Names, phone numbers, email addresses, references, and profile photos are not included in connected AI resume-writing requests. Users can disable on-device intelligence, pause AI entirely, and opt out of anonymous aggregate product counters in Privacy Centre. Metrics never contain content, identity, URLs, or a persistent device identifier.

## Plans and in-app purchases

The résumé builder remains useful without payment: manual editing, ATS checks, application tracking, iCloud sync, privacy controls, unlimited on-device import previews, and unwatermarked PDF, DOCX, and text export are free. AI-assisted résumé import has a separate daily allowance and never spends monthly AI credits.

- **Free**: three saved résumé versions, five AI-assisted imports per day, 34 résumé templates, 16 cover-letter templates, one active trackable résumé link, 10 introductory AI credits, then five credits per month.
- **Go — R49.99/month**: all templates, unlimited versions, 20 AI-assisted imports per day, 35 AI credits per month, one active hosted Review Room, and five active trackable links.
- **Pro — R129.99/month**: everything in Go, 30 AI-assisted imports per day, 150 AI credits per month, up to ten active hosted Review Rooms, and 25 active trackable links.
- **Design Pack Forever — R299.99 once-off**: all current and future templates plus unlimited local versions. AI and hosted-service allowances remain on the user's active Free, Go, or Pro plan.

Verified members can share a referral link. A new member who claims it during their first 30 days receives 10 bonus AI credits, while the inviter receives 5. Rewards are enforced by Firebase, limited to three successful referrals per UTC day and 20 in a rolling 90-day window, and exclude duplicate and self-referrals.

AI actions use weighted credits: résumé import uses its separate daily allowance; focused writing and Career Coach responses cost one; job analysis, cover letters, voice feedback and career-toolkit drafts cost three; tailoring, interview packs, and evidence-preserving translation cost five. The Firebase backend verifies StoreKit's signed transaction JWS and performs the relevant daily-import or credit reservation in Firestore before calling the model. Failed upstream requests are refunded automatically.

The local Xcode catalog is `ResumeStudio/Configuration.storekit` and is selected by the shared Run scheme. The production products must use these exact identifiers:

```text
com.halalisanimbanjwa.ResumeStudio.go.monthly
com.halalisanimbanjwa.ResumeStudio.pro.monthly
com.halalisanimbanjwa.ResumeStudio.designpack.forever
```

In App Store Connect:

1. Accept the Paid Apps Agreement and finish banking/tax setup.
2. Create one auto-renewable subscription group named `ResumeStudio Plans`.
3. Add Pro Monthly at service level 1 and Go Monthly at service level 2, using the identifiers and South African prices above.
4. Add Design Pack Forever as a non-consumable in-app purchase.
5. Add the required localization, review screenshots, and subscription terms, then submit the products with the app version.
6. Add the app's numeric Apple ID to the deployed Functions environment as `APP_APPLE_ID`. Production subscription proofs intentionally fall back to Free until this value is configured.

For local purchase testing, run the shared scheme and use Xcode's **Debug > StoreKit > Manage Transactions** window to renew, expire, refund, or revoke the test products.

### Run the AI proxy locally

1. Install the function dependencies:

   ```sh
   cd functions
   npm install
   ```

2. Create `functions/.secret.local` (it is ignored by Git) containing:

   ```text
   OPENAI_API_KEY=your_key_here
   ```

3. Start the emulators from the repository root (Firestore and Storage are
   required by the Review Room and trackable-link routes; they run on ports
   8480 and 9399):

   ```sh
   firebase emulators:start
   ```

4. In the Xcode scheme, add this launch environment variable:

   ```text
   AI_SERVICE_BASE_URL=http://127.0.0.1:5001/resumestudio-4addf/europe-west1/api
   ```

The emulator intentionally bypasses App Check. Production never does. When the
`AI_SERVICE_BASE_URL` override is present the trackable-link client also skips
minting an App Check token, so simulators whose debug token is not registered
in the Firebase console can still exercise the link routes locally. To point a
booted simulator at the emulator without editing the scheme:

```sh
SIMCTL_CHILD_AI_SERVICE_BASE_URL="http://127.0.0.1:5001/resumestudio-4addf/europe-west1/api" \
  xcrun simctl launch <device> com.halalisanimbanjwa.ResumeStudio
```

### Deploy the AI proxy

The Firebase project uses the Blaze plan and the function is deployed in `europe-west1`. To rotate the secret and redeploy:

```sh
firebase functions:secrets:set OPENAI_API_KEY
firebase deploy --only functions:api
```

Firebase App Check is registered with App Attest for the production iOS app. Debug builds use Firebase's App Check debug provider; each new simulator or development device needs its printed debug token registered in Firebase Console before it can call the deployed function.

## Run

1. Open `ResumeStudio.xcodeproj` in Xcode 26 or newer.
2. Select the `ResumeStudio` scheme.
3. Run on an iPhone or iPad simulator running iOS 17 or newer.

## Tests

```sh
xcodebuild -project ResumeStudio.xcodeproj \
  -scheme ResumeStudio \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  test
```
