# 06b: Gemini API for Airlog (sub-agent report, accessed 2026-09-29)

This is a condensed, verbatim-sourced record from the research sub-agent. The full citations are in the session transcript; each claim below names its page.

## Terms that bind the product (ai.google.dev/gemini-api/terms, updated 2026-04-28)
- **Age:** users must be 18 or older, and the API can't be used in apps likely to be accessed by under-18s.
- **No medical advice:** the terms forbid using the Services in clinical practice or to give medical advice.
- **Professional use only:** Google AI Studio and the Gemini API are for developers with professional or business purposes, **not for consumer use**. Whether a user bringing their own key (BYOK) counts as consumer use is unresolved; Google staff didn't rule on it in an Aug-2026 forum thread.
- **Paid tier required in the EEA, Switzerland and the UK** when offering apps to users there.
- **Free tier:** prompts are used to improve Google products, human reviewers may read them, and the terms say "Do not submit sensitive…personal information to the Unpaid Services."
- **Paid tier:** prompts are not used for training, processing falls under the DPA, and data is kept 55 days for abuse monitoring. The Developer API has no guaranteed zero data retention (that needs Vertex / Agent Platform).

## Models (ai.google.dev/gemini-api/docs/models, 2026-09-24)
Google recommends these two for new projects:

| Model | Price per 1M tokens (in / out) | Notes |
|---|---|---|
| `gemini-3.8-flash` | $0.75 / $3.75 intro, **doubling on 2027-01-01** | Thinking default medium |
| `gemini-3.5-flash-lite` | $0.30 / $2.50 | Thinking default minimal |

- **Gemini 2.5:** not available to new projects (the Firebase FAQ says it shuts down in Oct 2026).
- **Deprecated parameters:** `temperature`, `top_p` and `top_k` (2026-07-21). Use `thinking_level` instead.
- **Structured output:** `responseSchema` / `responseJsonSchema` are deprecated in favour of `responseFormat`.
- **API choice:** generateContent is still fully supported, but the Interactions API is recommended for new work.
- **Function calling:**
  - Modes are AUTO, ANY, NONE and VALIDATED; parallel and compositional calls are both supported.
  - On 3.8, every FunctionResponse must carry `call_id` and `name`.
  - Keep the active tool set at 10–20.

## SDKs
- **`google_generative_ai`** (Dart) is deprecated and its repo is archived.
- **`firebase_ai` 4.0.0** (2026-08-24) is the supported Flutter route (Firebase AI Logic):
  - it proxies requests, so there's no API key in the app;
  - **App Check enforcement is mandatory from 2026-11-02**;
  - it needs a Firebase project, and the Blaze plan plus Prepay for the paid tier.
- **Genkit Dart** is in preview.

## Cost per chat turn (8k input tokens, 400–2,400 output)

| Model | Per turn |
|---|---|
| `gemini-3.5-flash-lite` | $0.0034–0.0084 |
| `gemini-3.8-flash` | $0.0075–0.015 (doubles in 2027) |

## Decision for Airlog v1
- **Gemini is optional, bring-your-own-key, over raw REST generateContent**, and requires the user to confirm the key belongs to a **billing-enabled (paid) project**.
- **Warning copy:** free-tier keys train on prompts and allow human review; the service is 18+ only; it isn't medical advice.
- **Default model:** `gemini-3.8-flash`, with `gemini-3.5-flash-lite` as the budget option.
- **Hosted Gemini via Firebase AI Logic + App Check** only if the app goes public. That adds a Firebase dependency and affects the Data safety form.
