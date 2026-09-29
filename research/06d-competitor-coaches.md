# AI health and fitness coaches in wearable apps: state of play, 2025 to Sept 2026

**Method notes**
- Research date: 2026-09-29.
- Sources: official vendor pages were fetched where possible, some through Firecrawl when WebFetch was blocked (403 on whoop.com and techradar.com). Reddit evidence comes only from articles that quote threads; the thread URLs given are the ones those articles cite.
- **Paraphrase vs quote:** everything below is paraphrase except one item marked [QUOTE]. Policy allows only one short verbatim quote per response, which overrides the brief's request for a quote on every claim.
- **Dates:** help-center pages with no visible publish date are marked "date unknown (accessed 2026-09-29)".
- **Names:** forum usernames and individuals' names are left out on purpose.

---

## Bottom line

1. **Google.** Google Health Coach, launched May 19, 2026, has the most sophisticated published architecture of any of these products: multiple agents, a data-science agent that writes code, and large human evaluation. It also has the worst public record on hallucination and verbosity. Google's response so far has been a public roadmap (May 26) and an option to hide the coach from the Today tab (v5.06, Aug 2026). No formal statement was found.
2. **WHOOP and Oura.** Both have converged on the same pattern: a visible, editable memory store, proactive check-ins, and morning and evening briefings. WHOOP bundles AI coaching into every tier. Oura includes it in a $5.99/mo membership and routes women's-health questions to its own model.
3. **Apple.** Apple has not shipped a chat coach. What it announced on Sept 9, 2026 is an Apple Intelligence "Insights" tab: summaries plus guidance, with no chat mentioned, arriving "later this year" in US English. The dedicated coach ("Mulberry") and a paid Health+ tier exist only in reports.
4. **Samsung.** Samsung launched a US beta of its conversational Health Assistant on July 21, 2026. It has not disclosed the model or the price.
5. **Question types.** Across vendor data, users mostly ask four kinds of questions: (a) explain my score, (b) what should I do today, (c) does X affect my sleep or recovery, (d) build me a plan. Chat-based logging (food, workouts) is a large and failure-prone category of its own.
6. **Top complaints.** The most-cited failures are fabricated events, treating missing data as real data, memory that won't forget, and unconfirmed writes to the user's logs.

---

## Comparison table

| Product | Price (US) | LLM provider | Memory: view / delete | Proactive | Chats used for training? | Stated data window |
|---|---|---|---|---|---|---|
| Google Health Coach | $9.99/mo or $99/yr (Premium); free with Google AI Pro/Ultra | Gemini (version not disclosed) | Delete conversations one by one or all; no separate memory viewer found | Yes (Today tab; hideable since v5.06) | Only if you opt into research (de-identified) | Asks over a month, 3 months or a year; no maximum stated |
| WHOOP | In all tiers: One $199/yr, Peak $239/yr, Life $359/yr | GPT-4 at launch (2023); 2026 partner not named, plus a "fine-tuned" model | My Memory: 7 categories; view, add, edit, delete, or turn off | Yes (Daily Outlook, Day in Review, Proactive Check-ins) | FAQ says anonymized member data is used for AI model training | Any date (2023 CTO example asks about a date a year back) |
| Oura Advisor | In membership: $5.99/mo or $69.99/yr (€5.99 / €69.99 in EU) | General model not named; women's-health model is Oura's own | Memories: view and delete; "Reset Advisor" | Yes (configurable check-in notifications) | Women's-health model: never used to train third-party AI; general policy not stated | "Short- and long-term data"; tags from the past 7 days |
| Samsung Health Assistant | Beta; price not announced | Not disclosed | Not found | Energy Score and wellness tips; calendar context planned | Separate AI-training consent prompt (July 2026) | Not found |
| Apple Health Insights | Free; later 2026 | Apple Intelligence (Health backend not detailed) | Not applicable (no chat) | Summary updates through the day | Not stated | Not stated |
| Bevel Intelligence | Pro $14.99/mo or $99.99/yr, with a weekly usage allowance | Third-party LLM partners (not named) | "Files": view and delete one or all; Ghost Mode | Yes (check-ins; daily, weekly, monthly summaries) | Anonymized health data sent to LLM partners; sensitive data kept 30 days for debugging | Not stated |
| Garmin Connect+ | $6.99/mo or $69.99/yr | Not disclosed | Not applicable | Proactive insights only (beta) | Not stated | Not stated |

---

## 1. Google Health app: Google Health Coach, Fitbit Labs, Google Health Premium

