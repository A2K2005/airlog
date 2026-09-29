// Fixtures for the coach ("Ask") screens.
//
//  * FakeCoachRepository  CoachRepository in memory; records every call, so a
//                         test can prove nothing was saved without a tap.
//  * FakeCoachService     CoachService with scripted answers:
//                           verified (with refs) · fallback · safety ·
//                           error (thrown, or stored as `error`) · memory
//                         and an optional hold, to see the waiting state.
//  * pumpCoach            pumps a screen at 412×915 (or any size) with the
//                         real theme, the coach routes, a fixed clock and a
//                         log of every other route pushed.

import 'dart:async';

import 'package:airlog/app/providers.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/insight_contracts.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/coach/coach_history_screen.dart';
import 'package:airlog/features/coach/coach_memory_screen.dart';
import 'package:airlog/features/coach/coach_screen.dart';
import 'package:airlog/features/coach/coach_settings_screen.dart';
import 'package:airlog/features/coach/coach_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_repo.dart';

/// Monday 28 September 2026, 19:30: the coach goldens' clock.
final kCoachNow = DateTime(2026, 9, 28, 19, 30);
const kCoachToday = '2026-09-28';
const kCoachPhone = Size(412, 915);

// ── scripted answers ──────────────────────────────────────────────────────

/// What the fake answers next.
enum Scripted {
  verified,
  fallback,
  safety,
  memory,

  /// A health-history proposal whose words the category guess misses.
  sensitiveMemory,
  errorMessage,
  cloud,

  /// Opus 5.5 was busy: Sonnet 5.5 (the next model) answered.
  viaBackup,

  /// Every Claude model was busy: answered on this phone.
  onDeviceFallback,
}

abstract final class CoachScript {
  static const verifiedText =
      'Your Recovery is 64 % today [r1], a little under your usual. HRV was '
      '52 ms [r2], below your 30-night range, and you slept 6h 40m [r3]. A '
      'lighter day would suit it.';

  static const refs = <SourceRef>[
    SourceRef(
      id: 'r1',
      label: 'Recovery · Mon 28 Sep',
      value: 64,
      unit: '%',
      date: kCoachToday,
      route: Routes.recovery,
    ),
    SourceRef(
      id: 'r2',
      label: 'HRV · Mon 28 Sep',
      value: 52,
      unit: 'ms',
      date: kCoachToday,
      route: Routes.recovery,
    ),
    SourceRef(
      id: 'r3',
      label: 'Sleep · Sun 27 Sep',
      value: 400,
      unit: 'min',
      date: '2026-09-27',
      route: Routes.sleep,
    ),
  ];

  static const fallbackText =
      "I couldn't check every number in my answer, so here are the facts "
      'from your data:\n'
      '- Recovery · Mon 28 Sep: 64 % [r1]\n'
      '- HRV · Mon 28 Sep: 52 ms [r2]';

  static const safetyText =
      "I can't help with chest pain here. If you have chest pain, faint, or "
      'find it hard to breathe, call your local emergency number now. '
      'Airlog is a wellness app and cannot assess symptoms.';

  static const memoryText =
      'Good luck with the half marathon. Your Recovery is 64 % today [r1], '
      'so a steady run fits.';

  static const memoryFact = 'Training for a half marathon on 15 Nov';

  /// The model tags it healthHistory; guessCategory() would say
  /// preferences, so only the model's category triggers the confirm.
  static const sensitiveFact = 'Gets migraines after short nights';

  static const sent = SentPayload(
    provider: CoachProvider.claude,
    model: 'claude-opus-5-5',
    toolsCalled: ['get_day', 'get_range'],
    dataTypes: ['Recovery (1 day)', 'HRV (30 nights)', 'Sleep (1 night)'],
    approxChars: 4200,
  );

