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
//              free-tier keys allow only a few requests per minute)
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

/// 45 min of questions plus the pauses between them.
const _delayMsDefine = int.fromEnvironment('EVAL_DELAY_MS', defaultValue: 0);
final evalTimeout =
    const Duration(minutes: 45) +
    const Duration(milliseconds: _delayMsDefine) * 60;

void main() {
  test('live eval (opt-in)', () async {
    final gemini = const String.fromEnvironment('EVAL_PROVIDER') == 'gemini';
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
    const delayMs = _delayMsDefine;

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
      final ok =
          a.error == null &&
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
      out.writeln('${ok ? 'PASS' : 'FAIL'} ${r['id']} ${r['q']}');
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
      ..writeln('delay between questions   $delayMs ms')
      ..writeln('requests                  ${u?.requests ?? 0}')
      ..writeln('input tokens              ${u?.inputTokens ?? 0}')
      ..writeln('output tokens             ${u?.outputTokens ?? 0}')
      ..writeln(
        'estimated cost (USD)      '
        '${cost == null ? 'unknown model' : cost.toStringAsFixed(4)}',
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
