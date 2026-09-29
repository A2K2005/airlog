// Coach setup (pushed): choose the engine, and for a cloud engine the key,
// the model (with its estimated cost), the mode, exactly what can leave the
// phone and to whom, the 18+ (and, for Gemini, paid-project) confirmations,
// and the affirmative "I agree — turn on …". Withdraw lives here too.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/day_key.dart';
import 'coach_setup_view_model.dart';
import 'widgets/check_row.dart';

class CoachSetupScreen extends ConsumerStatefulWidget {
  const CoachSetupScreen({super.key});

  @override
  ConsumerState<CoachSetupScreen> createState() => _CoachSetupScreenState();
}

class _CoachSetupScreenState extends ConsumerState<CoachSetupScreen> {
  final _key = TextEditingController();

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  CoachSetupViewModel get _vm => ref.read(coachSetupProvider.notifier);

  Future<void> _agree(CoachSetupState s) async {
    FocusScope.of(context).unfocus();
    final ok = await _vm.agree();
    if (!mounted) return;
    _key.clear();
    snack(
      context,
      ok
          ? '${CoachCopy.providerName(s.engine)} is on. You can turn it off '
                'any time.'
          : 'Could not save. Nothing was turned on.',
    );
    if (ok && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _withdraw(CoachSetupState s) async {
    final name = CoachCopy.providerName(s.saved.provider);
    final yes = await showDialog<bool>(
      context: context,
      animationStyle: dialogMotion(context),
      builder: (d) => AlertDialog(
        title: Text('Turn off $name?'),
        content: const Text(CoachCopy.withdrawBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(
              'Turn off',
              style: F.head.copyWith(color: P.of(d).on(C.recRed)),
            ),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final ok = await _vm.withdraw();
    if (!mounted) return;
    _key.clear();
    snack(
      context,
      ok
          ? 'Back to on-device. Your key was deleted.'
          : 'Could not turn it off. Try again.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final async = ref.watch(coachSetupProvider);
    final s = async.value;

    final List<Widget> body;
    if (s == null && async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Could not open setup',
          body: 'The coach settings on this phone could not be read.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(coachSetupProvider),
        ),
      ];
    } else if (s == null) {
      body = const [AppCard(child: SkeletonLines(lines: 5))];
    } else {
      body = _content(context, s);
    }

    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        title: const Text('Coach setup'),
        actions: SampleDataChip.action(context),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x12),
        children: body,
      ),
    );
  }

  List<Widget> _content(BuildContext context, CoachSetupState s) {
    final p = P.of(context);
    Widget section(String title, [String? sub]) => Padding(
      padding: const EdgeInsets.only(top: S.x6, bottom: S.x3),
      child: SectionHeader(title: title, subtitle: sub),
    );
    final name = CoachCopy.providerName(s.engine);
    final company = CoachCopy.company(s.engine);
    final cloudInUse = s.inUse != CoachProvider.offline;

    return [
      Text('Choose who answers', style: F.t1.copyWith(color: p.ink)),
      const SizedBox(height: S.x1),
      Text(
        'On-device is the default and sends nothing. A cloud engine is '
        'optional, uses your own key, and only starts after you agree below.',
        style: F.bodySm.copyWith(color: p.ink2),
      ),
      const SizedBox(height: S.x4),
      for (final e in CoachProvider.values) ...[
        _EngineCard(
          key: ValueKey('engine-${e.name}'),
          engine: e,
          selected: s.engine == e,
          inUse: s.inUse == e,
          onTap: () {
            _key.clear();
            _vm.chooseEngine(e);
          },
        ),
        const SizedBox(height: S.x2),
      ],
      if (!s.cloud) ...[
        const SizedBox(height: S.x2),
        if (cloudInUse)
          AppButton(
            key: const ValueKey('use-on-device'),
            label: 'Switch to on-device',
            icon: Icons.phone_android_rounded,
            expand: true,
            onTap: s.busy ? null : () => _withdraw(s),
          )
        else
          AppCard(
            tone: CardTone.inset,
            child: Row(
              children: [
                Icon(Icons.check_circle_outline_rounded, color: p.ink2),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Text(
                    'On-device is in use. Nothing leaves your phone.',
                    style: F.bodySm.copyWith(color: p.ink),
                  ),
                ),
              ],
            ),
          ),
      ],
      if (s.cloud) ...[
        section(
          s.engine == CoachProvider.claude
              ? 'Your Anthropic API key'
              : 'Your Gemini API key',
        ),
        _KeyCard(
          state: s,
          controller: _key,
          onChanged: _vm.setKeyDraft,
          onReplace: _vm.replaceKey,
        ),
        if (s.engine == CoachProvider.gemini) ...[
          const SizedBox(height: S.x3),
          const StatusCard(
            title: 'Paid keys only',
            body: CoachCopy.geminiWarning,
            tone: StatusTone.warning,
            icon: Icons.warning_amber_rounded,
          ),
        ],
        section('Model', 'Approximate cost per question · estimates'),
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: S.x1),
          child: Column(
            children: [
              for (final m in CoachCopy.modelsFor(s.engine))
                CheckRow(
                  key: ValueKey('model-${m.id}'),
                  radio: true,
                  value: s.model == m.id,
                  title: m.name,
                  trailing: m.cost,
                  onChanged: (_) => _vm.setModel(m.id),
                ),
            ],
          ),
        ),
        const SizedBox(height: S.x2),
        Text(
          'Estimates at list prices for a typical question; longer answers '
          'cost more. $company bills your key directly. Set a spending limit '
          'in their console.',
          style: F.cap.copyWith(color: p.ink3),
        ),
        section('Mode'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedControl<CoachMode>(
                values: CoachMode.values,
                selected: s.mode,
                label: (m) =>
                    m == CoachMode.useMyData ? 'Use my data' : 'General only',
                semanticsLabel: 'Mode',
                onChanged: _vm.setMode,
              ),
              const SizedBox(height: S.x3),
              Text(
                s.mode == CoachMode.useMyData
                    ? CoachCopy.useMyDataBody
                    : CoachCopy.generalOnlyBody,
                style: F.bodySm.copyWith(color: p.ink2),
              ),
            ],
          ),
        ),
        section(
          'What can leave your phone',
          'Per question, only what it needs',
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line
                  in s.mode == CoachMode.useMyData
                      ? CoachCopy.sentWithData
                      : CoachCopy.sentGeneral)
                BulletLine(line, icon: Icons.north_east_rounded),
              const SizedBox(height: S.x3),
              const OverLabel('Never sent'),
              const SizedBox(height: S.x1),
              for (final line in CoachCopy.neverSent)
                BulletLine(line, icon: Icons.block_rounded),
              const SizedBox(height: S.x3),
              Divider(height: 1, color: p.line),
              const SizedBox(height: S.x3),
              Text(
                CoachCopy.recipient(s.engine),
                style: F.bodySm.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: S.x1),
              Text(
                CoachCopy.retention(s.engine),
                style: F.bodySm.copyWith(color: p.ink2),
              ),
            ],
          ),
        ),
        if (s.consented) ...[
          const SizedBox(height: S.x5),
          AppCard(
            tone: CardTone.inset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('$name is on', style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: S.x1),
                Text(
                  'You agreed on ${_day(s.saved.consentAt!)}. Changing the '
                  'model, or narrowing to General only, needs no new consent.',
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
                const SizedBox(height: S.x3),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(
                    label: 'Save changes',
                    kind: AppButtonKind.secondary,
                    onTap:
                        s.busy ||
                            (s.model == s.saved.model && s.mode == s.saved.mode)
                        ? null
                        : () async {
                            final ok = await _vm.saveChanges();
                            if (context.mounted) {
                              snack(context, ok ? 'Saved.' : 'Could not save.');
                            }
                          },
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          section('Your consent'),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: S.x1),
            child: Column(
              children: [
                CheckRow(
                  key: const ValueKey('adult'),
                  value: s.adult,
                  title: CoachCopy.adult,
                  subtitle: 'Cloud AI engines are for adults only.',
                  onChanged: _vm.setAdult,
                ),
                if (s.engine == CoachProvider.gemini)
                  CheckRow(
                    key: const ValueKey('paid'),
                    value: s.paid,
                    title: CoachCopy.paidKey,
                    subtitle:
                        'Free keys may be used for training and human review.',
                    onChanged: _vm.setPaid,
                  ),
              ],
            ),
          ),
          const SizedBox(height: S.x4),
          AppButton(
            key: const ValueKey('agree'),
            label: s.busy ? 'Turning on…' : CoachCopy.agree(s.engine),
            expand: true,
            onTap: s.canAgree ? () => _agree(s) : null,
          ),
          const SizedBox(height: S.x2),
          Text(
            s.missing.isEmpty
                ? 'By agreeing, each question you ask sends the items above '
                      'to $company. You can turn it off any time.'
                : 'Still needed: ${s.missing.join(', ')}.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ],
      if (cloudInUse && s.cloud) ...[
        section(CoachSettingsCopy.withdrawTitle),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                CoachCopy.withdrawBody,
                style: F.bodySm.copyWith(color: p.ink2),
              ),
              const SizedBox(height: S.x3),
              Align(
                alignment: Alignment.centerLeft,
                child: AppButton(
                  key: const ValueKey('withdraw'),
                  label: 'Turn off ${CoachCopy.providerName(s.saved.provider)}',
                  icon: Icons.power_settings_new_rounded,
                  kind: AppButtonKind.quiet,
                  accent: C.recRed,
                  onTap: s.busy ? null : () => _withdraw(s),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }

  static String _day(DateTime t) => '${shortDay(DayKey.of(t))}, ${clockOf(t)}';
}

class _EngineCard extends StatelessWidget {
  const _EngineCard({
    super.key,
    required this.engine,
    required this.selected,
    required this.inUse,
    required this.onTap,
  });

  final CoachProvider engine;
  final bool selected;
  final bool inUse;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final (IconData icon, String body) = switch (engine) {
      CoachProvider.offline => (
        Icons.phone_android_rounded,
        CoachCopy.onDeviceBody,
      ),
      CoachProvider.claude => (Icons.cloud_outlined, CoachCopy.claudeBody),
      CoachProvider.gemini => (Icons.cloud_outlined, CoachCopy.geminiBody),
    };
    final name = CoachCopy.providerName(engine);
    final tag = engine == CoachProvider.offline
        ? 'Default'
        : 'Your key · ${CoachCopy.company(engine)}';
    return Semantics(
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        selected: selected,
        scale: .985,
        semanticLabel: '$name${inUse ? ', in use' : ''}. $tag. $body',
        child: ExcludeSemantics(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(S.x4),
            decoration: BoxDecoration(
              color: p.card,
              borderRadius: R.rCard,
              border: Border.all(
                color: selected ? p.ink : p.line,
                width: selected ? 2 : S.hair,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 22, color: p.ink),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: S.x2,
                        runSpacing: S.x1,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(name, style: F.head.copyWith(color: p.ink)),
                          Text(tag, style: F.cap.copyWith(color: p.ink3)),
                          if (inUse)
                            const StatePill(label: 'In use', color: C.recGreen),
                        ],
                      ),
                      const SizedBox(height: S.x1),
                      Text(body, style: F.bodySm.copyWith(color: p.ink2)),
                    ],
                  ),
                ),
                const SizedBox(width: S.x2),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 22,
                  color: selected ? p.ink : p.ink3,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyCard extends StatelessWidget {
  const _KeyCard({
    required this.state,
    required this.controller,
    required this.onChanged,
    required this.onReplace,
  });

  final CoachSetupState state;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final s = state;
    final showField = !s.hasKey || s.replacingKey;
    final tail = s.keyTail[s.engine];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!showField)
            Row(
              children: [
                Icon(Icons.key_rounded, size: 18, color: p.ink2),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    tail == null
                        ? 'Key saved on this phone'
                        : 'Key saved ••••$tail',
                    style: F
                        .tab(F.body)
                        .copyWith(color: p.ink, fontWeight: FontWeight.w600),
                  ),
                ),
                AppButton(
                  label: 'Replace',
                  kind: AppButtonKind.quiet,
                  compact: true,
                  onTap: onReplace,
                ),
              ],
            )
          else
            TextField(
              key: const ValueKey('api-key'),
              controller: controller,
              onChanged: onChanged,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              style: F.body.copyWith(color: p.ink),
              decoration: InputDecoration(
                labelText: 'API key',
                hintText: s.engine == CoachProvider.claude
                    ? 'sk-ant-…'
                    : 'AIza…',
                errorText: s.keyError,
                errorMaxLines: 2,
              ),
            ),
          const SizedBox(height: S.x3),
          Text(CoachCopy.keyStorage, style: F.cap.copyWith(color: p.ink3)),
        ],
      ),
    );
  }
}
