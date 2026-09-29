// Today's smaller cards: the one-line summary, the journal card, the
// collapsed informational notes and the profile nudge.

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/models.dart';
import '../../../domain/results.dart';

/// The deterministic plain-English line under the rings. Tapping it opens
/// the Recovery breakdown that backs every number in it.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.why,
    required this.verdict,
    this.onTap,
  });

  /// The signals ("HRV is 14 % above your usual…").
  final String why;

  /// The score and what it suggests, set a step stronger.
  final String verdict;
  final VoidCallback? onTap;

  String get text => why.isEmpty ? verdict : '$why $verdict';

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      onTap: onTap,
      semanticLabel: onTap == null ? null : '$text Opens the breakdown.',
      child: ExcludeSemantics(
        excluding: onTap != null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  if (why.isNotEmpty) TextSpan(text: '$why '),
                  TextSpan(
                    text: verdict,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              style: F.tab(F.body).copyWith(color: p.ink),
            ),
            if (onTap != null) ...[
              const SizedBox(height: S.x3),
              Row(
                children: [
                  Text(
                    'See the breakdown',
                    style: F.cap.copyWith(
                      color: p.ink2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: S.x1),
                  Icon(Icons.chevron_right_rounded, size: 16, color: p.ink3),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Journal entry point. In the evening it asks for tonight's factors;
/// otherwise it is a quiet link. Shows what is already logged.
class JournalCard extends StatelessWidget {
  const JournalCard({
    super.key,
    required this.evening,
    required this.logged,
    required this.onTap,
  });

  final bool evening;
  final Set<JournalFactor> logged;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final names = [
      for (final f in JournalFactor.values)
        if (logged.contains(f)) f.label,
    ];
    final title = names.isNotEmpty
        ? 'Logged tonight'
        : evening
        ? 'Log tonight\'s factors'
        : 'Journal';
    final body = names.isNotEmpty
        ? names.join(' · ')
        : evening
        ? 'Alcohol, late caffeine, screens before bed… A few taps now; in a '
              'few weeks you see what moves your recovery.'
        : 'Tag your evenings to see what moves your next-day recovery.';
    final prompt = evening && names.isEmpty;
    return AppCard(
      onTap: onTap,
      tone: prompt ? CardTone.tinted : CardTone.base,
      accent: DomainColors.sleep,
      semanticLabel: '$title. $body',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: prompt ? p.card : p.wash(DomainColors.sleep),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.edit_note_rounded,
                size: 22,
                color: p.on(DomainColors.sleep),
              ),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: F.head.copyWith(color: p.ink)),
                  const SizedBox(height: 2),
                  Text(body, style: F.bodySm.copyWith(color: p.ink2)),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            Icon(Icons.chevron_right_rounded, size: 22, color: p.ink3),
          ],
        ),
      ),
    );
  }
}

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

  /// "Data notes": the row's title; defaults to "N notes about this day's
  /// data".
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          tone: CardTone.inset,
          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
          onTap: () => setState(() => _open = !_open),
          semanticLabel:
              '$n ${n == 1 ? 'note' : 'notes'} about this day\'s data: '
              '$names. ${_open ? 'Hide' : 'Show'}.',
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
                        widget.title == null
                            ? '$n ${n == 1 ? 'note' : 'notes'} about this day\'s data'
                            : '${widget.title} · $n',
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

/// One quiet line instead of the per-day "assumed max HR" and "Pulse Age
/// needs your birth year" notes.
class ProfileNudge extends StatelessWidget {
  const ProfileNudge({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      tone: CardTone.inset,
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      onTap: onTap,
      semanticLabel:
          'Add your birth year. Heart-rate zones use an assumed maximum '
          'until you do. Opens your profile.',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Icon(Icons.cake_outlined, size: 18, color: p.ink2),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add your birth year',
                    style: F.bodySm.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Heart-rate zones use an assumed maximum until you do.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 22, color: p.ink3),
          ],
        ),
      ),
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
