// Settings → Profile: birth year, sex, max heart rate, weight, each with
// why the scores need it. Saving recomputes every score.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
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
    final now = ref.watch(clockProvider)();
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
            content: const Text('Your edits to the profile are not saved.'),
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
      appBar: AppBar(
        title: const Text('Profile'),
        actions: SampleDataChip.action(context),
      ),
      body: d == null
          ? ListView(
              padding: const EdgeInsets.all(S.gutter),
              children: [
                if (async.hasError)
                  const StatusCard(
                    title: 'Profile could not load',
                    body:
                        'The data store did not answer. Go back and try again.',
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
      ok
          ? 'Saved. Every score was recalculated with it.'
          : 'Check the highlighted fields.',
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

    Widget explain(String s) => Padding(
      padding: const EdgeInsets.only(top: S.x2),
      child: Text(s, style: F.cap.copyWith(color: p.ink3)),
    );

    Widget card(List<Widget> children) => Padding(
      padding: const EdgeInsets.only(bottom: S.x3),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
      children: [
        Text(
          'Four facts that make the maths yours. They stay on this phone.',
          style: F.bodySm.copyWith(color: p.ink2),
        ),
        const SizedBox(height: S.x4),
        card([
          field(
            label: 'Birth year',
            ctl: _year,
            onChanged: c.setBirthYear,
            error: d.birthYearError(widget.now),
            hint: 'e.g. 1992',
          ),
          explain(
            'Sets your age-predicted max heart rate '
            '(${numText(StrainEngine.tanakaIntercept)} − '
            '${numText(StrainEngine.tanakaSlope)} × age, '
            'Tanaka 2001), which places every heart-rate zone. Without it '
            'Airlog assumes 30 and says so.',
          ),
        ]),
        card([
          Text(
            'Sex',
            style: F.bodySm.copyWith(
              color: p.ink2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: S.x2),
          SegmentedControl<Sex>(
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
          explain(
            'Picks the TRIMP weighting curve, which differs by sex. '
            '“Not specified” uses the average of both.',
          ),
        ]),
        card([
          field(
            label: 'Max heart rate (optional)',
            ctl: _max,
            onChanged: c.setMaxHr,
            error: d.maxHrError,
            hint: predicted == null
                ? 'From your data'
                : 'Predicted ${predicted.round()}',
            suffix: 'bpm',
          ),
          explain(
            predicted == null
                ? 'Only if you have measured it in a hard, all-out effort. '
                      'Without it or a birth year, zones use the highest heart '
                      'rate your data has shown.'
                : 'Only if you have measured it in a hard, all-out effort. It '
                      'replaces the prediction (${predicted.round()} bpm) for '
                      'zones and strain. Leave empty to use the prediction.',
          ),
        ]),
        card([
          field(
            label: 'Weight (optional)',
            ctl: _weight,
            onChanged: c.setWeight,
            error: d.weightError,
            suffix: 'kg',
            decimal: true,
          ),
          explain(
            'Not used in any score. It stays with your profile on this '
            'phone.',
          ),
        ]),
        const SizedBox(height: S.x3),
        AppButton(
          label: d.saving ? 'Saving…' : 'Save',
          expand: true,
          onTap: d.saving || !d.dirty || !d.valid(widget.now) ? null : _save,
        ),
        const SizedBox(height: S.x2),
        Text(
          'Saving recalculates every day’s scores with the new values.',
          textAlign: TextAlign.center,
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    );
  }
}
