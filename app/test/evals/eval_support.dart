// Shared helpers for the CI eval suites in test/evals/: JSONL golden files,
// a pass-rate table printed to the test log, and a threshold check.
// No network: every suite runs on demo data with scripted or deterministic
// engines. See docs/EVALS.md.

import 'dart:convert';
import 'dart:io';

/// Rows of a JSONL file under test/evals/data/.
List<Map<String, dynamic>> loadJsonl(String name) {
  final f = File('test/evals/data/$name');
  return [
    for (final line in f.readAsLinesSync())
      if (line.trim().isNotEmpty) jsonDecode(line) as Map<String, dynamic>,
  ];
}

/// One line of a suite's result table.
class EvalRow {
  EvalRow(this.metric, this.passed, this.total, this.threshold,
      {this.higherIsBetter = true});
  final String metric;
  final int passed;
  final int total;

  /// Required rate (0–1): minimum when [higherIsBetter], else maximum.
  final double threshold;
  final bool higherIsBetter;

  double get rate => total == 0 ? 1 : passed / total;
  bool get ok => higherIsBetter ? rate >= threshold - 1e-9 : rate <= threshold + 1e-9;

  String get line {
    final pct = (rate * 100).toStringAsFixed(1).padLeft(6);
    final need = '${higherIsBetter ? '≥' : '≤'}${(threshold * 100).toStringAsFixed(0)}%';
    return '${metric.padRight(46)} ${'$passed/$total'.padLeft(8)} $pct%  '
        '${need.padLeft(6)}  ${ok ? 'PASS' : 'FAIL'}';
  }
}

/// Prints the suite's table (and failures) and writes it to
/// `build/evals/<suite>.txt` for the combined report.
void report(
  String suite,
  List<EvalRow> rows, {
  List<String> failures = const [],
  List<String> notes = const [],
}) {
  final b = StringBuffer()
    ..writeln('── eval: $suite ${'─' * (60 - suite.length).clamp(0, 60)}')
    ..writeln('${'metric'.padRight(46)} ${'pass'.padLeft(8)}   rate   need  result');
  for (final r in rows) {
    b.writeln(r.line);
  }
  for (final n in notes) {
    b.writeln('  · $n');
  }
  for (final f in failures.take(40)) {
    b.writeln('  ✗ $f');
  }
  // ignore: avoid_print
  print(b.toString());
  try {
    final dir = Directory('build/evals')..createSync(recursive: true);
    File('${dir.path}/$suite.txt').writeAsStringSync(b.toString());
  } catch (_) {}
}
