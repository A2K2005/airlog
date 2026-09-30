// Today's smaller cards: the collapsed informational notes and the
// first-load skeleton.

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/results.dart';

/// Informational notes behind one row, so a normal day is not a wall of
/// cards; each is one tap away and says what is missing and how to fix it.
class MoreNotes extends StatefulWidget {
  const MoreNotes({
    super.key,
    required this.notes,
    this.onFixSources,
    this.title,
  });
  final List<StatusNote> notes;
  final VoidCallback? onFixSources;

  /// "About today’s data": the row's title; defaults to "N notes about
  /// this day’s data".
  final String? title;

  @override
  State<MoreNotes> createState() => _MoreNotesState();
}

class _MoreNotesState extends State<MoreNotes> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final n = widget.notes.length;
    final names = widget.notes.map((e) => e.title).join(' · ');
    final heading = widget.title == null
        ? '$n ${n == 1 ? 'note' : 'notes'} about this day’s data'
        : '${widget.title} · $n';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          tone: CardTone.inset,
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          onTap: () => setState(() => _open = !_open),
          semanticLabel:
              '${widget.title == null ? heading : '${widget.title}, $n '
                        '${n == 1 ? 'note' : 'notes'}'}: $names. '
              '${_open ? 'Hide' : 'Show'}.',
          child: ExcludeSemantics(
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 18, color: p.ink2),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        style: F.bodySm.copyWith(
                          color: p.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!_open)
                        Text(
                          names,
                          style: F.cap.copyWith(color: p.ink3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 22,
                  color: p.ink3,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final note in widget.notes) ...[
            const SizedBox(height: S.x3),
            StatusCard.fromNote(note),
          ],
      ],
    );
  }
}

/// A skeleton card for first load (static, no shimmer).
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.lines = 3, this.height});
  final int lines;
  final double? height;

  @override
  Widget build(BuildContext context) => AppCard(
    child: height == null
        ? SkeletonLines(lines: lines)
        : SizedBox(
            height: height,
            child: SkeletonLines(lines: lines),
          ),
  );
}
