// The thinking state: animated dots and "Thinking", shown while an answer
// is on its way. It waits Motion.fast (160 ms) before it appears, so an
// answer from this phone (often instant) never flashes it. The dots are
// the design system's one bounded loop (ThinkingDots), static under reduced
// motion. A polite live region says "Coach is thinking".

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import 'message_widgets.dart' show CoachEnter;

class ThinkingRow extends StatefulWidget {
  const ThinkingRow({super.key});

  static const label = 'Thinking';
  static const spoken = 'Coach is thinking';

  @override
  State<ThinkingRow> createState() => _ThinkingRowState();
}

class _ThinkingRowState extends State<ThinkingRow> {
  Timer? _grace;
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    _grace = Timer(Motion.fast, () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  void dispose() {
    _grace?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    if (!_shown) return const SizedBox(key: ValueKey('thinking-grace'));
    return CoachEnter(
      play: true,
      child: Semantics(
        liveRegion: true,
        label: ThinkingRow.spoken,
        child: ExcludeSemantics(
          child: Row(
            key: const ValueKey('thinking-row'),
            children: [
              ThinkingDots(color: p.ink2),
              const SizedBox(width: S.x3),
              Text(
                ThinkingRow.label,
                style: F.bodySm.copyWith(color: p.ink2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
