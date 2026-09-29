# Airlog on iPhone: plan

**Status (2026-09-30):** not started. The app is Android-only: there is no `ios/` folder, and three parts are native Kotlin (`HealthConnectBridge.kt`, `AirlogWidgetProvider.kt`, `MainActivity.kt`). The engine, coach, UI and database are Flutter/Dart and run on iOS unchanged.

**When:** after Android v1 is in daily use (PRODUCT_PLAN §5, Phase 2 exit). Decision row in PRODUCT_PLAN §7.

**Scope:** parity with Android, plus three iOS-only surfaces:
- a home-screen and lock-screen widget;
- a Live Activity (lock screen + Dynamic Island) for live workouts;
- a few Siri shortcuts.

**Estimate:** about 2.5–3.5 weeks with cloud builds, or about 2 weeks with a Mac. The main cost is iteration speed without a Mac, not the amount of code.

---

## 1. How Flutter and React Native developers ship iOS

| | Flutter | React Native |
|---|---|---|
| Most common setup | A Mac (a Mac mini is the usual cheap option) | A Mac, or Expo without one |
| Without a Mac: build | Cloud macOS CI: Codemagic, GitHub Actions macOS runners, Bitrise. Builds, signs and uploads to TestFlight | **Expo EAS Build** (`eas build -p ios`) from Windows. Expo handles signing; `eas submit` uploads to TestFlight |
| Without a Mac: test | TestFlight on a real iPhone. No iOS Simulator; no hot reload or debugger on the iPhone (Flutter needs Xcode for that) | Build a dev client once in the cloud. After that, JS changes hot-reload onto the iPhone from Windows |
| Native iOS parts (widgets, Live Activities, Siri) | Swift targets. You add them in Xcode, or script it on the cloud Mac | Also Swift. Expo config plugins (e.g. `expo-apple-targets`) generate the targets from config, so Xcode isn't needed |
| Occasional Xcode GUI work | Rent a remote Mac by the hour or day (e.g. MacinCloud, AWS EC2 Mac) | Same, less often |

**Takeaway:** React Native with Expo has the smoother no-Mac workflow. Flutter without a Mac works, but every iOS change is a full cloud build and test round on the phone. A rewrite to React Native would cost far more than the port, so Airlog stays Flutter.

**Chosen path:** Flutter, then Codemagic (or GitHub Actions macOS), then TestFlight, then your iPhone. If iteration is too slow by the end of Phase 1, get a used Mac mini.

---

## 2. What you provide

- An iPhone (iOS 17+ recommended; Live Activities need 16.1+, Dynamic Island needs iPhone 14 Pro or later).
- **Apple Developer Program**, $99/year. Needed for TestFlight, the App Store and a proper install on your phone.
- An App Store Connect API key, stored as a secret in the CI service (never in the repo or in chat).
- A decision on which watch or ring you'll wear with the iPhone. It changes what Apple Health contains (§4).

---

## 3. Phases

| Phase | Work | Estimate | Exit criteria |
|---|---|---|---|
| **0: Pipeline** | `flutter create --platforms=ios .`; bundle id; CI workflow file in the repo; signing; TestFlight upload | 1–2 days | The current app opens on your iPhone in sample-data mode |
| **1: Data** | Apple Health (HealthKit) source; Google Health API on iOS; permissions; background sync; per-platform copy (§4) | 4–6 days | Today's plan is built from your real data on the iPhone for 7 days in a row |
| **2: Widgets** | WidgetKit extension (SwiftUI): small and medium home-screen widgets plus lock-screen widgets; data shared through an App Group (`home_widget` supports iOS); dot-matrix numerals redrawn in SwiftUI | 2–3 days | Widget matches Today after sync and after midnight (Android bug QA-08 not repeated) |
| **3: Live Activity** | ActivityKit: live workout with HR, zone and strain so far, on the lock screen and Dynamic Island (compact and expanded) | 2–3 days | A 30-minute workout updates the lock screen throughout and ends cleanly |
| **4: Siri** | App Intents + App Shortcuts: "How's my recovery?", "What should I do today?", "Start a workout". Answered on the phone from the App Group snapshot; no network, no LLM | 1–2 days | All three work from Siri, Spotlight and the Shortcuts app |
| **5: QA + release** | Privacy strings, App Store privacy label, HealthKit review rules, TestFlight beta review | 2–4 days | Accepted to external TestFlight |

---

## 4. Data on iOS: what changes

- **Apple Health replaces Health Connect.** The `health` plugin (already a dependency) reads HealthKit. A small Swift bridge covers what it lacks, as the Kotlin bridge does on Android. The origin is the HealthKit source's bundle id, so the "one persisted origin per metric" rule carries over.
- **HRV is SDNN, not RMSSD.** Apple Health stores HRV as SDNN. It becomes its own definition (`hk_sleep_sdnn@origin`) with its own baseline, labelled "HRV (SDNN)". Recovery scores HRV against your own baseline, so it still works, but the values can't be compared with Fitbit's RMSSD. Apple Watch takes only a few HRV samples a night; the minimum per night is set from real data in Phase 1, and below it Recovery shows "without HRV".
- **Other metrics** exist in HealthKit: resting HR, respiratory rate, wrist temperature (Apple Watch Series 8 and later), SpO₂, sleep stages (iOS 16+), workouts and steps.
- **Fitbit Air on iPhone:** as far as we know, the Fitbit app doesn't write to Apple Health. The band's data comes through the Google Health API, which the app already supports (Enhanced mode, `flutter_appauth` on iOS). The 100-user cap before OAuth verification still applies (PRODUCT_PLAN §6).
- **Permissions:** HealthKit never tells an app whether read access was denied. The Android "denied twice" path doesn't apply. Onboarding says: "If nothing shows up, check Health → Sharing → Airlog."
- **Background sync:** HealthKit background delivery (observer queries) replaces the periodic `workmanager` job. iOS background refresh is opportunistic, so the app also syncs on open.
- **Coach:** unchanged. Claude and Gemini are plain HTTPS; keys go to the Keychain through `flutter_secure_storage`.

---

## 5. Limits we accept

- **No server, so no push updates.** The Live Activity updates only while the app is running (a live workout, kept alive by Bluetooth background mode). A "recovery is ready" morning Live Activity isn't possible without a push server, which the plan excludes.
- **Live Activity time limit:** iOS ends a Live Activity after about 8 hours. That's fine for a workout.
- **Font licence:** the Subway Ticker Grid font is personal-use only. Bundling it in the widget extension has the same licence issue as the app: buy the licence before publishing.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| Swift errors only show up in cloud builds, so each fix costs a build round | Keep Swift small (widget, Live Activity, intents, HealthKit bridge); all logic stays in Dart. Get a Mac if Phase 1 drags |
| Apple Watch HRV too sparse at night | Per-night sample gate; fall back to "without HRV" (existing floor) |
| Fitbit Air data only through the Google Health API on iPhone | Same path and cap as Android Enhanced mode |
| App Review rejects health-data use | Declare only the types we read; no ads, no server; privacy policy linked in-app |

---

## 7. Open questions

- Which wearable goes with the iPhone (Apple Watch, Fitbit Air, Oura, other)?
- Cloud CI (Codemagic or GitHub Actions) or a Mac?