  static ChatMessage answer(
    Scripted kind, {
    required String id,
    required String conversationId,
    required DateTime at,
  }) => switch (kind) {
    Scripted.verified => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: verifiedText,
      at: at,
      refs: refs,
      verification: const Verification(
        checkedNumbers: 3,
        unsupported: [],
        repaired: false,
      ),
    ),
    Scripted.cloud => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: verifiedText,
      at: at,
      refs: refs,
      verification: const Verification(
        checkedNumbers: 3,
        unsupported: [],
        repaired: false,
      ),
      sent: sent,
    ),
    Scripted.viaBackup => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: verifiedText,
      at: at,
      refs: refs,
      verification: const Verification(
        checkedNumbers: 3,
        unsupported: [],
        repaired: false,
      ),
      sent: sent,
      answeredBy: 'claude-sonnet-5-5',
      fallbackFrom: 'claude-opus-5-5',
      fallbackReason: 'server',
    ),
    Scripted.onDeviceFallback => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: verifiedText,
      at: at,
      refs: refs,
      verification: const Verification(
        checkedNumbers: 3,
        unsupported: [],
        repaired: false,
      ),
      sent: sent,
      answeredBy: ChatMessage.onDevice,
      fallbackFrom: 'claude-opus-5-5',
      fallbackReason: 'server',
    ),
    Scripted.fallback => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: fallbackText,
      at: at,
      refs: refs.take(2).toList(),
      verification: const Verification(
        checkedNumbers: 2,
        unsupported: ['a 5 am run on Sunday'],
        repaired: true,
      ),
    ),
    Scripted.safety => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: safetyText,
      at: at,
      safety: true,
    ),
    Scripted.memory => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: memoryText,
      at: at,
      refs: refs.take(1).toList(),
      verification: const Verification(
        checkedNumbers: 1,
        unsupported: [],
        repaired: false,
      ),
      proposedMemories: const [memoryFact],
    ),
    Scripted.sensitiveMemory => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: memoryText,
      at: at,
      refs: refs.take(1).toList(),
      verification: const Verification(
        checkedNumbers: 1,
        unsupported: [],
        repaired: false,
      ),
      proposedMemories: const [sensitiveFact],
      proposedCategories: const ['healthHistory'],
    ),
    Scripted.errorMessage => ChatMessage(
      id: id,
      conversationId: conversationId,
      role: ChatRole.assistant,
      text: '',
      at: at,
      error: CoachErrorKind.rateLimited.name,
    ),
  };
}

// ── repository ────────────────────────────────────────────────────────────

class FakeCoachRepository implements CoachRepository {
  FakeCoachRepository({
    CoachSettings settings = const CoachSettings(),
    Map<CoachProvider, String>? keys,
    List<MemoryFact>? memories,
    this.memoryOn = true,
    DateTime Function()? clock,
  }) : _cur = settings,
       keys = keys ?? {},
       _memories = memories ?? [],
       _clock = clock ?? (() => kCoachNow);

  CoachSettings _cur;
  final Map<CoachProvider, String> keys;
  final List<MemoryFact> _memories;
  bool memoryOn;
  final DateTime Function() _clock;

  final convs = <Conversation>[];
  final msgs = <String, List<ChatMessage>>{};

  /// Every call, in order ('saveSettings', 'addMemory:…', …).
  final calls = <String>[];
  var _n = 0;

  CoachSettings get current => _cur;
  List<MemoryFact> get memoryList => List.unmodifiable(_memories);

  /// Adds a stored conversation with [messages] (for history and goldens).
  Conversation seedConversation(
    String title,
    List<ChatMessage> Function(String id) messages, {
    DateTime? at,
  }) {
    final id = 'c${++_n}';
    final when = at ?? _clock();
    final c = Conversation(
      id: id,
      title: title,
      createdAt: when,
      updatedAt: when,
    );
    convs.add(c);
    msgs[id] = messages(id);
    return c;
  }

  @override
  Future<CoachSettings> settings() async => _cur;

  @override
  Future<void> saveSettings(CoachSettings s) async {
    calls.add('saveSettings');
    _cur = s;
  }

  @override
  Future<bool> hasApiKey(CoachProvider p) async => keys.containsKey(p);

  @override
  Future<void> saveApiKey(CoachProvider p, String key) async {
    calls.add('saveApiKey:${p.name}');
    keys[p] = key;
  }

  @override
  Future<void> deleteApiKey(CoachProvider p) async {
    calls.add('deleteApiKey:${p.name}');
    keys.remove(p);
  }

