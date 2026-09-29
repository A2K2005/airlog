# 07: What the Google Health app declares (static APK inspection)

**Source:** `Google Health (Fitbit)`, package `com.fitbit.FitbitMobile`, version `5.08.health-mobile-1104114328`, posted 2026-09-24. It's an APKMirror bundle (arm64-v8a, 480 dpi, Android 11+) that the user supplied.

**Method:**
- read the manifest with `apkanalyzer manifest print`
- dumped the English resource strings with `aapt2 dump strings` from `base.apk` and `split_config.en.apk`

**Not done:**
- The app wasn't installed or run. It needs a Google sign-in and a paired device, so it would show nothing beyond the sign-in screen.
- No code was decompiled, and no code, prompts or assets were copied. This is Google's proprietary app, so the notes below paraphrase it for interoperability and product research.

## 1. Health Connect permissions: resolves part of the Phase 0 question

The manifest declares **77** Health Connect permissions. It declares these **26 WRITE** permissions:

| Written type | Relevance to Airlog |
|---|---|
| HEART_RATE, HEART_RATE_VARIABILITY, RESTING_HEART_RATE, RESPIRATORY_RATE, SKIN_TEMPERATURE, SLEEP | All our Recovery inputs **are declared as writable** |
| VO2_MAX | Cardio fitness and Pulse Age |
| **OXYGEN_SATURATION** | **New: SpO₂ may be available in Health Connect**, not only via the Google Health API (PRODUCT_PLAN §2.1 assumed API-only) |
| EXERCISE, EXERCISE_ROUTE, STEPS, DISTANCE, SPEED, TOTAL_CALORIES_BURNED, FLOORS_CLIMBED, ELEVATION_GAINED | Strain and workouts |
| WEIGHT, BODY_FAT, BODY_TEMPERATURE, HYDRATION, NUTRITION, MENSTRUATION, INTERMENSTRUAL_BLEEDING, BLOOD_GLUCOSE, MEDICAL_DATA | Context |

It also declares READ access for 51 types, including history and background reads, and handles `SHOW_PERMISSIONS_RATIONALE` / `VIEW_PERMISSION_USAGE`.

**What this proves and doesn't:**
- A declared WRITE permission means the app *can* write that type, so the claim "Google Health doesn't write HR/HRV" is now less likely.
- It does **not** prove that the *Air's* samples are written, how dense they are, or that no filter applies to some devices. Phase 0 still decides that.

**Actions taken:**
- Add SpO₂ from Health Connect as an optional read (`READ_OXYGEN_SATURATION`). Resolver priority is Health Connect, then the Google Health API.
- Use the app's own wording in DAY1_CHECKLIST. Its settings entry is "Health connect settings" / "Sync with Health Connect", and its onboarding asks the user to allow Google Health to write sleep data.

## 2. Bluetooth and companion device
- Declares `BLUETOOTH_SCAN/CONNECT/PRIVILEGED` and `REQUEST_COMPANION_PROFILE_WATCH` / `…RUN_IN_BACKGROUND` / `…USE_DATA_IN_BACKGROUND`.
- So the band is paired as a **Companion Device Manager** watch profile. The standard HR-profile route for live HR is unaffected.
- An open question for day 1 remains: does the band advertise `0x180D` while bonded to Google Health?

## 3. The Google Health Coach: product findings (paraphrased from UI strings)

| Aspect | What the strings indicate |
|---|---|
| Model and brand | "Google Health Coach", described as built with Gemini and designed with guidance from medical and fitness experts |
| Price | **Premium only**. Trials of 1 day to 3 months are offered; free users get basic updates without coach messages |
| Eligibility | Needs a paired Fitbit or Google device. Some regions or accounts are told it isn't available |
| Consent | An explicit opt-in lets the coach use *historical and future* Google Health data, with a linked list of data types. It re-asks consent when the set of data types expands |
| Surfaces | Chat ("Ask Coach", with a free-text prompt and suggested "Try saying" examples), **proactive coach messages on Today**, and a Coach Messages setting (full or basic) |
| Capabilities | Answers questions about your data; logs how you feel and symptoms; updates your plan; weekly cardio focus with a load target; generates weekly workouts; sleep coaching with a sleep profile; logs activities for you ("Log with Coach"); adapts plans after poor sleep |
| Memory | **Goals and preferences live inside chats.** Deleting a chat means the coach can no longer use the goals you shared there, and deleting the chat holding fitness preferences stops new workout plans |
| Safety copy | A persistent "AI, can make mistakes, not medical advice" disclaimer, plus 18+ notes on some health features |
| Privacy | Human review of chats happens only if you submit feedback or consent separately to R&D. Chat history can be deleted at any time |
| Extra data | Location for coaching and weather; a CGM integration marketed as boosting coaching |

## 4. What this means for Airlog's AI coach
- **Match:**
  - an explicit consent sheet listing the data types used;
  - a persistent disclaimer;
  - deletable history;
  - suggested prompts;
  - proactive insights on Today.
- **Beat:**
  - **Free.** The coach is a Premium upsell there.
  - **Grounded.** Answers come from tool calls over local data, show the exact numbers, and a check rejects any number not found in the tool results. This targets the #1 complaint (hallucinated events).
  - **Memory separate from chats.** A visible, editable list of facts the coach knows. Deleting a chat shouldn't silently delete your goals.
  - **Provider choice with privacy by default.** Send only what a question needs, and say exactly what leaves the phone.
  - **Works without a Google Premium account.**
