// SourceRef bookkeeping for tool payloads: every numeric fact a tool
// returns goes through [RefSink.fact], which records a SourceRef and returns
// the compact map the model sees ({"value": 58, "unit": "%", "ref": "r1"}).
//
// Tools run in parallel, so each call gets its own sink with LOCAL ids
// ("#1", "#2", …); [RefSink.renumber] rewrites them to turn-wide ids
// ("r7", …) in call order once every call has finished, so numbering is
// deterministic. Pure Dart.

import 'coach_contracts.dart';
import 'format.dart';
import 'quoted.dart';

class RefSink {
  final List<SourceRef> refs = [];

  /// Records a fact and returns its payload map. [value] is rounded to
  /// [decimals] first: the ref holds exactly what the model is shown.
  Map<String, dynamic> fact(
    String label,
    double value,
    String unit, {
    String? date,
    String? route,
    int decimals = 0,
  }) {
    final v = CoachFormat.round(value, decimals);
    final id = '#${refs.length + 1}';
    refs.add(
      SourceRef(
        id: id,
        label: label,
        value: v,
        unit: unit,
        date: date,
        route: route,
      ),
    );
    return {
      'value': jsonNumber(v),
      'unit': unit,
      if (const {'min', 'clock', '°C', 'steps'}.contains(unit))
        'display': CoachFormat.value(v, unit),
      'ref': id,
    };
  }

  /// Re-records an existing fact (an insight card's ref) under a new local
  /// id, value unchanged. Returns its payload map, like [fact].
  Map<String, dynamic> ref(SourceRef r) {
    final id = '#${refs.length + 1}';
    refs.add(
      SourceRef(
        id: id,
        label: r.label,
        value: r.value,
        unit: r.unit,
        date: r.date,
        route: r.route,
      ),
    );
    return {
      'label': QuotedText.wrap(r.label, max: 80),
      if (r.value != null) 'value': jsonNumber(r.value!),
      if (r.unit != null) 'unit': r.unit,
      if (r.value != null &&
          const {'min', 'clock', '°C', 'steps'}.contains(r.unit))
        'display': CoachFormat.value(r.value!, r.unit),
      if (r.date != null) 'date': r.date,
      'ref': id,
    };
  }

  /// 58.0 → 58 so JSON shows what the text should say.
  static num jsonNumber(double v) =>
      (v - v.roundToDouble()).abs() < 1e-9 && v.abs() < 1e15 ? v.round() : v;

  /// Rewrites local ids ("#3") in [content] and [refs] to "r{offset+3}".
  static (Map<String, dynamic>, List<SourceRef>) renumber(
    Map<String, dynamic> content,
    List<SourceRef> refs,
    int offset,
  ) {
    String map(String id) =>
        id.startsWith('#') ? 'r${offset + int.parse(id.substring(1))}' : id;
    Object? walk(Object? v) {
      if (v is Map) {
        return {
          for (final e in v.entries)
            e.key as String: e.key == 'ref' && e.value is String
                ? map(e.value as String)
                : walk(e.value),
        };
      }
      if (v is List) return [for (final x in v) walk(x)];
      return v;
    }

    return (
      walk(content) as Map<String, dynamic>,
      [
        for (final r in refs)
          SourceRef(
            id: map(r.id),
            label: r.label,
            value: r.value,
            unit: r.unit,
            date: r.date,
            route: r.route,
          ),
      ],
    );
  }
}

/// Routes the UI opens from a source chip.
abstract final class CoachRoutes {
  static const recovery = '/recovery';
  static const sleep = '/sleep';
  static const strain = '/strain';
  static const trends = '/trends';
  static const journal = '/journal';
  static const methodology = '/methodology';
  static const sources = '/settings/sources';
}
