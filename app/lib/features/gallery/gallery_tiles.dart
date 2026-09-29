// The gallery's "Design tiles" section: every design tile with app-style
// sample values (the Figma diff fixtures in test/goldens carry the PNGs' own
// text), plus the tile kit (GlowTile, DotMatrixNumber, skeletons, the
// plan panel, the Sample data chip).

import 'package:flutter/material.dart';

import '../../design/design.dart';
import '../../domain/today_plan.dart';

List<Widget> designTileCases() => [
  _case(
    'Kit: glow tile, dot numerals, skeleton, chip',
    const BentoGrid(
      children: [
        GlowTile(
          size: TileSize.small,
          glow: GlowRecipes.s9,
          semanticLabel: 'An empty glow tile',
          children: [
            TileText(
              'Glow tile',
              x: S.tilePad,
              baseline: 36,
              style: F.tileTitle,
            ),
          ],
        ),
        SizedBox(
          width: S.tileW,
          height: S.tileW,
          child: Center(child: DotMatrixNumber('56.7', style: F.dot40)),
        ),
        TileSkeleton(size: TileSize.small),
        SizedBox(
          width: S.tileW,
          height: S.tileW,
          child: Center(child: SampleDataChip()),
        ),
      ],
    ),
  ),
  _case(
    'Plan (no PNG: built from the kit)',
    BentoGrid(
      children: [
        PlanTile(
          plan: const TodayPlan(
            date: '2026-09-28',
            state: DayState.ready,
            headline: 'Ready to push',
            summary: 'HRV is 13% above your usual and you slept 7 h 1 m.',
            evidence: [
              PlanEvidence(label: 'Recovery', value: '78%', route: '/recovery'),
              PlanEvidence(label: 'HRV', value: '62 ms', comparison: '+13%'),
            ],
            actions: [
              PlanAction(
                kind: PlanActionKind.effort,
                title: 'Go for it: strain 14–16',
                why: 'Recovery 78% leaves room for a hard session.',
              ),
              PlanAction(
                kind: PlanActionKind.sleep,
                title: 'Asleep by 23:35',
                why: 'Tonight’s target is 7 h 51 m.',
              ),
            ],
          ),
          onOpen: (_) {},
        ),
        const GlowPanel(child: Text('A glow panel of any height.')),
      ],
    ),
  ),
  _case(
    'Scores',
    BentoGrid(
      children: [
        ReadinessTile(
          title: 'Recovery',
          score: '78',
          status: 'Good',
          statA: 'HRV vs usual',
          valueA: '+13%',
          statB: 'Resting HR vs usual',
          valueB: '−3 bpm',
          usual: 70,
          steps: const [
            ReadinessStep(value: 64, label: '64'),
            ReadinessStep(value: 71, label: '71', delta: '+7'),
            ReadinessStep(value: 58, label: '58', delta: '−13'),
            ReadinessStep(value: 66, label: '66', delta: '+8'),
            ReadinessStep(value: 74, label: '74', delta: '+8'),
            ReadinessStep(value: 78, label: '78', delta: '+4'),
          ],
          onTap: () {},
        ),
        ArcScoreTile(
          title: 'Strain',
          value: '12.4',
          unit: 'Target 14.0',
          progress: 12.4 / 21,
          onTap: () {},
        ),
        RingScoreTile(
          title: 'Sleep',
          value: '89',
          caption: '7h 1m',
          progress: .89,
          onTap: () {},
        ),
      ],
    ),
  ),
  _case(
    'Vitals against the usual range',
    const BentoGrid(
      children: [
        LineBaselineTile(
          title: 'HRV',
          value: '62',
          unit: 'ms',
          status: 'In range',
          statusColor: C.recGreen,
          position: .62,
        ),
        ArcBaselineTile(
          title: 'Resting HR',
          value: '54',
          unit: 'bpm',
          status: 'In range',
          position: .4,
        ),
        BandBaselineTile(
          title: 'Respiration',
          value: '15.2',
          unit: '/min',
          status: 'Above usual',
          statusColor: C.amber,
          position: .9,
        ),
        TopArcTile(
          title: 'Skin temp',
          value: '+0.1',
          unit: '°C',
          status: 'In range',
          position: .55,
        ),
        HealthAlertTile(
          title: 'Worth a look',
          readings: [
            AlertReading('62', 'Resting HR · above'),
            AlertReading('38', 'HRV · below'),
          ],
          lowLabel: '2 outside your usual',
          highLabel: '3 within',
          segments: [AlertSegment(2, C.amber), AlertSegment(3, C.recGreen)],
          axis: ['HRV', 'RHR', 'Resp', 'Temp', 'SpO₂'],
        ),
        ProgressTile(
          title: 'Learning your normal',
          value: '9',
          unit: 'of 14 nights',
          progress: 9 / 14,
        ),
      ],
    ),
  ),
  _case(
    'Sleep, strain, week, workouts',
    const BentoGrid(
      children: [
        SleepSummaryTile(
          title: 'Sleep',
          stats: [
            ('7:01', 'Time asleep'),
            ('89%', 'Performance'),
            ('7:51', 'Sleep target'),
          ],
          deltaColor: TileInk.primary,
          blocks: [
            SleepBlock(SleepLane.core, 0, .2),
            SleepBlock(SleepLane.deep, .2, .3),
            SleepBlock(SleepLane.rem, .3, .45),
            SleepBlock(SleepLane.awake, .45, .47),
            SleepBlock(SleepLane.core, .47, .8),
            SleepBlock(SleepLane.rem, .8, 1),
          ],
          startLabel: '23:40',
          endLabel: '07:12',
          totals: [
            SleepStageTotal('Awake', ['14', ' min']),
            SleepStageTotal('REM', ['1', 'h', ' 32', 'min']),
            SleepStageTotal('Core', ['3', 'h', ' 58', 'min']),
            SleepStageTotal('Deep', ['1', 'h', ' 17', 'min']),
          ],
        ),
        ArcStateTile(
          title: 'Strain',
          trailing: 'Mon 28 Sep',
          value: '12.4',
          unit: '',
          caption: 'Target 14.0',
          progress: 12.4 / 21,
          panels: [
            StatePanel(
              icon: Icons.local_fire_department,
              label: 'Calories',
              value: '412',
              unit: 'kcal',
            ),
            StatePanel(
              icon: Icons.timer_outlined,
              label: 'Active',
              value: '48',
              unit: 'min',
            ),
          ],
        ),
        ZoneBarTile(
          title: 'Heart rate zones',
          columns: [
            ZoneColumn('96', 'Light', 96),
            ZoneColumn('31', 'Moderate', 31),
            ZoneColumn('12', 'Hard', 12),
            ZoneColumn('3', 'Max', 3),
          ],
        ),
        WeeklyBarsTile(
          title: 'This week',
          leadLabel: 'Most strained day:',
          leadValue: 'Thursday',
          totals: [
            ('Average strain', '10.8', 'OF 21'),
            ('Highest', '15.6', 'STRAIN'),
          ],
          values: [8.2, 12.1, 9.4, 15.6, 11.0, 7.3, 12.4],
          days: ['T', 'W', 'T', 'F', 'S', 'S', 'M'],
          highlight: 3,
        ),
        WorkoutSummaryTile(
          title: 'Workouts',
          rows: [
            WorkoutRow(
              value: '412',
              label: 'Calories',
              refLabel: 'Usual',
              refValue: '380',
              refUnit: 'kcal',
            ),
            WorkoutRow(
              value: '8.400',
              label: 'Steps',
              refLabel: 'Usual',
              refValue: '7.900',
              refUnit: 'steps',
            ),
            WorkoutRow(value: '48', label: 'Active time', unit: 'MIN'),
          ],
        ),
      ],
    ),
  ),
  _case(
    'Live, consistency, VO₂ max, training load',
    const BentoGrid(
      children: [
        HeartRateTile(
          title: 'Heart rate',
          value: '132',
          unit: 'bpm',
          samples: [120, 124, 131, 128, 135, 140, 133, 129, 132, 138, 136, 132],
          badgeValue: 'Z3',
          badgeUnit: 'zone',
        ),
        WeekDotsTile(
          title: 'Consistency',
          trailing: '5 of 7 days',
          letters: ['T', 'W', 'T', 'F', 'S', 'S', 'M'],
          numbers: ['22', '23', '24', '25', '26', '27', '28'],
          marks: [
            DayMark.done,
            DayMark.done,
            DayMark.open,
            DayMark.done,
            DayMark.done,
            DayMark.done,
            DayMark.today,
          ],
          pages: 1,
        ),
        BandMediumTile(
          title: 'VO₂ max',
          value: '45.0',
          status: 'Your tracker’s estimate',
          position: .5,
        ),
        SegmentScaleTile(
          title: 'Training load',
          value: '1.12',
          lead: 'your load is',
          verdict: 'Optimal',
          marker: .41,
          bands: [
            ScaleBand('Detraining', '<0.8', C.green800),
            ScaleBand('Optimal', '0.8–1.3', C.green600),
            ScaleBand('Elevated', '1.3–1.5', C.green400),
            ScaleBand('High', '>1.5', C.green200),
          ],
        ),
      ],
    ),
  ),
];

Widget _case(String title, Widget child) => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    OverLabel(title.toUpperCase()),
    const SizedBox(height: S.x3),
    child,
  ],
);
