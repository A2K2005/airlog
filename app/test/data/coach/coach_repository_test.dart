// CoachRepositoryImpl over SQLite (sqflite_common_ffi): the v1 → v2
// migration, round-trips, the daily budget meter, the wipe hook, and API
// keys never leaving secure storage.

import 'dart:convert';
import 'dart:io';

import 'package:airlog/data/coach/coach_repository_impl.dart';
import 'package:airlog/data/coach/secret_store.dart';
import 'package:airlog/data/coach/sqlite_coach_store.dart';
import 'package:airlog/data/db/schema.dart';
import 'package:airlog/data/db/sqlite_stores.dart';
import 'package:airlog/data/repositories/in_memory_health_repository.dart';
import 'package:airlog/domain/coach/coach_contracts.dart';
import 'package:airlog/domain/coach/insight_contracts.dart';
import 'package:airlog/data/coach/coach_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const key = 'sk-ant-test-SECRETKEY-987654321';

class _Echo implements LlmClient {
  int calls = 0;
  @override
  CoachProvider get provider => CoachProvider.claude;
  @override
  String get model => 'echo';
  @override
  Future<LlmTurn> next({
    required String system,
    required List<LlmItem> transcript,
    required List<CoachToolSpec> tools,
    required ResponseLength length,
  }) async {
    calls++;
    return const LlmTurn(text: 'ok', inputTokens: 700, outputTokens: 30);
  }
}

