// Privacy policy. A REAL screen (not a placeholder): Android launches the app
// straight onto it from Health Connect's permissions screen, so it must build
// without any provider or data, as the initial route.
//
// Keep this text in step with what the app actually does. It is the in-app
// policy Health Connect requires and the Play data-safety form is based on it.

import 'package:flutter/material.dart';

import '../../app/copy.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart' show CoachProvider;

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const updated = '29 September 2026';

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
    Widget section(String title, List<Widget> body) => Padding(
      padding: const EdgeInsets.only(top: S.x6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(title, style: F.t2.copyWith(color: p.ink)),
          ),
          const SizedBox(height: S.x3),
          ...body,
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: [
          Text(
            'Your data stays on this phone',
            style: F.t1.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x2),
          Text('Last updated $updated', style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x5),
          AppCard(
            tone: CardTone.inset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (icon, text) in const [
                  (
                    Icons.phone_android_rounded,
                    'Every score is computed on this phone.',
                  ),
                  (
                    Icons.cloud_off_rounded,
                    'There is no Airlog server and no account.',
                  ),
                  (
                    Icons.visibility_off_outlined,
                    'No analytics, no ads, no crash reporting, no tracking.',
                  ),
                  (
                    Icons.ios_share_rounded,
                    'Export or delete everything at any time.',
                  ),
                  (
                    Icons.chat_bubble_outline_rounded,
                    'The coach runs on this phone unless you turn on a cloud '
                        'engine with your own key.',
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: S.x1 + 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, size: 18, color: p.ink),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Text(
                            text,
                            style: F.bodySm.copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          section('What Airlog reads from Health Connect', [
            para(
              'Airlog asks Health Connect for read access to the data '
              'types below, written there by your tracker’s app. '
              'You choose which to grant, and you can revoke any of them at '
              'any time in Health Connect settings. A type you do not grant '
              'shows as missing; it is never guessed.',
            ),
            for (final (type, why) in readTypes)
              Padding(
                padding: const EdgeInsets.only(bottom: S.x1),
                child: BulletLine(why, strong: '$type.', large: true),
              ),
          ]),
          section('Where it is kept', [
            para(
              'Data read from Health Connect, and the scores computed from '
              'it, are stored in a database in the app\'s private storage on '
              'this phone. Nothing is uploaded, unless you turn on a cloud '
              'engine for the coach (below). Uninstalling Airlog deletes it.',
            ),
          ]),
          section('Enhanced mode (optional)', [
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
          section('Live heart rate over Bluetooth', [
            para(
              'When you use the live screen, Airlog connects directly to '
              'your tracker over Bluetooth. The readings stay on this phone.',
            ),
          ]),
          section(CoachCopy.privacyTitle, [
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
          section('Export and delete', [
            para(
              '${SettingsCopy.exportPath} writes your raw data and every '
              'score as CSV and JSON files to this phone, to keep or share '
              'as you choose. ${SettingsCopy.deletePath} erases the local '
              'store. Revoking Health Connect access stops all further '
              'reads.',
            ),
          ]),
          section('Not medical advice', [
            para(
              'Airlog is a wellness app, not a medical device. Its scores '
              'are estimates that help you notice patterns against your own '
              'baseline. They do not diagnose, treat or prevent any '
              'condition. Talk to a clinician about any health concern.',
            ),
          ]),
          section('Changes', [
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
