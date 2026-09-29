// Component gallery (debug builds: route /gallery). Every component and chart
// in every state, with fixed sample values. It is also the visual QA surface:
// test/goldens/gallery_golden_test.dart renders each section in dark and
// light, and test/design/components_test.dart pumps every section at 320 px
// and at 1.3× text looking for overflow.
//
// When you add a component to lib/design, add it to a section here — the
// tokens test fails if a public widget in lib/design/components is missing.

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/results.dart';
import 'gallery_samples.dart';
import 'gallery_tiles.dart';

enum GallerySection {
  design('Design tiles'),
  rings('Score rings'),
  tiles('Metric tiles'),
  status('Honesty'),
  controls('Controls'),
  trends('Trend charts'),
  sleep('Sleep charts'),
  strain('Strain charts'),
  sheet('Explain sheet'),
  edges('Edge cases'),
  loading('Loading and empty');

  const GallerySection(this.title);
  final String title;
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key, this.section, this.animate = true});

  /// Fixed section (goldens, tests). Null shows the section picker.
  final GallerySection? section;

  /// False turns off the one-time ring sweeps (goldens).
  final bool animate;

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  late GallerySection _section = widget.section ?? GallerySection.rings;
  bool _reduced = false;
  int _replay = 0;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final fixed = widget.section != null;
    Widget body = GalleryBody(
      key: ValueKey('${_section.name}-$_replay'),
      section: _section,
      playSeed: widget.animate && !fixed ? 'gallery-$_replay' : null,
    );
    if (_reduced) {
      body = MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: body,
      );
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ScreenHeader(
              title: _section.title,
              subtitle: 'Component gallery',
              actions: fixed
                  ? const []
                  : [
                      AppIconButton(
                        icon: _reduced
                            ? Icons.motion_photos_off_outlined
                            : Icons.motion_photos_on_outlined,
                        semanticLabel: _reduced
                            ? 'Reduced motion on'
                            : 'Reduced motion off',
                        onTap: () => setState(() => _reduced = !_reduced),
                      ),
                      AppIconButton(
                        icon: Icons.replay_rounded,
                        semanticLabel: 'Replay animations',
                        onTap: () {
                          ScoreRing.resetPlayed();
                          setState(() => _replay++);
                        },
                      ),
                    ],
            ),
            if (!fixed)
              SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: S.gutter - 4),
                  children: [
                    for (final s in GallerySection.values)
                      Pressable(
                        selected: s == _section,
                        onTap: () => setState(() => _section = s),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: S.x3,
                            vertical: S.x2,
                          ),
                          decoration: BoxDecoration(
                            color: s == _section ? p.ink : p.card2,
                            borderRadius: R.rPill,
                          ),
                          child: Text(
                            s.title,
                            style: F.cap.copyWith(
                              fontWeight: FontWeight.w700,
                              color: s == _section ? p.inkInverse : p.ink2,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }
}

/// One section's cases in a scroll view.
class GalleryBody extends StatelessWidget {
  const GalleryBody({super.key, required this.section, this.playSeed});
  final GallerySection section;

  /// Non-null enables ring sweeps keyed by this seed.
  final String? playSeed;

  @override
  Widget build(BuildContext context) {
    final cases = switch (section) {
      GallerySection.design => designTileCases(),
      GallerySection.rings => _rings(),
      GallerySection.tiles => _tiles(),
      GallerySection.status => _status(),
      GallerySection.controls => _controls(),
      GallerySection.trends => _trends(),
      GallerySection.sleep => _sleep(),
      GallerySection.strain => _strain(),
      GallerySection.sheet => _sheet(),
      GallerySection.edges => _edges(),
      GallerySection.loading => _loading(),
    };
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x10),
      children: [
        for (var i = 0; i < cases.length; i++) ...[
          if (i > 0) const SizedBox(height: S.x5),
          cases[i],
        ],
      ],
    );
  }

  String? _key(String k) => playSeed == null ? null : '$playSeed:$k';

  // ── sections ──────────────────────────────────────────────────────────

  List<Widget> _rings() => [
    _Case(
      'Measured · recovery · strain · sleep',
      _RingRow(
        builder: (size) => [
          ScoreRing(
            label: 'Recovery',
            value: 72,
            unit: '%',
            color: DomainColors.recovery(72),
            size: size,
            playKey: _key('rec'),
          ),
          ScoreRing(
            label: 'Strain',
            value: 12.4,
            max: 21,
            valueText: '12.4',
            color: DomainColors.strain,
            caption: 'Target 14.0',
            size: size,
            playKey: _key('str'),
          ),
          ScoreRing(
            label: 'Sleep',
            value: 88,
            unit: '%',
            color: DomainColors.sleep,
            caption: '7h 12m',
            size: size,
            playKey: _key('slp'),
          ),
        ],
      ),
    ),
    _Case(
      'Provisional · hero size',
      Center(
        child: ScoreRing(
          label: 'Recovery',
          value: 58,
          unit: '%',
          color: DomainColors.recovery(58),
          state: RingState.provisional,
          caption: 'Provisional · baseline night 9 of 14',
          size: 164,
          playKey: _key('hero'),
        ),
      ),
    ),
    _Case(
      'Calibrating · loading · no data',
      _RingRow(
        builder: (size) => [
          ScoreRing(
            label: 'Recovery',
            color: DomainColors.recovery(72),
            state: RingState.calibrating,
            progress: 3 / 14,
            caption: 'Night 3 of 14',
            size: size,
          ),
          ScoreRing(
            label: 'Strain',
            color: DomainColors.strain,
            state: RingState.loading,
            size: size,
          ),
          ScoreRing(
            label: 'Sleep',
            color: DomainColors.sleep,
            state: RingState.noData,
            caption: 'Band not worn',
            size: size,
          ),
        ],
      ),
    ),
  ];

  List<Widget> _tiles() => [
    _Case(
      'MetricTile.health · in range · above · calibrating · no data',
      Column(
        children: [
          _Pair(
            MetricTile.health(
              Samples.metric(
                HealthMetricKind.restingHr,
                BandState.inRange,
                54,
                55,
                1.8,
                prov: Samples.provHcRhr,
              ),
              chart: Sparkline(
                values: Samples.rhr7,
                color: DomainColors.health,
                lower: 52,
                upper: 58,
              ),
            ),
            MetricTile.health(
              Samples.metric(
                HealthMetricKind.hrv,
                BandState.above,
                59,
                47,
                4.2,
                prov: Samples.provGhHrv,
              ),
              chart: Sparkline(
                values: [for (final v in Samples.hrv30.skip(23)) v],
                color: DomainColors.health,
              ),
            ),
          ),
          const SizedBox(height: S.x3),
          _Pair(
            MetricTile.health(
              Samples.metric(
                HealthMetricKind.skinTemp,
                BandState.calibrating,
                -0.4,
                0,
                .2,
              ),
            ),
            const MetricTile(
              label: 'SpO₂',
              band: BandStatus.noData,
              caption: 'Needs Enhanced mode',
            ),
          ),
        ],
      ),
    ),
    _Case(
      'Signed metric · "same as usual" · one-sided band (SpO₂ floor)',
      Column(
        children: [
          _Pair(
            MetricTile.health(
              Samples.metric(
                HealthMetricKind.skinTemp,
                BandState.inRange,
                .2,
                .1,
                .2,
              ),
            ),
            MetricTile.health(
              Samples.metric(
                HealthMetricKind.restingHr,
                BandState.inRange,
                55.2,
                54.8,
                1.8,
              ),
            ),
          ),
          const SizedBox(height: S.x3),
          _Pair(
            MetricTile.health(
              Samples.spo2(96),
              chart: Sparkline(
                values: Samples.spo2Nights,
                color: DomainColors.health,
                lower: 94,
              ),
            ),
            MetricTile.health(
              Samples.metric(
                HealthMetricKind.skinTemp,
                BandState.inRange,
                -.3,
                .1,
                .2,
              ),
            ),
          ),
        ],
      ),
    ),
    const _Case(
      'TrendArrow · only when significant',
      Wrap(
        spacing: S.x5,
        runSpacing: S.x2,
        children: [
          _Labelled(
            'HRV',
            TrendArrow(trend: Samples.trendUp, upIsGood: true, showLabel: true),
          ),
          _Labelled(
            'Resting HR',
            TrendArrow(
              trend: Samples.trendDown,
              upIsGood: false,
              showLabel: true,
            ),
          ),
          _Labelled(
            'Resp. rate',
            TrendArrow(
              trend: Samples.trendUp,
              upIsGood: false,
              showLabel: true,
            ),
          ),
          _Labelled(
            'Noise → nothing',
            TrendArrow(trend: Samples.trendNoise, upIsGood: true),
          ),
        ],
      ),
    ),
    _Case(
      'ProvenanceChip',
      Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          ProvenanceChip.of(Samples.provGhHrv),
          ProvenanceChip.of(Samples.provHcRhr),
          ProvenanceChip.of(Samples.provHcResp),
        ],
      ),
    ),
    _Case(
      'AppCard (Pressable) · StatePill · DemoBadge',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppCard(
            onTap: () {},
            child: Row(
              children: [
                Expanded(
                  child: Builder(
                    builder: (c) => Text(
                      'Press me: scales to 0.97',
                      style: F.body.copyWith(color: P.of(c).ink),
                    ),
                  ),
                ),
                Builder(
                  builder: (c) =>
                      Icon(Icons.chevron_right_rounded, color: P.of(c).ink3),
                ),
              ],
            ),
          ),
          const SizedBox(height: S.x3),
          const Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              StatePill(label: 'In your range', color: C.health),
              StatePill(label: 'Above your range', color: C.amber),
              StatePill(label: 'Provisional', color: C.sleep),
              DemoBadge(),
            ],
          ),
        ],
      ),
    ),
  ];

  List<Widget> _status() => [
    _Case(
      'FreshnessLine · fresh · stale · syncing · failed',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FreshnessLine(
            now: Samples.now,
            lastDataAt: plusMin(Samples.now, -12),
            lastSyncAt: plusMin(Samples.now, -2),
          ),
          const SizedBox(height: S.x2),
          FreshnessLine(
            now: Samples.now,
            lastDataAt: plusMin(Samples.now, -9 * 60),
            lastSyncAt: plusMin(Samples.now, -3),
          ),
          const SizedBox(height: S.x2),
          FreshnessLine(
            now: Samples.now,
            lastDataAt: plusMin(Samples.now, -40),
            syncing: true,
          ),
          const SizedBox(height: S.x2),
          FreshnessLine(
            now: Samples.now,
            lastDataAt: plusMin(Samples.now, -40),
            error: 'Health Connect permission missing',
          ),
        ],
      ),
    ),
    _Case('CalibrationBanner', CalibrationBanner(have: 9, onTap: () {})),
    const _Case(
      'PreparingNote · first launch, nothing stored yet',
      PreparingNote(
        title: PreparingNote.demoTitle,
        icon: Icons.science_outlined,
      ),
    ),
    _Case(
      'StatusCard.fromNote · info with fix + action · warning',
      Column(
        children: [
          StatusCard.fromNote(
            Samples.note,
            actionLabel: 'How to wear it',
            onAction: () {},
          ),
          const SizedBox(height: S.x3),
          StatusCard.fromNote(Samples.warnNote),
        ],
      ),
    ),
  ];

  List<Widget> _controls() => [
    _Case(
      'ScreenHeader · DaySwitcher',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: ScreenHeader(
              title: 'Today',
              actions: [
                AppIconButton(
                  icon: Icons.settings_outlined,
                  semanticLabel: 'Settings',
                  onTap: () {},
                ),
              ],
              below: FreshnessLine(
                now: Samples.now,
                lastDataAt: plusMin(Samples.now, -12),
                lastSyncAt: plusMin(Samples.now, -2),
              ),
            ),
          ),
          const SizedBox(height: S.x3),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: S.x2,
            children: [
              DaySwitcher(
                date: Samples.today,
                latest: Samples.today,
                today: Samples.today,
                onShift: (_) {},
              ),
              DaySwitcher(
                date: '2026-09-24',
                latest: Samples.today,
                today: Samples.today,
                onShift: (_) {},
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          const DaySwitcherSkeleton(),
        ],
      ),
    ),
    _Case(
      'OverLabel · KeyValueLine · BulletLine · quiet button on the edge',
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OverLabel('Data'),
            const SizedBox(height: S.x2),
            const KeyValueLine('Records', '1 440'),
            const KeyValueLine('Median spacing', '62 s'),
            const SizedBox(height: S.x2),
            const BulletLine(
              'Only while the Live screen is open.',
              strong: 'Bluetooth.',
            ),
            const BulletLine(
              'Keep the band snug on your wrist.',
              icon: Icons.watch_outlined,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: AppButton(
                label: 'The exact formula',
                kind: AppButtonKind.quiet,
                compact: true,
                icon: Icons.functions_rounded,
                onTap: () {},
              ),
            ),
          ],
        ),
      ),
    ),
    const _Case('SegmentedRange · SegmentedControl', _SegmentsDemo()),
    _Case(
      'SectionHeader',
      SectionHeader(
        title: 'Health monitor',
        subtitle: 'Against your 30-day baseline',
        actionLabel: 'How it works',
        onAction: () {},
      ),
    ),
    _Case(
      'AppButton · AppIconButton',
      Wrap(
        spacing: S.x2,
        runSpacing: S.x2,
        children: [
          AppButton(label: 'Export data', onTap: () {}),
          AppButton(
            label: 'Sync now',
            icon: Icons.sync_rounded,
            kind: AppButtonKind.secondary,
            onTap: () {},
          ),
          AppButton(
            label: 'Start workout',
            accent: DomainColors.strain,
            icon: Icons.play_arrow_rounded,
            onTap: () {},
          ),
          AppButton(
            label: 'Learn more',
            kind: AppButtonKind.quiet,
            onTap: () {},
          ),
          const AppButton(label: 'Disabled'),
          AppIconButton(
            icon: Icons.info_outline_rounded,
            semanticLabel: 'About',
            filled: true,
            onTap: () {},
          ),
        ],
      ),
    ),
  ];

  List<Widget> _trends() => [
    AppCard(
      child: BaselineBandChart(
        title: 'Heart rate variability',
        unit: 'ms',
        values: Samples.hrv30,
        mean: 47,
        lower: 47 - 1.65 * 4.2,
        upper: 47 + 1.65 * 4.2,
        color: DomainColors.health,
        xLabels: Samples.xLabelsFor(30),
        trailing: const TrendArrow(
          trend: Samples.trendUp,
          upIsGood: true,
          metric: 'HRV',
        ),
        // A change of source on day 20 of 30: a dotted vertical.
        xMarks: const [19 / 29],
        footnote:
            'Dotted line: the source changed, so a new baseline starts there.',
      ),
    ),
    AppCard(
      child: Builder(
        builder: (c) => BaselineBandChart(
          title: 'SpO₂ · one-sided band',
          unit: '%',
          values: Samples.spo2Nights,
          mean: 96.2,
          lower: 94,
          color: DomainColors.health,
          showUnit: false,
          trailing: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '95',
                  style: F.n24.copyWith(color: P.of(c).ink),
                ),
                TextSpan(
                  text: ' %',
                  style: F.cap.copyWith(color: P.of(c).ink3),
                ),
              ],
            ),
          ),
          xLabels: Samples.xLabelsFor(14),
        ),
      ),
    ),
    AppCard(
      child: DualAxisChart.recoveryStrain(
        recovery: Samples.recovery14,
        strain: Samples.strain14,
        xLabels: Samples.xLabelsFor(14),
      ),
    ),
    AppCard(
      child: Column(
        children: [
          _SparkRow('Resting HR', '54', 'bpm', Samples.rhr7),
          const SizedBox(height: S.x3),
          _SparkRow('Respiratory rate', '14.6', '/min', Samples.resp7),
          const SizedBox(height: S.x3),
          _SparkRow('Skin temp', '−0.4', '°C', Samples.skin7),
        ],
      ),
    ),
  ];

  List<Widget> _sleep() => [
    AppCard(child: HypnogramChart(stages: Samples.stages)),
    AppCard(
      child: ScatterConsistency(
        nights: Samples.nights,
        xLabels: Samples.xLabelsFor(21),
      ),
    ),
  ];

  List<Widget> _strain() {
    final total = Samples.zoneMinutes.fold(0.0, (a, b) => a + b);
    return [
      AppCard(
        child: ZoneTimeline(
          samples: Samples.hr,
          start: Samples.dayStart,
          end: Samples.dayEnd,
          zoneFloors: Samples.zoneFloors,
          workouts: [Samples.workout],
          rest: [Samples.sleepPrev],
        ),
      ),
      AppCard(
        child: Builder(
          builder: (c) => ChartFrame(
            title: 'Time in zones',
            unit: 'min',
            height: 22,
            legend: ZoneBar.legend(P.of(c)),
            series: Samples.zoneMinutes,
            footnote: '${total.round()} min in zones 1–5',
            child: CustomPaint(
              size: Size.infinite,
              painter: ZoneBar([
                for (final m in Samples.zoneMinutes) m / total,
              ], P.of(c)),
            ),
          ),
        ),
      ),
      AppCard(child: AcwrGauge.fromLoad(Samples.load)),
    ];
  }

  static final _sheetSections = [
    ExplainSection(
      title: 'Today’s inputs',
      child: ContributionBars.recovery(
        components: Samples.components,
        penalties: const [Samples.penalty],
        color: DomainColors.recovery(69),
        score: 69,
      ),
    ),
    const ExplainSection(
      title: 'Formula',
      body:
          'Each input is compared with your 30-day baseline and scored 0–1. '
          'Missing inputs are left out and the weights re-normalised.',
      formula: 'recovery = 100 × Σ (weight × sub-score) − penalties',
    ),
  ];

  List<Widget> _sheet() => [
    Builder(
      builder: (c) => DecoratedBox(
        decoration: BoxDecoration(
          color: P.of(c).sheet,
          borderRadius: R.rCard,
          border: Border.all(color: P.of(c).line),
        ),
        child: ExplainSheet(
          title: 'Recovery 69',
          lede:
              'How ready your body is today, from how last night '
              'compares with your normal.',
          children: _sheetSections,
        ),
      ),
    ),
    _Case(
      'showExplainSheet · NumberSwap · EnterFade',
      Builder(
        builder: (c) => Wrap(
          spacing: S.x3,
          runSpacing: S.x3,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            AppButton(
              label: 'Open sheet',
              kind: AppButtonKind.secondary,
              onTap: () => showExplainSheet<void>(
                c,
                title: 'Recovery 69',
                lede: 'How ready your body is today.',
                children: _sheetSections,
              ),
            ),
            const _SwapDemo(),
            EnterFade(
              enabled: playSeed != null,
              child: const StatePill(label: 'Entered once', color: C.sky),
            ),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _edges() => [
    const AppCard(
      child: BaselineBandChart(
        title: 'Empty series',
        unit: 'ms',
        values: [],
        color: DomainColors.health,
        height: 72,
      ),
    ),
    const AppCard(
      child: BaselineBandChart(
        title: 'One reading, gaps around it',
        unit: 'bpm',
        values: [null, null, null, 54, null, null],
        mean: 55,
        lower: 52,
        upper: 58,
        highlightIndex: 3,
        color: DomainColors.health,
        height: 96,
      ),
    ),
    AppCard(
      child: ZoneTimeline(
        samples: const [],
        start: Samples.dayStart,
        end: Samples.dayEnd,
        zoneFloors: Samples.zoneFloors,
        height: 72,
      ),
    ),
    const AppCard(child: HypnogramChart(stages: [], height: 72)),
    const AppCard(child: AcwrGauge(ratio: null)),
  ];

  List<Widget> _loading() => [
    const _Case(
      'SkeletonBox · SkeletonLines',
      AppCard(
        child: Row(
          children: [
            SkeletonBox.circle(size: 44),
            SizedBox(width: S.x3),
            Expanded(child: SkeletonLines(lines: 2)),
            SizedBox(width: S.x3),
            SkeletonBox(width: 40, height: 24),
          ],
        ),
      ),
    ),
    const _Case(
      'EmptyState',
      AppCard(
        child: EmptyState(
          icon: Icons.bedtime_outlined,
          title: 'No sleep recorded',
          body:
              'Wear the band to bed and the night will appear here in '
              'the morning.',
        ),
      ),
    ),
    _Case(
      'Reduced motion: no sweep, fades kept',
      Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(disableAnimations: true),
          child: Center(
            child: ScoreRing(
              label: 'Recovery',
              value: 81,
              unit: '%',
              color: DomainColors.recovery(81),
              size: 104,
              playKey: _key('rm'),
            ),
          ),
        ),
      ),
    ),
  ];
}

/// A labelled case.
class _Case extends StatelessWidget {
  const _Case(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label.toUpperCase(),
          style: F.over.copyWith(color: p.ink3),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: S.x3),
        child,
      ],
    );
  }
}

