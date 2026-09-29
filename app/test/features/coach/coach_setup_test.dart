// Coach setup and consent: a cloud engine cannot be turned on without a
// key of the right shape, the 18+ tick and the agree tap (and, for Gemini,
// the paid-project tick); agreeing stores the key and then the consent time
// and version; the key is never shown again; withdrawing deletes the key and
// returns to on-device; a wider mode asks again.

import 'package:airlog/app/copy.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/features/coach/coach_setup_view_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';
import '../../support/fonts.dart';

const _claudeKey = 'sk-ant-api03-abcdefghijklmnop-9876';
const _geminiKey = 'AIzaSyA1234567890abcdefghijklmnopq4321';

Finder get _agree => find.byKey(const ValueKey('agree'));

Future<void> _scrollTo(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    final list = find.byType(Scrollable).first;
    try {
      await t.scrollUntilVisible(f, 200, scrollable: list);
    } catch (_) {
      await t.scrollUntilVisible(f, -200, scrollable: list);
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
bool _hasTap(WidgetTester t) {
  final node = t.getSemantics(_agree);
  return node.getSemanticsData().hasAction(SemanticsAction.tap);
}

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

  testWidgets('Claude: key, 18+ and the agree tap are all required', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coachSetup);
    expect(find.text('In use'), findsOneWidget); // on-device
    await t.tap(find.byKey(const ValueKey('engine-claude')));
    await t.pumpAndSettle();

    await _scrollTo(t, _agree);
    expect(find.text(CoachCopy.agree(CoachProvider.claude)), findsOneWidget);
    expect(_hasTap(t), isFalse);
    expect(
      find.text('Still needed: your API key, the 18+ confirmation.'),
      findsOneWidget,
    );

    // A key of the wrong shape does not count.
    await _scrollTo(t, find.byKey(const ValueKey('api-key')));
    await t.enterText(find.byKey(const ValueKey('api-key')), 'sk-proj-12345');
    await t.pumpAndSettle();
    expect(find.textContaining('start with “sk-ant-”'), findsOneWidget);
    await _tap(t, find.byKey(const ValueKey('adult')));
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isFalse);

    // The right shape, but no 18+ tick: still off.
    await _scrollTo(t, find.byKey(const ValueKey('api-key')));
    await t.enterText(find.byKey(const ValueKey('api-key')), _claudeKey);
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('adult'))); // un-tick
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isFalse);
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
  });

  testWidgets('Gemini also needs the paid-project tick', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coachSetup);
    await t.tap(find.byKey(const ValueKey('engine-gemini')));
    await t.pumpAndSettle();
    await _scrollTo(t, find.text('Paid keys only'));
    expect(find.text('Paid keys only'), findsOneWidget);
    await _scrollTo(t, find.byKey(const ValueKey('api-key')));
    await t.enterText(find.byKey(const ValueKey('api-key')), _geminiKey);
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('adult')));
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isFalse);
    expect(
      find.text('Still needed: the paid-project confirmation.'),
      findsOneWidget,
    );
    await _tap(t, find.byKey(const ValueKey('paid')));
    await _tap(t, find.byKey(const ValueKey('model-gemini-3.5-flash-lite')));
    await _scrollTo(t, _agree);
    expect(_hasTap(t), isTrue);
    await _tap(t, _agree);
    expect(repo.current.provider, CoachProvider.gemini);
    expect(repo.current.model, 'gemini-3.5-flash-lite');
    expect(repo.keys[CoachProvider.gemini], _geminiKey);
  });

  testWidgets('a stored key is never shown again', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, home: const _SetupHost());
    await t.tap(find.text('open setup'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('engine-claude')));
    await t.pumpAndSettle();
    await _scrollTo(t, find.byKey(const ValueKey('api-key')));
    await t.enterText(find.byKey(const ValueKey('api-key')), _claudeKey);
    await _tap(t, find.byKey(const ValueKey('adult')));
    await _tap(t, _agree);
    // Agreeing returns to the chat; reopening setup shows only the tail.
    expect(find.text('open setup'), findsOneWidget);
    await t.tap(find.text('open setup'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('api-key')), findsNothing);
    expect(find.textContaining(_claudeKey), findsNothing);
    await _scrollTo(t, find.textContaining('Key saved'));
    expect(find.text('Key saved on this phone'), findsOneWidget);
    await _scrollTo(t, find.text('Claude is on'));
  });

  testWidgets('the tail of a key saved this session is shown', (t) async {
    final repo = FakeCoachRepository();
    await pumpCoach(t, repo: repo, initial: Routes.coachSetup);
    await t.tap(find.byKey(const ValueKey('engine-claude')));
    await t.pumpAndSettle();
    final ctx = t.element(find.byKey(const ValueKey('engine-claude')));
    final c = coachContainer(t);
    c.read(coachSetupProvider.notifier)
      ..setKeyDraft(_claudeKey)
      ..setAdult(true);
    expect(await c.read(coachSetupProvider.notifier).agree(), isTrue);
    await t.pumpAndSettle();
    expect(ctx.mounted, isTrue);
    await _scrollTo(t, find.textContaining('Key saved'));
    expect(find.text('Key saved ••••9876'), findsOneWidget);
  });

  testWidgets('withdraw: key deleted, back to on-device', (t) async {
    final repo = FakeCoachRepository(
      settings: CoachSettings(
        provider: CoachProvider.claude,
        model: 'claude-opus-5-5',
        consentAt: kCoachNow,
        consentVersion: CoachCopy.consentVersion,
        adultConfirmed: true,
      ),
      keys: {CoachProvider.claude: _claudeKey},
    );
    await pumpCoach(t, repo: repo, initial: Routes.coachSetup);
    await _tap(t, find.byKey(const ValueKey('withdraw')));
    expect(find.text('Turn off Claude?'), findsOneWidget);
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(repo.keys, isEmpty);
    expect(repo.current.provider, CoachProvider.offline);
    expect(repo.current.hasConsent, isFalse);
    expect(repo.calls, contains('deleteApiKey:claude'));
    expect(repo.calls, contains('deleteApiKey:gemini'));
    expect(
      find.text('Back to on-device. Your key was deleted.'),
      findsOneWidget,
    );
  });

  testWidgets('widening to Use my data asks for consent again; a model '
      'change does not', (t) async {
    final repo = FakeCoachRepository(
      settings: CoachSettings(
        provider: CoachProvider.claude,
        model: 'claude-opus-5-5',
        mode: CoachMode.generalOnly,
        consentAt: kCoachNow,
        consentVersion: CoachCopy.consentVersion,
        adultConfirmed: true,
      ),
      keys: {CoachProvider.claude: _claudeKey},
    );
    await pumpCoach(t, repo: repo, initial: Routes.coachSetup);
    await _scrollTo(t, find.text('Claude is on'));
    await _tap(t, find.byKey(const ValueKey('model-claude-haiku-4-5')));
    await _tap(t, find.text('Save changes'));
    expect(repo.current.model, 'claude-haiku-4-5');
    expect(repo.current.mode, CoachMode.generalOnly);

    await _tap(t, find.text('Use my data'));
    expect(find.text('Claude is on'), findsNothing);
    await _scrollTo(t, _agree);
    expect(find.text(CoachCopy.agree(CoachProvider.claude)), findsOneWidget);
    // The 18+ answer is remembered; the key is stored: agree is enough.
    expect(_hasTap(t), isTrue);
    await _tap(t, _agree);
    expect(repo.current.mode, CoachMode.useMyData);
  });

  testWidgets('switching to on-device from a cloud engine deletes the key', (
    t,
  ) async {
    final repo = FakeCoachRepository(
      settings: CoachSettings(
        provider: CoachProvider.gemini,
        consentAt: kCoachNow,
        consentVersion: CoachCopy.consentVersion,
        adultConfirmed: true,
      ),
      keys: {CoachProvider.gemini: _geminiKey},
    );
    await pumpCoach(t, repo: repo, initial: Routes.coachSetup);
    await t.tap(find.byKey(const ValueKey('engine-offline')));
    await t.pumpAndSettle();
    await _tap(t, find.byKey(const ValueKey('use-on-device')));
    await t.tap(find.text('Turn off'));
    await t.pumpAndSettle();
    expect(repo.keys, isEmpty);
    expect(repo.current.provider, CoachProvider.offline);
  });
}

class _SetupHost extends StatelessWidget {
  const _SetupHost();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).pushNamed(Routes.coachSetup),
        child: const Text('open setup'),
      ),
    ),
  );
}