  @override
  Future<List<Conversation>> conversations() async =>
      [...convs]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
    ...?msgs[conversationId],
  ];

  @override
  Future<Conversation> createConversation(String title) async {
    calls.add('createConversation');
    final c = Conversation(
      id: 'c${++_n}',
      title: title,
      createdAt: _clock(),
      updatedAt: _clock(),
    );
    convs.add(c);
    msgs[c.id] = [];
    return c;
  }

  @override
  Future<void> appendMessage(ChatMessage m) async {
    calls.add('appendMessage:${m.role.name}');
    (msgs[m.conversationId] ??= []).add(m);
  }

  @override
  Future<void> deleteConversation(String id) async {
    calls.add('deleteConversation:$id');
    convs.removeWhere((c) => c.id == id);
    msgs.remove(id);
  }

  @override
  Future<void> deleteAllConversations() async {
    calls.add('deleteAllConversations');
    convs.clear();
    msgs.clear();
  }

  @override
  Future<List<MemoryFact>> memories() async => [..._memories];

  @override
  Future<MemoryFact> addMemory(
    String text, {
    MemoryCategory category = MemoryCategory.preferences,
    String? expiresOn,
  }) async {
    calls.add('addMemory:${category.name}:$text');
    final m = MemoryFact(
      id: 'm${++_n}',
      text: text,
      createdAt: _clock(),
      category: category,
      expiresOn: expiresOn,
    );
    _memories.add(m);
    return m;
  }

  @override
  Future<void> updateMemory(
    String id,
    String text, {
    MemoryCategory? category,
    String? expiresOn,
  }) async {
    calls.add('updateMemory:$id');
    final i = _memories.indexWhere((m) => m.id == id);
    if (i < 0) return;
    final old = _memories[i];
    _memories[i] = MemoryFact(
      id: id,
      text: text,
      createdAt: old.createdAt,
      updatedAt: _clock(),
      category: category ?? old.category,
      expiresOn: expiresOn,
    );
  }

  @override
  Future<bool> memoryEnabled() async => memoryOn;

  @override
  Future<void> setMemoryEnabled(bool on) async {
    calls.add('setMemoryEnabled:$on');
    memoryOn = on;
  }

  @override
  Future<void> deleteMemory(String id) async {
    calls.add('deleteMemory:$id');
    _memories.removeWhere((m) => m.id == id);
  }

  @override
  Future<LlmClient> client() async =>
      throw const CoachException(CoachErrorKind.notConfigured);

  @override
  Future<List<LlmClient>> modelChain() async =>
      throw const CoachException(CoachErrorKind.notConfigured);

  @override
  LlmClient onDeviceClient() =>
      throw UnimplementedError('The UI fakes have no on-device engine.');

  /// Models the test says are down (the "Ask again" action hides).
  final Map<String, ModelDown> down = {};

  @override
  Future<void> noteModelUnavailable(String model, ModelUnavailable e) async {}

  @override
  Future<ModelDown?> modelDown(String model) async => down[model];

  /// Today's cloud usage; null = offline or not tracked.
  CoachUsage? usage;

  @override
  Future<CoachUsage?> usageToday() async => usage;
}

// ── service ───────────────────────────────────────────────────────────────

class FakeCoachService implements CoachService {
  FakeCoachService(this.repo, {List<Object>? script, this.storeUser = true})
    : script = script ?? [];

  final FakeCoachRepository repo;

  /// Next answers, in order: a [Scripted] or a [CoachException] to throw.
  /// Empty = [Scripted.verified].
  final List<Object> script;

  /// Whether ask() stores the user's question too (as a real service does).
  final bool storeUser;

  /// Hold every answer until [release] (the waiting state).
  bool hold = false;
  Completer<void>? _gate;

  final asked = <(String, String?, AskContext?)>[];
  final suggestionContexts = <AskContext?>[];

  List<String> starters = const [
    'How did I sleep last night?',
    'Why is my Recovery lower today?',
    'How hard was my last workout?',
  ];

  var _n = 0;

  void release() {
    _gate?.complete();
    _gate = null;
  }

  @override
  Future<ChatMessage> ask(
    String question, {
    String? conversationId,
    AskContext? context,
  }) async {
    asked.add((question, conversationId, context));
    if (hold) {
      _gate = Completer<void>();
      await _gate!.future;
    }
    final next = script.isEmpty ? Scripted.verified : script.removeAt(0);
    final convId =
        conversationId ??
        (await repo.createConversation(
          question.length > 40 ? question.substring(0, 40) : question,
        )).id;
    final at = repo._clock();
    if (storeUser) {
      await repo.appendMessage(
        ChatMessage(
          id: 'u${++_n}',
          conversationId: convId,
          role: ChatRole.user,
          text: question,
          at: at,
        ),
      );
    }
    if (next is CoachException) throw next;
    final m = CoachScript.answer(
      next as Scripted,
      id: 'a${++_n}',
      conversationId: convId,
      at: at,
    );
    await repo.appendMessage(m);
    return m;
  }

