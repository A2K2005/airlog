// Connecting Claude or Gemini (Settings → Coach → the Connect sheet; there
// is no setup screen and no wall before the chat). A cloud engine cannot be
// turned on without a key of the right shape, the 18+ tick and the agree
// tap (and, for Gemini, the paid-project tick); nothing is saved before the
// agree tap, which stores the key and then the consent time and version;
// the key is never shown again; On this phone deletes the key; a wider mode
// asks again. The consent text is CoachCopy's, word for word.

import 'package:airlog/app/copy.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/features/coach/coach_settings_screen.dart';
import 'package:airlog/features/coach/coach_setup_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';
import '../../support/fonts.dart';

const _claudeKey = 'sk-ant-api03-abcdefghijklmnop-9876';
const _geminiKey = 'AIzaSyA1234567890abcdefghijklmnopq4321';

Finder get _agree => find.byKey(const ValueKey('agree'));

/// The scrollable of the sheet on top (else the page's).
Finder get _scrollable {
  final inSheet = find.descendant(
    of: find.byType(BottomSheet),
    matching: find.byType(Scrollable),
  );
  return inSheet.evaluate().isNotEmpty
      ? inSheet.first
      : find.byType(Scrollable).first;
}

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    try {
      await t.scrollUntilVisible(f, 200, scrollable: _scrollable);
    } catch (_) {
      await t.scrollUntilVisible(f, -200, scrollable: _scrollable);
    }
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
}

