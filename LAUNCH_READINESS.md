# Android launch readiness

Updated: 2026-09-30. Scope: Android only. The owner requested commit and push, and explicitly excluded test files. No store deployment or production signing is authorized.

## Release decision

**Implementation delivered for review, not approved for public launch.** The owner stopped further QA and requested the implementation be committed and pushed. Final exhaustive validation is incomplete. A source fix is not device acceptance, and deterministic tests do not establish wearable compatibility or model accuracy.

The evidence register is `APP_REVIEW.md`. Its original findings remain historical evidence; this file tracks remediation and current release gates.

## Implementation workstreams

| Area | Owner | State | Required evidence |
|---|---|---|---|
| Durable sync, recompute, concurrent writes, source corrections, deletion | Data agent | Implemented | Focused database/adapter tests passed locally; physical provider acceptance remains |
| Scoring, unknown inputs, confidence, source comparability, live anchors | Metrics agent | Implemented | Domain/score contracts passed locally; field validity unverified |
| Cloud consent, provenance, verifier, history isolation, deletion outcomes | Coach agent | Implemented | Deterministic privacy/retrieval tests passed; live model and secure-storage acceptance remain |
| Lifecycle clock, shared controls, accessibility, motion and onboarding | Main agent | Implemented | Five main screens at 320px/2x text and both motion settings passed; bounded screenshot review |
| Reproducible setup, font distribution and signing | Main agent | Debug APK built | Production credentials absent; release signing guard rejected unsigned release |
| Dynamic cards and Android launcher widget | Metrics agent | Implemented | Source coverage in app/docs/DYNAMIC_UI.md; native widget field acceptance remains |

## Approach and boundaries

- Preserve the incumbent dark visual identity and short motion language. Correct state handling, readability and accessibility before decorative changes.
- Keep the existing architecture. Add explicit consistency and authorization contracts where the review found incompatible assumptions.
- Preserve unknown or insufficient inputs as unavailable, not unfavorable-looking fabricated measurements.
- Conservative cloud sharing is acceptable when reliable derived-data lineage is absent, provided users are clearly told the limitation and retain on-device functionality.
- Do not fabricate personal health data, test provider credentials, signing keys, privacy-policy URLs or release approvals.

## Additional findings during implementation

- U01: Retained clock-dependent screens need minute-boundary and resume invalidation, not only an injected clock function. Covers D18.
- U02: Interrupted hold-to-delete resumes from remaining progress. Every new press must require a fresh uninterrupted two-second hold; disabling the control must cancel an active hold.
- U03: Custom press targets lack keyboard activation and an explicit disabled button state. Shared controls need accessible focus and activation semantics.
- B01: A gitignored personal-use-only font prevents reproducible builds and distribution. Bundle an open-licensed dot-matrix replacement and its license; review the resulting glyph/layout differences rather than silently accepting old goldens.
- B02: Machine-specific D-drive paths and debug-signed release builds are not a release setup. Use explicit environment configuration and fail closed for production signing.

## Validation log

- Initial environment: no Flutter, Dart, Java or ADB on PATH; no Android SDK found in conventional user location.
- Official Flutter tag `3.47.5` verified at `6a19cca56475dbfba1478ee68d7bd0c2ef891da1`; task-local Flutter, JDK17, Android SDK and Android15 emulator installed.
- Android debug APK built successfully, including the final Coach, native-widget and onboarding changes. APK is local and excluded from Git.
- Domain/score contracts: 284 passed before final UI-only additions. Database/metric subset: 269 passed. Integrated Coach/privacy/dynamic contracts: 227 passed. Large-text plus onboarding route checks: 23 passed. These overlapping runs must not be summed.
- Latest visual-baseline run: 135 passed. Original Figma artwork remains unchanged; candidate release baselines and updated screenshots remain local per the owner's exclusion.
- Final all-tests run was stopped at the owner's request, not reported as a full-suite pass. Analyzer's final two style/type diagnostics were corrected, but a clean rerun was not completed before the stop request.
- Emulator: APK installed/launched; onboarding privacy disclosure and underage validation exercised. Found and fixed PopScope timing that prevented completed onboarding from leaving; added route-completion tests. Full final native journey and launcher pinning were not completed.
- Offline release dry-run rejected packaging without the four signing variables, with the intended signing error.
- Test sources, golden PNGs, audit probe and the new CI workflow are intentionally excluded from this commit. Existing tracked tests/baselines still describe pre-change behavior in places; the local companion updates are required before claiming a green fresh-checkout suite.

## Remediation map

- D01-D06: durable pending recomputation, generation-fenced writes, coherent bundles, full invalidation and foreground revision refresh; background failures no longer silently report success.
- D07-D09: immutable HR epoch anchor/schema4, adapter metadata verification, HRV-shape invalidation and correction/deletion ordering. Pre-upgrade lost identities cannot be reconstructed without authoritative backfill.
- D10-D12: shared effective provenance and HR anchors, missing/invalid inputs remain unavailable, complete-day load and confidence-qualified guidance; algorithm version3.
- D13-D17: send/retry consent checks, conservative historical Google Health source firewall, mode/provider/privacy/memory-scoped history and truthful key-deletion outcomes. Already transmitted requests cannot be recalled.
- D18-D19: minute/resume-driven time state and bounded Google requests.
- Additional UI: keyboard/focus/disabled controls, fresh hold-to-delete, reduced-motion behavior, readable large-text alternatives, higher contrast, bundled OFL Doto font, duplicate Sleep/Strain score removal and Recovery wrapping.
- Additional data: export/probe writes coordinated with wipe, snapshot-consistent launcher payload, sleep rounding/quality/staleness labels and corrected chart markers.
- Coach personalization: bounded current/recent evidence retrieval, confirmed memory provenance/expiry/review flags, correction-aware history isolation and evidence-led answer contract. See app/docs/COACH_MEMORY.md for exact coverage and limitations.

## External release gates

- Android toolchain/device or emulator acceptance, including actual Health Connect permissions, corrections/deletions, background sync and Bluetooth reconnect.
- Provider OAuth configuration and consent-screen review using the release application identity.
- Production signing key supplied securely by the owner, not generated or committed during an audit.
- Real-wearable validation of the supported source/metric matrix and explicit product approval of score/advice wording.
- Store privacy/data-safety declarations, policy URL, target audience and final release asset/content review.
