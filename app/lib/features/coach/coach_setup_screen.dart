// Coach setup (pushed): choose the engine, and for a cloud engine the key,
// the model (with its estimated cost), the mode, exactly what can leave the
// phone and to whom, the 18+ (and, for Gemini, paid-project) confirmations,
// and the affirmative "I agree — turn on …". Withdraw lives here too.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/copy.dart';
import '../../app/screen_kit.dart';
import '../../design/design.dart';
import '../../domain/coach/coach_contracts.dart';
import '../../domain/day_key.dart';
import 'coach_setup_view_model.dart';
import 'widgets/check_row.dart';

/// This screen's own words (docs/UI_REVAMP.md). CoachCopy keeps the consent
/// and disclosure lines; these are the short labels around them.
abstract final class _SetupCopy {
  static const title = 'Choose who answers';
  static const lede =
      'On-device is the default and sends nothing. Claude or Gemini is '
      'optional: your own key, and only after you agree below.';
  static const nothingLeaves = 'In use. Nothing leaves your phone.';
  static const keyTitle = 'Your API key';
  static String keyLine(String company) =>
      'Encrypted on this phone. Sent only to $company.';
  static const costTitle = 'What a question costs';
  static const sent = 'Sent with a question';
}

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
          : 'Withdrawal could not finish. Check the engine and stored keys, '
                'then try again.',
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
    Widget section(String title, {String? sub, Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: S.x6, bottom: S.x3),
      child: SectionHeader(title: title, subtitle: sub, trailing: trailing),
    );
    final name = CoachCopy.providerName(s.engine);
    final company = CoachCopy.company(s.engine);
    final cloudInUse = s.inUse != CoachProvider.offline;

    return [
      GlowPanel(
        glow: GlowRecipes.m8,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(S.x5, S.x5, S.x5, S.x5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                _SetupCopy.title,
                style: F.tileHeadline.copyWith(color: TileInk.primary),
              ),
            ),
            const SizedBox(height: S.x2),
            Text(
              _SetupCopy.lede,
              style: F.tileBody.copyWith(
                color: TileInk.unit,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: S.x4),
      _EnginePicker(
        selected: s.engine,
        inUse: s.inUse,
        onPick: (e) {
          _key.clear();
          _vm.chooseEngine(e);
        },
      ),
      const SizedBox(height: S.x3),
      _EngineDetail(
        engine: s.engine,
        onDeviceSettled:
            !s.cloud &&
            !cloudInUse &&
            !s.keys.values.any((present) => present),
      ),
      if (!s.cloud &&
          (cloudInUse || s.keys.values.any((present) => present))) ...[
        const SizedBox(height: S.x3),
        AppButton(
          key: const ValueKey('use-on-device'),
          label: cloudInUse ? 'Switch to on-device' : 'Remove stored keys',
          icon: Icons.phone_android_rounded,
          expand: true,
          onTap: s.busy ? null : () => _withdraw(s),
        ),
      ],
      if (s.cloud) ...[
        section(
          s.engine == CoachProvider.claude
              ? 'Your Anthropic API key'
              : 'Your Gemini API key',
          trailing: const InfoButton(
            title: _SetupCopy.keyTitle,
            lede: CoachCopy.keyStorage,
            footnote: null,
          ),
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
        section(
          'Model',
          sub: 'Approximate cost per question · estimates',
          trailing: InfoButton(
            title: _SetupCopy.costTitle,
            lede:
                'Estimates at list prices for a typical question; longer '
                'answers cost more. $company bills your key directly. Set a '
                'spending limit in their console.',
            footnote: null,
          ),
        ),
        _ModelPicker(
          models: CoachCopy.modelsFor(s.engine),
          selected: s.model,
          onPick: _vm.setModel,
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
          sub: 'Per question, only what it needs',
        ),
        _SentCard(
          icon: Icons.north_east_rounded,
          accent: C.amber,
          title: _SetupCopy.sent,
          lines: s.mode == CoachMode.useMyData
              ? CoachCopy.sentWithData
              : CoachCopy.sentGeneral,
        ),
        const SizedBox(height: S.x3),
        const _SentCard(
          icon: Icons.block_rounded,
          accent: C.recGreen,
          title: 'Never sent',
          lines: CoachCopy.neverSent,
        ),
        const SizedBox(height: S.x3),
        AppCard(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const IconBadge(icon: Icons.domain_rounded),
              const SizedBox(width: S.x3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
            ],
          ),
        ),
        if (s.consented) ...[
          const SizedBox(height: S.x5),
          AppCard(
            tone: CardTone.tinted,
            accent: C.recGreen,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$name is on',
                        style: F.head.copyWith(color: p.ink),
                      ),
                    ),
                    const StatePill(label: 'On', color: C.recGreen),
                  ],
                ),
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
      if ((cloudInUse || s.hasKey) && s.cloud) ...[
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
                  label: cloudInUse
                      ? 'Turn off ${CoachCopy.providerName(s.saved.provider)}'
                      : 'Remove stored keys',
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

(IconData, Color) _engineLook(CoachProvider e) => switch (e) {
  CoachProvider.offline => (Icons.phone_android_rounded, C.health),
  CoachProvider.claude => (Icons.cloud_outlined, C.violet),
  CoachProvider.gemini => (Icons.cloud_outlined, C.sky),
};

String _engineBody(CoachProvider e) => switch (e) {
  CoachProvider.offline => CoachCopy.onDeviceBody,
  CoachProvider.claude => CoachCopy.claudeBody,
  CoachProvider.gemini => CoachCopy.geminiBody,
};

String _engineTag(CoachProvider e) => e == CoachProvider.offline
    ? 'Default'
    : 'Your key · ${CoachCopy.company(e)}';

/// The three engines as one row of tiles; the chosen one is outlined.
class _EnginePicker extends StatelessWidget {
  const _EnginePicker({
    required this.selected,
    required this.inUse,
    required this.onPick,
  });

  final CoachProvider selected;
  final CoachProvider inUse;
  final ValueChanged<CoachProvider> onPick;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final e in CoachProvider.values) ...[
          if (e != CoachProvider.values.first) const SizedBox(width: S.x2),
          Expanded(
            child: _EngineTile(
              key: ValueKey('engine-${e.name}'),
              engine: e,
              selected: selected == e,
              inUse: inUse == e,
              onTap: () => onPick(e),
            ),
          ),
        ],
      ],
    ),
  );
}