  @override
  Future<List<String>> suggestions({AskContext? context}) async {
    suggestionContexts.add(context);
    return starters;
  }
}

// ── insight cards ─────────────────────────────────────────────────────────

/// Scripted insight cards for kCoachToday.
abstract final class InsightScript {
  static final sleep = Insight(
    id: 'sleep:$kCoachToday',
    kind: InsightKind.sleep,
    date: kCoachToday,
    createdAt: DateTime(2026, 9, 28, 7, 10),
    headline: "Here's how you slept",
    body:
        '7h 12m asleep, 40 minutes more than your usual. You woke twice, '
        'both briefly.',
    bullets: const [
      InsightBullet('Timing', 'Asleep at 23:05, close to your usual time.'),
      InsightBullet('Consistency', '5 of 7 nights within 30 minutes.'),
    ],
    // Chips in the templates' "<what> · <day>" style (insight_templates.dart
    // builds 'Asleep · Mon 28 Sep'); Airlog has no sleep score.
    metrics: const [
      SourceRef(
        id: 's1',
        label: 'Asleep · Mon 28 Sep',
        value: 432,
        unit: 'min',
        date: kCoachToday,
        route: Routes.sleep,
      ),
      SourceRef(
        id: 's3',
        label: 'Usual sleep · 30 nights',
        value: 392,
        unit: 'min',
        route: Routes.trends,
      ),
    ],
    refs: const [
      SourceRef(
        id: 's1',
        label: 'Asleep · Mon 28 Sep',
        value: 432,
        unit: 'min',
        date: kCoachToday,
        route: Routes.sleep,
      ),
      SourceRef(
        id: 's2',
        label: 'Awake · Mon 28 Sep',
        value: 11,
        unit: 'min',
        date: kCoachToday,
        route: Routes.sleep,
      ),
      SourceRef(
        id: 's3',
        label: 'Usual sleep · 30 nights',
        value: 392,
        unit: 'min',
        route: Routes.trends,
      ),
    ],
    route: Routes.sleep,
  );

  /// An AI-reworded card that used memory 'f1'.
  static final recoveryAi = Insight(
    id: 'recovery:$kCoachToday',
    kind: InsightKind.recovery,
    date: kCoachToday,
    createdAt: DateTime(2026, 9, 28, 7, 30),
    headline: 'A lighter day suits you',
    body:
        'Recovery is 64 %, a little under your usual, with HRV at 52 ms. '
        'With your half marathon ahead, an easy run keeps the plan on track.',
    metrics: const [
      SourceRef(
        id: 'r1',
        label: 'Recovery',
        value: 64,
        unit: '%',
        date: kCoachToday,
        route: Routes.recovery,
      ),
      SourceRef(
        id: 'r2',
        label: 'HRV',
        value: 52,
        unit: 'ms',
        date: kCoachToday,
        route: Routes.recovery,
      ),
    ],
    refs: CoachScript.refs.take(2).toList(),
    source: InsightSource.llm,
    usedMemoryIds: const ['f1'],
    verification: const Verification(
      checkedNumbers: 2,
      unsupported: [],
      repaired: false,
    ),
    route: Routes.recovery,
  );

  static final strain = Insight(
    id: 'strain:$kCoachToday',
    kind: InsightKind.strain,
    date: kCoachToday,
    createdAt: DateTime(2026, 9, 28, 6, 0),
    headline: 'A moderate day so far',
    body: 'Strain is 9.4, in your usual range for a Monday.',
    metrics: const [
      SourceRef(
        id: 't1',
        label: 'Strain',
        value: 9.4,
        date: kCoachToday,
        route: Routes.strain,
      ),
    ],
    route: Routes.strain,
  );
}

/// InsightService in memory. Records every feedback and level change;
/// [watchDay] emits again after each change (hidden cards drop out).
class FakeInsightService implements InsightService {
  FakeInsightService({
    List<Insight>? insights,
    this.current = InsightLevel.basic,
  }) : all = insights ?? [];

