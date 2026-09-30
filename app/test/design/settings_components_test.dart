// The settings-screen kit: InfoButton, StatePill tones, the settings tile
// rows, NavTile / NavTileGrid, DotStat, MetricChip and the explanatory bars.

import 'package:airlog/app/screen_kit.dart' show InfoButton;
import 'package:airlog/design/design.dart';
import 'package:airlog/domain/models.dart' show SourceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';

Future<void> _pump(
  WidgetTester t,
  Widget child, {
  double width = 412,
  double scale = 1,
}) async {
  t.view.physicalSize = Size(width, 900) * 2;
  t.view.devicePixelRatio = 2;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            body: ListView(
              padding: const EdgeInsets.all(S.gutter),
              children: [child],
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

List<Widget> _tiles() => [
  NavTile(
    icon: Icons.hub_outlined,
    title: 'Data sources',
    status: StatePill.tone(PillTone.good, 'Connected'),
    onTap: () {},
  ),
  NavTile(
    icon: Icons.person_outline_rounded,
    title: 'Profile',
    caption: 'Born 1991 · Female',
    onTap: () {},
  ),
  NavTile(
    icon: Icons.receipt_long_outlined,
    title: 'Sync log',
    caption: 'Last sync 18 min ago',
    onTap: () {},
  ),
  NavTile(
    icon: Icons.chat_bubble_outline_rounded,
    title: 'Coach',
    caption: 'Who answers, notes, memory',
    onTap: () {},
  ),
];

void main() {
  setUpAll(loadAppFonts);

  testWidgets('InfoButton: 48 dp, "About {title}", opens its sheet', (t) async {
    await _pump(
      t,
      const Align(
        alignment: Alignment.centerLeft,
        child: InfoButton(
          title: 'Enhanced mode',
          lede: 'Optional, and in beta.',
          children: [ExplainSection(title: 'What it adds', body: 'More.')],
        ),
      ),
    );
    final f = find.bySemanticsLabel('About Enhanced mode');
    expect(f, findsOneWidget);
    final size = t.getSize(find.byType(InfoButton));
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await t.tap(find.byType(InfoButton));
    await t.pumpAndSettle();
    expect(find.text('Optional, and in beta.'), findsOneWidget);
    expect(find.text('WHAT IT ADDS'), findsOneWidget);
  });

  testWidgets('StatePill.tone keeps its word; locked shows a lock', (t) async {
    await _pump(
      t,
      Wrap(
        children: [
          for (final tone in PillTone.values) StatePill.tone(tone, tone.name),
        ],
      ),
    );
    for (final tone in PillTone.values) {
      expect(find.text(tone.name), findsOneWidget);
    }
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(PillTone.good.color, C.health);
    expect(PillTone.attention.color, C.amber);
  });

  testWidgets('SettingsSwitchRow: the whole row toggles, spoken as one', (
    t,
  ) async {
    var v = false;
    await _pump(
      t,
      StatefulBuilder(
        builder: (c, set) => SettingsTile(
          children: [
            SettingsSwitchRow(
              title: 'Use data from other apps',
              value: v,
              onChanged: (x) => set(() => v = x),
            ),
          ],
        ),
      ),
    );
    await t.tap(find.text('Use data from other apps'));
    await t.pumpAndSettle();
    expect(v, isTrue);
    final node = t.getSemantics(find.text('Use data from other apps'));
    expect(node.label, contains('Use data from other apps'));
    expect(node, isSemantics(hasToggledState: true, isToggled: true));
  });

  testWidgets('SettingsRow subtitles wrap instead of truncating', (t) async {
    const long =
        'A subtitle that is long enough to need a second and a third line '
        'on a narrow phone, and must never end in an ellipsis.';
    await _pump(
      t,
      const SettingsTile(
        children: [
          SettingsRow(icon: Icons.hub_outlined, title: 'Row', subtitle: long),
        ],
      ),
      width: 320,
      scale: 2,
    );
    final text = t.widget<Text>(find.text(long));
    expect(text.maxLines, isNull);
    expect(text.overflow, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('NavTileGrid: two columns, one at 2× text, never scaled', (
    t,
  ) async {
    await _pump(t, NavTileGrid(children: _tiles()));
    final a = t.getTopLeft(find.text('Data sources'));
    final b = t.getTopLeft(find.text('Profile'));
    expect(a.dy, b.dy, reason: 'side by side at 412 dp');
    for (final tile in t.widgetList(find.byType(NavTile))) {
      final s = t.getSize(find.byWidget(tile));
      expect(s.height, greaterThanOrEqualTo(48));
    }

    await _pump(t, NavTileGrid(children: _tiles()), width: 320, scale: 2);
    final a2 = t.getTopLeft(find.text('Data sources'));
    final b2 = t.getTopLeft(find.text('Profile'));
    expect(a2.dx, b2.dx, reason: 'one column at 2× text');
    expect(b2.dy, greaterThan(a2.dy));
    expect(find.byType(FittedBox), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('NavTile: a selected tile is a radio in a group', (t) async {
    await _pump(
      t,
      NavTileGrid(
        children: [
          NavTile(
            icon: Icons.science_outlined,
            title: 'Sample data',
            selected: true,
            onTap: () {},
          ),
          NavTile(
            icon: Icons.favorite_border_rounded,
            title: 'My data',
            selected: false,
            onTap: () {},
          ),
        ],
      ),
    );
    final on = t.getSemantics(find.text('Sample data'));
    expect(on, isSemantics(isSelected: true, isInMutuallyExclusiveGroup: true));
    final off = t.getSemantics(find.text('My data'));
    expect(off, isNot(isSemantics(isSelected: true)));
  });

  testWidgets('DotStat fits a long number at 320 dp and 2× text', (t) async {
    await _pump(
      t,
      const Row(
        children: [
          Expanded(child: DotStat(value: '9982', caption: 'Records')),
          Expanded(child: DotStat(value: '5', caption: 'Kinds of data')),
          Expanded(child: DotStat(value: '7', caption: 'Days checked')),
        ],
      ),
      width: 320,
      scale: 2,
    );
    expect(t.takeException(), isNull);
    expect(find.bySemanticsLabel('9982, Records'), findsOneWidget);
  });

  testWidgets('InputWeightBar speaks each part; BandScale each band', (
    t,
  ) async {
    await _pump(
      t,
      const Column(
        children: [
          InputWeightBar(
            parts: [
              WeightPart('HRV', .4, C.recGreen, valueText: '40%'),
              WeightPart('Sleep', .6, C.sleep, valueText: '60%'),
            ],
          ),
          BandScale(
            bands: [
              ScaleBand('Low', '1–33', C.recRed),
              ScaleBand('Good', '67–99', C.recGreen),
            ],
          ),
        ],
      ),
    );
    expect(find.bySemanticsLabel('HRV 40%, Sleep 60%'), findsOneWidget);
    expect(find.bySemanticsLabel('Low 1–33, Good 67–99'), findsOneWidget);
  });

  testWidgets('WeightStepBars becomes rows at large text', (t) async {
    const bars = WeightStepBars(
      color: C.strain,
      steps: [('Light', 'from 30%', 1), ('Max', 'from 85%', 11)],
    );
    await _pump(t, bars);
    final light = t.getTopLeft(find.text('Light'));
    final max = t.getTopLeft(find.text('Max'));
    expect(light.dy, max.dy, reason: 'columns side by side');
    await _pump(t, bars, width: 320, scale: 2);
    expect(
      t.getTopLeft(find.text('Max')).dy,
      greaterThan(t.getTopLeft(find.text('Light')).dy),
    );
    expect(find.text('×11 · from 85%'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('sourceName: the cloud source is "Enhanced mode"', () {
    expect(sourceName(SourceKind.googleHealthApi), 'Enhanced mode');
    expect(sourceName(SourceKind.healthConnect), 'Health Connect');
    expect(sourceName(SourceKind.ble), 'Bluetooth');
  });
}
