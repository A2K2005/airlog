// LIVE eval: opt-in, bring your own key, and it COSTS MONEY. Not part of
// CI or `flutter test` (it lives in tool/). It runs the golden grounding set
// (test/evals/data/golden_grounding.jsonl) against Claude or Gemini on DEMO
// data only (never your own data), through the real coach stack: tools,
// verifier, output policy, repair round, facts-table fallback, and the
// daily budget meter. It reports the pass rate, tokens and an estimated
// cost. It also replaces the earlier tool/coach_smoke.dart idea.
//
//   ANTHROPIC_API_KEY=sk-ant-... flutter test tool/eval_live.dart
//   GEMINI_API_KEY=...           flutter test tool/eval_live.dart \
//       --dart-define=EVAL_PROVIDER=gemini
//   options: --dart-define=EVAL_MODEL=claude-sonnet-5-5
//            --dart-define=EVAL_LIMIT=10   (first N questions)
//            --dart-define=EVAL_DELAY_MS=13000  (pause between questions;
//              default 20000 for Gemini, 0 for Claude: each question makes
//              2-3 requests and low-tier Gemini keys allow ~5 a minute)
//            --dart-define=EVAL_COOLDOWN_MS=60000  (extra pause after a
//              rate-limited or busy answer, so one 429 does not cascade)
//            --dart-define=EVAL_BACKUPS=false  (no backup models: measure
//              only the chosen model; failures still answer on-device)
//
// Without the key it prints how to run it and does nothing. The key is read
// from the environment only: never printed, logged or written anywhere.
// Gemini: use a key from a billing-enabled (paid) project; free-tier
// prompts may be used for training and read by human reviewers.
// See docs/EVALS.md.

import 'dart:convert';
import 'dart:io';

import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/coach/provider_models.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/coach_service.dart';
import 'package:airlog/domain/coach/policy.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore_for_file: avoid_print

const _gemini = String.fromEnvironment('EVAL_PROVIDER') == 'gemini';

/// Pause between questions (-1 = the provider's default).
const _delayMsDefine = int.fromEnvironment('EVAL_DELAY_MS', defaultValue: -1);
const _delayMs = _delayMsDefine >= 0 ? _delayMsDefine : (_gemini ? 20000 : 0);

/// Extra pause after a rate-limited / busy answer.
const _cooldownMs = int.fromEnvironment(
  'EVAL_COOLDOWN_MS',
  defaultValue: 60000,
);

/// 45 min of questions plus the pauses (and a cooldown per question, worst
/// case) between them.
final evalTimeout =
    const Duration(minutes: 45) +
    const Duration(milliseconds: _delayMs + _cooldownMs) * 60;

