// SQLite [CoachStore] over the app database (schema v2, kCoachSchemaV2 in
// data/db/schema.dart). The database opens lazily: every call awaits [db].
// Messages are stored as ChatMessage JSON, in insertion order.
//
// Never stores API keys (see secret_store.dart) and is never exported.

import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../domain/coach/coach_contracts.dart';
import '../../domain/coach/insight_contracts.dart';
import 'coach_store.dart';

class SqliteCoachStore implements CoachStore {
  SqliteCoachStore(this._db);

  /// The (lazily opened) app database.
  final Future<Database> Function() _db;

  @override
  Future<String?> getValue(String key) async {
    final rows = await (await _db()).query(
      'coach_kv',
      where: 'key = ?',
      whereArgs: [key],
    );
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> setValue(String key, String? value) async {
    final db = await _db();
    if (value == null) {
      await db.delete('coach_kv', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('coach_kv', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Conversation _conv(Map<String, Object?> r) => Conversation(
    id: r['id'] as String,
    title: r['title'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
  );

  @override
  Future<List<Conversation>> conversations() async => [
    for (final r in await (await _db()).query(
      'coach_conversation',
      orderBy: 'updated_at DESC',
    ))
      _conv(r),
  ];

  @override
  Future<Conversation?> conversation(String id) async {
    final rows = await (await _db()).query(
      'coach_conversation',
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : _conv(rows.first);
  }

  @override
  Future<void> putConversation(Conversation c) async {
    await (await _db()).insert('coach_conversation', {
      'id': c.id,
      'title': c.title,
      'created_at': c.createdAt.millisecondsSinceEpoch,
      'updated_at': c.updatedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<ChatMessage>> messages(String conversationId) async => [
    for (final r in await (await _db()).query(
      'coach_message',
      where: 'conversation_id = ?',
      whereArgs: [conversationId],
      orderBy: 'seq ASC',
    ))
      ChatMessage.fromJson(
        jsonDecode(r['json'] as String) as Map<String, dynamic>,
      ),
  ];

  @override
  Future<void> putMessage(ChatMessage m) async {
    final db = await _db();
    await db.transaction((tx) async {
      final existing = await tx.query(
        'coach_message',
        columns: ['seq'],
        where: 'id = ?',
        whereArgs: [m.id],
      );
      int seq;
      if (existing.isNotEmpty) {
        seq = existing.first['seq'] as int;
      } else {
        final r = await tx.rawQuery(
          'SELECT COALESCE(MAX(seq), -1) + 1 AS n FROM coach_message '
          'WHERE conversation_id = ?',
          [m.conversationId],
        );
        seq = (r.first['n'] as num).toInt();
      }
      await tx.insert('coach_message', {
        'id': m.id,
        'conversation_id': m.conversationId,
        'at': m.at.millisecondsSinceEpoch,
        'seq': seq,
        'json': jsonEncode(m.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<void> deleteConversation(String id) async {
    final db = await _db();
    await db.transaction((tx) async {
      await tx.delete(
        'coach_message',
        where: 'conversation_id = ?',
        whereArgs: [id],
      );
      await tx.delete('coach_conversation', where: 'id = ?', whereArgs: [id]);
    });
  }

  @override
  Future<void> deleteAllConversations() async {
    final db = await _db();
    await db.transaction((tx) async {
      await tx.delete('coach_message');
      await tx.delete('coach_conversation');
    });
  }

  @override
  Future<List<MemoryFact>> memories() async => [
    for (final r in await (await _db()).query(
      'coach_memory',
      orderBy: 'created_at ASC',
    ))
      MemoryFact(
        id: r['id'] as String,
        text: r['text'] as String,
        category: MemoryCategory.values.firstWhere(
          (c) => c.name == r['category'],
          orElse: () => MemoryCategory.preferences,
        ),
        expiresOn: r['expires_on'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at'] as int),
        updatedAt: r['updated_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['updated_at'] as int),
      ),
  ];

  @override
  Future<void> putMemory(MemoryFact m) async {
    await (await _db()).insert('coach_memory', {
      'id': m.id,
      'text': m.text,
      'category': m.category.name,
      'expires_on': m.expiresOn,
      'created_at': m.createdAt.millisecondsSinceEpoch,
      'updated_at': m.updatedAt?.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteMemory(String id) async =>
      (await _db()).delete('coach_memory', where: 'id = ?', whereArgs: [id]);

  @override
  Future<void> deleteAllMemories() async =>
      (await _db()).delete('coach_memory');

  @override
  Future<UsageRow> usage(String day, CoachProvider p) async {
    final rows = await (await _db()).query(
      'coach_usage',
      where: 'day = ? AND provider = ?',
      whereArgs: [day, p.name],
    );
    if (rows.isEmpty) return const UsageRow();
    final r = rows.first;
    return UsageRow(
      requests: r['requests'] as int,
      inputTokens: r['input_tokens'] as int,
      outputTokens: r['output_tokens'] as int,
    );
  }

  @override
  Future<void> putUsage(String day, CoachProvider p, UsageRow row) async {
    await (await _db()).insert('coach_usage', {
      'day': day,
      'provider': p.name,
      'requests': row.requests,
      'input_tokens': row.inputTokens,
      'output_tokens': row.outputTokens,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<CachedInsight>> insights(String date) async => [
    for (final r in await (await _db()).query(
      'coach_insight',
      where: 'date = ?',
      whereArgs: [date],
    ))
      CachedInsight(
        id: r['id'] as String,
        date: r['date'] as String,
        revision: r['revision'] as int,
        algoVersion: r['algo_version'] as int,
        level: InsightLevel.values.firstWhere(
          (l) => l.name == r['level'],
          orElse: () => InsightLevel.basic,
        ),
        json: jsonDecode(r['json'] as String) as Map<String, dynamic>,
      ),
  ];

  @override
  Future<void> putInsight(CachedInsight c) async {
    await (await _db()).insert('coach_insight', {
      'id': c.id,
      'date': c.date,
      'revision': c.revision,
      'algo_version': c.algoVersion,
      'level': c.level.name,
      'json': jsonEncode(c.json),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Map<String, InsightFeedback>> feedback() async => {
    for (final r in await (await _db()).query('coach_insight_feedback'))
      r['id'] as String: InsightFeedback.values.firstWhere(
        (f) => f.name == r['feedback'],
        orElse: () => InsightFeedback.none,
      ),
  };

  @override
  Future<void> putFeedback(String insightId, InsightFeedback f) async {
    await (await _db()).insert('coach_insight_feedback', {
      'id': insightId,
      'feedback': f.name,
      'at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteAllInsights() async {
    final db = await _db();
    await db.transaction((tx) async {
      await tx.delete('coach_insight');
      await tx.delete('coach_insight_feedback');
    });
  }
}
