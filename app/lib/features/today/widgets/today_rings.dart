// The three score rings, sized to the width (three across down to 320 px).

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/results.dart';
import '../today_view_model.dart';

class TodayRings extends StatelessWidget {
  const TodayRings({
    super.key,
    required this.recovery,
    required this.strain,
    required this.sleep,
    this.date,
    this.playDate,
    this.onRecovery,
    this.onStrain,
    this.onSleep,
  });

  final RingVm recovery, strain, sleep;

  /// The day shown. The rings are rebuilt per day, so stepping days draws
  /// each day's rings at once instead of morphing from the last day's (day
  /// switching is done tens of times a day: no animation).
  final String? date;

  /// The day key whose rings may sweep once (today only); null = no sweep.
  final String? playDate;
  final VoidCallback? onRecovery, onStrain, onSleep;

  String? _key(String name) => playDate == null ? null : '$name:$playDate';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final size = ((box.maxWidth - S.x4 * 2) / 3).clamp(80.0, 112.0);
        Widget ring(
          String label,
          RingVm vm,
          Color color, {
          double max = 100,
          String? unit,
          String key = '',
          VoidCallback? onTap,
        }) => ScoreRing(
          key: ValueKey('ring-$key'),
          label: label,
          color: color,
          value: vm.value,
          max: max,
          state: vm.state,
          valueText: vm.valueText,
          unit: unit,
          caption: vm.caption,
          progress: vm.progress,
          size: size,
          playKey: _key(key),
          onTap: onTap,
          reserveCaption: true,
        );
        return Row(
          key: ValueKey('rings-$date'),
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ring(
              'Recovery',
              recovery,
              DomainColors.recoveryZone(recovery.zone ?? RecoveryZone.green),
              unit: '%',
              key: 'recovery',
              onTap: onRecovery,
            ),
            ring(
              'Strain',
              strain,
              DomainColors.strain,
              max: 21,
              key: 'strain',
              onTap: onStrain,
            ),
            ring(
              'Sleep',
              sleep,
              DomainColors.sleep,
              unit: '%',
              key: 'sleep',
              onTap: onSleep,
            ),
          ],
        );
      },
    );
  }
}
