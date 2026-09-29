# 06c: On-device LLM options (sub-agent report, 2026-09-29)

## Gemini Nano (ML Kit GenAI Prompt API)
- **Status:** `com.google.mlkit:genai-prompt:1.0.0-beta4` (2026-07-21) is **Beta**. Structured output is **Alpha** and Kotlin/KSP-only. The `tools` field is experimental and undocumented.
- **Limits:**
  - under 4,000 input tokens (system instructions included) and up to 4K output;
  - no multi-turn;
  - foreground only;
  - per-app quotas that aren't published.
- **Devices** (developers.google.com/ml-kit/genai, 2026-09-24):
  - Pixel 9, 10 and 11;
  - Galaxy S26 and the 2025–26 foldables;
  - various Chinese-brand flagships.
  - **Not supported:** Pixel 8, the a-series, Galaxy S25 (feature-specific APIs only) and mainstream mid-range phones.
- **Reach:** an estimated **~5–15% of Android Air owners** (UNVERIFIED: this is an estimate).
- **Terms:** 18+ only, no medical advice or clinical use, and Preview/Experimental features aren't allowed in production.
- **Flutter:** there's no official plugin. The recommended route is a thin Kotlin + Pigeon bridge.

## Gemma via LiteRT-LM or flutter_gemma
- Gemma 4 E2B (Apache-2.0) is a 2.0–2.6 GB download, and Google Gallery sets a minimum of 8 GB RAM.
- On a Pixel 8 it runs at about 11 tok/s (one community report). Mid-range GPU paths are fragile.
- The download is too big for one Play AI pack (1.5 GB cap).
- MediaPipe LLM Inference is in maintenance mode, and the AI Edge function-calling SDK is deprecated.

## llama.cpp (llamadart and others)
It works, but you own the whole stack (models, templates, grammars, per-SoC quirks) and gain no quality advantage.

## Evidence on small models
- **BFCL:** Gemma 3 1B scores 7.2% and Gemma 3 4B 19.6%.
- **WearableQA (2026-09):** small models score about 20% (chance is 10%).
- **Tools help a lot:** GPT-5.4 went from 51% to 71% with a Python tool, and PHIA reached 84% with code tools.
- So small models must not compute or compare numbers.

## Decision
- **v1 base: a deterministic on-device "Ask"**, with no model. Intent routing picks from the same read-only tools, and templated answers carry numbers the verifier checks. It works for every user.
- **Optional upgrade:** Claude or Gemini with the user's own key.
- **v1.5:** Gemini Nano, only as a phrasing layer over pre-computed facts, gated by `checkStatus()`.
- **v2:** Gemma 4 E2B, after benchmarking on real mid-range phones.
