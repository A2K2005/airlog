// Fixtures for the Today / Recovery / Sleep / Journal screen tests
// (screen engineer A). Built on the data layer's in-memory demo repository:
// the real resolver + engine over a seeded synthetic band, at a fixed clock.

import 'dart:async';

import 'package:airlog/app/providers.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/day_key.dart';
import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/repositories.dart';
import 'package:airlog/domain/results.dart';
import 'package:airlog/features/journal/journal_screen.dart';
import 'package:airlog/features/recovery/recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Monday 28 September 2026, 09:30 local: the demo's "today".
final kNow = DateTime(2026, 9, 28, 9, 30);

/// 19:30 the same day (the journal prompt shows in the evening).
final kEvening = DateTime(2026, 9, 28, 19, 30);

String get kToday => DayKey.of(kNow);

/// The planted illness (demo days −24…−21): the Health Monitor alerts here.
String get kAlertDay => DayKey.add(kToday, -23);

const kPhone = Size(412, 915);

/// The demo repository at [now] ([days] of history).
InMemoryHealthRepository demoRepo({DateTime? now, int days = 90}) =>
    InMemoryHealthRepository.demo(now: now ?? kNow, days: days);

/// Sizes the test view (logical px at 2× pixels).
void phoneView(WidgetTester t, {Size size = kPhone, double dpr = 2}) {
  t.view.physicalSize = size * dpr;
  t.view.devicePixelRatio = dpr;
  addTearDown(t.view.reset);
}

/// A screen inside the real theme and router, with the repository and the
/// clock overridden. Tab bodies are wrapped in a Scaffold as the shell does.
Widget screenApp({
  required HealthRepository repo,
  required Widget screen,
  Brightness brightness = Brightness.dark,
  DateTime? now,
  bool tab = false,
  String? selectedDate,
  double textScale = 1,
}) {
  final clock = now ?? kNow;
  return ProviderScope(
    overrides: [
      healthRepositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => clock),
      if (selectedDate != null)
        selectedDateProvider.overrideWith(() => _Fixed(selectedDate)),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness),
      onGenerateRoute: _route,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: tab
          ? Builder(
              builder: (c) =>
                  Scaffold(backgroundColor: P.of(c).bg, body: screen),
            )
          : screen,
    ),
  );
}

/// The routes these screens push. Our own screens are real; everything else
/// is a stub page naming the route (so these tests do not depend on other
/// features compiling or on their data).
Route<dynamic> _route(RouteSettings settings) => MaterialPageRoute<dynamic>(
  settings: settings,
  builder: (_) => switch (settings.name) {
    Routes.recovery => const RecoveryScreen(),
    Routes.journal => const JournalScreen(),
    final name => StubPage(name ?? ''),
  },
);

class StubPage extends StatelessWidget {
  const StubPage(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('route $name')));
}

class _Fixed extends SelectedDate {
  _Fixed(this.initial);
  final String initial;
  @override
  String? build() => initial;
}

/// The demo, re-computed by the engine with some inputs removed from the
/// newest [nights] records (e.g. no HRV → "missing HRV" notes, re-weighted
/// Recovery). Records are deep-copied: the demo repository caches and
/// shares its DayRecords.
class EditedDemoRepo implements HealthRepository {
  EditedDemoRepo._(this._base, this._bundles);

  static Future<EditedDemoRepo> create({
    required void Function(DayRecord r) edit,
    int nights = 1,
    DateTime? now,
    String? asOf,
  }) async {
    final base = demoRepo(now: now);
    final latest = (await base.latestDate())!;
    final all = await base.range(DayKey.add(latest, -89), latest);
    final records = [
      for (final b in all) DayRecord.fromJson(b.record.toJson()),
    ];
    for (final r in records) {
      if (DayKey.diff(r.date, latest) < nights) edit(r);
    }
    final results = Engine.computeRange(records, now: now ?? kNow);
    final byDate = {for (final r in results) r.date: r};
    return EditedDemoRepo._(base, {
      for (final r in records)
        if (byDate[r.date] != null &&
            (asOf == null || r.date.compareTo(asOf) <= 0))
          r.date: DayBundle(r, byDate[r.date]!),
    });
  }

  /// The demo as it stood on [date]: nothing newer exists (Today always
  /// shows the newest day).
  static Future<EditedDemoRepo> asOfDay(String date) =>
      create(edit: (_) {}, nights: 0, asOf: date);

