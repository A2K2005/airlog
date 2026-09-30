// Settings → Licences and credits: the open-source projects Airlog is built
// on (with links), the fonts, every licence text (Flutter's licence page),
// and the legal lines: not medical advice, not affiliated, the trademarks.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';

class LicencesScreen extends ConsumerWidget {
  const LicencesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = P.of(context);
    final open = ref.read(linkOpenerProvider);
    SettingsRow credit(String title, String body, String url) => SettingsRow(
      icon: Icons.open_in_new_rounded,
      accent: C.sky,
      title: title,
      subtitle: body,
      semanticLabel: '$title. $body. Opens the project page.',
      onTap: () => open(Uri.parse(url)),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Licences and credits')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          const OverLabel('Built on open source'),
          const SizedBox(height: S.x3),
          SettingsTile(
            children: [
              credit(
                'Pulse (Apache-2.0)',
                'Score formulas, the sample-data idea, the sync log.',
                'https://github.com/Luraxx/pulse',
              ),
              credit(
                'Edge (MIT)',
                'Charts, theme, motion, the Bluetooth heart-rate reader.',
                'https://github.com/OpenStrap/edge',
              ),
            ],
          ),
          const SizedBox(height: S.x5),
          const OverLabel('Fonts'),
          const SizedBox(height: S.x3),
          const SettingsTile(
            children: [
              SettingsRow(
                icon: Icons.text_fields_rounded,
                title: 'DM Sans (OFL)',
                subtitle: 'All text.',
              ),
              SettingsRow(
                icon: Icons.grid_on_rounded,
                title: 'Subway Ticker Grid (K-Type)',
                subtitle: 'Dot-matrix numbers. Personal-use licence.',
              ),
              SettingsRow(
                icon: Icons.text_fields_rounded,
                title: 'Manrope (OFL)',
                subtitle: 'The subscript ₂ only.',
              ),
            ],
          ),
          const SizedBox(height: S.x5),
          SettingsTile(
            children: [
              SettingsRow(
                icon: Icons.description_outlined,
                title: 'All open-source licences',
                onTap: () =>
                    Navigator.of(context).pushNamed(Routes.licensesAll),
              ),
            ],
          ),
          const SizedBox(height: S.x5),
          AppCard(
            tone: CardTone.inset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const OverLabel('Legal'),
                const SizedBox(height: S.x2),
                Text(
                  'Not medical advice. Not affiliated with Google, Fitbit or '
                  'WHOOP.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
                const SizedBox(height: S.x2),
                Text(
                  'WHOOP is a trademark of WHOOP, Inc. Google, Fitbit, Fitbit '
                  'Air and Google Health are trademarks of Google LLC. Airlog '
                  'is independent and not affiliated with any of them.',
                  style: F.cap.copyWith(color: p.ink3),
                ),
                const SizedBox(height: S.x2),
                Text(
                  'Public articles on recovery, strain and sleep were read for '
                  'inspiration only. No other app’s formula or code is used, '
                  'and the numbers are not comparable.',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
