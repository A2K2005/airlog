// An answer's reply text, on the page with no card. The model cites every
// number with a marker ("[r3]"); the verifier checks each one against the
// answer's tool results, and the markers never reach the screen: checked
// numbers read as plain text. The proof lives behind the answer's ⋯ menu
// ("Checked against your data": each number and where it came from).
//
// A little structure is kept from the model's text: paragraphs, "- " bullet
// lines and **bold**. Anything else prints as written.

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';

/// "[r1]", "[r1, r2]", "[r1][r2]".
final _marker = RegExp(r'\[\s*(r\d+(?:\s*,\s*r\d+)*)\s*\]');
final _bold = RegExp(r'\*\*(.+?)\*\*');

/// Splits [text] into plain runs and citation groups (ref numbers, 1-based
/// in [refs] order). Markers citing nothing in [refs] are dropped.
List<Object> citationRuns(String text, List<SourceRef> refs) {
  final index = {for (var i = 0; i < refs.length; i++) refs[i].id: i + 1};
  final out = <Object>[];
  var at = 0;
  for (final m in _marker.allMatches(text)) {
    if (m.start > at) out.add(text.substring(at, m.start).trimRight());
    final nums = [for (final id in m.group(1)!.split(',')) ?index[id.trim()]];
    if (nums.isNotEmpty) out.add(nums);
    at = m.end;
  }
  if (at < text.length) out.add(text.substring(at));
  return [
    for (final r in out)
      if (r is String)
        r
            .replaceAllMapped(_percent, (m) => '${m[1]}%')
            .replaceAllMapped(_unit, (m) => '${m[1]} ')
      else
        r,
  ];
}

/// "64 %" reads "64%", the way the app writes a percentage everywhere.
final _percent = RegExp(r'(\d) %');

/// A space between a number and its unit ("52 ms", "6h 40m"): kept on one
/// line.
final _unit = RegExp(
  r'(\d) (?=(ms|bpm|min\b|h\b|kcal|km|kg|°C|/min|br/min|nights?\b|days?\b))',
);

/// [text] without its markers or **bold**. With [sources], each marker
/// reads "(source 1)" (the report copied for the developer).
String plainAnswer(String text, List<SourceRef> refs, {bool sources = true}) {
  final b = StringBuffer();
  for (final r in citationRuns(text, refs)) {
    if (r is String) {
      b.write(r.replaceAllMapped(_bold, (m) => m.group(1)!));
    } else if (sources) {
      b.write(' (source ${(r as List<int>).join(', ')})');
    }
  }
  return b.toString().replaceAll(RegExp(r' +([.,;:])'), r'$1');
}

/// The reply: plain text on the page (no card, no citation marks).
class ReplyText extends StatelessWidget {
  const ReplyText({super.key, required this.text, required this.refs});

  final String text;
  final List<SourceRef> refs;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final base = F.tab(F.body).copyWith(color: p.ink);
    final bullet = RegExp(r'^\s*([-*•])\s+');
    final blocks = text
        .replaceAll('\r\n', '\n')
        .split(RegExp(r'\n\s*\n'))
        .where((b) => b.trim().isNotEmpty)
        .toList();
    final children = <Widget>[];
    for (final block in blocks) {
      // Runs of prose lines stay one paragraph; each bullet line is its own
      // row.
      final prose = <String>[];
      void flush() {
        if (prose.isEmpty) return;
        children.add(_line(prose.join('\n'), base));
        prose.clear();
      }

      for (final l in block.split('\n')) {
        if (l.trim().isEmpty) continue;
        if (!bullet.hasMatch(l)) {
          prose.add(l.replaceFirst(RegExp(r'^#+\s*'), ''));
          continue;
        }
        flush();
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: S.x1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 9, right: S.x3),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: p.ink3,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                Expanded(child: _line(l.replaceFirst(bullet, ''), base)),
              ],
            ),
          ),
        );
      }
      flush();
      children.add(const SizedBox(height: S.x2));
    }
    if (children.isNotEmpty) children.removeLast();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _line(String s, TextStyle base) {
    final spans = <InlineSpan>[];
    for (final r in citationRuns(s, refs)) {
      if (r is! String) continue;
      var at = 0;
      for (final m in _bold.allMatches(r)) {
        if (m.start > at) spans.add(TextSpan(text: r.substring(at, m.start)));
        spans.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
        at = m.end;
      }
      if (at < r.length) spans.add(TextSpan(text: r.substring(at)));
    }
    return Text.rich(
      TextSpan(children: spans),
      style: base,
      semanticsLabel: plainAnswer(s, refs, sources: false),
    );
  }
}
