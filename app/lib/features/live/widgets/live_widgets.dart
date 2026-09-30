// Feature-private widgets for the Live screen.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/screen_kit.dart' show InfoButton;
import '../../../design/design.dart';
import '../../../domain/engine/strain.dart' show StrainEngine;
import '../../../domain/results.dart' show StrainMethod;
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
    this.zonesFromMaxHr = false,
  });
  final int zone;
  final List<double> floors;
  final bool active;
  final bool zonesFromMaxHr;

  static final _pct = zoneRanges(
    StrainEngine.displayZoneLowerBounds,
    withRest: true,
  );

  /// The glossary's zone words (COPY_REVIEW §2).
  static const _names = ['Very light', 'Light', 'Moderate', 'Hard', 'Max'];

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final z = zone.clamp(0, 5);
    final name = z == 0 ? 'Resting' : 'Zone $z · ${_names[z - 1]}';
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
          ? zonesFromMaxHr
                ? '$name, $range, based on your max heart rate'
                : '$name, ${range.isEmpty ? _pct[z] : range}'
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
                  ? '$name${range.isEmpty ? '' : ' · $range'}'
                  : 'Your zone shows with the first reading',
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
                ? 'Your workout so far is safe. Move your phone closer to '
                      'your tracker, then tap Reconnect.'
                : 'Your tracker stopped sending. Move your phone closer, '
                      'then reconnect.',
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
        if (s.zoneFloors.isNotEmpty)
          ZoneBand(
            zone: s.zone,
            floors: s.zoneFloors,
            active: s.bpm != null,
            zonesFromMaxHr: s.restingHr == null,
          )
        else
          Text(
            'Heart rate is coming in. Add your birth year in Profile to see '
            'zones and Strain.',
            style: F.bodySm.copyWith(color: p.ink2),
          ),
        const SizedBox(height: S.x6),
        if (recording || cooling) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: _Stat('Time', clockSeconds(s.elapsed))),
                    Expanded(
                      child: _Stat(
                        'Strain',
                        live == null || live.method == StrainMethod.none
                            ? '–'
                            : live.strain.toStringAsFixed(1),
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
            'After you tap Stop, stay still for 1 minute. Airlog measures how '
            'fast your heart rate drops.',
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
                  'Measuring how fast your heart rate drops.',
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
            'Sit still for 2 minutes while Airlog measures your HRV.',
          )
        : missing
        ? (
            'HRV check isn’t available',
            'Your tracker shares heart rate, but not the timing of each beat, '
                'which HRV needs. Your nightly HRV isn’t affected.',
          )
        : s == null
        ? (
            'HRV check',
            'Works after you connect, if your tracker shares the timing of '
                'each beat.',
          )
        : ('HRV check', 'Checking if your tracker shares beat timing…');
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
                StatePill.tone(
                  missing ? PillTone.off : PillTone.locked,
                  missing ? 'Not available' : 'Locked',
                ),
              const InfoButton(
                title: 'HRV check',
                children: [
                  ExplainSection(
                    title: 'What it measures',
                    body:
                        'The tiny changes in time between heartbeats, while '
                        'you sit still for 2 minutes.',
                  ),
                  ExplainSection(
                    title: 'Why it can be locked',
                    body:
                        'It needs the timing of each beat. Some trackers share '
                        'heart rate without it. Your nightly HRV isn’t '
                        'affected.',
                  ),
                ],
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
        GlowPanel(
          glow: GlowRecipes.l6,
          width: double.infinity,
          padding: const EdgeInsets.all(S.x5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const OverLabel('Strain'),
              const SizedBox(height: S.x2),
              DotStat(
                value: w == null || w.method == StrainMethod.none
                    ? DotMatrixNumber.missing
                    : w.strain.toStringAsFixed(1),
                style: F.dot48,
                color: p.on(DomainColors.strain),
                semanticsLabel: w == null || w.method == StrainMethod.none
                    ? 'Strain not measured'
                    : 'Strain ${w.strain.toStringAsFixed(1)}',
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
              const SizedBox(height: S.x4),
              _Plates([
                ('Time', clockSeconds(s.elapsed), null),
                if (w?.avgHr != null) ('Average', '${w!.avgHr!.round()}', 'bpm'),
                if (w?.peakHr != null) ('Peak', '${w!.peakHr!.round()}', 'bpm'),
              ]),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        SettingsTile(
          glow: GlowRecipes.m16,
          title: 'Heart-rate recovery',
          icon: Icons.trending_down_rounded,
          accent: C.recRed,
          dividers: false,
          info: const InfoButton(
            title: 'Heart-rate recovery',
            lede:
                'How far your heart rate drops in the first minute after you '
                'stop.',
            children: [
              ExplainSection(
                title: 'How it’s measured',
                body:
                    'Airlog takes your heart rate when you tap Stop, and again '
                    '60 seconds later (each within 10 seconds). This is HRR-60 '
                    '(Cole et al. 1999).',
              ),
              ExplainSection(
                title: 'Reading it',
                body:
                    'Compare it with your own past workouts, not with a chart.',
              ),
            ],
          ),
          children: [
            if (hrr != null) ...[
              SettingsBlock(
                child: DotStat(
                  value: '${hrr.abs().round()}',
                  unit: hrr >= 0
                      ? 'bpm drop in the first minute'
                      : 'bpm rise in the first minute',
                  style: F.dot40,
                  semanticsLabel:
                      'Heart-rate recovery: your heart rate '
                      '${hrr >= 0 ? 'dropped' : 'rose'} ${hrr.abs().round()} '
                      'beats per minute in the first minute',
                ),
              ),
              SettingsBlock(
                top: 0,
                child: Text(
                  'A bigger drop usually means better fitness.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
              ),
            ] else
              SettingsBlock(
                child: Text(
                  s.coolDownSkipped
                      ? 'Not measured: you skipped the 1-minute cool-down.'
                      : 'Not measured: your tracker didn’t send a reading '
                            'during the cool-down. Keep it connected until the '
                            'minute is up next time.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
              ),
          ],
        ),
        const SizedBox(height: S.x5),
        if (s.saved)
          StatusCard(
            title: 'Saved',
            body:
                'It now counts toward today’s Strain and shows in your '
                'workouts.',
            icon: Icons.check_circle_outline_rounded,
            actionLabel: 'Back to live heart rate',
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
              'Workouts under 1 minute aren’t saved.',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3),
            ),
          ],
          if (s.saveError != null) ...[
            const SizedBox(height: S.x2),
            Text(
              'Couldn’t save: ${s.saveError}',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.on(C.recRed)),
            ),
          ],
          const SizedBox(height: S.x2),
          Center(
            child: AppButton(
              label: 'Delete',
              kind: AppButtonKind.quiet,
              onTap: controller.backToLive,
            ),
          ),
        ],
      ],
    );
  }
}

