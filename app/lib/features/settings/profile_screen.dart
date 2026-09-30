// Settings → Profile: the max heart rate your details give (the number
// that sets zones and Strain), then birth year, sex, max heart rate and
// weight, each with one short helper line and the reason behind ⓘ. Saving
// recomputes every score.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../design/design.dart';
import '../../domain/engine/strain.dart' show StrainEngine;
import '../../domain/models.dart';
import 'profile_view_model.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileControllerProvider);
    final d = async.value;
    final now = ref.watch(currentTimeProvider);
    final dirty = d?.dirty ?? false;
    // Back with unsaved edits asks first (QA-19).
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await showDialog<bool>(
          context: context,
          animationStyle: dialogMotion(context),
          builder: (c) => AlertDialog(
            title: const Text('Discard changes?'),
            content: const Text('Your changes aren’t saved.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.of(c).pop(true),
                child: const Text('Discard'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          ref.invalidate(profileControllerProvider);
          Navigator.of(context).pop();
        }
      },
      child: _scaffold(context, async, d, now),
    );
  }

  Widget _scaffold(
    BuildContext context,
    AsyncValue<ProfileDraft> async,
    ProfileDraft? d,
    DateTime now,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: d == null
          ? ListView(
              padding: const EdgeInsets.all(S.gutter),
              children: [
                if (async.hasError)
                  const StatusCard(
                    title: 'Couldn’t load your profile',
                    body: 'Go back and try again.',
                    tone: StatusTone.warning,
                  )
                else
                  const AppCard(child: SkeletonLines(lines: 5)),
              ],
            )
          : _Form(draft: d, now: now),
    );
  }
}

class _Form extends ConsumerStatefulWidget {
  const _Form({required this.draft, required this.now});
  final ProfileDraft draft;
  final DateTime now;

  @override
  ConsumerState<_Form> createState() => _FormState();
}

class _FormState extends ConsumerState<_Form> {
  late final _year = TextEditingController(text: widget.draft.birthYear);
  late final _max = TextEditingController(text: widget.draft.maxHr);
  late final _weight = TextEditingController(text: widget.draft.weight);

