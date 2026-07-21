# ResumeStudio Product and Release Roadmap

This roadmap tracks the release-hardening and product-workflow programme agreed for the 1.0 launch. Work is ordered by user risk and dependency, not visual prominence.

## Phase 1 — Release compliance and data control

- [x] Add password-reset support for email accounts.
- [x] Add in-app account deletion with reauthentication guidance.
- [x] Delete Firebase Auth, AI artifacts, referral data, credit records, and owned Review Rooms/PDFs.
- [x] Let the user separately erase local workspace data and the iCloud workspace archive.
- [x] Publish public Support and Privacy pages and link them from Settings and App Store metadata.
- [x] Add and validate the app privacy manifest.
- [x] Fix catalogue counts in tests and documentation.

Acceptance:

- A signed-in user can initiate permanent deletion from Account Settings.
- The UI clearly distinguishes account/server deletion, on-device deletion, and iCloud deletion.
- Deleted Review Room links stop working immediately and their PDF objects are removed.
- Support and Privacy URLs return successful public responses.
- The catalogue test and full iOS suite pass.

## Phase 2 — Conflict-safe sync

- [x] Version the cloud archive with a workspace revision and device identifier.
- [x] Create automatic local snapshots before every remote import or overwrite.
- [x] Detect divergent local/remote changes instead of silently choosing the newest archive.
- [x] Add a conflict-resolution screen with local, cloud, and merge choices.
- [x] Keep backward compatibility with the original unversioned `workspace.json` archive.

Acceptance:

- Concurrent edits from different devices produce a visible conflict.
- No conflict choice is destructive until a recovery snapshot exists.
- Existing users can read their legacy cloud archive.

## Phase 3 — Today and application workflow

- [x] Replace the static top of Home with a ranked Today action queue.
- [x] Include follow-ups, incomplete application packets, imminent interviews, ATS actions, and expiring Review Rooms.
- [x] Promote Applications to the persistent app navigation; keep templates available from Documents and editors.
- [x] Add a resumable Application Pack workflow:
  capture job → choose résumé → match analysis → reviewed tailoring → cover letter/email → deadline → interview plan.
- [x] Show the maximum AI-credit cost before starting and checkpoint every completed step.
- [x] Close the application loop with private outcome debriefs, exact résumé-version attribution, local recommendations, and reviewable improvement versions.

Acceptance:

- Today always explains why an action is recommended and opens the exact destination.
- Application Pack can be left and resumed without losing completed steps.
- AI output is never silently applied to a résumé.
- Outcome learning preserves the historical résumé used and creates a separate version for every accepted improvement.

## Phase 4 — iPad professional workspace

- [x] Add a split editor/live-preview workspace on regular-width devices.
- [x] Add application list/detail split navigation.
- [x] Support dropped PDF, DOCX, text, and LinkedIn export files.
- [x] Add keyboard commands for common document and navigation actions.
- [x] Support multiple résumé windows.

Acceptance:

- iPad no longer renders the primary workspace as a centred phone column.
- Editing updates the adjacent PDF preview.
- A supported document dropped into the app enters the existing reviewable import flow.

## Phase 5 — Interview practice and Review Rooms

- [x] Calculate pace, filler-word count, pause estimate, and answer length on device.
- [x] Add timed panel mode and adaptive follow-up prompts.
- [x] Persist delivery metrics and show progress across attempts.
- [x] Add Review Room revoke and delete endpoints.
- [x] Add immediate remote disabled state and reviewer-comment notifications.

Acceptance:

- Delivery metrics work without uploading raw audio.
- Adaptive prompts remain grounded in the selected role and prior answer.
- Revoked Review Rooms return an unavailable response immediately.
- The owner can distinguish open, expired, revoked, and deleted rooms.

## Phase 6 — Secure offline-first operation

- [x] Cache the last locally verified StoreKit entitlement, product, verification date, and expiry.
- [x] Continue paid template/version access while the signed entitlement is still within its verified period.
- [x] Never extend an expired subscription merely because the device is offline.
- [x] Let local editing, preview, export, applications, and interview history work without a network.
- [x] Mark AI and Review Room hosted actions as network-required while local features remain usable.
- [x] Make Firebase, App Check, StoreKit, and iCloud startup failures non-blocking.
- [x] Add offline-entitlement and conflict regression coverage; enforce a bounded splash handoff.

Acceptance:

- A returning paid user can launch offline and use everything already paid for until the verified expiry.
- The splash screen always hands off to the local app shell on a bounded timer.
- Offline state cannot manufacture, extend, or upgrade an entitlement.
- Reconnection refreshes entitlement and cloud state without discarding offline edits.

## Phase 7 — Accessibility floor

- [x] Give every icon-only control an accessibility label naming its action.
- [x] Announce scores and progress as a labelled value rather than a bare number:
  readiness, first-impression, campaign progress, and the delivery-score trend.
- [x] Add Dynamic Type-aware `scaledFont`/`displayFont` modifiers and move screen
  titles and pinned copy onto them; `Theme.display(_:)` never scaled, despite
  its documentation saying it did.
- [x] Hide decorative artwork from VoiceOver and honour Reduce Motion on the
  career-hub orbit graphic.
- [x] Audit the two failures in `Tools/AuditAccessibility.py`, with an opt-out
  marker that requires a written reason.
- [x] Teach `Tools/AuditLocalization.py` about accessibility strings, which
  localize like visible copy and were previously unaudited.
- [ ] Translate the accessibility strings the localization audit now reports.

Acceptance:

- No control announces itself as a raw SF Symbol name.
- A score is never spoken as an integer with no unit or subject.
- `python3 Tools/AuditAccessibility.py` exits zero.

## Phase 8 — Opportunity integrity

- [x] Preserve schema.org JobPosting data from Safari sharing and direct public-page capture.
- [x] Add an explainable on-device pre-apply report for freshness, employer verification, listing quality, and applicant-safety traps.
- [x] Let users include an optional recruiter message while keeping it in the local application archive.
- [x] Record public-page status and repost/change history without treating blocked or ambiguous pages as proof that a role is closed.
- [x] Refresh a bounded due set when the app returns online and support manual refresh from application details.
- [x] Add unresolved signals to Today and blend them with résumé fit, deadlines, and warm contacts in Where to Apply.

Acceptance:

- The feature says strong signals, verify first, or high-risk signals; it never claims to prove that a job is real or fake.
- Payment, money-transfer, cheque/equipment, and premature identity-data language cannot receive a strong verdict.
- A removed or expired listing is visible before tailoring, and a redirected or blocked page remains explicitly inconclusive or unreachable.
- Résumé and personal-profile data are never included in public-page checks.
- Existing saved application archives decode without migration.

## Quality gates

- `npm run check` passes for Firebase Functions.
- `python3 Tools/AuditAccessibility.py` reports no unnamed control or pinned copy.
- Backend route tests cover account deletion and Review Room lifecycle.
- The iOS test suite passes on the supported simulator runtime.
- App privacy report and archive validation complete without unresolved issues.
- Live Support, Privacy, backend health, deletion, and Review Room probes pass after deployment.
