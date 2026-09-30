// Journal: loading, error (FakeRepo), a demo history with solid and emerging
// insights, optimistic toggles that save at once (in order, without a
// skeleton flash), stepping to earlier evenings, the empty-insights state,
// and no overflow at 320 px with 1.3× text.

import 'package:airlog/design/design.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/features/journal/journal_screen.dart';
import 'package:airlog/features/journal/journal_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_repo.dart';
import '../../support/fonts.dart';
import '../../support/screens_a_fixtures.dart';

Future<void> _pump(
  WidgetTester t, {
  HealthRepository? repo,
  String? selectedDate,
  Size size = const Size(412, 2800),
  double textScale = 1,
}) async {
  phoneView(t, size: size);
  await t.pumpWidget(
    screenApp(
      repo: repo ?? demoRepo(),
      screen: const JournalScreen(),
      selectedDate: selectedDate,
      textScale: textScale,
    ),
  );
  await t.pumpAndSettle();
}

FactorChip _chip(WidgetTester t, JournalFactor f) =>
    t.widget<FactorChip>(find.byKey(ValueKey('factor-${f.name}')));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('loading: skeletons', (t) async {
    phoneView(t);
    await t.pumpWidget(
      screenApp(repo: PendingRepo(), screen: const JournalScreen()),
    );
    await t.pump();
    expect(find.byType(SkeletonBox), findsWidgets);
  });

  testWidgets('a failing repository shows an error, not a crash', (t) async {
    await _pump(t, repo: FakeRepo());
    expect(find.text('Couldn’t open the journal'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('insights: clear first, maybes apart, caveat shown', (t) async {
    await _pump(t);
    expect(find.text('What happened this evening?'), findsOneWidget);
    expect(find.byType(FactorChip), findsNWidgets(JournalFactor.values.length));
    // "Associated with" wording (PRODUCT_PLAN §7).
    expect(
      find.textContaining('Alcohol is associated with', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('15 days with · 64 without'), findsOneWidget);
    expect(find.text('Clear'), findsWidgets);
    expect(find.text('Maybe'), findsWidgets);
    // The gap is unsigned in dot matrix; the direction is in words.
    final stats = t.widgetList<DotStat>(find.byType(DotStat));
    expect(stats.any((d) => d.unit == 'pts lower'), isTrue);
    expect(stats.every((d) => !d.value.contains('−')), isTrue);
    expect(find.text('NOT ENOUGH DAYS YET'), findsOneWidget);
    expect(find.text('A link, not a cause.'), findsOneWidget);
    await t.tap(find.bySemanticsLabel('About A link, not a cause'));
    await t.pumpAndSettle();
    expect(find.textContaining('Welch’s test'), findsOneWidget);
  });

  testWidgets('a tap saves at once, optimistically, with no skeleton', (
    t,
  ) async {
    final repo = demoRepo();
    await _pump(t, repo: repo);
    expect(_chip(t, JournalFactor.alcohol).selected, isFalse);
    await t.tap(find.text('Alcohol'));
    await t.pump();
    expect(_chip(t, JournalFactor.alcohol).selected, isTrue);
    expect(find.byType(SkeletonBox), findsNothing);
    await t.pumpAndSettle();
    expect(_chip(t, JournalFactor.alcohol).selected, isTrue);
    expect(find.text('1 tagged · saved on this phone'), findsOneWidget);
    expect((await repo.journal(kToday)).factors, {JournalFactor.alcohol});
  });

  testWidgets('fast taps land in order', (t) async {
    final repo = demoRepo();
    await _pump(t, repo: repo);
    // By key: a habit without enough days also shows as a quiet chip.
    await t.tap(find.byKey(const ValueKey('factor-stress')));
    await t.tap(find.byKey(const ValueKey('factor-travel')));
    await t.tap(find.byKey(const ValueKey('factor-stress')));
    await t.pump();
    expect(_chip(t, JournalFactor.stress).selected, isFalse);
    expect(_chip(t, JournalFactor.travel).selected, isTrue);
    final c = ProviderScope.containerOf(t.element(find.byType(JournalScreen)));
    await c.read(journalViewModelProvider.notifier).settled;
    await t.pumpAndSettle();
    expect((await repo.journal(kToday)).factors, {JournalFactor.travel});
    expect(_chip(t, JournalFactor.travel).selected, isTrue);
  });

  testWidgets('earlier evenings: step back, never past today', (t) async {
    await _pump(t);
    final next = t.widget<AppIconButton>(
      find.widgetWithIcon(AppIconButton, Icons.chevron_right_rounded),
    );
    expect(next.onTap, isNull);
    await t.tap(find.byIcon(Icons.chevron_left_rounded));
    await t.pumpAndSettle();
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('What happened that evening?'), findsOneWidget);
    // The demo tagged yesterday.
    expect(_chip(t, JournalFactor.meditation).selected, isTrue);
    expect(_chip(t, JournalFactor.exercised).selected, isTrue);
  });

  testWidgets('at 00:30 a tag lands on the evening that just ended', (t) async {
    final repo = demoRepo();
    phoneView(t, size: const Size(412, 2800));
    await t.pumpWidget(
      screenApp(
        repo: repo,
        screen: const JournalScreen(),
        now: DateTime(2026, 9, 29, 0, 30),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('What happened this evening?'), findsOneWidget);
    expect(find.text('Mon 28 Sep'), findsOneWidget);
    await t.tap(find.text('Alcohol'));
    await t.pumpAndSettle();
    expect(
      (await repo.journal(kToday)).factors,
      contains(JournalFactor.alcohol),
    );
    expect((await repo.journal('2026-09-29')).factors, isEmpty);
  });

  testWidgets('opens on the day selected elsewhere', (t) async {
    final day = DayKey.add(kToday, -1);
    await _pump(t, selectedDate: day);
    expect(find.text('Yesterday'), findsOneWidget);
  });

  testWidgets('too few days: explains what the patterns need', (t) async {
    await _pump(t, repo: demoRepo(days: 3));
    expect(find.text('Patterns take a few weeks'), findsOneWidget);
    expect(
      find.textContaining('needs 10 tagged days with it and 10 without'),
      findsOneWidget,
    );
    expect(find.text('A link, not a cause.'), findsOneWidget);
  });

  testWidgets('no overflow at 320 px and 1.3× and 2× text', (t) async {
    for (final scale in const [1.3, 2.0]) {
      await t.pumpWidget(const SizedBox());
      await _pump(t, size: const Size(320, 640), textScale: scale);
      expect(t.takeException(), isNull);
      await scrollThrough(t);
    }
  });
}