void main() {
  sqfliteFfiInit();
  late Directory tmp;
  late Database db;
  late MemorySecretStore secrets;
  late CoachRepositoryImpl repo;
  final now = DateTime(2026, 9, 29, 9);
  final echo = _Echo();

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('airlog_coach');
    db = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'c.db'),
    );
    secrets = MemorySecretStore();
    repo = CoachRepositoryImpl(
      store: SqliteCoachStore(() async => db),
      secrets: secrets,
      clock: () => now,
      clients: (_, _, _) => echo,
    );
  });
  tearDown(() async {
    await db.close();
    await tmp.delete(recursive: true);
  });

  test('a v1 database upgrades to v2 with the coach tables', () async {
    final path = p.join(tmp.path, 'old.db');
    var d = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: path,
      version: 1,
      migrations: const [],
    );
    await d.close();
    d = await AirlogDatabase.open(factory: databaseFactoryFfi, path: path);
    final tables = (await d.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table'",
    )).map((r) => r['name']).toSet();
    expect(tables, containsAll(kCoachTables));
    expect(await d.getVersion(), kSchemaVersion);
    await d.close();
  });

  test('settings, chats, memories and cards round-trip', () async {
    await repo.saveSettings(
      const CoachSettings(
        mode: CoachMode.generalOnly,
        length: ResponseLength.detailed,
        dailyRequestLimit: 20,
      ),
    );
    final fresh = CoachRepositoryImpl(
      store: SqliteCoachStore(() async => db),
      secrets: secrets,
    );
    final s = await fresh.settings();
    expect(s.mode, CoachMode.generalOnly);
    expect(s.dailyRequestLimit, 20);

    final c = await repo.createConversation('How did I sleep');
    for (var i = 0; i < 3; i++) {
      await repo.appendMessage(
        ChatMessage(
          id: 'm$i',
          conversationId: c.id,
          role: i.isEven ? ChatRole.user : ChatRole.assistant,
          text: 'text $i',
          at: now.add(Duration(seconds: i)),
          sampleData: i == 1,
        ),
      );
    }
    final ms = await fresh.messages(c.id);
    expect(ms.map((m) => m.text), ['text 0', 'text 1', 'text 2']);
    expect(ms[1].sampleData, isTrue);
    expect((await fresh.conversations()).single.title, 'How did I sleep');

    final m = await repo.addMemory(
      'Half marathon on 15 Nov',
      category: MemoryCategory.events,
      expiresOn: '2026-11-15',
    );
    await repo.updateMemory(
      m.id,
      'Half marathon on 16 Nov',
      category: MemoryCategory.events,
      expiresOn: '2026-11-16',
    );
    final mem = (await fresh.memories()).single;
    expect(mem.text, 'Half marathon on 16 Nov');
    expect(mem.expiresOn, '2026-11-16');
    expect(() => repo.addMemory('  '), throwsA(isA<CoachException>()));

    final store = SqliteCoachStore(() async => db);
    await store.putFeedback('sleep:2026-09-29', InsightFeedback.hidden);
    expect(
      (await store.feedback())['sleep:2026-09-29'],
      InsightFeedback.hidden,
    );
    await store.putInsight(
      const CachedInsight(
        id: 'sleep:2026-09-29',
        date: '2026-09-29',
        revision: 7,
        algoVersion: 2,
        level: InsightLevel.basic,
        json: {'headline': 'h'},
      ),
    );
    expect((await store.insights('2026-09-29')).single.revision, 7);

    await repo.deleteConversation(c.id);
    expect(await fresh.conversations(), isEmpty);
  });

  test('API keys live only in secure storage', () async {
    await repo.saveSettings(
      const CoachSettings(provider: CoachProvider.claude),
    );
    await repo.saveApiKey(CoachProvider.claude, '  $key ');
    expect(await repo.hasApiKey(CoachProvider.claude), isTrue);
    expect(
      secrets.values[CoachRepositoryImpl.secretKeyFor(CoachProvider.claude)],
      key,
    );
    await repo.createConversation('x');
    await db.close();
    final bytes = await File(p.join(tmp.path, 'c.db')).readAsBytes();
    expect(latin1.decode(bytes, allowInvalid: true).contains(key), isFalse);
    db = await AirlogDatabase.open(
      factory: databaseFactoryFfi,
      path: p.join(tmp.path, 'c.db'),
    );
    await repo.deleteApiKey(CoachProvider.claude);
    expect(await repo.hasApiKey(CoachProvider.claude), isFalse);
  });

  test(
    'client(): offline needs no key; cloud without a key is notConfigured',
    () async {
      expect((await repo.client()).provider, CoachProvider.offline);
      await repo.saveSettings(
        const CoachSettings(provider: CoachProvider.gemini),
      );
      await expectLater(repo.client(), throwsA(isA<CoachException>()));
    },
  );

  test('the meter records usage and blocks once the budget is spent', () async {
    await repo.saveSettings(
      const CoachSettings(provider: CoachProvider.claude, dailyRequestLimit: 2),
    );
    await repo.saveApiKey(CoachProvider.claude, key);
    final c = await repo.client();
    final before = echo.calls;
    for (var i = 0; i < 2; i++) {
      await c.next(
        system: 's',
        transcript: const [LlmUser('q')],
        tools: const [],
        length: ResponseLength.brief,
      );
    }
    final u = await repo.usageToday();
    expect(u!.requests, 2);
    expect(u.inputTokens, 1400);
    expect(u.exhausted, isTrue);
    await expectLater(
      c.next(
        system: 's',
        transcript: const [LlmUser('q')],
        tools: const [],
        length: ResponseLength.brief,
      ),
      throwsA(
        isA<CoachException>().having(
          (e) => e.kind,
          'kind',
          CoachErrorKind.dailyLimit,
        ),
      ),
    );
    expect(echo.calls - before, 2, reason: 'no request once exhausted');
  });

  test('wiping the health data clears chats, memories and cards', () async {
    final health = InMemoryHealthRepository.demo(now: now)..onWipe = repo.wipe;
    final c = await repo.createConversation('x');
    await repo.appendMessage(
      ChatMessage(
        id: 'a',
        conversationId: c.id,
        role: ChatRole.user,
        text: 'q',
        at: now,
      ),
    );
    await repo.addMemory('Goal: 10k in November');
    await health.wipeData();
    expect(await repo.conversations(), isEmpty);
    expect(await repo.memories(), isEmpty);
  });
}