class _EngineTile extends StatelessWidget {
  const _EngineTile({
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
    final (icon, accent) = _engineLook(engine);
    final name = CoachCopy.providerName(engine);
    return Semantics(
      inMutuallyExclusiveGroup: true,
      child: Pressable(
        onTap: onTap,
        selected: selected,
        semanticLabel:
            '$name${inUse ? ', in use' : ''}. ${_engineTag(engine)}. '
            '${_engineBody(engine)}',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(S.x3),
            decoration: BoxDecoration(
              color: selected
                  ? Color.alphaBlend(p.wash(accent), p.card)
                  : p.card,
              borderRadius: R.rCard,
              border: Border.all(
                color: selected ? p.ink : p.line,
                width: selected ? 2 : S.hair,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(icon: icon, accent: accent, size: 32),
                    const Spacer(),
                    Icon(
                      selected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: selected ? p.ink : p.ink3,
                    ),
                  ],
                ),
                const SizedBox(height: S.x3),
                Text(name, style: F.head.copyWith(color: p.ink)),
                const SizedBox(height: 2),
                Text(
                  engine == CoachProvider.offline ? 'Default' : 'Your key',
                  style: F.cap.copyWith(color: p.ink3),
                ),
                const Spacer(),
                if (inUse) ...[
                  const SizedBox(height: S.x2),
                  const StatePill(label: 'In use', color: C.recGreen),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the chosen engine does, in one card under the tiles.
class _EngineDetail extends StatelessWidget {
  const _EngineDetail({required this.engine, required this.onDeviceSettled});
  final CoachProvider engine;

  /// On-device is chosen and in use, and no cloud key is stored.
  final bool onDeviceSettled;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final (icon, accent) = _engineLook(engine);
    return AppCard(
      padding: const EdgeInsets.all(S.x4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, accent: accent),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${CoachCopy.providerName(engine)} · ${_engineTag(engine)}',
                  style: F.bodySm.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _engineBody(engine),
                  style: F.bodySm.copyWith(color: p.ink2),
                ),
                if (onDeviceSettled) ...[
                  const SizedBox(height: S.x2),
                  Row(
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 16,
                        color: p.on(C.recGreen),
                      ),
                      const SizedBox(width: S.x2),
                      Expanded(
                        child: Text(
                          _SetupCopy.nothingLeaves,
                          style: F.cap.copyWith(color: p.ink2),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The models as tiles: name and estimated cost per question.
class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.models,
    required this.selected,
    required this.onPick,
  });

  final List<CoachModel> models;
  final String? selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final cols = models.length <= 3 ? models.length : 2;
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - (cols - 1) * S.x2) / cols;
        return Wrap(
          spacing: S.x2,
          runSpacing: S.x2,
          children: [
            for (final m in models)
              SizedBox(
                width: w,
                child: Pressable(
                  key: ValueKey('model-${m.id}'),
                  onTap: () => onPick(m.id),
                  child: Semantics(
                    selected: selected == m.id,
                    inMutuallyExclusiveGroup: true,
                    label: '${m.name}. ${m.cost}',
                    child: ExcludeSemantics(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(S.x3),
                        decoration: BoxDecoration(
                          color: p.card,
                          borderRadius: R.rLg,
                          border: Border.all(
                            color: selected == m.id ? p.ink : p.line,
                            width: selected == m.id ? 2 : S.hair,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              selected == m.id
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 20,
                              color: selected == m.id ? p.ink : p.ink3,
                            ),
                            const SizedBox(height: S.x2),
                            Text(m.name, style: F.head.copyWith(color: p.ink)),
                            const SizedBox(height: 2),
                            Text(
                              m.cost,
                              style: F
                                  .tab(F.cap)
                                  .copyWith(
                                    color: p.ink2,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One side of "What can leave your phone": sent, or never sent.
class _SentCard extends StatelessWidget {
  const _SentCard({
    required this.icon,
    required this.accent,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconBadge(icon: icon, accent: accent, size: 32),
              const SizedBox(width: S.x3),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(title, style: F.head.copyWith(color: p.ink)),
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          for (final line in lines) BulletLine(line),
        ],
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
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 14, color: p.ink3),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(
                  _SetupCopy.keyLine(CoachCopy.company(s.engine)),
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
