// Connect Claude or Gemini: a sheet from Settings → Coach (there is no setup
// screen and no wall before the chat). Two steps in one sheet:
//
//   1. Your key       pasted here (or already stored), shape-checked
//   2. Consent        the data mode, what each question sends and what is
//                     never sent, who receives it and how long they keep
//                     it, the model and its rough cost, 18+ (and, for
//                     Gemini, the paid-project box), then "I agree: turn on
//                     Claude"
//
// Consent is still required before any cloud request: nothing is saved
// until the agree tap, which writes the key, provider, model, mode and
// consent in one save (CoachSetupViewModel.agree). Every consent string is
// CoachCopy's, word for word. Once connected, the same sheet opens on step
// 2 to change the model or the mode ("Save changes" when no new consent is
// needed).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/copy.dart';
import '../../../app/screen_kit.dart';
import '../../../design/design.dart';
import '../../../domain/coach/coach_contracts.dart';
import '../../../domain/day_key.dart';
import '../coach_setup_view_model.dart';
import 'check_row.dart';

/// Opens the Connect sheet for [provider]. True when it was turned on or
/// changed.
Future<bool> showConnectSheet(
  BuildContext context,
  CoachProvider provider,
) async {
  final done = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    sheetAnimationStyle: sheetMotion(context),
    builder: (c) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * .92),
      child: _ConnectSheet(provider: provider),
    ),
  );
  return done ?? false;
}

class _ConnectSheet extends ConsumerStatefulWidget {
  const _ConnectSheet({required this.provider});
  final CoachProvider provider;

  @override
  ConsumerState<_ConnectSheet> createState() => _ConnectSheetState();
}

class _ConnectSheetState extends ConsumerState<_ConnectSheet> {
  final _key = TextEditingController();