  final List<Insight> all;
  InsightLevel current;

  final feedback = <(String, InsightFeedback)>[];
  final levels = <InsightLevel>[];
  final watched = <String>[];
  final _changes = StreamController<void>.broadcast();

  /// Replaces the cards and emits.
  void emit(List<Insight> cards) {
    all
      ..clear()
      ..addAll(cards);
    _changes.add(null);
  }

  List<Insight> _day(String date) => [
    for (final i in all)
      if (i.date == date && i.feedback != InsightFeedback.hidden) i,
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Stream<List<Insight>> watchDay(String date) async* {
    watched.add(date);
    yield _day(date);
    await for (final _ in _changes.stream) {
      yield _day(date);
    }
  }

  @override
  Future<void> setFeedback(String insightId, InsightFeedback f) async {
    feedback.add((insightId, f));
    final i = all.indexWhere((x) => x.id == insightId);
    if (i >= 0) all[i] = all[i].copyWith(feedback: f);
    _changes.add(null);
  }

  @override
  Future<InsightLevel> level() async => current;

  @override
  Future<void> setLevel(InsightLevel level) async {
    levels.add(level);
    current = level;
  }
}

// ── pumping ───────────────────────────────────────────────────────────────

/// Pushed routes that are not the coach's own, in order.
final class RouteLog {
  final pushed = <RouteSettings>[];
  List<String?> get names => [for (final r in pushed) r.name];
}

class CoachStubPage extends StatelessWidget {
  const CoachStubPage(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text('route $name')));
}

Route<dynamic> Function(RouteSettings) coachRouter(RouteLog log) =>
    (s) => MaterialPageRoute<dynamic>(
      settings: s,
      builder: (_) {
        switch (s.name) {
          case Routes.coach:
            return const CoachScreen();
          case Routes.coachSetup:
            return const CoachSetupScreen();
          case Routes.coachMemory:
            return const CoachMemoryScreen();
          case Routes.coachHistory:
            return const CoachHistoryScreen();
          case Routes.settingsCoach:
            return const CoachSettingsScreen();
        }
        log.pushed.add(s);
        return CoachStubPage(s.name ?? '');
      },
    );

/// The overrides every coach test needs.
List<Override> coachOverrides(
  FakeCoachRepository repo,
  CoachService service, {
  HealthRepository? health,
  DateTime Function()? clock,
  InsightService? insights,
}) => [
  coachRepositoryProvider.overrideWithValue(repo),
  coachServiceProvider.overrideWithValue(service),
  insightServiceProvider.overrideWithValue(insights ?? FakeInsightService()),
  healthRepositoryProvider.overrideWithValue(health ?? FakeRepo()),
  clockProvider.overrideWithValue(clock ?? () => kCoachNow),
];

/// Pumps [home] as the first route (or [initial] pushed over a blank home,
/// with [arguments]) on a phone-sized view.
Future<RouteLog> pumpCoach(
  WidgetTester t, {
  required FakeCoachRepository repo,
  CoachService? service,
  Widget? home,
  String? initial,
  Object? arguments,
  Brightness brightness = Brightness.dark,
  Size size = kCoachPhone,
  double textScale = 1,
  HealthRepository? health,
  InsightService? insights,
  List<Override> extra = const [],
  bool reduceMotion = false,
}) async {
  t.view.physicalSize = size * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  final log = RouteLog();
  final key = GlobalKey<NavigatorState>();
  await t.pumpWidget(
    ProviderScope(
      overrides: [
        ...coachOverrides(
          repo,
          service ?? FakeCoachService(repo),
          health: health,
          insights: insights,
        ),
        ...extra,
      ],
      child: MaterialApp(
        navigatorKey: key,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(brightness),
        onGenerateRoute: coachRouter(log),
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: w!,
        ),
        home: home ?? const _Blank(),
      ),
    ),
  );
  if (initial != null) {
    unawaited(key.currentState!.pushNamed(initial, arguments: arguments));
  }
  await t.pumpAndSettle();
  return log;
}

class _Blank extends StatelessWidget {
  const _Blank();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('home')));
}

/// The ProviderContainer behind the widget tree.
ProviderContainer coachContainer(WidgetTester t) =>
    ProviderScope.containerOf(t.element(find.byType(Navigator).first));
