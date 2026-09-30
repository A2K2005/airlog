// The insight-card kit (lib/app/insight_card.dart) over a fake
// InsightService: the feed shows nothing unless there is a card to show
// (loading, empty, error, an unwired coach, Coach messages Off, the master
// switch off); at most one card by default; Discuss seeds the chat without
// sending; no votes (v1 has no thumbs); the ⋮ options (hide, why,
// settings); the memory chip; the AI-summary label; "Sample data" in demo
// mode only; the card tap opens its screen on its day; one
// spoken summary; no overflow at 320 px and 1.3× text; 48 dp targets.

import 'dart:async';

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/insight_card.dart';
import 'package:airlog/app/providers.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/insight_contracts.dart';
import 'package:airlog/domain/repositories.dart' show DataMode;
import 'package:airlog/features/coach/coach_memory_screen.dart';
import 'package:airlog/features/coach/coach_screen.dart';
import 'package:airlog/features/coach/coach_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/coach_fixtures.dart';
import '../support/fake_repo.dart';
import '../support/fonts.dart';

final _memories = [
  MemoryFact(
    id: 'f1',
    text: 'Training for a half marathon',
    createdAt: kCoachNow,
    category: MemoryCategory.goals,
  ),
];

Widget _page(Widget child) => Scaffold(
  body: ListView(padding: const EdgeInsets.all(S.gutter), children: [child]),
);

Future<(FakeCoachRepository, FakeInsightService, RouteLog)> _pump(
  WidgetTester t, {
  List<Insight>? cards,
  Widget? child,
  CoachSettings settings = const CoachSettings(),
  InsightLevel level = InsightLevel.basic,
  Size size = kCoachPhone,
  double textScale = 1,
  FakeCoachService? service,
  DataMode mode = DataMode.demo,
}) async {
  final repo = FakeCoachRepository(
    settings: settings,
    memories: [..._memories],
  );
  final insights = FakeInsightService(
    insights: cards ?? [InsightScript.sleep],
    current: level,
  );
  final log = await pumpCoach(
    t,
    repo: repo,
    service: service,
    insights: insights,
    health: FakeRepo(mode: mode),
    size: size,
    textScale: textScale,
    home: _page(child ?? const InsightFeed(date: kCoachToday)),
  );
  return (repo, insights, log);
}

Future<void> _option(WidgetTester t, String label) async {
  await t.tap(find.byKey(const ValueKey('insight-options')).first);
  await t.pumpAndSettle();
  await t.tap(find.text(label));
  await t.pumpAndSettle();
}