  /// The user pressed Continue after pasting a key.
  bool _keyDone = false;
  bool _chosen = false;

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
          : 'Couldn’t save. Nothing was turned on.',
    );
    if (ok) Navigator.of(context).pop(true);
  }

  Future<void> _save() async {
    final ok = await _vm.saveChanges();
    if (!mounted) return;
    snack(context, ok ? 'Saved.' : 'Couldn’t save.');
    if (ok) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final async = ref.watch(coachSetupProvider);
    final s = async.value;
    if (s != null && !_chosen) {
      _chosen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _vm.chooseEngine(widget.provider);
      });
    }
    final List<Widget> body;
    if (s == null && async.hasError) {
      body = [
        EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'Couldn’t open setup',
          body: 'Airlog couldn’t open Coach’s settings.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(coachSetupProvider),
        ),
      ];
    } else if (s == null || s.engine != widget.provider) {
      body = const [SkeletonLines(lines: 5)];
    } else if ((!s.hasKey || s.replacingKey) && !_keyDone) {
      body = _keyStep(context, s);
    } else {
      body = _consentStep(context, s);
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x3, S.gutter, S.x8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
            ),
          ),
          const SizedBox(height: S.x4),
          ...body,
        ],
      ),
    );
  }

  List<Widget> _keyStep(BuildContext context, CoachSetupState s) {
    final p = P.of(context);
    final name = CoachCopy.providerName(s.engine);
    return [
      Semantics(
        header: true,
        child: Text('Connect $name', style: F.t1.copyWith(color: p.ink)),
      ),
      const SizedBox(height: S.x2),
      Text(
        s.engine == CoachProvider.claude
            ? CoachCopy.claudeBody
            : CoachCopy.geminiBody,
        style: F.bodySm.copyWith(color: p.ink2),
      ),
      const SizedBox(height: S.x4),
      Row(
        children: [
          Expanded(
            child: Text(
              s.engine == CoachProvider.claude
                  ? 'Your Anthropic API key'
                  : 'Your Gemini API key',
              style: F.head.copyWith(color: p.ink),
            ),
          ),
          InfoButton(
            title: 'Your API key',
            lede: CoachCopy.keyStorageFor(s.engine),
          ),
        ],
      ),
      const SizedBox(height: S.x2),
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
      const SizedBox(height: S.x5),
      AppButton(
        key: const ValueKey('connect-continue'),
        label: 'Continue',
        expand: true,
        onTap: s.draftOk
            ? () {
                FocusScope.of(context).unfocus();
                setState(() => _keyDone = true);
              }
            : null,
      ),
    ];
  }

  List<Widget> _consentStep(BuildContext context, CoachSetupState s) {
    final p = P.of(context);
    Widget section(String title, {String? sub, Widget? trailing}) => Padding(
      padding: const EdgeInsets.only(top: S.x6, bottom: S.x3),
      child: SectionHeader(title: title, subtitle: sub, trailing: trailing),
    );
    final name = CoachCopy.providerName(s.engine);
    final company = CoachCopy.company(s.engine);
    return [
      Semantics(
        header: true,
        child: Text(
          s.consented ? name : 'What $name will receive',
          style: F.t1.copyWith(color: p.ink),
        ),
      ),
      const SizedBox(height: S.x2),
      Text(
        CoachCopy.recipient(s.engine),
        style: F.bodySm.copyWith(color: p.ink2),
      ),
      if (s.hasKey) ...[
        section(
          s.engine == CoachProvider.claude
              ? 'Your Anthropic API key'
              : 'Your Gemini API key',
          trailing: InfoButton(
            title: 'Your API key',
            lede: CoachCopy.keyStorageFor(s.engine),
          ),
        ),
        _KeyCard(
          state: s,
          controller: _key,
          onChanged: _vm.setKeyDraft,
          onReplace: _vm.replaceKey,
        ),
      ],
      if (s.engine == CoachProvider.gemini && !s.consented) ...[
        const SizedBox(height: S.x3),
        const StatusCard(
          title: 'Paid keys only',
          body: CoachCopy.geminiWarning,
          tone: StatusTone.warning,
          icon: Icons.warning_amber_rounded,
        ),
      ],
      section('Data'),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedControl<CoachMode>(
              values: CoachMode.values,
              selected: s.mode,
              label: CoachCopy.modeLabel,
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
      section('What can leave your phone', sub: 'Only what each question needs'),
      _SentCard(
        icon: Icons.north_east_rounded,
        accent: C.amber,
        title: 'Sent with a question',
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
      Text(
        CoachCopy.retention(s.engine),
        style: F.bodySm.copyWith(color: p.ink2),
      ),
      section(
        'Model',
        sub: 'Rough cost per question',
        trailing: InfoButton(
          title: 'What a question costs',
          lede:
              'For a typical question. Longer answers cost more. $company '
              'charges your key directly, so set a spending limit in your '
              '$company account.',
        ),
      ),
      _ModelPicker(
        models: CoachCopy.modelsFor(s.engine),
        selected: s.model,
        onPick: _vm.setModel,
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
                'You agreed on ${_day(s.saved.consentAt!)}. Switching model, '
                'or switching to General only, doesn’t need a new OK.',
                style: F.bodySm.copyWith(color: p.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        AppButton(
          key: const ValueKey('connect-save'),
          label: 'Save changes',
          expand: true,
          onTap:
              s.busy || (s.model == s.saved.model && s.mode == s.saved.mode)
              ? null
              : _save,
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
                subtitle: 'Claude and Gemini are for adults only.',
                onChanged: _vm.setAdult,
              ),
              if (s.engine == CoachProvider.gemini)
                CheckRow(
                  key: const ValueKey('paid'),
                  value: s.paid,
                  title: CoachCopy.paidKey,
                  subtitle:
                      'With a free key, Google may train on what you send, '
                      'and people may read it.',
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
              ? 'When you agree, each question you ask sends the items above '
                    'to $company. You can turn it off any time.'
              : 'Still needed: ${s.missing.join(', ')}.',
          style: F.cap.copyWith(color: p.ink3),
        ),
      ],
    ];
  }

  static String _day(DateTime t) => '${shortDay(DayKey.of(t))}, ${clockOf(t)}';
}

/// The models as tiles: name and rough cost per question.
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
                  'Encrypted on this phone. Sent only to '
                  '${CoachCopy.company(s.engine)}.',
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
