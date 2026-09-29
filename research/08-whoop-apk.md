# 08: What the WHOOP app contains (static APK inspection)

**Source:** WHOOP, package `com.whoop.android`, version `5.470.0`, posted 2026-09-25, APKMirror bundle (all ABIs, minSdk 28).
- A **release build**, not debuggable.
- Signed by `CN=whoop.com, O=WHOOP Inc., Boston` (SHA-256 `4ff1dac8…c8e2`).

**Method:** manifest via `apkanalyzer`, resource strings via `aapt2`, and a list of the Kotlin module and native-library names. Nothing was decompiled.

The user says WHOOP gave explicit permission to copy. There is still **no copyable scoring code**:
- The app is compiled Kotlin/R8. It can't be pasted into Flutter.
- It has a `nested-bff` (backend-for-frontend) module and a `strap-history-sync` module, and no on-device scoring native library. So Recovery, Strain and Sleep are computed on WHOOP's servers.
- WHOOP's name, logo and brand stay out of Airlog regardless (Play impersonation policy).

## 1. Health Connect
WHOOP declares 35 Health Connect permissions:

| Direction | Types | What it tells us |
|---|---|---|
| **Writes** | HR, RHR, respiratory rate, **SpO₂**, sleep, exercise, steps, active calories, weight, lean mass | It writes no HRV |
| **Reads** | Mostly context: nutrition, hydration, cycle, weight, BP, glucose, VO₂ max, SpO₂ | It **doesn't read HRV** or skin temperature from other apps |

So WHOOP keeps HRV as its own moat. It uses Health Connect for export and context, the same pattern we planned for "other apps".

## 2. Feature map (158 Kotlin feature modules; names are self-describing)
**Coaching and AI**
- `ai-insights`
- `coach-everywhere` (the coach is available from every screen)
- `bot`
- `sms` (text the coach)
- `stream-chat-*` (chat UI)
- `clinician-in-the-loop`
- `sleep-coach`
- `weekly-plan`
- `training`

**Behaviour → outcome**
- `journal`
- `behavior-impact`
- `recovery-impacts-mini-arch`

**Health**
- `health-monitor`
- `heart-health-common` (ECG and heart screener)
- `stress`
- `healthspan` (WHOOP Age and Pace of Aging)
- `hormonal-insights`
- `pregnancy`
- `advanced-labs` (blood tests)

**Everyday**
- `home`, `home-customization`
- `last-night-sleep`
- `trends`, `deep-dive`
- `streaks`, `achievements`
- `smart-alarm`
- `stealth-mode`
- `weightlifting`
- `gps-tracking`, `strava`
- `widget`
- `member-data-export`

## 3. Product details worth adopting (paraphrased)

| Area | WHOOP's approach | Airlog decision |
|---|---|---|
| **Coach privacy mode** | Two coaching modes: personalised with your data, or a *generic* mode that never uses your data (science and training info only) | **Adopt.** Two modes, "Use my data" and "General only", with General as the default until the user consents |
| **Response length** | The user chooses how detailed answers are | **Adopt:** a Brief / Detailed toggle |
| **Memory** | The coach tells you it is taking in past feedback and context, and reviewing what you shared | **Adopt, and make it visible:** a "What Coach knows" list the user can edit and delete, stored locally |
| **Coach everywhere** | Coach can be reached from any screen with context | **Adopt:** an "Ask about this" entry on Recovery, Sleep, Strain and Trends that pre-fills the screen and date |
| **Channels** | SMS coaching | Skip, because it needs a server |
| **Journal UX** | An option to pre-fill today's answers with your most recent entries; "see how your behaviours impact your recovery" | **Adopt** the pre-fill toggle (we already have the impacts) |
| **Strain target** | Needs 4 days of data; shows a calculating state; you can set your own goal when Recovery is missing | **Adopt:** a manual goal when there's no Recovery; show "needs N more days" |
| **Stealth mode** | Hide Recovery (and hence the strain target); a separate switch hides WHOOP Age | **Adopt later:** a "Hide scores" calm mode (fits our calm principle) |
| **Explanations** | Short, plain definitions of HRV and RHR (what it is, what up or down means) | Our explain sheets already do this. Keep our own wording |
| **Health Monitor copy** | Lists benign and serious causes of high HR without diagnosing | Keep our non-diagnostic alert copy |
