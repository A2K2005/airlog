// ProvenanceChip — where a number came from: "Deep-sleep RMSSD · Google
// Health API". Shown next to every metric so a source switch (which starts a
// new baseline) is never invisible.

import 'package:flutter/material.dart';

import '../../domain/models.dart' show Provenance, SourceKind;
import '../tokens/tokens.dart';
import 'pressable.dart';

class ProvenanceChip extends StatelessWidget {
  const ProvenanceChip({
    super.key,
    required this.label,
    this.icon = Icons.sensors_rounded,
    this.onTap,
    this.plain = false,
  });

  factory ProvenanceChip.of(
    Provenance p, {
    Key? key,
    VoidCallback? onTap,
    bool plain = false,
  }) => ProvenanceChip(
    key: key,
    label: describe(p),
    icon: iconFor(p.source),
    onTap: onTap,
    plain: plain,
  );

  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  /// No pill: icon + caption that may wrap to two lines (tight tiles).
  final bool plain;

  static const _known = {
    'ghapi_deep_sleep_rmssd': 'Deep-sleep RMSSD',
    'hc_sleep_mean_rmssd': 'Sleep-mean RMSSD',
    'hc_daily_rhr': 'Daily resting HR',
  };

  static const _tokens = {
    'rmssd': 'RMSSD',
    'hrv': 'HRV',
    'hr': 'HR',
    'rhr': 'resting HR',
    'spo2': 'SpO₂',
    'resp': 'respiratory rate',
    'vo2max': 'VO₂ max',
    'bpm': 'bpm',
  };

  /// Human label for a provenance: known definitions get their proper name,
  /// others are de-snake-cased with acronyms kept.
  static String describe(Provenance p) {
    final known = _known[p.definition];
    final name = known ?? _pretty(p.definition);
    return '$name · ${p.source.label}';
  }

  static String _pretty(String d) {
    final parts = d.split('_').where((s) => s.isNotEmpty).toList();
    if (parts.length > 1 &&
        const {
          'hc',
          'ghapi',
          'ble',
          'takeout',
          'context',
          'demo',
        }.contains(parts.first)) {
      parts.removeAt(0);
    }
    if (parts.isEmpty) return d;
    final words = [for (final w in parts) _tokens[w] ?? w];
    final s = words.join(' ');
    return s[0].toUpperCase() + s.substring(1);
  }

  static IconData iconFor(SourceKind k) => switch (k) {
    SourceKind.healthConnect => Icons.favorite_border_rounded,
    SourceKind.googleHealthApi => Icons.cloud_outlined,
    SourceKind.ble => Icons.bluetooth_rounded,
    SourceKind.takeout => Icons.archive_outlined,
    SourceKind.context => Icons.apps_rounded,
    SourceKind.demo => Icons.science_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final chip = Container(
      padding: plain
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: S.x2, vertical: 3),
      decoration: plain
          ? null
          : BoxDecoration(color: p.card2, borderRadius: R.rPill),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: plain
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: plain ? 1.5 : 0),
            child: Icon(icon, size: 12, color: p.ink3),
          ),
          const SizedBox(width: S.x1 + 1),
          Flexible(
            child: Text(
              label,
              style: F.micro.copyWith(color: p.ink3),
              maxLines: plain ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    final labelled = Semantics(
      label: 'Source: $label',
      child: ExcludeSemantics(child: chip),
    );
    if (onTap == null) return labelled;
    return Pressable(onTap: onTap, child: labelled);
  }
}
