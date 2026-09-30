// The permission rationale Settings → Data sources shows BEFORE the Health
// Connect system sheet: every data type Airlog asks for and the one feature
// it powers. The list is app/copy.dart's hcReadTypes, the same one the
// privacy policy prints, so Data sources and the policy can never disagree.
// (Onboarding no longer embeds it: "Use my tracker" opens Health Connect's
// own sheet directly.)
//
// Shared kit for features/ (settings): imports no feature.

import 'package:flutter/material.dart';

import '../design/design.dart';
import 'copy.dart';

/// The list itself (Data sources shows it in a sheet).
class HcRationaleList extends StatelessWidget {
  const HcRationaleList({super.key});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (type, why) in hcReadTypes) BulletLine(why, strong: '$type.'),
    ],
  );
}

/// Shows the rationale; resolves true when the user chose to continue to the
/// system permission sheet.
Future<bool> showHcRationale(BuildContext context) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: sheetMotion(context),
    builder: (c) {
      final p = P.of(c);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(c).height * .88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: S.x3),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  S.gutter,
                  S.x5,
                  S.gutter,
                  S.x4,
                ),
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      'What Airlog will read',
                      style: F.t1.copyWith(color: p.ink),
                    ),
                  ),
                  const SizedBox(height: S.x2),
                  Text(
                    'Next, Health Connect asks about each kind of data. Allow '
                    'the ones you want. Anything you skip shows as missing, '
                    'never guessed. Airlog only reads your data. It never '
                    'changes it.',
                    style: F.body.copyWith(color: p.ink2),
                  ),
                  const SizedBox(height: S.x4),
                  const HcRationaleList(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                S.gutter,
                S.x2,
                S.gutter,
                S.x5,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppButton(
                    label: 'Continue to Health Connect',
                    expand: true,
                    onTap: () => Navigator.of(c).pop(true),
                  ),
                  const SizedBox(height: S.x1),
                  AppButton(
                    label: 'Not now',
                    kind: AppButtonKind.quiet,
                    expand: true,
                    onTap: () => Navigator.of(c).pop(false),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  return ok ?? false;
}