/// The summary's facts as Medium/19 plates (label, dot-matrix value, unit):
/// side by side, stacked at large text.
class _Plates extends StatelessWidget {
  const _Plates(this.items);
  final List<(String, String, String?)> items;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget plate((String, String, String?) it) => Container(
      padding: const EdgeInsets.all(S.x3),
      decoration: const BoxDecoration(color: C.plate, borderRadius: R.rPanel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(it.$1, style: F.cap.copyWith(color: p.ink2)),
          const SizedBox(height: S.x1),
          DotStat(
            value: it.$2,
            unit: it.$3,
            style: F.dot24,
            semanticsLabel: '${it.$1} ${it.$2}${it.$3 == null ? '' : ' ${it.$3}'}',
          ),
        ],
      ),
    );
    if (bigText(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: S.x2),
            plate(items[i]),
          ],
        ],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: S.x2),
            Expanded(child: plate(items[i])),
          ],
        ],
      ),
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
                'Your tracker stopped sending. Cancel, move your phone '
                'closer, and try again.',
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
          'Rest your arm, stay quiet, and breathe the way you normally do. '
          'Deep breathing changes the result.',
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
            title: 'Not enough clear beats',
            body:
                'Airlog needs at least 30 clear beats and got ${s.rrCount}. '
                'Moving can blur beats. Airlog shows no number rather than a '
                'guess.',
            fix: 'Sit still with your tracker snug, then try again.',
            actionLabel: 'Back to live heart rate',
            onAction: controller.backToLive,
          )
        else ...[
          SettingsTile(
            glow: GlowRecipes.m12,
            title: 'HRV',
            icon: Icons.monitor_heart_outlined,
            accent: C.health,
            dividers: false,
            info: const InfoButton(
              title: 'Your HRV check',
              children: [
                ExplainSection(
                  title: 'Reading it',
                  body:
                      'Higher usually means more relaxed, for you. A daytime '
                      'check reads differently from your overnight HRV, so '
                      'compare checks with each other, not with Recovery.',
                ),
                ExplainSection(
                  title: 'Breathing',
                  body: 'Deep breathing changes the result.',
                ),
              ],
            ),
            children: [
              SettingsBlock(
                child: DotStat(
                  value: s.rmssd!.round().toString(),
                  unit: 'ms',
                  style: F.dot48,
                  color: p.on(C.health),
                  semanticsLabel: 'HRV ${s.rmssd!.round()} milliseconds',
                ),
              ),
              SettingsBlock(
                top: 0,
                child: KeyValueLine('Beats checked', '${s.rrCount}'),
              ),
            ],
          ),
          const SizedBox(height: S.x5),
          if (s.saved)
            StatusCard(
              title: 'Saved',
              body: 'Saved with today’s data.',
              icon: Icons.check_circle_outline_rounded,
              actionLabel: 'Back to live heart rate',
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
                label: 'Delete',
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