class _Labelled extends StatelessWidget {
  const _Labelled(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: F.bodySm.copyWith(color: p.ink)),
        const SizedBox(width: S.x1),
        child,
      ],
    );
  }
}

/// Two tiles side by side, equal height.
class _Pair extends StatelessWidget {
  const _Pair(this.a, this.b);
  final Widget a, b;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: a),
        const SizedBox(width: S.x3),
        Expanded(child: b),
      ],
    ),
  );
}

/// Three rings sized to the available width.
class _RingRow extends StatelessWidget {
  const _RingRow({required this.builder});
  final List<Widget> Function(double size) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (c, box) {
      final size = ((box.maxWidth - S.x4 * 2) / 3).clamp(64.0, 108.0);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: builder(size),
      );
    },
  );
}

class _SegmentsDemo extends StatefulWidget {
  const _SegmentsDemo();

  @override
  State<_SegmentsDemo> createState() => _SegmentsDemoState();
}

class _SegmentsDemoState extends State<_SegmentsDemo> {
  int _days = 30;
  String _view = 'Night';

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedRange(days: _days, onChanged: (d) => setState(() => _days = d)),
      const SizedBox(height: S.x3),
      SegmentedControl<String>(
        values: const ['Night', 'Week', 'Month'],
        selected: _view,
        label: (s) => s,
        onChanged: (s) => setState(() => _view = s),
      ),
    ],
  );
}

class _SwapDemo extends StatefulWidget {
  const _SwapDemo();

  @override
  State<_SwapDemo> createState() => _SwapDemoState();
}

class _SwapDemoState extends State<_SwapDemo> {
  int _v = 72;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Pressable(
      semanticLabel: 'Change number',
      onTap: () => setState(() => _v = _v == 72 ? 58 : 72),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
        child: NumberSwap('$_v%', style: F.n24.copyWith(color: p.ink)),
      ),
    );
  }
}

/// Label · value · sparkline, the compact trend row.
class _SparkRow extends StatelessWidget {
  const _SparkRow(this.label, this.value, this.unit, this.values);
  final String label, value, unit;
  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Text(
            label,
            style: F.bodySm.copyWith(color: p.ink2),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: F.n18.copyWith(color: p.ink),
                ),
                TextSpan(
                  text: ' $unit',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ],
            ),
            maxLines: 1,
          ),
        ),
        Expanded(
          flex: 5,
          child: Sparkline(
            values: values,
            color: DomainColors.health,
            height: 26,
          ),
        ),
      ],
    );
  }
}
