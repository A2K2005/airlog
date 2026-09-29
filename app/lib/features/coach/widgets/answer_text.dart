// An answer's text with its citations: every inline "[r3]" marker becomes a
// small numbered chip, numbered as in the Sources row under the answer. The
// chips are visual only (the Sources row is the tappable part, with 48 dp
// targets); a screen reader hears "source 1" in their place.
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
      if (r is String) r.replaceAllMapped(_unit, (m) => '${m[1]}\u00A0') else r,
  ];
}

/// A space between a number and its unit ("64 %", "52 ms"): kept on one
/// line.
final _unit = RegExp(
  r'(\d) (?=(%|ms|bpm|min\b|h\b|kcal|km|kg|°C|/min|br/min|nights?\b|days?\b))',
);

/// [text] without its markers (for copying and for a screen reader).
String plainAnswer(String text, List<SourceRef> refs) {
  final b = StringBuffer();
  for (final r in citationRuns(text, refs)) {
    if (r is String) {
      b.write(r.replaceAllMapped(_bold, (m) => m.group(1)!));
    } else {
      b.write(' (source ${(r as List<int>).join(', ')})');
    }
  }
  return b.toString().replaceAll(RegExp(r' +([.,;:])'), r'$1');
}

class CitedText extends StatelessWidget {
  const CitedText({super.key, required this.text, required this.refs});

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
        children.add(_line(context, prose.join('\n'), base));
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
                Expanded(
                  child: _line(context, l.replaceFirst(bullet, ''), base),
                ),
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

  Widget _line(BuildContext context, String s, TextStyle base) {
    final spans = <InlineSpan>[];
    for (final r in citationRuns(s, refs)) {
      if (r is String) {
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
      } else {
        for (final n in r as List<int>) {
          spans.add(
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: CiteMark(number: n),
            ),
          );
        }
      }
    }
    return Text.rich(
      TextSpan(children: spans),
      style: base,
      semanticsLabel: plainAnswer(s, refs),
    );
  }
}

/// The small numbered citation chip, inline and in the Sources row.
class CiteMark extends StatelessWidget {
  const CiteMark({super.key, required this.number, this.inline = true});

  final int number;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ExcludeSemantics(
      child: Container(
        margin: inline
            ? const EdgeInsets.only(left: 3, right: 1)
            : EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 17),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: p.wash(C.health, strength: 1.4),
          borderRadius: R.rXs,
        ),
        child: Text(
          '$number',
          textAlign: TextAlign.center,
          style: F
              .tab(F.micro)
              .copyWith(
                color: p.on(C.health),
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
        ),
      ),
    );
  }
}
