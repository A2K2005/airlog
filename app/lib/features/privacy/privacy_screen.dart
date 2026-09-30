// Privacy policy. A REAL screen (not a placeholder): Android launches the app
// straight onto it from Health Connect's permissions screen, so it must build
// without any provider or data, as the initial route.
//
// Keep this text in step with what the app actually does. It is the in-app
// policy Health Connect requires and the Play data-safety form is based on it.
//
// Layout: the five promises as summary tiles on top, then the full policy,
// one tile per section. The policy text itself stays on the page (never
// behind ⓘ): it is the policy.

import 'package:flutter/material.dart';

import '../../app/copy.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart' show CoachProvider;

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const updated = '1 October 2026';

  /// Health Connect data types read, and why: app/copy.dart's list, which
  /// the onboarding and Sources rationale print too.
  static const readTypes = hcReadTypes;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget para(String s) => Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: Text(s, style: F.body.copyWith(color: p.ink2)),
    );
    Widget section(IconData icon, String title, List<Widget> body) => Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: SettingsTile(
        title: title,
        icon: icon,
        dividers: false,
        children: [
          SettingsBlock(
            top: S.x3,
            bottom: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: body,
            ),
          ),
        ],
      ),
    );
    NavTile promise(IconData icon, String title, String sentence) => NavTile(
      icon: icon,
      accent: C.health,
      title: title,
      caption: sentence,
      semanticLabel: sentence,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          Semantics(
            header: true,
            child: Text(
              'Private by default. Cloud only by choice.',
              style: F.t1.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: S.x2),
          Text('Last updated $updated', style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x5),
          NavTileGrid(
            children: [
              promise(
                Icons.phone_android_rounded,
                'On this phone',
                'Every score is worked out on this phone.',
              ),
              promise(
                Icons.cloud_off_rounded,
                'No server',
                'There is no Airlog server and no account.',
              ),
              promise(
                Icons.visibility_off_outlined,
                'No tracking',
                'No analytics, no ads, no crash reporting, no tracking.',
              ),
              promise(
                Icons.ios_share_rounded,
                'Yours to keep',
                'Save a copy of your readings and scores, or delete them.',
              ),
              promise(
                Icons.chat_bubble_outline_rounded,
                'Coach stays here',
                'Coach runs on this phone unless you turn on Claude or Gemini '
                    'with your own key.',
              ),
            ],
          ),
          const SizedBox(height: S.x6),
          const OverLabel('The full policy'),
          section(
            Icons.favorite_border_rounded,
            'What Airlog reads from Health Connect',
            [
              para(
                'Airlog asks Health Connect to read the kinds of data below, '
                'which your tracker’s app puts there. You choose which to '
                'allow, and you can turn any of them off at any time in '
                'Health Connect’s settings. Anything you don’t allow shows as '
                'missing. It’s never guessed.',
              ),
              for (final (type, why) in readTypes)
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x1),
                  child: BulletLine(why, strong: '$type.', large: true),
                ),
              const SizedBox(height: S.x3),
            ],
          ),
          section(Icons.storage_rounded, 'Where it’s kept', [
            para(
              'Data read from Health Connect, and the scores worked out from '
              'it, are stored in Airlog’s private storage on this phone. '
              'Nothing is uploaded unless you turn on Claude or Gemini for '
              'Coach (below). Uninstalling Airlog deletes it.',
            ),
          ]),
          section(Icons.cloud_outlined, 'Enhanced mode (optional)', [
            para(
              'If you turn on Enhanced mode, Airlog signs in to the Google '
              'Health API with your Google account (OAuth) and requests your '
              'own data directly from Google, for example overnight SpO₂ '
              'and deep-sleep HRV. These requests go only to Google. The '
              'sign-in token is kept in Android\'s encrypted storage on this '
              'phone. Turning Enhanced mode off signs out and stops the '
              'requests.',
            ),
          ]),
          section(Icons.bluetooth_rounded, 'Live heart rate over Bluetooth', [
            para(
              'When you use the live screen, Airlog connects directly to '
              'your tracker over Bluetooth. The readings stay on this phone.',
            ),
          ]),
          section(Icons.chat_bubble_outline_rounded, CoachCopy.privacyTitle, [
            para(CoachCopy.privacyOnDevice),
            para(CoachCopy.privacyCloud),
            for (final s in CoachCopy.sentWithData) BulletLine(s, large: true),
            const SizedBox(height: S.x3),
            para(CoachCopy.privacyGeneral),
            for (final s in CoachCopy.neverSent) BulletLine(s, large: true),
            const SizedBox(height: S.x3),
            para(
              '${CoachCopy.retention(CoachProvider.claude)} '
              '${CoachCopy.retention(CoachProvider.gemini)} A Gemini key '
              'must be on a paid project: free keys may be used for training '
              'and human review.',
            ),
            para(CoachCopy.keyStorage),
            para(CoachCopy.privacyMemories),
            para(CoachCopy.privacyDelete),
          ]),
          section(Icons.ios_share_rounded, 'Export and delete', [
            para(
              '${SettingsCopy.exportPath} saves your raw data and every '
              'score as CSV and JSON files on this phone, to keep or share as '
              'you choose. ${SettingsCopy.deletePath} deletes everything '
              'Airlog stored on this phone. Turning off Health Connect access '
              'stops all further reads.',
            ),
          ]),
          section(Icons.health_and_safety_outlined, 'Not medical advice', [
            para(
              'Airlog is a wellness app, not a medical device. Its scores '
              'are estimates that help you notice patterns against your own '
              'baseline. They do not diagnose, treat or prevent any '
              'condition. Talk to a clinician about any health concern.',
            ),
          ]),
          section(Icons.update_rounded, 'Changes', [
            para(
              'If this policy changes, the new version ships inside the app '
              'with a new date at the top of this page.',
            ),
          ]),
        ],
      ),
    );
  }
}
