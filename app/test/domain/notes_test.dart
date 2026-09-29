// Honesty notes for absent inputs; never a guessed number. [ours]

import 'package:airlog/domain/engine/engine.dart';
import 'package:airlog/domain/engine/notes.dart';
import 'package:airlog/domain/engine/source_apps.dart';
import 'package:airlog/domain/models.dart';
import 'package:airlog/domain/results.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/builders.dart';

Set<String> metrics(DayResult r) => {for (final n in r.notes) n.metric};

void main() {
  final now = DateTime(2026, 9, 1);

  test('empty day: no recovery, and a note for every absent input', () {
    final r = Engine.computeDay(
      DayRecord(date: '2026-08-10'),
      history: const [],
      now: now,
    );
    expect(r.recovery, isNull);
    expect(r.strain!.method, StrainMethod.none);
    expect(r.sleep!.hasData, isFalse);
    expect(
      metrics(r),
      containsAll(<String>[
        'recovery', 'hrv', 'rhr', 'sleep', 'resp', 'spo2', 'skin_temp', //
        'hr', 'steps', 'strain',
      ]),
    );
    expect(metrics(r), isNot(contains('pulse_age')), reason: 'no Pulse Age');
    final recoveryNote = r.notes.firstWhere((n) => n.metric == 'recovery');
    expect(recoveryNote.severity, NoteSeverity.warning);
    expect(recoveryNote.fix, isNotNull);
  });

  test('HRV note explains the causes and gives a fix', () {
    final r = Engine.computeDay(
      denseDay('2026-08-10', hrv: null),
      history: const [],
      now: now,
    );
    final n = r.notes.firstWhere((n) => n.metric == 'hrv');
    expect(n.body, contains('not worn to bed'));
    expect(n.body, contains('Health Connect permission'));
    expect(n.body, contains('Google Health'));
    expect(n.fix, isNotNull);
    expect(n.title, 'No HRV yet');
    expect(r.recovery, isNotNull, reason: 'RHR alone still scores');
    expect(r.recovery!.components.any((c) => c.key == 'hrv'), isFalse);
    expect(r.notes.any((n) => n.title == 'No Recovery score'), isFalse);
  });

  test('"seen before" wording once the metric has history', () {
    final history = denseRange('2026-08-09', 5);
    final r = Engine.computeDay(
      denseDay('2026-08-10', hrv: null),
      history: history,
      now: now,
    );
    expect(
      r.notes.firstWhere((n) => n.metric == 'hrv').title,
      'No HRV for this night',
    );
  });

  test('complete day with profile: only the always-absent inputs remain', () {
    final history = denseRange('2026-08-09', 20);
    final r = Engine.computeDay(
      denseDay('2026-08-10', spo2Avg: 96, spo2Min: 93, vo2max: 45),
      history: history,
      now: now,
      config: const EngineConfig(profile: UserProfile(birthYear: 1990)),
    );
    expect(
      metrics(
        r,
      ).intersection({'hrv', 'rhr', 'sleep', 'resp', 'spo2', 'hr', 'recovery'}),
      isEmpty,
      reason: r.notes.map((n) => n.title).join(' | '),
    );
    expect(r.pulseAge, isNull, reason: 'Pulse Age is not computed in v1');
    expect(r.strain!.maxHrSource, MaxHrSource.birthYear);
    expect(r.notes.any((n) => n.title.contains('max heart rate')), isFalse);
  });

  test('no birth year: zones use the observed maximum, labelled', () {
    final days = denseRange('2026-08-10', 5);
    final r = Engine.computeRange(days, now: now).last;
    expect(r.strain!.method, StrainMethod.hrZones);
    expect(r.strain!.maxHrSource, MaxHrSource.observed);
    final peaks = [
      for (final d in days)
        ([for (final s in d.hrSamples) s.bpm]..sort()).reversed.elementAt(2),
    ];
    final best = peaks.reduce((a, b) => a > b ? a : b);
    expect(r.strain!.maxHrUsed, best);
    final n = r.notes.firstWhere(
      (n) => n.title == 'Zones use your highest observed heart rate',
    );
    expect(n.body, contains('${best.toStringAsFixed(0)} bpm'));
    expect(n.fix, contains('birth year'));
  });

  test('a max-HR override wins over the birth year', () {
    final r = Engine.computeDay(
      denseDay('2026-08-10'),
      history: const [],
      now: now,
      config: const EngineConfig(
        profile: UserProfile(birthYear: 1990, maxHrOverride: 201),
      ),
    );
    expect(r.strain!.maxHrUsed, 201);
    expect(r.strain!.maxHrSource, MaxHrSource.override);
  });

  test('calibrating note during the first nights', () {
    final results = Engine.computeRange(denseRange('2026-08-10', 3), now: now);
    expect(results.last.recovery!.calibrating, isTrue);
    expect(
      results.last.notes.any((n) => n.title == 'Calibrating your baseline'),
      isTrue,
    );
  });

  test('sparse heart rate: partial strain with an explanatory note', () {
    final r = Engine.computeDay(
      denseDay('2026-08-10', hrStepMinutes: 5),
      history: const [],
      now: now,
    );
    expect(r.strain!.method, StrainMethod.hrZones);
    expect(
      r.notes.any(
        (n) =>
            n.metric == 'strain' && n.title == 'Strain from partial heart rate',
      ),
      isTrue,
    );
  });

  test('no heart rate: no strain score, and the note says why', () {
    final r = Engine.computeDay(
      denseDay('2026-08-10', hr: false),
      history: const [],
      now: now,
    );
    expect(r.strain!.method, StrainMethod.none);
    expect(r.strain!.steps, 9000);
    final n = r.notes.firstWhere((n) => n.title == 'No Strain score');
    expect(n.body, contains('only from measured heart rate'));
  });

  test('no Recovery, app shares neither: the fix names Samsung Health\'s '
      'own setting only for Samsung Health, generic copy otherwise', () {
    final samsung = Notes.recoveryNotShared(
      'Samsung Health',
      origin: SourceApps.samsungHealth,
    );
    expect(
      samsung.fix,
      startsWith(
        'Turn on continuous heart-rate measurement in Samsung Health '
        '(Heart rate → Measure continuously).',
      ),
    );
    final other = Notes.recoveryNotShared('Zepp', origin: SourceApps.zepp);
    expect(other.fix, startsWith('Turn on continuous heart rate in Zepp.'));
    expect(other.fix, isNot(contains('Samsung')));
    expect(other.fix, isNot(contains('Measure continuously')));
    // An unknown package: its display name, still generic.
    final unknown = Notes.recoveryNotShared(
      'Acme Band',
      origin: 'com.acme.band',
    );
    expect(
      unknown.fix,
      startsWith(
        'Turn on continuous heart rate in Acme '
        'Band.',
      ),
    );
    expect(unknown.body, startsWith('Acme Band doesn'));
  });
}