### Timeline and context
- The coach entered public preview on Oct 27, 2025 for US Android Fitbit Premium users. [https://blog.google/products/fitbit/personal-health-coach-public-preview/, 2025-10-27]
- In February 2026 the preview reached iOS and the UK, Canada, Australia, New Zealand and Singapore. This comes from a search snippet only. [https://9to5google.com/2026/02/10/fitbit-coach-international-preview-ios/, 2026-02-10]
- The Mar 31, 2026 update added:
  - Cycle Health, with coach cycle insights
  - Mental Wellbeing (the "resilience" score)
  - nutrition and water logging with personalized macro ranges
  - [https://blog.google/products-and-platforms/devices/fitbit/fitbit-personal-health-coach-new-features/, 2026-03-31]
- On May 19, 2026 the Fitbit app became Google Health and Fitbit Premium became Google Health Premium. The rollout finished by May 26. [https://blog.google/products-and-platforms/products/google-health/google-health-coach/, 2026-05-07; https://support.google.com/googlehealth/answer/17068213, date unknown]

### What users can ask
- The help center lists these categories:
  - insights and trends over the past month, 3 months or year
  - correlations (for example, does sleep improve on exercise days)
  - wellness guidance (for example, raising VO2 max; nutrition tips)
  - goal-setting and schedule changes
  - logging and editing entries (workouts, weight, water)
  - device and sync support
  - style preferences (for example, shorter answers)
  - [https://support.google.com/googlehealth/answer/17053789, date unknown]
- Launch example prompts: a 30-minute hotel-room upper-body workout; why I woke up tired; my sleep compared with similar people; how to get more deep sleep; find patterns in my sleep. [https://blog.google/products/fitbit/personal-health-coach-public-preview/, 2025-10-27]
- The coach can also summarize US medical records. It takes logs by voice, photo or file. [https://blog.google/products-and-platforms/products/google-health/google-health-coach/, 2026-05-07; https://techcrunch.com/2026/05/07/googles-9-99-per-month-ai-health-coach-launches-may-19/, 2026-05-07]
- The fitness plan tab gives weekly targets plus recommended workouts, adjustable by chat. [https://support.google.com/googlehealth/answer/16961408, date unknown]

### Grounding: what data, how far back, numbers
- **Data read:**
  - activity and exercise; sleep; body and health metrics; general device data
  - Google Account profile
  - app interactions
  - synced medical records
  - linked third-party apps; manual entries
  - location and weather
  - [https://support.google.com/googlehealth/answer/17055092, date unknown]
- **Medical records** are used for personalization only if the coach is on and the user consents. [same page]
- **How it answers a question.** For a question like "do I sleep better after exercising," Google says the coach:
  - checks that recent data is available
  - picks the right metrics and contrasts the relevant days
  - compares against personal baselines and population statistics
  - folds in prior conversations
  - [https://research.google/blog/how-we-are-building-the-personal-health-coach/, 2025-10-27]
- **Architecture (same post):**
  - a conversational agent: intent, orchestration, context gathering
  - a data-science agent that repeatedly calls tools to fetch, analyze and summarize data, generating code when needed
  - a domain-expert agent (for example, fitness) that builds and adapts plans
- **Look-back:** no maximum is stated. The troubleshooting page says to ask about a longer period (weeks or months) if the coach says it needs more data. It also says to check that the coach is pulling from the correct dates when numbers look wrong. [https://support.google.com/googlehealth/answer/17056906, date unknown]
- **Evaluation:** Google's SHARP framework scores safety, helpfulness, accuracy, relevance and personalization. It used over 1 million human annotations and over 100k hours of evaluation by generalists and specialists (sports, sleep, family medicine, cardiology, endocrinology), plus automated raters. [https://research.google/blog/how-we-are-building-the-personal-health-coach/, 2025-10-27]
- **Research lineage:**
  - **Personal Health Agent (PHA)** paper, 38 authors.
    - Submitted Aug 27, 2025, revised Sept 18, 2025. [https://arxiv.org/abs/2508.20148]
    - The abstract names three sub-agents: data science, health domain expert, health coach.
    - Evaluation: 10 benchmark tasks, over 7,000 annotations, over 1,100 hours.
  - **Google's blog on PHA** describes four user-need areas:
    - general health knowledge
    - interpreting personal data
    - actionable wellness advice
    - symptom assessment
    - [https://research.google/blog/the-anatomy-of-a-personal-health-agent/, 2025-09-30]
  - **Data-science agent results (same blog):**
    - It first turns the question into a statistical analysis plan, then writes code.
    - It scored 75.6% on analysis planning versus 53.7% for the baseline.
    - It was tested against 173 unit tests on code generation.
    - The domain-expert agent is grounded through NCBI databases.
    - The coach agent uses motivational interviewing.
    - The orchestrator runs a loop of collaboration, reflection and memory updates.
  - **PHIA** (earlier agent work): code generation plus retrieval, tested on over 4,000 questions. It scored 84% on objective numeric questions. [https://arxiv.org/abs/2406.06464, submitted 2024-06-10, revised 2025-09-08]
  - **PH-LLM** (a fine-tuned Gemini) appeared in Nature Medicine vol. 31, 2025. [https://www.nature.com/articles/s41591-025-03888-0, 2025] Its reported exam scores (see UNVERIFIED) came from a search snippet.

### Memory
- The coach automatically saves what you share. Onboarding context (goals, challenges) lives in the conversation transcripts under Ask Coach → History. [https://support.google.com/googlehealth/answer/17055092; https://support.google.com/googlehealth/answer/16961408, dates unknown]
- You can delete one conversation or all of them via Profile → Google Health settings → Manage data and privacy → Coach activity. [https://support.google.com/googlehealth/answer/17055092, date unknown]
- Revoking consent or deleting a data category does not remove that information from conversation history. You have to delete the conversations. [same page]
- One reviewer found no way to audit what the app knows about you, and no way to make it forget. One question about supplements turned into a nightly routine check. [https://www.androidauthority.com/google-health-app-two-months-later-3694569/, 2026-08-09]
- Google's roadmap marks as improved the coach's recall of instructions such as "Stop mentioning…", "Forget that I…" and "I am no longer…". [https://support.google.com/googlehealth/thread/437068226/sharing-upcoming-roadmap-and-improvements, 2026-05-26]

### Proactive insights vs chat
- The Today tab carries coach messages through the day: sleep, post-workout, daily recaps. [https://support.google.com/googlehealth/answer/16961408, date unknown]
- Daily workout suggestions factor in readiness, progress and weather. [https://blog.google/products-and-platforms/products/google-health/google-health-coach/, 2026-05-07]
- **v5.06 (Aug 2026)** added a Coach setting with two modes: "Standard" and "No Coach insights". Chat and fitness plans stay available in both. [TechRadar embedding Google's post: https://www.techradar.com/health-fitness/fitness-apps/the-latest-google-health-update-lets-you-hide-the-ai-coach-and-ill-be-glad-to-take-a-break-from-its-advice, 2026-08-15]
- The roadmap also promises tuning which activities trigger a message ("less commentary on brief walks"). [https://support.google.com/googlehealth/thread/437068226/sharing-upcoming-roadmap-and-improvements, 2026-05-26]

### Safety
- The coach is informational only. It does not diagnose, treat, cure or prevent disease, and users should not change medication, diet, fitness plan or sleep schedule without a doctor. [https://support.google.com/googlehealth/answer/17053789, date unknown]
- It is for adults 18+ only. [QUOTE] "Your coach is AI and can make mistakes." [https://support.google.com/googlehealth/answer/16961408, date unknown]
- If the coach states something false, users are told to correct it in chat. Unsafe answers should get a thumbs-down or go to support. [https://support.google.com/googlehealth/answer/17056906, date unknown]
- Google also has a Consumer Health Advisory Panel and uses expert-consensus methods. [https://research.google/blog/how-we-are-building-the-personal-health-coach/, 2025-10-27]
- No published list of refusal categories or escalation path to clinicians was found.

### Paywall and price
- $9.99/month or $99/year. Included with Google AI Pro and Ultra. [https://blog.google/products-and-platforms/products/google-health/google-health-coach/, 2026-05-07]
- TechCrunch reports it is bundled with the $99 Fitbit Air. [https://techcrunch.com/2026/05/07/googles-9-99-per-month-ai-health-coach-launches-may-19/, 2026-05-07] The "3 months free" length is UNVERIFIED.
- Requires a Fitbit or Pixel Watch. Available in about 37 countries, including the US, UK, India, Japan, Brazil, most of the EU, Canada, Australia, South Korea, Singapore and Taiwan. [https://support.google.com/googlehealth/answer/16961408, date unknown]

### Data and privacy
- Built on Gemini models. Google commits not to use Fitbit health data for Google Ads. [https://blog.google/products-and-platforms/products/google-health/google-health-coach/, 2026-05-07]
- Coach chats train the model only if you opted into research, and that data is de-identified. [https://support.google.com/googlehealth/answer/17055092, date unknown]
- Human reviewers see conversations only if you submit feedback or separately consent to research. [same page]
- Location data is deleted automatically after 30 days. [same page]
- A TechRadar reviewer points out that the Ads pledge rests on a 10-year EU commitment from the 2020 acquisition. [https://www.techradar.com/health-fitness/ive-been-using-google-healths-new-ai-coach-for-a-week-heres-3-things-i-liked-about-the-fitbit-premium-revamp-and-2-i-really-didnt, 2026-06-06]
- The roadmap marks as done ("[PUBLISHED CLI]") support for CLIs and "other AI skills" on top of user data. [https://support.google.com/googlehealth/thread/437068226/sharing-upcoming-roadmap-and-improvements, 2026-05-26]

### Fitbit Labs
- Google names Fitbit Insights Explorer and the Sleep and Symptom Checker Labs as sources of feedback from consented research. [https://research.google/blog/how-we-are-building-the-personal-health-coach/, 2025-10-27]
- Other Labs details are snippet-level only (see UNVERIFIED): Medical Record Navigator, Symptom Checker with follow-up questions, Unusual Trends. [https://9to5google.com/2025/05/12/fitbit-labs-medical-records/, 2025-05-12]

### User sentiment
**Praise**
- A TechRadar reviewer called it the best health AI assistant they had used. They praised:
  - pasting gym notes to log sessions correctly
  - generating 5x5 push/pull/leg plans
  - photo food logging, with exact nutrition for packaged foods
  - the coach remembering a recent illness when it commented on a short run
  - [https://www.techradar.com/health-fitness/ive-been-using-google-healths-new-ai-coach-for-a-week-heres-3-things-i-liked-about-the-fitbit-premium-revamp-and-2-i-really-didnt, 2026-06-06]
- Android Authority found the explanatory summaries useful. A sleep-on-workout-days versus rest-days comparison worked. [https://www.androidauthority.com/google-health-app-two-months-later-3694569/, 2026-08-09]
- DC Rainmaker described Google's coach as very good at remembering things. [https://www.dcrainmaker.com/2026/05/whoops-defensive-hastily-features.html, 2026-05-10]

**Complaints: hallucination** (already documented; brief)
- A 5-mile run that never happened; when challenged, the coach admitted inventing it but partly blamed the user. [https://www.androidauthority.com/google-health-coach-hallucinations-3667257/, 2026-05-14]
- Walking or folding laundry logged as swims; imagined 5am runs and a house move; repeated questions about a cruise that hadn't happened; sleep "recorded" while the tracker was off. [https://www.techradar.com/ai-platforms-assistants/nonstop-lies-from-the-ai-as-google-launches-the-pixel-watch-5-its-redesigned-google-health-app-is-leaving-fitbit-users-incensed-at-its-crazy-hallucinations, 2026-08-12]
- TechRadar asked Google about the hallucinations and had no reply at publication. [same article]

**Complaints: newer evidence**
- **Food logging** was called almost dangerously inaccurate (eggs over-counted, Greek yogurt under-counted, database errors). Others said the AI fails to add foods and randomly changes workouts. [https://www.techradar.com/ai-platforms-assistants/this-is-a-neverending-fight-fitbit-users-are-sick-of-google-healths-ai-hallucinations-and-now-its-affecting-their-food-tracking-metrics, 2026-09-02; thread https://www.reddit.com/r/fitbit/comments/1w4gmks/]
- **Context-blind advice:**
  - the coach suggested ditching a dog to walk faster
  - another user was told to ditch a toddler
  - one user says it recommends rest every single day
  - a day the watch wasn't worn was labeled a "full recovery day"
  - A "Does anyone actually use the AI Coach?" thread was full of plans to cancel after the trial and of complaints about walls of obvious or outdated text.
  - [https://www.techradar.com/ai-platforms-assistants/fitbits-gemini-ai-coach-is-giving-users-unhinged-fitness-advice-heres-why-users-are-saying-they-cannot-wait-for-my-trial-to-end, 2026-06-29; threads https://www.reddit.com/r/fitbit/comments/1ufd1o3/, https://www.reddit.com/r/fitbit/comments/1uhw9eh/]
- **Verbosity and clutter:**
  - Coach summaries fill about half the Today view.
  - One recap used a header, five sentences and a question just to report steps and calories.
  - Correcting a misdetected activity (basketball logged as a run) did not update the coach.
  - Before v5.06 the only control was all-or-nothing.
  - [https://www.androidauthority.com/google-health-premium-not-worth-it-3685642/, 2026-07-13]
- Redditors complained the coach plays "20 questions" every morning. [TechRadar 2026-08-15, above; thread https://www.reddit.com/r/fitbit/comments/1vbsu8p/]
- **Duplicate proactive messages:** the coach re-evaluated the same workout 4+ times over several hours, sending a notification each time; sleep evaluation changed three times. A product expert redirected users to in-app feedback. [https://support.google.com/googlehealth/thread/452108425/ai-health-coach-hallucinations, 2026-07-17]
- **Reviewer comparison:** Google's summaries carry few specific data points and constantly push the next action. Apple's (previewed) summaries are short and backed by charts. [https://www.androidauthority.com/apple-google-health-redesign-3712230/, 2026-09-21]
- **Willingness to pay:** in a TechRadar reader poll, only 20% said they would pay for coach features. This is a reader poll, not a representative sample. [https://www.techradar.com/health-fitness/fitness-apps/google-health-is-getting-heat-for-being-unbelievably-bad-after-replacing-the-fitbit-app-but-google-says-fixes-are-coming, 2026-05-27]

**Google's de facto response**
- The May 26 roadmap from the community manager promises:
  - more concise messages, balancing positivity and objectivity
  - more charts and glanceable stats
  - asking for intent more often before answering
  - fewer references to stale information
  - fewer error-outs and non-answers
  - deleting logs via chat
  - adding fat type, sodium and fiber to chat-logged food
  - bringing back structured weekly schedules later in the year
  - [https://support.google.com/googlehealth/thread/437068226/sharing-upcoming-roadmap-and-improvements, 2026-05-26; coverage https://9to5google.com/2026/05/27/google-health-roadmap-fitbit-backlash/, 2026-05-27]
- Then v5.06 added "No Coach insights" (Aug 2026, above).
- No published hallucination-rate figure or formal statement was found.

---

## 2. WHOOP Coach and WHOOP AI

### What users can ask
- **2023 launch categories:**
  - bespoke plans (for example, a 24-minute 5K; staying fit with a newborn)
  - "why am I tired / am I getting sick"
  - science explainers (HRV, Zone 2)
  - comparisons with similar members
  - membership support
  - [https://www.whoop.com/us/en/thelocker/whoop-unveils-the-new-whoop-coach-powered-by-openai/, 2023-09-26]
- **2026 FAQ examples:** how should I train today; why is my Recovery low; when should I go to bed; how does my sleep compare with people like me. [https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/, 2026-04-30]
- **Other capabilities:**
  - post-workout follow-up questions in Activity Insights
  - custom Journal behaviors created through chat
  - a Strength Trainer workout built from typed text or a photo, shown back to the user for editing
  - [https://support.whoop.com/s/article/How-to-Use-the-AI-Powered-WHOOP-Coach, last published 2026-09-18]

### Grounding
- **2023 architecture, per the CTO:**
  1. An internal model answers FAQ-type questions directly.
  2. For other questions, personal details are replaced with random IDs and the question goes to the LLM, which extracts the topic and date.
  3. WHOOP pulls the matching data (for example, sleep on a given date plus journal and behavior impacts).
  4. Another model searches for links to WHOOP performance science.
  5. The context, stripped of personal details, goes back to the LLM.
  6. A WHOOP model re-inserts personal data and adds links to articles and app screens.
  7. Most answers take under 3 seconds.
  - The worked example asked about a date one year earlier, so any historical date can be retrieved.
  - [https://www.whoop.com/us/en/thelocker/behind-the-development-of-whoop-coach/, 2023-09-27]
- **2026:** WHOOP combines 24/7 biometrics (HRV, sleep, strain, Recovery) with My Memory context and a fine-tuned LLM. It explains screens in context, for example why Recovery dipped, with sleep consistency and strain as contributors. [https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/, 2026-04-30]
- It also uses weather, air quality and location for Daily Outlook and strain adjustments. [support article, 2026-09-18]
- **Coaching Mode:** "Customized with your data" or "Education and Support Only" (generic advice, no personal data). [same]

### Memory
- **My Memory** has 7 categories: Goals, Identity, Lifestyle, Preferences, Events, Health History, Mood. [https://www.whoop.com/us/en/thelocker/my-memory-whoop/, 2026-05-01]
- You can view, add, edit or remove entries, or turn memory off. WHOOP updates it automatically. Temporary patterns (for example, a past illness) are remembered but not actively coached on. [same]
- Access via the lightbulb icon in chat or Profile → Personalization. [support article, 2026-09-18]
- Launched May 8, 2026 together with Proactive Check-ins. [https://www.whoop.com/us/en/press-center/whoop-expands-health-platform-with-on-demand-clinician-access-and-new-ai-features/, 2026-05-08]

### Proactive insights vs chat
- **Daily Outlook** each morning: strain target, training windows, weather.
- **Activity Insights** after workouts.
- **Day in Review** at night: bedtime range, behaviors.
- **Proactive Check-ins** by push, for example before a big day, after poor sleep or around a shared goal. WHOOP says it stays quiet when nothing warrants action.
- [https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/, 2026-04-30; https://www.whoop.com/us/en/thelocker/2026-whats-next/, 2026-05-08]
- **Voice:** the Journal accepts voice or text, and the AI suggests behaviors to track. [press release, 2026-05-08] No voice chat with the coach was found.

### Safety
- WHOOP says it is a wellness feature, not medical advice, and does not replace a human coach. [support article, 2026-09-18]
- The FAQ describes the AI as in beta with variable results, and tells users to see a professional for persistent symptoms. [https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/, 2026-04-30]
- **Escalation:**
  - If WHOOP decides you need more help, you can opt in to have a support ticket filed automatically. [same]
  - A paid add-on for live video visits with a licensed clinician (US, summer 2026) and HealthEx EHR sync were announced. [press release, 2026-05-08] Pricing and launch status were not found.

### Paywall and price
- AI coaching is included in every tier: One $199/yr, Peak $239/yr, Life $359/yr, with a 1-month free trial. [https://www.whoop.com/us/en/membership/, date unknown (accessed 2026-09-29)]
- Advanced Labs bloodwork is a separate purchase. Launched Sept 30, 2025. [https://www.businesswire.com/news/home/20250930178710/en/, 2025-09-30] Prices are UNVERIFIED.

### Data and privacy
- Launched on OpenAI GPT-4 in 50+ languages. [2023-09-26 post]
- The 2026 pages name only a "third-party" LLM partner. Metrics are anonymized before processing, conversations are not accessed without consent, and data is not stored with third parties. [https://www.whoop.com/us/en/thelocker/my-memory-whoop/, 2026-05-01]
- The same FAQ says WHOOP uses anonymized member data for AI model training. [https://www.whoop.com/us/en/thelocker/new-ai-guidance-from-whoop/, 2026-04-30]
- There is a "Personalized Product Recommendations" privacy toggle, and WHOOP says it never shares location with third parties. [support article, 2026-09-18]

### User sentiment
- **Praise (Reddit via Gear Patrol):**
  - compares cardio sessions against past ones
  - suggests exercises with weights and reps, and builds weekly plans
  - daily jet-lag plans
  - memory-driven illness check-ins
  - [https://www.gearpatrol.com/fitness/whoop-ai-reddit-user-feedback-pros-cons/, 2026-07-06]
- **Complaints (same article):**
  - invented elevation data on a hike
  - invented night-time wakefulness, then assumed the user was sick
  - falsely logged caffeine
  - logged alcohol after a sober night out dancing
  - a pushy tone (some screenshots are of disputed authenticity)
- DC Rainmaker called Memory and check-ins a reaction to Google's coach. He found voice journaling useful. He said price is the complaint users actually care about. [https://www.dcrainmaker.com/2026/05/whoops-defensive-hastily-features.html, 2026-05-10]

---

## 3. Oura Advisor

### What users can ask
- Personalized answers on Sleep, Activity, Readiness and Resilience. General questions on heart health and similar topics. [https://ouraring.com/blog/oura-advisor/, 2025-03-31 with 2026 edits]
- **Use cases:**
  - why Readiness is dipping
  - sleep tips and resilience strategies
  - goal plans and accountability
  - tag-based trends
  - long-term trends (HR, HRV, stress)
  - meal planning from what's in your kitchen
  - emotional support
  - [https://ouraring.com/blog/how-to-use-oura-advisor/, 2025-03-31]
- **Women's health:** since Apr 8, 2026, questions about cycle, hormones, pregnancy or menopause go automatically to Oura's own model. Example: why a cycle suddenly became irregular. [https://ouraring.com/blog/womens-health-ai-model/, 2026-04-08; https://support.ouraring.com/hc/en-us/articles/39512345699219-Oura-Advisor, updated 2026-06-11]
- Lab uploads (PDFs) can be discussed with Advisor (rolling out June 30, 2026). [https://ouraring.com/blog/new-software-features/, 2026-05-28]

### Grounding
- **Inputs:** scores and contributors, activities and tags, profile, and past Advisor interactions. [support article, 2026-06-11]
- Uses "short- and long-term data" and can show charts. [blog, 2025-03-31]
- Tags are read only from the past 7 days. [how-to blog, 2025-03-31]
- At full launch, "Trend Detection" let it pull metric baselines and trends it has detected. [https://www.techradar.com/health-fitness/the-oura-rings-ai-powered-wellness-advisor-just-got-a-major-upgrade-and-i-cant-wait-to-use-it-more, 2025-03-31]
- **Oura's own caveats:** Advisor's numbers may not match the rest of the app, it is not integrated with every feature, and Meals may not work in non-English languages. [support article, 2026-06-11]

### Memory
- Things you share are stored as Memories. You can view or delete them in Advisor Settings, or "Reset Advisor" to wipe all data, memories and settings. [support article, 2026-06-11]
- Conversation history (continue or delete threads) arrived in app v7.17.0 in June 2026. Earlier chats weren't saved. [same]
- In the Labs survey, 87% said Advisor remembered their goals accurately. [https://www.businesswire.com/news/home/20250331565896/en/, 2025-03-31]

### Proactive insights vs chat
- Check-in notifications with configurable frequency and time. Readiness messages invite you into Advisor. [support article, 2026-06-11; blog, 2025-03-31]
- The press release says Advisor can proactively flag a recent change in deep sleep. [BusinessWire, 2025-03-31]
- Tone options: "conversational" or "direct". [blog, 2025-03-31]
- Health Radar (proactive blood-pressure and breathing signals; US, UAE and India) sits alongside Advisor. [https://ouraring.com/blog/new-software-features/, 2026-05-28]

### Safety
- Oura says the ring is not a medical device, and users should not change medication, nutrition or workouts without a clinician. [support article, 2026-06-11]
- The women's-health model was built with OB-GYNs and tuned to be non-dismissive and to prepare users for doctor visits. [2026-04-08]
- **Escalation, Counsel Health (Oura Labs, from June 16, 2026, 43 US states):**
  - Oura may suggest connecting to Counsel's medical AI when a user asks Advisor for medical advice or gets a Symptom Radar alert.
  - The user can escalate to a licensed physician; visits cost extra.
  - Not for emergencies.
  - [https://ouraring.com/blog/counsel-integration-oura-app/, 2026-06-08]

### Paywall and price
- Included in membership: $5.99/mo or $69.99/yr (US); €5.99 or €69.99 (EU); first month included with a ring. [https://support.ouraring.com/hc/en-us/articles/4409086524819-Oura-Membership, date unknown]
- Needs a Gen3 or newer ring. Available in 10 languages. [support article, 2026-06-11]

### Data and privacy
- Data is processed in Oura's cloud and never sold. The women's-health model is fine-tuned and hosted on Oura infrastructure, and its conversations are never used to train public or third-party AI. [support article, 2026-06-11; 2026-04-08]
- The general Advisor is described only as a "state-of-the-art LLM"; the provider isn't named.
- Advisor collects nothing until you set it up. [support article]
- Data deletion by time window arrived June 4, 2026. [2026-05-28]

### User sentiment
- **Vendor survey** (3,655 Labs testers; over 1M messages):
  - 83% found answers reliable
  - 60% said it helped them understand metrics
  - 56% turned insights into actions
  - [https://ouraring.com/blog/oura-advisor/, 2025-03-31; BusinessWire, same date]
- **Labs usage:** 60% used it several times a week, 20% daily. A TechRadar reviewer was positive. [TechRadar, 2025-03-31]
- No independent Reddit or review complaints were found in this pass. A Reddit meal-planning quote appears only on Oura's own blog, so it is vendor-curated.

---

## 4. Samsung Health AI

### What shipped
- **Samsung Health Assistant (beta), July 21, 2026**, for eligible US users.
  - It connects five areas (sleep, activity, nutrition, mindfulness, vitals), answers questions, spots patterns, and shows Energy Score with tailored advice.
  - Samsung says a team of physicians and certified health coaches validated its recommendations.
  - Planned next: behavior-change coaching, weight management, and use of the Personal Data Engine (calendar events, habits).
  - [https://news.samsung.com/us/samsung-launches-health-assistant-beta-first-fully-integrated-ai-powered-assistant/, 2026-07-21; https://www.fiercehealthcare.com/ai-and-machine-learning/samsung-launches-beta-version-ai-powered-health-assistant-across-us, 2026-07-22]
- **Energy Score** needs Android 11+, Samsung Health v6.27+, and a Galaxy Watch or Ring with the previous day's activity, sleep and overnight heart rate. [newsroom, 2026-07-21]
- The **June 2026 app update** added proactive (non-chat) features:
  - Vitals (five overnight metrics against your baseline)
  - Heart Health Score
  - Daily Cardio Load (needs 7 days of data; 28 recommended)
  - Fitness Index against peers
  - a new layout built around the same five pillars
  - [https://news.samsung.com/us/samsung-introduces-next-gen-galaxy-watch-features-ai-powered-everyday-health-companion/, 2026-06-04]
- **2025 background:**
  - Samsung planned a US AI coach beta by end of 2025, including help following doctors' prescriptions. It was reported as free at launch with monetization later. That slipped to July 2026. [https://www.kedglobal.com/healthcare/newsView/ked202507110004, 2025-07-11]
  - Samsung acquired Xealth, which links wellness data to care teams. [newsroom, 2025-07-08]
  - Galaxy Watch8 (July 2025) features such as Bedtime Guidance and Running Coach are snippet-level only (see UNVERIFIED).

### Grounding and memory
- Reads Samsung Health's five areas plus manual logs. [https://www.digitaltrends.com/phones/samsungs-new-ai-assistant-wants-to-explain-what-your-health-data-actually-means/, 2026-07 (exact date unknown)]
- **Not found:** look-back window, whether answers cite numbers, and any memory controls.

### Safety
- Samsung says the assistant gives no medical advice, diagnosis or treatment recommendations. [newsroom footnote, 2026-07-21]

### Price
- Not announced. Eligible devices were not disclosed either. [Digital Trends, 2026-07]

### Data and privacy
- **LLM provider:** not disclosed.
- **AI-training consent:** in July 2026 Samsung Health started asking users to allow their health data for AI training. The first warning suggested that declining would stop cloud sync and permanently delete data. Samsung clarified that only data collected for AI training is deleted, and SamMobile found sync kept working after opting out. [https://www.digitaltrends.com/phones/refusing-samsung-health-ai-training-will-not-wipe-your-health-history-after-all/, 2026-07 (SamMobile post dated 2026-07-14)]

### User sentiment
- No independent user sentiment on Health Assistant was found. The consent-wording backlash above is the main public reaction.

---

## 5. Apple

### What shipped vs rumor
- **Shipped (Sept 2025):** Workout Buddy in watchOS 26. It gives spoken, generative motivation during workouts, using a voice built from Fitness+ trainer recordings and your fitness history. Requirements: an Apple Intelligence iPhone, headphones, English; specific workout types. [https://www.apple.com/newsroom/2025/06/watchos-26-delivers-more-personalized-ways-to-stay-active-and-connected/, 2025-06; https://support.apple.com/guide/watch/use-workout-buddy-apd65c7938e6/watchos, date unknown]
- **watchOS 27 (Sept 14, 2026)** extends Workout Buddy: it uses more fitness data, adds Spanish and, per the newsroom, can run on the watch without a connection. [https://www.apple.com/newsroom/2026/09/apple-advances-health-and-fitness-capabilities-using-apple-intelligence/, 2026-09-09]
- **Announced Sept 9, 2026, arriving "later this year" in US English:**
  - a redesigned Health app with an Apple Intelligence Insights tab
    - its summary updates through the day across heart, sleep, readiness, fitness, vitals and cycle
    - a For You section gives recommendations
  - a 0–10 readiness score with four bands: Recover, Pace Yourself, Ready, Go For It
  - Health Age and a Longevity tab
  - camera-based movement and VO2 max tests that run on device
  - a $119 Quest lab panel
  - No chat or Q&A interface is mentioned.
  - [Apple newsroom, 2026-09-09; https://techcrunch.com/2026/09/09/apples-revamped-health-app-will-calculate-your-health-age-and-readiness-score/, 2026-09-09; https://www.macrumors.com/guide/ios-27-health-app-new-features/, 2026-09-10]
- **Mulberry / Health+ reporting timeline (all reports; labeled rumor):**
  - Feb 6, 2026, Bloomberg via Macworld: the paid AI coach service was being wound down. The new services head reportedly judged Oura and WHOOP more compelling, and parts might fold into the Health app. [https://www.macworld.com/article/3055235/apples-ai-powered-health-service-is-reportedly-on-life-support.html]
  - May 24, 2026: the coach may not debut at the iOS 27 launch. [https://9to5mac.com/2026/05/24/apple-improving-heart-rate-tracking-in-watchos-27-mulberry-health-coach-delays/]
  - Aug 29, 2026, Gurman: an AI coach using Health data is still expected. The standalone Health+ plan was reportedly folded into the regular Health app. Camera workout coaching is not in the first iOS 27 release. [https://9to5mac.com/2026/08/29/apple-health-revamp-ai-coach-new-apple-watch-next-month/]
  - Sept 9, 2026 newsroom: no mention of Health+ or a chat coach.
  - TechRadar's Sept 13 claim that Gemini models underpin Apple Intelligence, and so the Health app, is UNVERIFIED for Health. [https://www.techradar.com/ai-platforms-assistants/apple-intelligence/google-health-is-a-grave-warning-for-apples-new-ai-powered-health-app, 2026-09-13]

### Grounding, memory, safety, price, privacy
- **Grounding:** a reviewer describes the summaries as short and backed by data points, graphs and charts. [https://www.androidauthority.com/apple-google-health-redesign-3712230/, 2026-09-21]
- **Memory:** not applicable (no chat).
- **Price:** no Health+ price was announced. The new Insights features are presented as part of the Health app.
- **Privacy:** movement tests run entirely on device and no video is stored. [newsroom, 2026-09-09] Training and processing policy for Insights: not stated.
- **Sentiment:** apart from the comparison above and TechRadar's worry, none was found. No Workout Buddy sentiment was found.

---

## 6. Bevel Intelligence

### What users can ask and do
- **Capabilities:**
  - scheduled check-ins; daily, weekly and monthly summaries
  - food logging from images or text; menu analysis; meal plans from your fridge; weekly meal plans; shopping lists; estimated glycemic curves; nutrient gaps
  - multi-week training plans that adapt to recovery; goal plans (for example, a half marathon); strength and cardio templates, including rebuilding a plan from photos; progressive-overload advice; recovery time per muscle group
  - custom charts (for example, sleep score against next-day HRV; stress against HRV); a "habit impact matrix" (caffeine or alcohol against sleep); predictive modeling (for example, race times)
  - biomarker analysis; symptom-trigger tracking (for example, migraines); weather factors; research summaries
  - [https://help.bevel.health/en/articles/11586817, date unknown]
- **v3.1.0 (July 13, 2026) added:**
  - cardio templates sent to Apple Watch
  - Google or iCloud Calendar integration
  - Ghost Mode (temporary chats; you can choose whether Files persist)
  - Thinking Modes (Fast, Thinking, Adaptive)
  - a Google Health / Fitbit Air integration
  - [https://docs.bevel.health/release-notes, 2026-07-13]
- **Stated limits:** it cannot log or edit journal entries, sleep data, individual data points (for example, VO2 max) or cycle data. It cannot send real-time threshold notifications (for example, stress). [https://help.bevel.health/en/articles/11586817, date unknown]

### Grounding
- Reads the biometrics you authorize from HealthKit and other sources. [https://www.bevel.health/privacy-policy, updated 2026-04-27]
- Actions taken in the background are listed in a dropdown inside the chat. [https://help.bevel.health/en/articles/11586753, date unknown]
- Web access is used for medical research and references. [https://help.bevel.health/en/articles/11583937, date unknown]
- A July 2026 fix addressed Bevel Intelligence missing historical food logs on first load. [release notes, 2026-07-13]
- **Look-back window:** not stated.

### Memory
- "Files" replaced the separate Memory section. Files hold Memories, Plans, Artifacts (charts), Notes (check-in summaries), Logs and Core (profile and personality). [https://help.bevel.health/en/articles/11586881, date unknown]
- You can delete a file through chat or its menu, or use "Delete all Chats / Delete all Files". [same]
- Bevel publishes a prompt for exporting memories from ChatGPT, Claude or Gemini into Files. [https://help.bevel.health/en/articles/11586753, date unknown]

### Proactive insights
- Check-ins on a configurable schedule, plus recurring summaries. [capabilities page]

### Safety
- Bevel's privacy policy says responses may be inaccurate, incomplete or inconsistent, and are not medical advice. [privacy policy, 2026-04-27]
- No escalation path was found.

### Paywall and price
- Pro: $14.99/mo, $99.99/yr, or $10.99/mo on a 12-month commitment (not offered in the US or Singapore).
- The weekly usage allowance resets every 7 days. Basic food capture and template tools don't use credits.
- Core tracking is free.
- [https://help.bevel.health/en/articles/11583937, date unknown]

### Data and privacy
- Biometric data stays on device unless Bevel Intelligence is on. It then goes to unnamed third-party cloud and LLM partners in anonymized, minimal form.
- Reproductive data is excluded by default and needs a separate opt-in, citing Washington's and California's health-data laws.
- Sensitive data used to generate chats is kept up to 30 days for debugging. Chat history is kept until you delete it.
- [privacy policy, 2026-04-27]
- Bevel says it is HIPAA and SOC 2 Type II compliant. [release notes, 2026-07-13]

### User sentiment
- **Company metrics:** over 100k daily active users, 8 app opens a day on average, over 80% retention at 90 days. [https://techcrunch.com/2025/10/30/bevel-raises-10m-series-a-from-general-catalyst-for-its-ai-health-companion/, 2025-10-30]
- **Review:** the priciest app in its category. Health App Insider calls the AI the newest and least battle-tested part of the app, and notes that WHOOP has sued Bevel over its WHOOP data access. [https://www.healthappinsider.com/en/reviews/bevel-review, updated 2026-07-20]
- **App Store (date unknown):** mostly praise for AI food logging and multi-device data merging. One review complains that the new personality system made the bot say less.

---

## 7. Other products (shorter)

- **Welltory AI Coach**
  - A custom GPT inside ChatGPT, built on OpenAI's GPTs. Needs both Welltory Premium and ChatGPT Plus.
  - Welltory says it opted out of OpenAI training on users' chats and cannot see conversations.
  - Labeled experimental and not medical advice, and warns of hallucinations.
  - [https://help.welltory.com/en/articles/8727843-how-to-use-welltory-ai-coach, date unknown]
- **Athlytic**
  - "Ask Athlytic" (app v26.4.2, May 21, 2026) runs on on-device Apple Intelligence; data never leaves the phone. There are also Apple Intelligence workout and journal summaries, and Siri queries in iOS 27.
  - The App Store privacy label is "Data Not Collected". Price is $4.99/mo or $29.99/yr from a two-person company.
  - [https://apps.apple.com/us/app/athlytic-fitness-recovery/id1543571755, accessed 2026-09-29; https://athlyticapp.com/, date unknown]
  - Its release notes mention fixing repeated answers and improving reliability. [App Store version history]
- **Sonar AI (Sonar 4.0, May 1, 2026)**
  - A Pro-only "personal health agent" across multiple wearables: Q&A, trend exploration, and explanations of score changes.
  - Remembers context such as marathon training, illness or travel. Says it gives no diagnosis or treatment.
  - Pro price: not found.
  - One App Store review reports Sonar showing different HR and pace than Strava. [https://apps.apple.com/us/app/sonar-health-performance/id1595073849, accessed 2026-09-29]
- **Garmin Connect+ "Active Intelligence"**
  - AI insights through the day, in beta. $6.99/mo or $69.99/yr with a 30-day trial. [https://www.garmin.com/en-US/newsroom/press-release/wearables-health/elevate-your-health-and-fitness-goals-with-garmin-connect/, 2025-03-27]
  - A year on, Wareable called its AI "incredibly basic". The "Garmin Chat Connector" (an MCP bridge to ChatGPT and Claude) is a third-party project, not Garmin's. [https://www.wareable.com/garmin/garmin-chat-connector-simplifies-your-watch-data-into-a-conversation, 2026-03-17]
- **Strava Athlete Intelligence**
  - Generative summaries on runs, rides, walks and hikes, with "Say More" for detail. For subscribers and trial users; can be hidden.
  - Draws on relevant past activities, for example the previous 30 days for Relative Effort. Personalized by the user's stated focus; mobile only.
  - [https://support.strava.com/en-us/articles/15401629-athlete-intelligence-on-strava, date unknown]
- **Ultrahuman Jade (Feb 27, 2026)**
  - Pitched as "real-time biointelligence". Claims it can take actions (start breathwork, trigger AFib detection), with future plans such as ordering food.
  - Free platform upgrade for all users, including the US. [https://cyborg.ultrahuman.com/press-releases/ultrahuman-unveils-ring-pro-with-category-defining-15-day-battery-and-jade-worlds-first-real-time-biointelligence-ai, 2026-02-27]
  - Chat Q&A over sleep, recovery, metabolism and linked biomarkers (for example, vitamin D). [https://gadgetsandwearables.com/2026/03/17/ultrahuman-jade-ai/, URL-dated 2026-03-17]
  - Since July 2026 the app processes insights on device, and an "UltraSphere" engine suggests next best actions. [https://www.engadget.com/2220780/ultrahuman-overhauls-app-brings-all-of-its-analysis-on-device/, 2026-07-23]
- **Polar:** no native generative AI coach found.
- **Context: ChatGPT Health** (a general-LLM competitor)
  - Launched Jan 7, 2026; opened to US users 18+ on web and iOS on July 23, 2026.
  - Connects Apple Health, MyFitnessPal, Function and US medical records. Health chats are not used to train foundation models.
  - OpenAI says over 230M people ask health questions weekly.
  - [https://openai.com/index/introducing-chatgpt-health/, 2026-01-07 with 2026-07-23 update]

---

## Synthesis A: what users actually ask

### Evidence and its biases

| Source | What it shows | Bias |
|---|---|---|
| Oura Labs, n=3,655 testers, >1M messages [https://ouraring.com/blog/oura-advisor/, 2025-03-31] | Most-discussed topics: sleep and recovery 75%, stress and resilience 57%, activity and workouts 45%. Top feature requests: charts and longer-term trends. | Self-selected beta testers; vendor survey; answers can overlap |
| WHOOP 2023 [https://www.whoop.com/us/en/thelocker/podcast-251-year-in-review-unpacking-2023s-health-and-wellness-trends/, republished 2026-06-10, originally 2023-12-13] | Top 3 prompts: how to improve HRV, how my sleep compares with similar people, how to improve sleep quality | Launch-period data from 2023 |
| Google PHA research [https://research.google/blog/the-anatomy-of-a-personal-health-agent/, 2025-09-30] | Four need areas: general health knowledge, interpreting personal data, actionable advice, symptom assessment | Research sample (from Search, Gemini, forums and Labs), not live coach logs |
| Google help-center Ask Coach categories [https://support.google.com/googlehealth/answer/17053789] | Trends over periods, correlations, VO2 max advice, goals, logging and edits, device support, style | Vendor-designed menu |
| OpenAI [2026-01-07] | Over 230M weekly health askers on a general LLM | Not wearable-specific |

### Taxonomy
The question types below are consistent across the sources above. Example prompts are vendor-published unless marked.

1. **Explain my score or state.** Why is my Recovery or Readiness low; why did I wake up tired. (WHOOP, Oura, Google)
2. **Decide today.** How hard should I train; what time should I go to bed; I have 30 minutes, what workout. (WHOOP, Google)
3. **Cause and effect.** Do I sleep better on exercise days; how do caffeine or alcohol affect sleep. Examples: Bevel's habit impact matrix, WHOOP Behavior Trends, Google's correlations.
4. **Trends and benchmarks.** Is my HRV improving; how do I compare with people like me. (WHOOP, Oura, Google)
5. **Build a plan.** 5K, 10K, half marathon; 5x5 strength; meal plans. (all; reviewers praise this)
6. **Log by conversation.** Pasting workouts, food photos, water or weight; editing entries. Heavily used in reviews, and a major failure point (Google food logging, WHOOP false logs).
7. **Illness and symptoms.** Am I getting sick (WHOOP's 2023 example); symptom assessment (Google PHA); medical questions sent from Advisor to Counsel (Oura).
8. **Life context.** Travel and jet lag; a new baby; injury; stress. Praised on WHOOP (jet lag) and Google (illness context).
9. **Labs and records.** Biomarker interpretation (Bevel, Oura lab uploads, WHOOP Advanced Labs, Google medical records, Ultrahuman).
10. **Cycle and hormones.** Oura's dedicated model; Google Cycle Health.
11. **App and device help.** Syncing, where is feature X. (Google, WHOOP, Bevel)

---

## Synthesis B: features loved vs hated (across products)

**Loved**
- **Memory of life context, when accurate:** illness remembered after a cold (Google, TechRadar 2026-06-06); illness check-ins and jet-lag plans (WHOOP, Gear Patrol 2026-07-06); 87% said Oura remembered goals (vendor survey).
- **Conversational logging and plan generation:** workouts from pasted notes and food photos (Google); workouts from photos (WHOOP, Bevel).
- **Correlations on your own data:** sleep on workout vs rest days (Android Authority 2026-08-09).
- **Charts inside answers:** Oura's top request; Bevel artifacts; Google's roadmap promises more visuals.
- **Tone controls:** Oura's conversational or direct; WHOOP Preferences; Bevel personalities; Google "shorter answers". Tone can also backfire, as in Bevel's "Commander" personality complaint.
- **On-device privacy:** Athlytic's privacy messaging, Ultrahuman's on-device processing. No user sentiment on this was found.

**Hated**
- **Fabricated events and data:** Google workouts, swims, a cruise; WHOOP elevation, caffeine, alcohol.
- **Missing data treated as real:** Google recorded "sleep" while the tracker was off and called an unworn day "full recovery".
- **Verbosity, walls of text, sycophantic cheer that buries the stats:** Google (TechRadar 2026-06-06, 2026-06-29; Android Authority 2026-07-13, 2026-09-21).
- **Over-frequent or duplicate proactive messages:** "20 questions" every morning; the same workout re-evaluated 4+ times with a notification each time (Google community 2026-07-17); nagging about a one-off supplement question.
- **Memory that won't forget or goes stale:** cruise, supplements. There is also no audit view in Google's coach.
- **Context-blind advice:** ditch the dog or toddler; rest every day.
- **Inaccurate nutrition estimates and database errors:** Google, 2026-09-02.
- **All-or-nothing controls:** Google, fixed partly by v5.06.
- **Paywalls on the AI layer:** only 20% of TechRadar poll respondents would pay; Bevel is the priciest app in its category; WHOOP's price is the main complaint.
- **Forced AI:** AI imposed on existing users (Fitbit migration backlash, 2026-05-27).

---

## Synthesis C: how vendors ground answers in numbers

- **Retrieve by topic and date, with personal data stripped (WHOOP, 2023):**
  - The LLM parses the question into topic and date.
  - WHOOP's own services fetch the exact records, journal entries and behavior impacts.
  - A correlation model adds performance science.
  - Personal details are swapped for IDs before any LLM call and re-inserted afterwards.
  - Deterministic data access plus an LLM for language.
- **Multiple agents plus code execution (Google):**
  - A conversational orchestrator.
  - A data-science agent that plans the analysis and then writes and runs code over the time series.
  - A domain-expert agent grounded in NCBI and fitness frameworks.
  - A coach agent using motivational interviewing.
  - Published accuracy figures:
    - PHA analysis planning: 75.6% vs a 53.7% baseline
    - PHIA numeric questions: 84%
  - The production coach explicitly checks that data is available and contrasts baseline with population values.
- **Routing to specialist models (Oura):** a general LLM plus health-sensing algorithms and baseline "Trend Detection". Women's-health questions go to a proprietary model fine-tuned on vetted clinical sources. Medical questions can be handed to Counsel's medical AI and physicians.
- **A visible agent with tools and files (Bevel):**
  - Tools: a calendar tool, web search, chart-building, plan and memory files.
  - An action log in the chat UI.
  - User-selectable reasoning depth.
  - Usage metered by weekly credits.
- **Summaries without chat (Apple, Strava, Garmin):** Apple generates short summaries tied to charts and scores. Strava summarizes each activity with a defined look-back (for example, 30 days for Relative Effort). Garmin offers proactive-only insights.
- **On-device models (Athlytic, Ultrahuman):** Athlytic uses Apple's on-device model, so no data leaves the phone. Ultrahuman runs insight processing on device and claims Jade can trigger in-app actions.
- **Look-back windows stated publicly:** Oura tags 7 days; Strava 30 days (example); Google's "month / 3 months / year" query framing; WHOOP any date (2023 example). The rest publish none. Bevel's 30 days is a data-retention limit, not an analysis window.

### Complaints mapped to grounding gaps
| Complaint | Likely gap | Counter-example or fix seen |
|---|---|---|
| Sleep recorded while tracker off; unworn day called "recovery" | No wear-time or missing-data check before interpreting. Google's blog says the coach verifies data availability, so this step is failing. | Have the model state explicitly when data is absent |
| Invented runs, swims, elevation, 5am runs | Generated text not constrained to retrieved records; no link to a source record | WHOOP's 2023 fetch-by-date pipeline; Bevel's action log |
| Cruise and supplement nagging | Memory has no expiry or correction | WHOOP keeps temporary patterns but doesn't coach on them; Oura view, delete, reset; Google's improved "Forget that I…" handling |
| False caffeine or alcohol logs; workouts "randomly changed" | Writes to the log happen without user confirmation | Bevel's "Add" confirmation for custom journal items; WHOOP shows what it picked up from an uploaded workout for editing |
| Same workout re-evaluated 4+ times | Proactive generation not deduplicated, and each version notifies | Google's promise to "tune which activities warrant a message" |
| Correcting activity type doesn't update the coach | Cached insights not recomputed after user edits | Not found |
| Walls of text, few numbers | Not constrained to lead with the metric | Apple's short summaries tied to charts; Google's roadmap for more glanceable stats |

---

## UNVERIFIED items (not confirmed from a primary or fetched source)

1. The LLM provider behind Samsung Health Assistant. Not disclosed. A search summary linking it to Gemini was a misattribution: the Digital Trends sentence referred to Google.
2. Samsung Health Assistant price and eligible devices. "Free at launch" comes only from a 2025 pre-launch report by KED Global.
3. The model behind Oura's general Advisor. Not named; only the women's-health model is confirmed as proprietary.
4. WHOOP's LLM provider in 2026. OpenAI GPT-4 is confirmed only for the 2023 launch.
5. Which Gemini version powers Google Health Coach. Not disclosed. That PHA ran on "Gemini 2.0" comes from a search snippet.
6. The PHA paper's 1,370+ queries, 555 Labs survey responses and 14-expert workshop. From search snippets of the paper; the full paper exceeded fetch limits.
7. PH-LLM exam scores: sleep 79% vs 76% for experts, fitness 88% vs 71%. From a search snippet of Nature Medicine and PubMed.
8. Fitbit Labs feature details beyond the names Insights Explorer and Symptom Checker: Medical Record Navigator, Unusual Trends, symptom follow-up questions.
9. That the Fitbit Air includes 3 months of Premium. Snippets only; TechCrunch confirms only a bundle.
10. The February 2026 expansion of the coach preview to iOS and the UK, Canada, Australia, New Zealand and Singapore. 9to5Google snippet.
11. Galaxy Watch8 features: Bedtime Guidance, Running Coach (3–5 week plans), Energy Score "driven by Google AI", Galaxy AI Wellness Tips. Snippets of Samsung pages.
12. Garmin Connect+ nutrition tracking added in January 2026. Snippet.
13. The 80%+ "very helpful" rating for Strava Athlete Intelligence. Snippet of a Strava press release.
14. WHOOP Advanced Labs prices ($199 / $349 / $599; $299 panels) and sales to non-members from Aug 18, 2026. Snippets.
15. Bevel v2.4.0 (Dec 18, 2025) making everything except Bevel Intelligence free. Third-party snippet.
16. Oura: deleting health data for any time range also deletes all Advisor chat history and memories. Search snippet of an Oura support page.
17. WHOOP suing Bevel over data access. Secondary; Health App Insider citing TechRadar.
18. Some Reddit screenshots of WHOOP AI, per Gear Patrol, which itself flags their authenticity as disputed.
19. Apple: whether the Health Insights model uses Gemini (TechRadar's claim), the fate of Mulberry and Health+, and when a chat coach might launch. All reports; nothing announced.
20. Workout Buddy running on the watch without a connection in watchOS 27. Came through a page summarizer; the Apple support page says it needs a paired Apple Intelligence iPhone.
21. Sonar Pro price. Not found.
22. Pricing and launch status of WHOOP's clinician-visit add-on. Not found.
23. Any Google statement or benchmark on hallucination rates for the production coach. Not found; the roadmap and the v5.06 setting are the only responses.
