// The evals' test bench: demo data at a fixed clock, the real coach stack
// (CoachServiceImpl + CoachRepositoryImpl + tools + verifier + policy) and a
// scripted LLM that stands in for Claude / Gemini. No network, ever.

import 'dart:async';

import 'package:airlog/data/coach/coach_module.dart';
import 'package:airlog/data/coach/offline_client.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/prompts.dart';

/// The fixed "now" every eval runs at (demo data ends today).
final kEvalNow = DateTime(2026, 9, 29, 9);

/// Cloud settings with consent, 18+ and a budget the evals never hit.
final kCloudSettings = CoachSettings(
  provider: CoachProvider.claude,
  consentAt: DateTime(2026, 9, 1),
  consentVersion: 1,
  adultConfirmed: true,
  dailyRequestLimit: 1000000,
  dailyTokenLimit: 1000000000,
);

class Bench {
  Bench._(this.health, this.module);

  final InMemoryHealthRepository health;
  final CoachModule module;

  static Bench offline({CoachSettings settings = const CoachSettings()}) {
    final h = InMemoryHealthRepository.demo(now: kEvalNow);
    return Bench._(
      h,
      CoachModule.inMemory(h, clock: () => kEvalNow, settings: settings),
    );
  }

  /// A cloud-configured coach whose client is [llm].
  static Bench cloud(LlmClient llm, {CoachSettings? settings}) {
    final h = InMemoryHealthRepository.demo(now: kEvalNow);
    return Bench._(
      h,
      CoachModule.inMemory(
        h,
        clock: () => kEvalNow,
        settings: settings ?? kCloudSettings,
        clients: (_, _, _) => llm,
        keys: const {CoachProvider.claude: 'sk-ant-test-FAKEKEY123'},
      ),
    );
  }

  Future<ChatMessage> ask(String q, {AskContext? context}) =>
      module.service.ask(q, context: context);
}

/// One request the scripted LLM received.
class LlmRequest {
  LlmRequest(this.system, this.transcript, this.tools);
  final String system;
  final List<LlmItem> transcript;
  final List<CoachToolSpec> tools;

  bool get isRepair => transcript.whereType<LlmUser>().any(
    (u) => u.text.startsWith(CoachPrompts.repairMarker),
  );

  /// Data attached to user messages (the card seed) and tool results in
  /// this request.
  List<ToolResult> get results => [
    for (final i in transcript)
      if (i is LlmUser) ...i.data else if (i is LlmToolResults) ...i.results,
  ];
}

/// A stand-in for a cloud model: [script] decides each turn.
class ScriptedLlm implements LlmClient {
  ScriptedLlm(this.script, {this.provider = CoachProvider.claude});

  final FutureOr<LlmTurn> Function(LlmRequest request, int turn) script;
  final List<LlmRequest> requests = [];

  @override
  final CoachProvider provider;

  @override
  String get model => 'scripted-fake';

  @override
  Future<LlmTurn> next({
    required String system,
    required List<LlmItem> transcript,
    required List<CoachToolSpec> tools,
    required ResponseLength length,
  }) async {
    final r = LlmRequest(system, List.of(transcript), tools);
    requests.add(r);
    return script(r, requests.length - 1);
  }
}

/// What the deterministic engine would do for this request: its tool calls
/// on the first turn, its grounded answer after. Scripted fakes start from
/// it and then misbehave.
Future<LlmTurn> offlineTurn(LlmRequest r) => const OfflineClient().next(
  system: r.system,
  transcript: r.transcript,
  tools: r.tools,
  length: ResponseLength.brief,
);
