// Feature-private widgets for the Live screen.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../design/design.dart';
import '../../../domain/engine/strain.dart' show StrainEngine;
import '../live_view_model.dart';

/// The hero number: F.n96, tabular (never re-flows). It changes about once
/// a second, so it swaps instantly: a crossfade on every beat would leave the
/// number half-blurred a fifth of the time.
class BigBpm extends StatelessWidget {
  const BigBpm({super.key, required this.bpm});
  final int? bpm;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final b = bpm;
    return Semantics(
      label: b == null ? 'Waiting for heart rate' : '$b beats per minute',
      liveRegion: false,
      child: ExcludeSemantics(
        child: SizedBox(
          height: F.n96.fontSize! * 1.1,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: b == null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x6),
                    child: Text(
                      'Waiting for heart rate…',
                      style: F.head.copyWith(color: p.ink3),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        '$b',
                        maxLines: 1,
                        softWrap: false,
                        style: F.n96.copyWith(color: p.ink),
                      ),
                      const SizedBox(width: S.x2),
                      Text('bpm', style: F.n24.copyWith(color: p.ink3)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Rest + zones 1–5 as six segments; the current one lit in its colour.
class ZoneBand extends StatelessWidget {
  const ZoneBand({
    super.key,
    required this.zone,
    required this.floors,
    this.active = true,
  });
  final int zone;
  final List<double> floors;
  final bool active;

  static final _pct = zoneRanges(
    StrainEngine.displayZoneLowerBounds,
    withRest: true,
  );

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final z = zone.clamp(0, 5);
    final name = z == 0 ? 'Below zone 1' : 'Zone $z';
    final range = floors.length < 5
        ? ''
        : z == 0
        ? 'under ${floors[0].round()} bpm'
        : z < 5
        ? '${floors[z - 1].round()}–${floors[z].round() - 1} bpm'
        : '${floors[4].round()}+ bpm';
    final fade = motion(context, Motion.base, fade: true);
    return Semantics(
      label: active
          ? '$name, ${_pct[z]} of heart-rate reserve'
          : 'Zone unknown',
      child: ExcludeSemantics(
        child: Column(
          children: [
            SizedBox(
              height: 12,
              child: Row(
                children: [
                  for (var i = 0; i <= 5; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(
                      // Colour only (not an AnimatedContainer, which would
                      // animate whatever else changed too).
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(
                          end: active && i == z
                              ? p.mark(DomainColors.hrZone(i))
                              : active && i < z
                              ? p
                                    .mark(DomainColors.hrZone(i))
                                    .withValues(alpha: .28)
                              : p.track,
                        ),
                        duration: fade,
                        curve: Motion.enter,
                        // Fills its 12 px slot (a childless DecoratedBox
                        // would size to nothing).
                        builder: (context, c, _) => DecoratedBox(
                          decoration: BoxDecoration(
                            color: c,
                            borderRadius: R.rPill,
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: S.x2),
            Text(
              active
                  ? '$name · ${_pct[z]} HRR${range.isEmpty ? '' : ' · $range'}'
                  : 'Zone appears with the first reading',
              textAlign: TextAlign.center,
              style: F
                  .tab(F.bodySm)
                  .copyWith(
                    color: active && z > 0
                        ? p.on(DomainColors.hrZone(z))
                        : p.ink2,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Column(
      children: [
        // Ticks every second: an instant, tabular swap (no crossfade).
        Text(
          value,
          maxLines: 1,
          softWrap: false,
          style: F.n32.copyWith(color: color ?? p.ink),
        ),
        const SizedBox(height: S.x1),
        Text(
          label.toUpperCase(),
          style: F.over.copyWith(color: p.ink3),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class LiveDashboard extends StatelessWidget {
  const LiveDashboard({
    super.key,
    required this.state,
    required this.controller,
  });
  final LiveState state;
  final LiveController controller;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = state;
    final recording = s.stage == LiveStage.recording;
    final cooling = s.stage == LiveStage.coolDown;
    final live = s.live;
    final zones = live?.zoneMinutes ?? const <double>[];
    final zt = zones.fold(0.0, (a, b) => a + b);
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
      children: [
        if (s.lost) ...[
          StatusCard(
            title: 'Connection lost',
            body: recording || cooling
                ? 'Your session so far is kept. Move the phone closer to the '
                      'tracker; it reconnects when you tap below.'
                : 'Your tracker stopped sending. Move the phone closer and '
                      'reconnect.',
            tone: StatusTone.warning,
            icon: Icons.bluetooth_disabled_rounded,
            actionLabel: 'Reconnect',
            onAction: controller.reconnect,
          ),
          const SizedBox(height: S.x4),
        ],
        Row(
          children: [
            Icon(
              Icons.bluetooth_connected_rounded,
              size: 16,
              color: p.on(DomainColors.strain),
            ),
            const SizedBox(width: S.x2),
            Expanded(
              child: Text(
                s.device?.name ?? 'Tracker',
                style: F.bodySm.copyWith(
                  color: p.ink2,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (recording)
              const StatePill(
                label: 'Recording',
                color: C.recRed,
                icon: Icons.fiber_manual_record_rounded,
              )
            else if (cooling)
              const StatePill(
                label: 'Cool-down',
                color: C.sky,
                icon: Icons.timer_outlined,
              ),
          ],
        ),
        const SizedBox(height: S.x5),
        Center(child: BigBpm(bpm: s.bpm)),
        const SizedBox(height: S.x4),
        ZoneBand(zone: s.zone, floors: s.zoneFloors, active: s.bpm != null),
        const SizedBox(height: S.x6),
        if (recording || cooling) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _Stat('Elapsed', clockSeconds(s.elapsed))),
                    Expanded(
                      child: _Stat(
                        'Strain',
                        live == null ? '0.0' : live.strain.toStringAsFixed(1),
                        color: p.on(DomainColors.strain),
                      ),
                    ),
                    Expanded(
                      child: _Stat(
                        'Avg bpm',
                        s.avgHr == null ? '–' : '${s.avgHr!.round()}',
                      ),
                    ),
                  ],
                ),
                if (zt > 0) ...[
                  const SizedBox(height: S.x4),
                  SizedBox(
                    height: 12,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: ZoneBar([for (final m in zones) m / zt], p),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: S.x4),
        ],
        if (cooling) ...[
          CoolDownCard(left: s.coolDownLeft, onSkip: controller.skipCoolDown),
          const SizedBox(height: S.x4),
        ],
        if ((recording || cooling) &&
            s.startAt != null &&
            s.trace.length > 1) ...[
          AppCard(
            child: ZoneTimeline(
              title: 'This session',
              samples: s.trace,
              start: s.startAt!,
              end: s.trace.last.t.isAfter(s.startAt!)
                  ? s.trace.last.t
                  : s.startAt!,
              zoneFloors: s.zoneFloors,
              height: 110,
              maxGapMinutes: 1,
            ),
          ),
          const SizedBox(height: S.x4),
        ],
        if (recording)
          AppButton(
            label: 'Stop',
            icon: Icons.stop_rounded,
            expand: true,
            onTap: controller.stopWorkout,
          )
        else if (!cooling) ...[
          AppButton(
            label: 'Start workout',
            icon: Icons.play_arrow_rounded,
            accent: DomainColors.strain,
            expand: true,
            onTap: s.lost ? null : controller.startWorkout,
          ),
          const SizedBox(height: S.x4),
          HrvCheckCard(state: s, onStart: controller.startHrvCheck),
          const SizedBox(height: S.x4),
          Center(
            child: AppButton(
              label: 'Disconnect',
              kind: AppButtonKind.quiet,
              onTap: controller.disconnect,
            ),
          ),
        ],
        if (recording) ...[
          const SizedBox(height: S.x3),
          Text(
            'After Stop, keep still for 60 seconds: the drop in heart rate '
            'over that minute is your heart-rate recovery.',
            textAlign: TextAlign.center,
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ],
    );
  }
}

class CoolDownCard extends StatelessWidget {
  const CoolDownCard({super.key, required this.left, required this.onSkip});
  final int left;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final done = 1 - left / kCoolDownSeconds;
    return AppCard(
      tone: CardTone.tinted,
      accent: C.sky,
      child: Row(
        children: [
          SizedBox.square(
            dimension: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size.square(64),
                  painter: Ring(done, p.mark(C.sky), p.track, stroke: 6),
                ),
                Text('$left', style: F.n24.copyWith(color: p.ink)),
              ],
            ),
          ),
          const SizedBox(width: S.x4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay still for $left s',
                  style: F.head.copyWith(color: p.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  'Measuring heart-rate recovery (HRR-60).',
                  style: F.cap.copyWith(color: p.ink2),
                ),
                const SizedBox(height: S.x2),
                AppButton(
                  label: 'Skip',
                  kind: AppButtonKind.secondary,
                  compact: true,
                  onTap: onSkip,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The on-demand HRV check: locked until the tracker sends RR intervals.
/// [state] null = not connected yet.
class HrvCheckCard extends StatelessWidget {
  const HrvCheckCard({super.key, required this.state, this.onStart});
  final LiveState? state;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = state;
    final unlocked = s != null && s.rrAvailable;
    final missing = s != null && s.rrMissing;
    final (String title, String body) = unlocked
        ? (
            'HRV check',
            'Two minutes sitting still. RMSSD from the time between '
                'individual beats.',
          )
        : missing
        ? (
            'HRV check unavailable',
            'Your tracker sends heart rate but not the time between beats '
                '(RR intervals), and HRV is computed from those. Its '
                'broadcast may simply not include them. Your '
                'nightly HRV from sleep is unaffected.',
          )
        : s == null
        ? (
            'HRV check',
            'Unlocks after you connect, if your tracker sends '
                'beat-to-beat (RR) intervals.',
          )
        : (
            'HRV check',
            'Checking whether your tracker sends beat-to-beat '
                'intervals…',
          );
    return AppCard(
      tone: unlocked ? CardTone.base : CardTone.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                unlocked ? Icons.favorite_rounded : Icons.lock_outline_rounded,
                size: 18,
                color: unlocked ? p.on(C.health) : p.ink3,
              ),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(title, style: F.head.copyWith(color: p.ink)),
              ),
              if (!unlocked)
                StatePill(
                  label: missing ? 'No RR data' : 'Locked',
                  color: C.neutral,
                ),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(body, style: F.bodySm.copyWith(color: p.ink2)),
          if (unlocked) ...[
            const SizedBox(height: S.x3),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'Start HRV check',
                icon: Icons.timer_outlined,
                kind: AppButtonKind.secondary,
                onTap: onStart,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class WorkoutSummary extends StatelessWidget {
  const WorkoutSummary({
    super.key,
    required this.state,
    required this.controller,
  });
  final LiveState state;
  final LiveController controller;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = state;
    final w = s.live;
    final zones = w?.zoneMinutes ?? const <double>[];
    final zt = zones.fold(0.0, (a, b) => a + b);
    final hrr = s.hrr60;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    w == null ? '0.0' : w.strain.toStringAsFixed(1),
                    style: F.n64.copyWith(color: p.on(DomainColors.strain)),
                  ),
                  const SizedBox(width: S.x2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'STRAIN',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x4),
              KeyValueLine('Duration', clockSeconds(s.elapsed)),
              if (w?.avgHr != null)
                KeyValueLine('Average', '${w!.avgHr!.round()} bpm'),
              if (w?.peakHr != null)
                KeyValueLine('Peak', '${w!.peakHr!.round()} bpm'),
              if (w?.trimp != null)
                KeyValueLine('TRIMP (cross-check)', '${w!.trimp!.round()}'),
              if (zt > 0) ...[
                const SizedBox(height: S.x3),
                SizedBox(
                  height: 12,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: ZoneBar([for (final m in zones) m / zt], p),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        AppCard(
          semanticLabel: hrr == null
              ? 'Heart-rate recovery not measured'
              : 'Heart-rate recovery ${hrr.round()} beats per minute in the first minute',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Heart-rate recovery',
                  style: F.bodySm.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: S.x3),
                if (hrr != null) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${hrr >= 0 ? '−' : '+'}${hrr.abs().round()}',
                        style: F.n44.copyWith(color: p.ink),
                      ),
                      const SizedBox(width: S.x2),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 5),
                        child: Text(
                          'bpm in the first minute',
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x2),
                  Text(
                    'How fast your heart rate falls after effort (HRR-60, Cole '
                    'et al. 1999). A bigger drop generally means a fitter '
                    'recovery; compare it with your own past sessions rather '
                    'than a chart.',
                    style: F.bodySm.copyWith(color: p.ink2),
                  ),
                ] else
                  Text(
                    s.coolDownSkipped
                        ? 'Not measured: the 60-second cool-down was skipped.'
                        : 'Not measured: no reading at Stop and 60 s later '
                              '(within 10 s). Keep your tracker connected through the '
                              'cool-down next time.',
                    style: F.bodySm.copyWith(color: p.ink2),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: S.x5),
        if (s.saved)
          StatusCard(
            title: 'Saved',
            body: 'The workout is in today’s strain and workouts list.',
            icon: Icons.check_circle_outline_rounded,
            actionLabel: 'Back to live',
            onAction: controller.backToLive,
          )
        else ...[
          AppButton(
            label: s.saving ? 'Saving…' : 'Save workout',
            icon: Icons.save_alt_rounded,
            accent: DomainColors.strain,
            expand: true,
            onTap: s.saving || s.elapsed < 60 ? null : controller.saveWorkout,
          ),
          if (s.elapsed < 60) ...[
            const SizedBox(height: S.x2),
            Text(
              'Workouts under a minute are not saved.',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
          if (s.saveError != null) ...[
            const SizedBox(height: S.x2),
            Text(
              'Could not save: ${s.saveError}',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.on(C.recRed)),
            ),
          ],
          const SizedBox(height: S.x2),
          Center(
            child: AppButton(
              label: 'Discard',
              kind: AppButtonKind.quiet,
              onTap: controller.backToLive,
            ),
          ),
        ],
      ],
    );
  }
}

class HrvRunning extends StatelessWidget {
  const HrvRunning({super.key, required this.state, required this.onCancel});
  final LiveState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = state;
    final done = 1 - s.hrvLeft / kHrvCheckSeconds;
    final size = math.min(
      MediaQuery.sizeOf(context).width - S.gutter * 2,
      220.0,
    );
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, S.x10),
      children: [
        if (s.lost) ...[
          const StatusCard(
            title: 'Connection lost',
            body:
                'Beats stopped arriving. Cancel and try again with the phone '
                'closer to your tracker.',
            tone: StatusTone.warning,
          ),
          const SizedBox(height: S.x4),
        ],
        Center(
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size.square(size),
                  painter: Ring(done, p.mark(C.health), p.track, stroke: 10),
                ),
                Semantics(
                  label: '${s.hrvLeft} seconds left',
                  child: ExcludeSemantics(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          clockSeconds(s.hrvLeft),
                          style: F.n64.copyWith(color: p.ink),
                        ),
                        Text('LEFT', style: F.over.copyWith(color: p.ink3)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: S.x6),
        Text(
          'Sit still and breathe normally',
          textAlign: TextAlign.center,
          style: F.t2.copyWith(color: p.ink),
        ),
        const SizedBox(height: S.x2),
        Text(
          'Rest your arm, keep quiet, and breathe the way you usually do. '
          'Paced or deep breathing raises RMSSD, so natural breathing keeps '
          'checks comparable with each other.',
          textAlign: TextAlign.center,
          style: F.bodySm.copyWith(color: p.ink2),
        ),
        const SizedBox(height: S.x4),
        Text(
          '${s.rrCount} beats so far${s.bpm == null ? '' : ' · ${s.bpm} bpm'}',
          textAlign: TextAlign.center,
          style: F.tab(F.cap).copyWith(color: p.ink3),
        ),
        const SizedBox(height: S.x6),
        Center(
          child: AppButton(
            label: 'Cancel',
            kind: AppButtonKind.secondary,
            onTap: onCancel,
          ),
        ),
      ],
    );
  }
}

class HrvResult extends StatelessWidget {
  const HrvResult({super.key, required this.state, required this.controller});
  final LiveState state;
  final LiveController controller;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = state;
    final ok = s.rmssd != null;
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
      children: [
        if (!ok)
          StatusCard(
            title: 'Not enough clean beats',
            body:
                'RMSSD needs at least 30 clean beat-to-beat intervals '
                '(${s.rrCount} arrived; movement and missed beats are '
                'filtered out). No number is shown rather than a guess.',
            fix: 'Sit still with your tracker snug, then try again.',
            actionLabel: 'Back to live',
            onAction: controller.backToLive,
          )
        else ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('RMSSD', style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x2),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      s.rmssd!.round().toString(),
                      style: F.n64.copyWith(color: p.on(C.health)),
                    ),
                    const SizedBox(width: S.x2),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('ms', style: F.head.copyWith(color: p.ink3)),
                    ),
                  ],
                ),
                const SizedBox(height: S.x4),
                KeyValueLine('Beats analysed', '${s.rrCount}'),
                const SizedBox(height: S.x3),
                Text(
                  'RMSSD is the beat-to-beat variation your vagus nerve '
                  'drives: higher is more relaxed, for you. A spot check '
                  'while awake reads differently from your overnight HRV, '
                  'so compare checks with each other, not with Recovery.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x5),
          if (s.saved)
            StatusCard(
              title: 'Saved',
              body: 'The check is stored with today’s data.',
              icon: Icons.check_circle_outline_rounded,
              actionLabel: 'Back to live',
              onAction: controller.backToLive,
            )
          else ...[
            AppButton(
              label: s.saving ? 'Saving…' : 'Save HRV check',
              icon: Icons.save_alt_rounded,
              accent: C.health,
              expand: true,
              onTap: s.saving ? null : controller.saveHrvCheck,
            ),
            const SizedBox(height: S.x2),
            Center(
              child: AppButton(
                label: 'Discard',
                kind: AppButtonKind.quiet,
                onTap: controller.backToLive,
              ),
            ),
          ],
        ],
      ],
    );
  }
}
