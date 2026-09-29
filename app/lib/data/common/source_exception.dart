// Typed failure raised by services (ARCHITECTURE.md §5). The sync layer
// catches it per data type, writes a SyncLogEntry and carries on.

import '../../domain/models.dart';

class SourceException implements Exception {
  SourceException(
    this.kind,
    this.dataType,
    this.cause, {
    this.status = 'error',
  });

  final SourceKind kind;

  /// e.g. 'HEART_RATE', 'sleep', 'oauth'.
  final String dataType;
  final Object cause;

  /// SyncLogEntry status: 'error' | 'denied' | 'skipped'.
  final String status;

  @override
  String toString() => 'SourceException(${kind.code}/$dataType: $cause)';
}
