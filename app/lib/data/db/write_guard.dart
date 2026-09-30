import 'dart:async';

import 'package:sqflite/sqflite.dart';

const mutationGenerationKey = 'data.generation';
String pendingRecomputeKey(String mode) => 'data.pending.$mode';
const _generationZone = #airlogWriteGeneration;

class SupersededMutation implements Exception {
  const SupersededMutation();
  @override
  String toString() => 'Data operation superseded by a newer operation';
}

/// Network reads stay outside transactions. Every durable write checks the
/// generation in its own short transaction, including worker-engine writes.
Future<T> guardedWrite<T>(Database db, Future<T> Function(Transaction) body) =>
    db.transaction((tx) async {
      final expected = Zone.current[_generationZone] as (String, int)?;
      if (expected != null && expected.$1 == db.path) {
        final rows = await tx.query(
          'settings',
          where: 'key = ?',
          whereArgs: [mutationGenerationKey],
        );
        final actual = rows.isEmpty
            ? 0
            : int.parse(rows.first['value'] as String);
        if (actual != expected.$2) throw const SupersededMutation();
      }
      return body(tx);
    });

Future<T> sqliteMutation<T>(
  Database db,
  Future<T> Function() body, {
  String? mode,
}) async {
  final inherited = Zone.current[_generationZone] as (String, int)?;
  if (inherited?.$1 == db.path) {
    if (mode != null) {
      await guardedWrite(db, (tx) async {
        await tx.insert('settings', {
          'key': pendingRecomputeKey(mode),
          'value': 'true',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    }
    return body();
  }
  final generation = await db.transaction((tx) async {
    final rows = await tx.query(
      'settings',
      where: 'key = ?',
      whereArgs: [mutationGenerationKey],
    );
    final next =
        (rows.isEmpty ? 0 : int.parse(rows.first['value'] as String)) + 1;
    await tx.insert('settings', {
      'key': mutationGenerationKey,
      'value': '$next',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    if (mode != null) {
      await tx.insert('settings', {
        'key': pendingRecomputeKey(mode),
        'value': 'true',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return next;
  });
  return runZoned(body, zoneValues: {_generationZone: (db.path, generation)});
}