  @override
  void dispose() {
    _year.dispose();
    _max.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final ok = await ref.read(profileControllerProvider.notifier).save();
    if (!mounted) return;
    snack(
      context,
      ok ? 'Saved. All your scores were updated.' : 'Check the highlighted fields.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final d = widget.draft;
    final c = ref.read(profileControllerProvider.notifier);
    // No birth year: no age prediction (never an assumed age); zones then
    // use the highest heart rate your data has shown.
    final predicted = d.birthYear.trim().isEmpty
        ? null
        : d.predictedMaxHr(widget.now);
    final override = d.maxHr.trim().isNotEmpty && d.maxHrError == null
        ? d.maxHrValue
        : null;
    final (String heroValue, String heroCaption) = override != null
        ? ('${override.round()}', 'You set this · sets your heart-rate zones')
        : predicted != null
        ? ('${predicted.round()}', 'From your age · sets your heart-rate zones')
        : (
            DotMatrixNumber.missing,
            'Add your birth year, or Airlog uses your highest heart rate.',
          );

    Widget field({
      required String label,
      required TextEditingController ctl,
      required ValueChanged<String> onChanged,
      String? error,
      String? hint,
      String? suffix,
      bool decimal = false,
    }) => TextField(
      controller: ctl,
      onChanged: onChanged,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(decimal ? r'[0-9.,]' : r'[0-9]'),
        ),
      ],
      style: F.tab(F.body).copyWith(color: p.ink),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        errorText: error,
      ),
    );

    /// One fact: badge, control, ⓘ; a one-line helper under it.
    Widget fact({
      required IconData icon,
      required Widget control,
      required String helper,
      Widget? info,
    }) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.card, vertical: S.x3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: S.x2),
            child: IconBadge(icon: icon, size: 32),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                control,
                const SizedBox(height: S.x2),
                Text(helper, style: F.cap.copyWith(color: p.ink2)),
              ],
            ),
          ),
          if (info != null)
            Padding(padding: const EdgeInsets.only(top: 2), child: info),
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
      children: [
        SettingsTile(
          glow: GlowRecipes.m16,
          title: 'Your max heart rate',
          icon: Icons.favorite_border_rounded,
          accent: C.recRed,
          dividers: false,
          info: const InfoButton(
            title: 'Your max heart rate',
            lede:
                'A few details that make your scores fit you. They stay on '
                'this phone.',
            children: [
              ExplainSection(
                title: 'What it does',
                body: 'Your max heart rate sets your heart-rate zones and Strain.',
              ),
            ],
          ),
          children: [
            SettingsBlock(
              child: DotStat(
                value: heroValue,
                unit: heroValue == DotMatrixNumber.missing ? null : 'bpm',
                caption: heroCaption,
                style: F.dot40,
                semanticsLabel: heroValue == DotMatrixNumber.missing
                    ? 'Max heart rate not set. $heroCaption'
                    : 'Max heart rate $heroValue bpm. $heroCaption',
              ),
            ),
          ],
        ),
        const SizedBox(height: S.x3),
        SettingsTile(
          children: [
            fact(
              icon: Icons.cake_outlined,
              control: field(
                label: 'Birth year',
                ctl: _year,
                onChanged: c.setBirthYear,
                error: d.birthYearError(widget.now),
                hint: 'e.g. 1992',
              ),
              helper: 'Sets your heart-rate zones.',
              info: InfoButton(
                title: 'Birth year',
                lede:
                    'Sets your max heart rate, which sets your heart-rate '
                    'zones. Without it, Airlog uses the highest heart rate it '
                    'has seen from you.',
                children: [
                  ExplainSection(
                    title: 'Formula',
                    formula:
                        '${numText(StrainEngine.tanakaIntercept)} − '
                        '${numText(StrainEngine.tanakaSlope)} × age '
                        '(Tanaka 2001)',
                  ),
                ],
              ),
            ),
            // Full width: three segments need the room ("Not specified").
            Padding(
              padding: const EdgeInsets.fromLTRB(S.card, S.x2, S.x1, S.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const IconBadge(
                        icon: Icons.person_outline_rounded,
                        size: 32,
                      ),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: Text(
                          'Sex',
                          style: F.bodySm.copyWith(
                            color: p.ink2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const InfoButton(
                        title: 'Sex',
                        lede:
                            'Doesn’t change your scores. It’s only used for a '
                            'second-opinion effort number on the How Strain '
                            'works page. “Not specified” uses the average of '
                            'both.',
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x2),
                  Padding(
                    padding: const EdgeInsets.only(right: S.card - S.x1),
                    child: SegmentedControl<Sex>(
                      values: const [Sex.female, Sex.male, Sex.unspecified],
                      selected: d.sex,
                      label: (s) => switch (s) {
                        Sex.female => 'Female',
                        Sex.male => 'Male',
                        Sex.unspecified => 'Not specified',
                      },
                      semanticsLabel: 'Sex',
                      onChanged: c.setSex,
                    ),
                  ),
                  const SizedBox(height: S.x2),
                  Text(
                    'Doesn’t change your scores.',
                    style: F.cap.copyWith(color: p.ink2),
                  ),
                ],
              ),
            ),
            fact(
              icon: Icons.monitor_heart_outlined,
              control: field(
                label: 'Max heart rate (optional)',
                ctl: _max,
                onChanged: c.setMaxHr,
                error: d.maxHrError,
                hint: predicted == null
                    ? 'From your data'
                    : 'From your age: ${predicted.round()}',
                suffix: 'bpm',
              ),
              helper: 'Only if you’ve measured it.',
              info: InfoButton(
                title: 'Max heart rate',
                lede: predicted == null
                    ? 'Only fill this in if you’ve measured it in an all-out '
                          'effort. Without it or a birth year, Airlog uses the '
                          'highest heart rate it has seen from you.'
                    : 'Only fill this in if you’ve measured it in an all-out '
                          'effort. Otherwise Airlog uses ${predicted.round()} '
                          'bpm, based on your age.',
              ),
            ),
            fact(
              icon: Icons.monitor_weight_outlined,
              control: field(
                label: 'Weight (optional)',
                ctl: _weight,
                onChanged: c.setWeight,
                error: d.weightError,
                suffix: 'kg',
                decimal: true,
              ),
              helper: 'Not used in any score.',
            ),
          ],
        ),
        const SizedBox(height: S.x5),
        AppButton(
          label: d.saving ? 'Saving…' : 'Save',
          expand: true,
          onTap: d.saving || !d.dirty || !d.valid(widget.now) ? null : _save,
        ),
        const SizedBox(height: S.x2),
        Text(
          'Saving updates all your scores.',
          textAlign: TextAlign.center,
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    );
  }
}
