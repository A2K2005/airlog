// Tolerant extraction from Google Health API JSON.
//
// Ported from Pulse `Core/API/JSONExtract.swift` (Luraxx/pulse @ 1f8975c,
// Apache-2.0, see third_party/pulse/NOTICE). The v4 API is new and some
// field names are not fully documented, so values are found by searching
// candidate keys in priority order (breadth-first, depth ≤ 4) instead of
// strict decoding.

abstract final class JsonExtract {
  static DateTime? date(Object? any) {
    if (any is! String) return null;
    final d = DateTime.tryParse(any);
    if (d != null) return d.toLocal();
    return null;
  }

  static double? number(Object? any) {
    if (any is num) return any.toDouble();
    if (any is String) return double.tryParse(any);
    return null;
  }

  /// Google CivilDate objects ({year, month, day}) or strings → "yyyy-MM-dd".
  static String? civilDate(Object? any) {
    if (any is String && any.length >= 10) return any.substring(0, 10);
    if (any is Map) {
      final y = number(any['year']),
          m = number(any['month']),
          d = number(any['day']);
      if (y != null && m != null && d != null) {
        return '${y.toInt().toString().padLeft(4, '0')}-'
            '${m.toInt().toString().padLeft(2, '0')}-'
            '${d.toInt().toString().padLeft(2, '0')}';
      }
    }
    return null;
  }

  static Object? search(Object? object, String key, {int depth = 4}) {
    final queue = <(Object?, int)>[(object, 0)];
    while (queue.isNotEmpty) {
      final (cur, level) = queue.removeAt(0);
      if (level > depth) continue;
      if (cur is Map) {
        if (cur.containsKey(key)) return cur[key];
        for (final v in cur.values) {
          queue.add((v, level + 1));
        }
      } else if (cur is List) {
        for (final v in cur.take(20)) {
          queue.add((v, level + 1));
        }
      }
    }
    return null;
  }

  static double? firstNumber(Object? object, List<String> keys) {
    for (final k in keys) {
      final v = number(search(object, k));
      if (v != null) return v;
    }
    return null;
  }

  static String? firstString(Object? object, List<String> keys) {
    for (final k in keys) {
      final v = search(object, k);
      if (v is String) return v;
      final c = civilDate(v);
      if (c != null) return c;
    }
    return null;
  }

  static DateTime? firstDate(Object? object, List<String> keys) {
    for (final k in keys) {
      final v = date(search(object, k));
      if (v != null) return v;
    }
    return null;
  }

  /// camelCase → snake_case ("heartRateVariability" → "heart_rate_variability").
  static String snakeCase(String camel) => camel.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m.group(0)!.toLowerCase()}',
  );
}