class _Silent implements InsightService {
  _Silent(this.stream);
  final Stream<List<Insight>> stream;
  @override
  Stream<List<Insight>> watchDay(String date) => stream;
  @override
  Future<void> setFeedback(String id, InsightFeedback f) async {}
  @override
  Future<InsightLevel> level() async => InsightLevel.basic;
  @override
  Future<void> setLevel(InsightLevel level) async {}
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a card: kind, headline, body, bullets and metrics', (t) async {
    await _pump(t);
    expect(find.byType(InsightCard), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text("Here's how you slept"), findsOneWidget);
    expect(find.textContaining('7h 12m asleep'), findsOneWidget);
    expect(
      find.textContaining('Asleep at 23:05', findRichText: true),
      findsOne,
    );
    expect(find.textContaining('5 of 7 nights', findRichText: true), findsOne);
    expect(
      find.textContaining('Asleep · Mon 28 Sep', findRichText: true),
      findsOne,
    );
    // A template card carries no AI label.
    expect(find.text(InsightCopy.aiSummary), findsNothing);
    expect(find.text(InsightCopy.discuss), findsOneWidget);
  });

  testWidgets('one spoken summary for the text; actions stay separate', (
    t,
  ) async {
    final h = t.ensureSemantics();
    await _pump(t);
    expect(
      find.bySemanticsLabel(
        RegExp(
          r"^Sleep\. Here's how you slept\. 7h 12m asleep.*Timing: "
          r'Asleep at 23:05.*Asleep · Mon 28 Sep 7h 12m\. Usual sleep · 30 '
          r'nights 6h 32m\. Opens the screen\.$',
        ),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel(InsightCopy.discuss), findsOneWidget);
    expect(find.bySemanticsLabel(InsightCopy.options), findsOneWidget);
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    h.dispose();
  });

  testWidgets('the feed shows at most one card by default, newest first', (
    t,
  ) async {
    await _pump(t, cards: [InsightScript.sleep, InsightScript.recoveryAi]);
    expect(find.byType(InsightCard), findsOneWidget);
    expect(find.text('A lighter day suits you'), findsOneWidget);
  });

  testWidgets('max: null shows all; kinds filters', (t) async {
    final cards = [
      InsightScript.sleep,
      InsightScript.recoveryAi,
      InsightScript.strain,
    ];
    await _pump(
      t,
      cards: cards,
      child: const InsightFeed(date: kCoachToday, max: null),
    );
    expect(find.byType(InsightCard), findsNWidgets(3));
    await _pump(
      t,
      cards: cards,
      child: const InsightFeed(
        date: kCoachToday,
        max: null,
        kinds: {InsightKind.sleep, InsightKind.strain},
      ),
    );
    expect(find.byType(InsightCard), findsNWidgets(2));
    expect(find.text('A lighter day suits you'), findsNothing);
  });

  group('nothing to show renders nothing', () {
    testWidgets('no card for the day', (t) async {
      await _pump(t, cards: const []);
      expect(find.byType(InsightCard), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('while loading', (t) async {
      final never = StreamController<List<Insight>>();
      addTearDown(never.close);
      await pumpCoach(
        t,
        repo: FakeCoachRepository(),
        insights: _Silent(never.stream),
        home: _page(const InsightFeed(date: kCoachToday)),
      );
      expect(find.byType(InsightCard), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SkeletonLines), findsNothing);
    });

    testWidgets('on an error', (t) async {
      await pumpCoach(
        t,
        repo: FakeCoachRepository(),
        insights: _Silent(Stream.error(StateError('boom'))),
        home: _page(const InsightFeed(date: kCoachToday)),
      );
      expect(find.byType(InsightCard), findsNothing);
      expect(find.byType(StatusCard), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('an unwired coach (no overrides): no card, Ask still shows', (
      t,
    ) async {
      await t.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: buildTheme(Brightness.dark),
            home: _page(
              Column(
                children: [
                  const InsightFeed(date: kCoachToday),
                  InsightCard(insight: _unwiredCard),
                  const AskAboutThis(screen: 'sleep'),
                  const AskIconButton(screen: 'sleep'),
                ],
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(InsightFeed), findsOneWidget);
      expect(find.text('Unwired'), findsNothing);
      expect(find.text(CoachCopy.askAboutThis), findsOneWidget);
      expect(find.bySemanticsLabel('Ask Coach'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Coach messages Off', (t) async {
      await _pump(t, level: InsightLevel.off);
      expect(find.byType(InsightCard), findsNothing);
    });

    testWidgets('the master switch off hides every entry point', (t) async {
      await _pump(
        t,
        settings: const CoachSettings(enabled: false),
        child: Column(
          children: [
            const InsightFeed(date: kCoachToday),
            InsightCard(insight: InsightScript.strain),
            const AskAboutThis(screen: 'sleep'),
            const AskIconButton(screen: 'sleep'),
          ],
        ),
      );
      expect(find.text("Here's how you slept"), findsNothing);
      expect(find.text('A moderate day so far'), findsNothing);
      expect(find.text(CoachCopy.askAboutThis), findsNothing);
      expect(find.bySemanticsLabel('Ask Coach'), findsNothing);
    });
  });

  testWidgets('Discuss opens the chat seeded with the card; nothing is sent', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    final service = FakeCoachService(repo);
    await _pump(t, service: service);
    await t.tap(find.text(InsightCopy.discuss));
    await t.pumpAndSettle();
    expect(find.byType(CoachScreen), findsOneWidget);
    final args =
        ModalRoute.of(t.element(find.byType(CoachScreen)))!.settings.arguments
            as CoachArgs;
    final ask = args.context!;
    expect(ask.insightId, InsightScript.sleep.id);
    expect(ask.screen, 'sleep');
    expect(ask.date, kCoachToday);
    expect(ask.seedText, startsWith("Here's how you slept\n"));
    expect(ask.seedRefs.map((r) => r.id), ['s1', 's2', 's3']);
    expect(service.asked, isEmpty);
  });

  testWidgets('no votes: v1 cards have no thumbs', (t) async {
    await _pump(t);
    expect(find.byIcon(Icons.thumb_up_outlined), findsNothing);
    expect(find.byIcon(Icons.thumb_down_outlined), findsNothing);
  });

  testWidgets('demo mode: the card says Sample data', (t) async {
    await _pump(t);
    expect(find.byKey(const ValueKey('insight-sample')), findsOneWidget);
    expect(find.text(CoachCopy.sampleData), findsOneWidget);
  });

  testWidgets('live data: no Sample data tag', (t) async {
    await _pump(t, mode: DataMode.live);
    expect(find.byType(InsightCard), findsOneWidget);
    expect(find.text(CoachCopy.sampleData), findsNothing);
  });

  testWidgets('⋮ Hide this card: hidden at once, and stored', (t) async {
    final (_, insights, _) = await _pump(t);
    await _option(t, InsightCopy.hide);
    expect(find.byType(InsightCard), findsNothing);
    expect(find.text(InsightCopy.hidden), findsOneWidget);
    expect(insights.feedback.single, (
      InsightScript.sleep.id,
      InsightFeedback.hidden,
    ));
  });

  testWidgets('⋮ Coach messages settings opens Settings → Coach', (t) async {
    await _pump(t);
    await _option(t, InsightCopy.settings);
    expect(find.byType(CoachSettingsScreen), findsOneWidget);
  });

  testWidgets('⋮ Why: sources open their screen; written on this phone', (
    t,
  ) async {
    final (_, _, log) = await _pump(t);
    await _option(t, InsightCopy.why);
    expect(find.text(InsightCopy.whyLede), findsOneWidget);
    expect(find.text(InsightCopy.writtenOnDevice), findsOneWidget);
    expect(find.text(InsightCopy.writtenByAi), findsNothing);
    expect(find.byKey(const ValueKey('why-ref-s3')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('why-ref-s3')));
    await t.pumpAndSettle();
    expect(log.names, [Routes.trends]);
  });

  testWidgets('an AI card: labelled, why says so, memories deletable', (
    t,
  ) async {
    final (repo, _, _) = await _pump(t, cards: [InsightScript.recoveryAi]);
    expect(find.text(InsightCopy.aiSummary), findsOneWidget);
    expect(
      find.text('${InsightCopy.usingMemory}: Training for a half marathon'),
      findsOneWidget,
    );
    await _option(t, InsightCopy.why);
    expect(find.text(InsightCopy.writtenByAi), findsOneWidget);
    expect(find.text(InsightCopy.memoriesUsed.toUpperCase()), findsOneWidget);
    expect(find.byKey(const ValueKey('why-memory-f1')), findsOneWidget);
    await t.tap(
      find.bySemanticsLabel('Delete memory: Training for a half marathon'),
    );
    await t.pumpAndSettle();
    expect(repo.calls, contains('deleteMemory:f1'));
    expect(find.byKey(const ValueKey('why-memory-f1')), findsNothing);
    // Back on the card, the chip went with the memory.
    await t.tapAt(const Offset(200, 60));
    await t.pumpAndSettle();
    expect(find.textContaining(InsightCopy.usingMemory), findsNothing);
  });

  testWidgets('the memory chip opens What Coach knows', (t) async {
    await _pump(t, cards: [InsightScript.recoveryAi]);
    await t.tap(find.byKey(const ValueKey('insight-memory')));
    await t.pumpAndSettle();
    expect(find.byType(CoachMemoryScreen), findsOneWidget);
  });

  testWidgets('tapping the card opens its screen on its day', (t) async {
    final past = Insight(
      id: 'sleep:2026-09-27',
      kind: InsightKind.sleep,
      date: '2026-09-27',
      createdAt: DateTime(2026, 9, 27, 7),
      headline: 'Sunday night',
      body: 'Asleep 6h 40m.',
      route: Routes.sleep,
    );
    final (_, _, log) = await _pump(
      t,
      cards: [past],
      child: const InsightFeed(date: '2026-09-27'),
    );
    await t.tap(find.text('Sunday night'));
    await t.pumpAndSettle();
    expect(log.names, [Routes.sleep]);
    expect(coachContainer(t).read(selectedDateProvider), '2026-09-27');
  });

  testWidgets('on its own screen the card does not open it again', (t) async {
    final (_, _, log) = await _pump(
      t,
      child: const InsightFeed(date: kCoachToday, hostRoute: Routes.sleep),
    );
    expect(find.byKey(const ValueKey('insight-open')), findsNothing);
    await t.tap(find.text("Here's how you slept"));
    await t.pumpAndSettle();
    expect(log.names, isEmpty);
  });

  for (final b in const [Brightness.dark]) { // dark only
    testWidgets('no overflow at 320 px and 1.3× text · ${b.name}', (t) async {
      await _pump(
        t,
        cards: [InsightScript.recoveryAi, InsightScript.sleep],
        child: const InsightFeed(date: kCoachToday, max: null),
        size: const Size(320, 900),
        textScale: 1.3,
      );
      expect(t.takeException(), isNull);
      expect(find.byType(InsightCard), findsNWidgets(2));
    });
  }
}

final _unwiredCard = Insight(
  id: 'x',
  kind: InsightKind.sleep,
  date: kCoachToday,
  createdAt: DateTime(2026, 9, 28),
  headline: 'Unwired',
  body: '',
);
