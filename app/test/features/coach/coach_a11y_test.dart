// Every coach screen at 320 px wide with 1.3× text lays out without an
// overflow, and the chat, a Discuss chat and Settings → Coach meet the
// 48 dp tap-target and labelled-target guidelines.

import 'package:airlog/app/ask_entry.dart';
import 'package:airlog/app/copy.dart';
import 'package:airlog/app/route_names.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/coach_fixtures.dart';
import '../../support/fonts.dart';

const _narrow = Size(320, 2600);

final _cloud = CoachSettings(
  provider: CoachProvider.claude,
  model: 'claude-opus-5-5',
  consentAt: kCoachNow,
  consentVersion: CoachCopy.consentVersion,
  adultConfirmed: true,
);

String _seed(FakeCoachRepository repo, Scripted kind) => repo
    .seedConversation(
      'Why is my Recovery lower today?',
      (id) => [
        ChatMessage(
          id: 'q-$id',
          conversationId: id,
          role: ChatRole.user,
          text: 'Why is my Recovery lower today?',
          at: kCoachNow,
        ),
        CoachScript.answer(
          kind,
          id: 'a-$id',
          conversationId: id,
          at: kCoachNow,
        ),
      ],
    )
    .id;

FakeCoachRepository _cloudRepo() =>
    FakeCoachRepository(
        settings: _cloud,
        keys: {CoachProvider.claude: 'sk-ant-api03-test'},
        memories: [
          MemoryFact(
            id: 'f1',
            text: 'Training for a half marathon on 15 November',
            createdAt: kCoachNow,
            category: MemoryCategory.goals,
            expiresOn: '2026-11-15',
          ),
        ],
      )
      ..usage = const CoachUsage(
        provider: CoachProvider.claude,
        requests: 50,
        inputTokens: 100000,
        outputTokens: 100000,
        requestLimit: 50,
        tokenLimit: 200000,
      );

void main() {
  setUpAll(loadAppFonts);

  final screens = <String, Future<void> Function(WidgetTester)>{
    'chat, empty': (t) async {
      await pumpCoach(
        t,
        repo: FakeCoachRepository(),
        initial: Routes.coach,
        size: _narrow,
        textScale: 1.3,
      );
    },
    'chat, cloud answer, spent budget': (t) async {
      final repo = _cloudRepo();
      final id = _seed(repo, Scripted.cloud);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        size: _narrow,
        textScale: 1.3,
      );
    },
    'chat, fallback and memory': (t) async {
      final repo = FakeCoachRepository();
      final id = _seed(repo, Scripted.memory);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coach,
        arguments: CoachArgs(conversationId: id),
        size: _narrow,
        textScale: 1.3,
      );
    },
    'chat, Discuss': (t) async {
      await pumpCoach(
        t,
        repo: FakeCoachRepository(),
        initial: Routes.coach,
        arguments: CoachArgs(context: InsightScript.recoveryAi.toAskContext()),
        size: _narrow,
        textScale: 1.3,
      );
    },
    'setup': (t) async {
      await pumpCoach(
        t,
        repo: FakeCoachRepository(),
        initial: Routes.coachSetup,
        size: _narrow,
        textScale: 1.3,
      );
      await t.tap(find.byKey(const ValueKey('engine-gemini')));
      await t.pumpAndSettle();
    },
    'memory': (t) async {
      await pumpCoach(
        t,
        repo: _cloudRepo(),
        initial: Routes.coachMemory,
        size: _narrow,
        textScale: 1.3,
      );
    },
    'history': (t) async {
      final repo = FakeCoachRepository();
      _seed(repo, Scripted.verified);
      await pumpCoach(
        t,
        repo: repo,
        initial: Routes.coachHistory,
        size: _narrow,
        textScale: 1.3,
      );
    },
    'settings': (t) async {
      await pumpCoach(
        t,
        repo: _cloudRepo(),
        initial: Routes.settingsCoach,
        size: _narrow,
        textScale: 1.3,
      );
    },
  };

  for (final e in screens.entries) {
    testWidgets('no overflow at 320 px and 1.3× text: ${e.key}', (t) async {
      await e.value(t);
      expect(t.takeException(), isNull);
    });
  }

  for (final name in ['chat, cloud answer, spent budget', 'chat, Discuss']) {
    testWidgets('tap targets and labels: $name', (t) async {
      final h = t.ensureSemantics();
      await screens[name]!(t);
      await expectLater(t, meetsGuideline(androidTapTargetGuideline));
      await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
      h.dispose();
    });
  }

  testWidgets('tap targets and labels: settings', (t) async {
    final h = t.ensureSemantics();
    await pumpCoach(
      t,
      repo: _cloudRepo(),
      initial: Routes.settingsCoach,
      size: const Size(412, 2000),
    );
    await expectLater(t, meetsGuideline(androidTapTargetGuideline));
    await expectLater(t, meetsGuideline(labeledTapTargetGuideline));
    h.dispose();
  });
}