void main() {
  test('live eval (opt-in)', () async {
    const gemini = _gemini;
    final provider = gemini ? CoachProvider.gemini : CoachProvider.claude;
    final envKey = gemini ? 'GEMINI_API_KEY' : 'ANTHROPIC_API_KEY';
    final key = Platform.environment[envKey];
    if (key == null || key.trim().isEmpty) {
      print(
        'eval_live: skipped. Set $envKey to run it (it costs money). '
        'See docs/EVALS.md.',
      );
      return;
    }
    const m = String.fromEnvironment('EVAL_MODEL');
    final model = m.isEmpty ? ProviderModels.defaultFor(provider)! : m;
    const limit = int.fromEnvironment('EVAL_LIMIT', defaultValue: 1000);
    const delayMs = _delayMs;

    // Demo data only, at a fixed clock.
    final now = DateTime(2026, 9, 29, 9);
    final health = InMemoryHealthRepository.demo(now: now);
    final coach = CoachModule.inMemory(
      health,
      clock: () => now,
      settings: CoachSettings(
        provider: provider,
        model: model,
        consentAt: now,
        consentVersion: kCoachConsentVersion,
        adultConfirmed: true,
        dailyRequestLimit: 100000,
        dailyTokenLimit: 1000000000,
        backupModels: const bool.fromEnvironment(
          'EVAL_BACKUPS',
          defaultValue: true,
        ),
      ),
      keys: {provider: key.trim()},
    );

    final rows = [
      for (final line in File(
        'test/evals/data/golden_grounding.jsonl',
      ).readAsLinesSync())
        if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
    ].take(limit).toList();

    var pass = 0, verified = 0, repaired = 0, fallback = 0, errors = 0;
    // Error answers by kind: busy (server), rate-limited, anything else.
    var errServer = 0, errRate = 0, errOther = 0;
    // Which engine wrote each answer (model fallback: a backup model of the
    // same provider, or on-device); errors are tallied as "error".
    final byModel = <String, int>{};
    var onDevice = 0;
    final out = StringBuffer();
    for (final (i, r) in rows.indexed) {
      if (i > 0 && delayMs > 0) {
        await Future<void>.delayed(const Duration(milliseconds: delayMs));
      }
      final ctx = r['screen'] == null && r['date'] == null
          ? null
          : AskContext(
              screen: r['screen'] as String?,
              date: r['date'] as String?,
            );
      final a = await coach.service.ask(r['q'] as String, context: ctx);
      final v = a.verification;
      final isFallback = a.text.startsWith('I couldn\'t');
      final by = a.error != null ? 'error' : a.answeredBy ?? model;
      byModel[by] = (byModel[by] ?? 0) + 1;
      final local = a.answeredBy == ChatMessage.onDevice;
      if (local) onDevice++;
      // An on-device fallback answer is verified by construction: it says
      // nothing about the model, so it never counts as a pass.
      final ok =
          a.error == null &&
          !local &&
          (v?.verified ?? false) &&
          !(v?.repaired ?? true) &&
          OutputPolicy.check(a.text).ok;
      if (ok) pass++;
      if (v?.verified ?? false) verified++;
      if (v?.repaired ?? false) repaired++;
      if (isFallback) fallback++;
      if (a.error != null) {
        errors++;
        switch (a.error) {
          case 'server':
            errServer++;
          case 'rateLimited':
            errRate++;
          default:
            errOther++;
        }
      }
      // Busy or rate-limited (an error, or the reason the coach fell back to
      // a backup model / this phone): back off before the next question so
      // the per-minute window can refill (the clients already retried twice).
      const busy = {'server', 'rateLimited'};
      if ((busy.contains(a.error) || busy.contains(a.fallbackReason)) &&
          _cooldownMs > 0 &&
          i < rows.length - 1) {
        await Future<void>.delayed(const Duration(milliseconds: _cooldownMs));
      }
      out.writeln('${ok ? 'PASS' : 'FAIL'} ${r['id']} [$by] ${r['q']}');
      if (a.fellBack) {
        out.writeln(
          '     fell back from ${a.fallbackFrom} '
          '(${a.fallbackReason ?? 'provider-side'})',
        );
      }
      if (!ok) {
        out.writeln(
          '     ${a.error ?? ''} ${v?.unsupported ?? ''} '
          '${a.text.replaceAll('\n', ' ')}',
        );
      }
    }
    final u = await coach.repository.usageToday();
    final cost = u == null
        ? null
        : estimateCostUsd(model, u.inputTokens, u.outputTokens);
    final n = rows.length;
    String pct(int x) => '${(100 * x / (n == 0 ? 1 : n)).toStringAsFixed(1)}%';
    final summary = StringBuffer()
      ..writeln('── live eval: ${provider.name} · $model · demo data ──')
      ..writeln('questions                 $n')
      ..writeln('pass (verified, no repair, policy-clean)  $pass  ${pct(pass)}')
      ..writeln('final answers verified    $verified  ${pct(verified)}')
      ..writeln('needed the repair round   $repaired  ${pct(repaired)}')
      ..writeln('fell back to facts table  $fallback  ${pct(fallback)}')
      ..writeln(
        'errors                    $errors  '
        '(server $errServer · rateLimited $errRate · other $errOther)',
      )
      ..writeln('answered on this phone    $onDevice  ${pct(onDevice)}')
      ..writeln('answered by (per model):')
      ..writeAll([
        for (final e
            in byModel.entries.toList()..sort((a, b) => b.value - a.value))
          '  ${e.key.padRight(24)}${e.value}  ${pct(e.value)}',
      ], '\n')
      ..writeln()
      ..writeln(
        'delay between questions   $delayMs ms (cooldown $_cooldownMs ms)',
      )
      ..writeln('requests                  ${u?.requests ?? 0}')
      ..writeln('input tokens              ${u?.inputTokens ?? 0}')
      ..writeln('output tokens             ${u?.outputTokens ?? 0}')
      ..writeln(
        'estimated cost (USD)      '
        '${cost == null ? 'unknown model' : cost.toStringAsFixed(4)}'
        '${byModel.keys.any((k) => k != model && k != 'error' && k != ChatMessage.onDevice) ? '  (all tokens priced as $model)' : ''}',
      );
    print(summary);
    print(out);
    try {
      final dir = Directory('build/evals')..createSync(recursive: true);
      File('${dir.path}/live_${provider.name}.txt')
          .writeAsStringSync('$summary\n$out');
    } catch (_) {}
  }, timeout: Timeout(evalTimeout));
}
