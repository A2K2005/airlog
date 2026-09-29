# Coach memory and grounded personalization

## What Coach can know

Coach has two distinct inputs. Confirmed memory contains facts the user chose to save: goals, preferences, events and other context. Health evidence is read fresh from recorded days, scores, journal entries and their existing tool results. We do not turn measurements into permanent biographical facts or claim complete knowledge of a person.

For recognized personalized cloud questions in **Use my data**, the app retrieves a bounded context before the first model request:

- Up to 20 relevant confirmed memories, when memory is on.
- Today's recorded summary, including missing-data notes.
- A 28-calendar-day relevant metric window: sleep duration, strain or Recovery, with existing coverage, trend and baseline evidence.
- Journal associations for habit/stress questions, or training load for training questions.

This uses existing tool implementations and their citation refs. It does not add a model request. The model can request a different metric/window when needed, within the existing 90-day tool window and request budget. Keyword routing is deliberately limited, not semantic understanding of every phrasing. On-device coaching remains the deterministic existing router/templates; it is not a personalized language model.

## Memory retrieval and lifecycle

`MemoryContext` ranks active facts by question-word overlap, then most recently confirmed. Stable IDs, category, user-confirmed provenance, confirmation timestamp, optional expiry and review status accompany the quoted text. The payload reports omitted facts and says it is not a complete biography. Expired memories are not retrieved. Text is capped at the repository's full 300-character limit, not silently truncated at 200.

Review intervals are product heuristics, not clinical thresholds: mood after 7 days, events after 30, health history after 90, goals after 180, and other categories after 365. Stale does not mean false. Such facts are labelled historical and must be reconfirmed before advice relies on them as current. Only fresh memories actually retrieved in this answer may ground the verifier's user-context exceptions. Numbers about measured health must still come from measured evidence.

Explicit correction phrases (for example "actually", "no longer", "I now" or "I do not") omit all saved-memory and earlier-chat context for that answer, instead of guessing which old fact conflicts. This is enforced before evidence verification, not only requested in a prompt. Other conflicting saved statements remain separate, timestamped facts; the model is instructed to ask rather than silently choose or merge them. This heuristic cannot detect every paraphrase or contradiction. A correction in chat does not silently persist: the user edits or deletes the existing fact in **What Coach knows**. Editing replaces that ID and advances its revision timestamp. Identical repeated confirmations reuse the existing fact. Invalid calendar expiry dates are rejected.

Proposals require content grounded in the current user statement and still save nothing until confirmation. The existing sensitive-category confirmation remains. Proposed expiry now survives tool result, message persistence and the Remember action; it is displayed before confirmation. There is no silent profile inference or model-driven deletion.

## Answer contract

Answer directly, explain the strongest recorded observation, incorporate a relevant confirmed preference when useful, and offer one practical next step only when supported. No generic wellness checklist, praise filler or fabricated certainty. Separate observations, user statements, journal associations and unknowns. Missing days are not zero or rest; journal associations are not causes.

All numeric health claims still pass existing source verification and output-policy checks. Failed output gets one repair attempt, then deterministic cited facts. These checks do not prove every qualitative sentence correct, nor guarantee prose quality from every live model response.

## Privacy boundaries

General-only gets no personal preload, health tools, history or memories. Memory-off disables memory retrieval/proposals but not consented health-data tools. Cloud history is scoped to provider, mode, sample/live state, current payload contract and memory context. Edits, deletions, expiry and transition into stale status prevent old memory-bearing history being replayed. Previously sent provider data cannot be recalled.

All automatic health retrieval uses the same source firewall. Mixed Google Health API history fails closed for cloud health tools; original insight cards remain local. Confirmed text and current question text are user-authored and not automatically redacted. Consent is rechecked before sends and revocation guards later HTTP retries. Metadata attached to an answer is evidence for that request, not a continuously synchronized biography.

## Regression evidence

`test/domain/coach/personal_context_test.dart` checks actual first-request evidence, 28-day coverage, verified versus fabricated answers, mode/memory boundaries, timestamps, stale and expired facts, bounded conflicting-context retrieval, edits/deletion and duplicate/date validation. Existing service tests cover history invalidation, consent changes and proposal expiry persistence. Privacy regressions cover source withholding and asynchronous revocation/deletion boundaries.

Live-provider answer quality, real Android secure-storage behavior and paraphrases beyond deterministic routing require device/live QA. Automated tests use deterministic clients and do not establish that the app understands everything about a user.