  /// Removes last night's HRV.
  static void noHrv(DayRecord r) {
    r.hrvRmssd = null;
    r.provenance.remove(Metric.hrv);
  }

  /// Removes last night's sleep sessions (no sleep recorded).
  static void noSleep(DayRecord r) {
    r.sleepSessions.clear();
    r.provenance.remove(Metric.sleep);
  }

  /// Removes every recovery input (no Recovery score at all).
  static void noNightly(DayRecord r) {
    r.hrvRmssd = null;
    r.restingHr = null;
    r.provenance.remove(Metric.hrv);
    r.provenance.remove(Metric.restingHr);
  }

  final InMemoryHealthRepository _base;
  final Map<String, DayBundle> _bundles;

  @override
  DataMode get mode => _base.mode;
  @override
  Future<void> setMode(DataMode mode) => _base.setMode(mode);
  @override
  int get revision => _base.revision;
  @override
  Stream<int> get revisions => _base.revisions;
  @override
  SyncStatus get syncStatus => _base.syncStatus;
  @override
  Stream<SyncStatus> get syncStatusChanges => _base.syncStatusChanges;
  @override
  Future<String?> latestDate() async =>
      _bundles.isEmpty ? null : (_bundles.keys.toList()..sort()).last;
  @override
  Future<DayBundle?> day(String date) async => _bundles[date];
  @override
  Future<List<DayBundle>> range(String from, String to) async => [
    for (final k in _bundles.keys.toList()..sort())
      if (k.compareTo(from) >= 0 && k.compareTo(to) <= 0) _bundles[k]!,
  ];
  @override
  Future<void> syncNow() async {}
  @override
  Future<JournalEntry> journal(String date) => _base.journal(date);
  @override
  Future<void> saveJournal(JournalEntry entry) => _base.saveJournal(entry);
  @override
  Future<List<FactorInsight>> journalInsights() => _base.journalInsights();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('EditedDemoRepo: ${invocation.memberName}');

  // Any-app sources (contract 2026-09-29). Placeholder; the Data agent
  // implements these for real in HealthRepositoryImpl.
  @override
  Future<List<SourceApp>> detectedSources() async => const [];

  @override
  Future<Map<Metric, SourceChoice>> sourceChoices() async => const {};

  @override
  Future<void> setSourceChoice(Metric metric, String? origin) async {}
}

/// A repository whose every read hangs (the loading state).
class PendingRepo implements HealthRepository {
  @override
  DataMode get mode => DataMode.demo;
  @override
  int get revision => 1;
  @override
  Stream<int> get revisions => const Stream.empty();
  @override
  SyncStatus get syncStatus => const SyncStatus(phase: SyncPhase.idle);
  @override
  Stream<SyncStatus> get syncStatusChanges => const Stream.empty();
  @override
  Future<String?> latestDate() => Future<String?>.value(kToday);
  @override
  Future<DayBundle?> day(String date) => _never();
  @override
  Future<List<DayBundle>> range(String from, String to) => _never();
  @override
  Future<JournalEntry> journal(String date) => _never();
  @override
  Future<List<FactorInsight>> journalInsights() => _never();

  /// Never completes (and leaves no timer behind).
  static Future<T> _never<T>() => Completer<T>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('PendingRepo: ${invocation.memberName}');

  // Any-app sources (contract 2026-09-29). Placeholder; the Data agent
  // implements these for real in HealthRepositoryImpl.
  @override
  Future<List<SourceApp>> detectedSources() async => const [];

  @override
  Future<Map<Metric, SourceChoice>> sourceChoices() async => const {};

  @override
  Future<void> setSourceChoice(Metric metric, String? origin) async {}
}

/// Scrolls [scrollable] to the end in steps, failing on any layout
/// exception along the way (ListView lays out lazily).
Future<void> scrollThrough(WidgetTester t, {Finder? scrollable}) async {
  final s = scrollable ?? find.byType(Scrollable).first;
  for (var i = 0; i < 40; i++) {
    await t.drag(s, const Offset(0, -400));
    await t.pump();
    expect(t.takeException(), isNull);
    final pos = t.state<ScrollableState>(s).position;
    if (pos.pixels >= pos.maxScrollExtent) break;
  }
}