Future<void> _tap(WidgetTester t, Finder f) async {
  await _scrollTo(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

/// The agree button is enabled (it exposes a tap action).
bool _hasTap(WidgetTester t, [Finder? f]) {
  final node = t.getSemantics(f ?? _agree);
  return node.getSemanticsData().hasAction(SemanticsAction.tap);
}

Future<void> _open(WidgetTester t, CoachProvider p) async {
  await _tap(t, find.byKey(ValueKey('engine-${p.name}')));
}

Future<void> _pasteKey(WidgetTester t, String key) async {
  await _scrollTo(t, find.byKey(const ValueKey('api-key')));
  await t.enterText(find.byKey(const ValueKey('api-key')), key);
  await t.pumpAndSettle();
}

CoachSettings _on(CoachProvider p, {CoachMode mode = CoachMode.useMyData}) =>
    CoachSettings(
      provider: p,
      model: p == CoachProvider.claude ? 'claude-opus-5-5' : null,
      mode: mode,
      consentAt: kCoachNow,
      consentVersion: CoachCopy.consentVersion,
      adultConfirmed: true,
    );

void main() {
  setUpAll(loadAppFonts);

  test('key shapes', () {
    expect(keyProblem(CoachProvider.claude, ''), isNotNull);
    expect(
      keyProblem(CoachProvider.claude, 'sk-proj-abcdefghijklmnopqrstu'),
      contains('sk-ant-'),
    );
    expect(keyProblem(CoachProvider.claude, 'sk-ant-short'), isNotNull);
    expect(keyProblem(CoachProvider.claude, _claudeKey), isNull);
    expect(
      keyProblem(CoachProvider.claude, 'sk-ant- api03-with space'),
      isNotNull,
    );
    expect(keyProblem(CoachProvider.gemini, _claudeKey), contains('AIza'));
    expect(keyProblem(CoachProvider.gemini, _geminiKey), isNull);
  });

  testWidgets('the old setup route opens Settings → Coach', (t) async {
    await pumpCoach(t, repo: FakeCoachRepository(), initial: Routes.coachSetup);
    expect(find.byType(CoachSettingsScreen), findsOneWidget);
    expect(find.text('Choose who answers'), findsNothing);
  });

  testWidgets('Claude: key first, then consent; 18+ and the agree tap are '
      'required; nothing is saved before agreeing', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await _open(t, CoachProvider.claude);
    expect(find.text('Connect Claude'), findsOneWidget);
    expect(find.text(CoachCopy.claudeBody), findsOneWidget);
    final cont = find.byKey(const ValueKey('connect-continue'));
    expect(_hasTap(t, cont), isFalse);

    // A key of the wrong shape does not count.
    await _pasteKey(t, 'sk-proj-12345');
    expect(find.textContaining('start with “sk-ant-”'), findsOneWidget);
    expect(_hasTap(t, cont), isFalse);

    await _pasteKey(t, _claudeKey);
    expect(_hasTap(t, cont), isTrue);
    await _tap(t, cont);
    expect(find.text('What Claude will receive'), findsOneWidget);
    await _scrollTo(t, _agree);
    expect(find.text(CoachCopy.agree(CoachProvider.claude)), findsOneWidget);
    expect(_hasTap(t), isFalse);
    expect(find.text('Still needed: the 18+ box.'), findsOneWidget);
    expect(repo.calls, isEmpty, reason: 'nothing saved before agreeing');

    await _tap(t, find.byKey(const ValueKey('adult')));
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isTrue);
    expect(repo.calls, isEmpty);

    await _tap(t, _agree);
    expect(repo.calls, ['saveApiKey:claude', 'saveSettings']);
    expect(repo.keys[CoachProvider.claude], _claudeKey);
    final s = repo.current;
    expect(s.provider, CoachProvider.claude);
    expect(s.model, 'claude-opus-5-5');
    expect(s.consentAt, kCoachNow);
    expect(s.consentVersion, CoachCopy.consentVersion);
    expect(s.adultConfirmed, isTrue);
    // The sheet closed; the row says Claude is in use.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('Your key · Anthropic ·'), findsOneWidget);
  });

  testWidgets('the consent step prints every consent line word for word', (
    t,
  ) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await _open(t, CoachProvider.gemini);
    expect(find.text(CoachCopy.geminiWarning), findsOneWidget);
    await _pasteKey(t, _geminiKey);
    await _tap(t, find.byKey(const ValueKey('connect-continue')));
    for (final line in [
      CoachCopy.recipient(CoachProvider.gemini),
      CoachCopy.useMyDataBody,
      ...CoachCopy.sentWithData,
      ...CoachCopy.neverSent,
      CoachCopy.retention(CoachProvider.gemini),
      CoachCopy.adult,
      CoachCopy.paidKey,
      CoachCopy.agree(CoachProvider.gemini),
    ]) {
      final f = find.text(line);
      await _scrollTo(t, f);
      expect(f, findsOneWidget, reason: line);
    }
    await _tap(t, find.text(CoachCopy.modeLabel(CoachMode.generalOnly)));
    for (final line in [CoachCopy.generalOnlyBody, ...CoachCopy.sentGeneral]) {
      final f = find.text(line);
      await _scrollTo(t, f);
      expect(f, findsOneWidget, reason: line);
    }
  });

  testWidgets('Gemini also needs the paid-project tick', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await _open(t, CoachProvider.gemini);
    expect(find.text('Paid keys only'), findsOneWidget);
    await _pasteKey(t, _geminiKey);
    await _tap(t, find.byKey(const ValueKey('connect-continue')));
    await _tap(t, find.byKey(const ValueKey('adult')));
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isFalse);
    expect(find.text('Still needed: the paid-project box.'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('paid')));
    await _tap(t, find.byKey(const ValueKey('model-gemini-3.5-flash-lite')));
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isTrue);
    await _tap(t, _agree);
    expect(repo.current.provider, CoachProvider.gemini);
    expect(repo.current.model, 'gemini-3.5-flash-lite');
    expect(repo.keys[CoachProvider.gemini], _geminiKey);
  });

  testWidgets('a stored key is never shown again; the tail of a key saved '
      'this session is', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await _open(t, CoachProvider.claude);
    final c = coachContainer(t);
    c.read(coachSetupProvider.notifier)
      ..setKeyDraft(_claudeKey)
      ..setAdult(true);
    expect(await c.read(coachSetupProvider.notifier).agree(), isTrue);
    await t.pumpAndSettle();
    // The consent step, with the key's tail only.
    expect(find.byKey(const ValueKey('api-key')), findsNothing);
    expect(find.textContaining(_claudeKey), findsNothing);
    await _scrollTo(t, find.text('Key saved ••••9876'));
    expect(find.text('Key saved ••••9876'), findsOneWidget);
    await _scrollTo(t, find.text('Claude is on'));
    expect(find.text('Claude is on'), findsOneWidget);
  });

  testWidgets('reopened later, a stored key shows only that it is saved', (
    t,
  ) async {
    final repo = FakeCoachRepository(
      settings: _on(CoachProvider.claude),
      keys: {CoachProvider.claude: _claudeKey},
    );
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await _open(t, CoachProvider.claude);
    expect(find.byKey(const ValueKey('api-key')), findsNothing);
    expect(find.textContaining(_claudeKey), findsNothing);
    await _scrollTo(t, find.text('Key saved on this phone'));
    expect(find.text('Key saved on this phone'), findsOneWidget);
  });

  testWidgets('On this phone: the key is deleted, cloud answers off', (
    t,
  ) async {
    final repo = FakeCoachRepository(
      settings: _on(CoachProvider.claude),
      keys: {CoachProvider.claude: _claudeKey},
    );
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await _open(t, CoachProvider.offline);
    expect(find.text('Turn off Claude?'), findsOneWidget);
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(repo.keys, isEmpty);
    expect(repo.current.provider, CoachProvider.offline);
    expect(repo.current.hasConsent, isFalse);
    expect(repo.calls, contains('deleteApiKey:claude'));
    expect(repo.calls, contains('deleteApiKey:gemini'));
    expect(
      find.text('Back to On this phone. Your key was deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('widening to your data asks for consent again; a model change '
      'does not', (t) async {
    final repo = FakeCoachRepository(
      settings: _on(CoachProvider.claude, mode: CoachMode.generalOnly),
      keys: {CoachProvider.claude: _claudeKey},
    );
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    await _tap(t, find.byKey(const ValueKey('row-model')));
    await _scrollTo(t, find.text('Claude is on'));
    await _tap(t, find.byKey(const ValueKey('model-claude-haiku-4-5')));
    await _tap(t, find.byKey(const ValueKey('connect-save')));
    expect(repo.current.model, 'claude-haiku-4-5');
    expect(repo.current.mode, CoachMode.generalOnly);

    await _tap(t, find.byKey(const ValueKey('row-data')));
    await _tap(t, find.text(CoachCopy.modeLabel(CoachMode.useMyData)));
    expect(find.text('Claude is on'), findsNothing);
    await _scrollTo(t, _agree);
    // The 18+ answer is remembered and the key stored: agree is enough.
    expect(_hasTap(t), isTrue);
    await _tap(t, _agree);
    expect(repo.current.mode, CoachMode.useMyData);
  });

  testWidgets('a consent from an older version asks for a quick review', (
    t,
  ) async {
    final repo = FakeCoachRepository(
      settings: _on(CoachProvider.claude).copyWith(consentVersion: 0),
      keys: {CoachProvider.claude: _claudeKey},
    );
    await pumpCoach(t, repo: repo, initial: Routes.settingsCoach);
    expect(find.text('Needs a quick review'), findsOneWidget);
    await _open(t, CoachProvider.claude);
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isTrue);
    await _tap(t, _agree);
    expect(repo.current.consentVersion, CoachCopy.consentVersion);
  });
}
