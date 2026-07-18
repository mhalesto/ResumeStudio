# Hybrid AI device QA

Run this matrix before each App Store release. The simulator validates UI and routing, but it does not prove Apple Intelligence model availability or output quality.

## Required hardware

- An Apple Intelligence-capable iPhone with the current production iOS release, Apple Intelligence enabled, and a supported device language.
- A non-eligible iPhone to verify the unavailable explanation and the connected fallback choice.
- Airplane mode and a normal network connection.

## Free plan

1. Keep **Use on-device intelligence** on and **Allow connected fallback on Free** off.
2. Run Improve bullet, Write profile, Suggest competencies, and Capture job.
3. Confirm successful results show **Processed on this iPhone**, no AI credit is spent, and the result appears with the same route in Saved AI work and Privacy Centre.
4. Use an oversized or deliberately weak input. Confirm the app explains that connected fallback needs approval and does not spend a credit.
5. Enable connected fallback, repeat the failed action, and confirm a connected result shows **Connected quality AI** and uses only the advertised credit cost.
6. In airplane mode, confirm eligible lightweight actions still work on-device and complex actions show the offline state.

## Go and Pro

1. Confirm the four lightweight actions use **Connected quality AI** under normal network conditions.
2. Interrupt the network during a request. If the failure is temporary and the device model is ready, confirm the private fallback shows **Processed on this iPhone** and no duplicate result is saved.
3. Confirm Tailor résumé, Interview plan, Career Coach, and other complex structured workflows never switch to the lightweight device model.

## Quality and privacy checks

- Bullet/profile output contains exactly three distinct, substantive alternatives.
- Competency suggestions contain at least six distinct skills and do not repeat existing skills.
- Job capture includes a role/company or enough source-backed description to be reviewable.
- Cancellation closes the workflow without a cloud retry, credit spend, artifact, or processing-history entry.
- Contact details, references, source links, and attached files are absent from connected request diagnostics.

Record the device model, iOS version, language, AI route shown, and pass/fail result with the release checklist. The currently attached iPhone 12 Pro Max can verify unavailable-device behavior but cannot validate Apple Intelligence output quality.
