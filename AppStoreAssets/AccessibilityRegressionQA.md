# Accessibility and UI regression QA

Use an iPhone and iPad simulator plus one physical iPhone before release.

- Run at default text size and the largest Accessibility text size; confirm onboarding, Today, weekly campaign, AI result lists, document import progress, Plans, and Privacy Centre remain scrollable and actionable.
- Enable VoiceOver and verify goal choices, follow-up completion, connected fallback, AI route badges, job-spec import progress, campaign steppers, and destructive confirmations have meaningful labels and traits.
- Enable Increase Contrast, Reduce Motion, and Differentiate Without Color. Confirm status remains understandable without colour alone.
- Test portrait and landscape on iPad, including split view, with no clipped sheet actions.
- Take reference screenshots for Home, Capture a Job, Privacy Centre, Plans, and Saved AI work at iPhone 17 Pro and iPad Pro 11-inch sizes.
- Confirm Cancel stops AI/import work and Back never commits an unsaved follow-up date.

The deterministic unit suite covers priority, campaign counting, storage compatibility, OCR composition, and policy allow-lists. This checklist covers OS accessibility and layout behaviours that require a rendered app.
