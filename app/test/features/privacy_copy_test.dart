// One permission list: the privacy policy, the onboarding rationale and the
// Sources rationale sheet all print app/copy.dart's hcReadTypes, which follows
// the manifest (docs/PLAY_RELEASE.md §2). And the policy's "Settings → …"
// paths name labels that exist in Settings.

import 'package:airlog/app/copy.dart';
import 'package:airlog/app/hc_rationale.dart';
import 'package:airlog/design/design.dart';
import 'package:airlog/features/privacy/privacy_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fonts.dart';

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: buildTheme(Brightness.dark),
  home: home,
);

List<String> _leads(WidgetTester t) => [
  for (final b in t.widgetList<BulletLine>(find.byType(BulletLine)))
    if (b.strong != null) b.strong!,
];

void main() {
  setUpAll(loadAppFonts);

  test('the list is the final manifest list', () {
    expect(
      [for (final (type, _) in hcReadTypes) type],
      [
        'Heart rate',
        'Heart rate variability (RMSSD)',
        'Resting heart rate',
        'Respiratory rate',
        'Skin temperature',
        'Sleep sessions and stages',
        'Exercise sessions',
        'Steps',
        'Weight (optional)',
        'VO₂ max',
        'Blood oxygen (SpO₂)',
        'Distance',
        'Total calories burned',
        'History and background reads (optional)',
      ],
    );
    expect(PrivacyScreen.readTypes, same(hcReadTypes));
  });

  testWidgets('privacy and rationale print the same rows', (t) async {
    t.view.physicalSize = const Size(412, 5000) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const PrivacyScreen()));
    await t.pumpAndSettle();
    final privacy = _leads(t);
    await t.pumpWidget(
      _app(
        const Scaffold(body: SingleChildScrollView(child: HcRationaleList())),
      ),
    );
    await t.pumpAndSettle();
    final rationale = _leads(t);
    final expected = [for (final (type, _) in hcReadTypes) '$type.'];
    expect(privacy, expected);
    expect(rationale, expected);
  });

  testWidgets('the policy names the Settings labels', (t) async {
    t.view.physicalSize = const Size(412, 5000) * 2;
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(_app(const PrivacyScreen()));
    await t.pumpAndSettle();
    expect(find.textContaining(SettingsCopy.deletePath), findsOneWidget);
    expect(find.textContaining(SettingsCopy.exportPath), findsOneWidget);
    expect(find.textContaining('Settings → Data'), findsNothing);
  });
}
