// Onboarding's building blocks. Feature-local (not in lib/design), so the
// gallery-coverage rule does not apply; they are built only from design
// tokens and components.
//
//   * ScoreChip        a 48 dp pill that opens a score's ⓘ sheet
//   * showScoreSheet   Recovery / Strain / Sleep in one plain sentence each
//   * WorksWithPanel   device types → Health Connect → Airlog, on a glow
//   * PromiseTile      one privacy promise on a glow (icon, title, line)
//   * SideBySide       two tiles in a row when they fit, else stacked
//   * ChoiceTile       a big tappable glow tile: one way to start
//   * BirthYearRow     the optional birth year: ⓘ and an Add / year button

import 'package:flutter/material.dart';

import '../../app/screen_kit.dart' show IconBadge, InfoButton;
import '../../design/design.dart';
import '../../domain/engine/recovery.dart' show RecoveryEngine;
import '../../domain/engine/strain.dart' show StrainEngine;
import 'onboarding_copy.dart';

// ── scores ────────────────────────────────────────────────────────────────

enum ScoreKind { recovery, strain, sleep }

extension on ScoreKind {
  String get label => switch (this) {
    ScoreKind.recovery => OnboardingCopy.recovery,
    ScoreKind.strain => OnboardingCopy.strain,
    ScoreKind.sleep => OnboardingCopy.sleep,
  };

  Color get color => switch (this) {
    ScoreKind.recovery => C.recGreen,
    ScoreKind.strain => C.strain,
    ScoreKind.sleep => C.sleep,
  };
}

/// What a score means, in one plain sentence (and one short section). The
/// numbers come from the engine's constants, never retyped.
Future<void> showScoreSheet(BuildContext context, ScoreKind kind) {
  const green = RecoveryEngine.greenFrom, yellow = RecoveryEngine.yellowFrom;
  return switch (kind) {
    ScoreKind.recovery => showExplainSheet<void>(
      context,
      title: OnboardingCopy.recovery,
      lede: OnboardingCopy.recoveryLede,
      footnote: OnboardingCopy.sheetFootnote,
      children: [
        ExplainSection(
          title: OnboardingCopy.recoveryZonesTitle,
          body: OnboardingCopy.recoveryZones(
            numText(green),
            numText(yellow),
            numText(green - 1),
          ),
        ),
      ],
    ),
    ScoreKind.strain => showExplainSheet<void>(
      context,
      title: OnboardingCopy.strain,
      lede: OnboardingCopy.strainLede(numText(StrainEngine.scaleMax)),
      footnote: OnboardingCopy.sheetFootnote,
    ),
    ScoreKind.sleep => showExplainSheet<void>(
      context,
      title: OnboardingCopy.sleep,
      lede: OnboardingCopy.sleepLede,
      footnote: OnboardingCopy.sheetFootnote,
      children: const [
        ExplainSection(
          title: OnboardingCopy.missedSleepTitle,
          body: OnboardingCopy.missedSleepBody,
        ),
      ],
    ),
  };
}

/// A score's name as a pill: a colour dot (decorative), the name and an ⓘ.
/// Opens the score's sheet.
class ScoreChip extends StatelessWidget {
  const ScoreChip(this.kind, {super.key});
  final ScoreKind kind;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Pressable(
      onTap: () => showScoreSheet(context, kind),
      semanticLabel: OnboardingCopy.about(kind.label),
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: S.tap),
          padding: const EdgeInsetsDirectional.fromSTEB(S.x3, 0, S.x2, 0),
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: p.mark(kind.color),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text(
                  kind.label,
                  style: F.bodySm.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: S.x1 + 2),
              Icon(Icons.info_outline_rounded, size: 16, color: p.ink2),
            ],
          ),
        ),
      ),
    );
  }
}

// ── works with ────────────────────────────────────────────────────────────

const _deviceIcons = [
  Icons.watch_rounded,
  Icons.radio_button_unchecked_rounded,
  Icons.monitor_heart_outlined,
  Icons.phone_android_rounded,
];

/// Device types (never app names or logos) → Health Connect → Airlog.
class WorksWithPanel extends StatelessWidget {
  const WorksWithPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final plates = [
      for (var i = 0; i < OnboardingCopy.devices.length; i++)
        _DevicePlate(icon: _deviceIcons[i], label: OnboardingCopy.devices[i]),
    ];
    return GlowPanel(
      glow: GlowRecipes.m20,
      width: double.infinity,
      semanticLabel: OnboardingCopy.worksLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                // Four in a row when they fit; a 2 × 2 grid otherwise.
                final row = box.maxWidth >= 280 && !bigText(context);
                if (row) {
                  return Row(
                    children: [
                      for (var i = 0; i < plates.length; i++) ...[
                        if (i > 0) const SizedBox(width: S.x2),
                        Expanded(child: plates[i]),
                      ],
                    ],
                  );
                }
                final w = (box.maxWidth - S.x2) / 2;
                return Wrap(
                  spacing: S.x2,
                  runSpacing: S.x2,
                  children: [
                    for (final pl in plates) SizedBox(width: w, child: pl),
                  ],
                );
              },
            ),
            const SizedBox(height: S.x4),
            const Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                _FlowPill(
                  icon: Icons.favorite_rounded,
                  label: OnboardingCopy.healthConnect,
                ),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 18,
                  color: TileInk.soft,
                ),
                _FlowPill(label: OnboardingCopy.airlog),
              ],
            ),
            const SizedBox(height: S.x3),
            Text(
              OnboardingCopy.worksBody,
              style: F.tileBody.copyWith(color: TileInk.soft),
            ),
          ],
        ),
      ),
    );
  }
}

class _DevicePlate extends StatelessWidget {
  const _DevicePlate({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: S.x3, horizontal: S.x1),
    decoration: const BoxDecoration(color: C.plate, borderRadius: R.rPanel),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 24, color: TileInk.primary),
        const SizedBox(height: S.x2 - 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: F.tileLabel.copyWith(color: TileInk.soft),
        ),
      ],
    ),
  );
}

class _FlowPill extends StatelessWidget {
  const _FlowPill({required this.label, this.icon});
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
    decoration: const BoxDecoration(color: C.plate, borderRadius: R.rPill),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: TileInk.primary),
          const SizedBox(width: S.x1 + 2),
        ],
        Flexible(
          child: Text(
            label,
            style: F.tileBody.copyWith(
              color: TileInk.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One privacy promise on a glow: an icon, a short title and one line.
class PromiseTile extends StatelessWidget {
  const PromiseTile({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.glow,
  });

  final IconData icon;
  final String title;
  final String body;
  final GlowRecipe glow;

  @override
  Widget build(BuildContext context) => GlowPanel(
    glow: glow,
    width: double.infinity,
    semanticLabel: '$title. $body',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: TileInk.primary),
          const SizedBox(height: S.x3),
          Text(
            title,
            style: F.tileTitle.copyWith(color: TileInk.primary),
          ),
          const SizedBox(height: S.x1),
          Text(body, style: F.tileBody.copyWith(color: TileInk.soft)),
        ],
      ),
    ),
  );
}

/// Two tiles side by side when both fit (≥ 340 dp and text scale ≤ 1.15),
/// stacked otherwise, so no title is squeezed. [builder] gets `side`.
class SideBySide extends StatelessWidget {
  const SideBySide({super.key, required this.builder});
  final List<Widget> Function(bool side) builder;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side =
          box.maxWidth >= 340 &&
          MediaQuery.textScalerOf(context).scale(1) <= 1.15;
      final c = builder(side);
      if (side) {
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: c[0]),
              const SizedBox(width: S.tileGap),
              Expanded(child: c[1]),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [c[0], const SizedBox(height: S.x3), c[1]],
      );
    },
  );
}

// ── choose ────────────────────────────────────────────────────────────────

/// One way to start: a big glow tile, one button for screen readers (its
/// title and body). [marker] shows where the data comes from.
class ChoiceTile extends StatelessWidget {
  const ChoiceTile({
    super.key,
    required this.icon,
    required this.accent,
    required this.title,
    required this.body,
    required this.marker,
    required this.glow,
    required this.onTap,
    required this.semanticLabel,
    this.fill = false,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String body;
  final Widget marker;
  final GlowRecipe glow;
  final VoidCallback? onTap;
  final String semanticLabel;

  /// Side by side: the marker sits at the bottom, level with its neighbour.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final busy = onTap == null;
    final tile = GlowPanel(
      glow: glow,
      width: double.infinity,
      onTap: onTap,
      semanticLabel: semanticLabel,
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBadge(icon: icon, accent: accent, size: 40),
                const Spacer(),
                Container(
                  width: 32,
                  height: 32,
                  decoration: const BoxDecoration(
                    color: C.badge,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                    color: TileInk.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: S.x4),
            Text(title, style: F.t2.copyWith(color: TileInk.primary)),
            const SizedBox(height: S.x1),
            Text(body, style: F.tileBody.copyWith(color: TileInk.soft)),
            const SizedBox(height: S.x3),
            if (fill) const Spacer(),
            marker,
          ],
        ),
      ),
    );
    return AnimatedOpacity(
      opacity: busy ? .55 : 1,
      duration: motion(context, Motion.fast, fade: true),
      curve: Motion.enter,
      child: tile,
    );
  }
}

/// The optional birth year: an icon, the label and its 18+ caption, an ⓘ
/// and a button that shows "Add" or the year in dots. The row itself is not
/// tappable, so the ⓘ stays reachable on its own.
class BirthYearRow extends StatelessWidget {
  const BirthYearRow({super.key, required this.year, required this.onEdit});
  final int? year;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final label = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(OnboardingCopy.birthYear, style: F.head.copyWith(color: p.ink)),
        const SizedBox(height: 2),
        Text(
          OnboardingCopy.birthYearCaption,
          style: F.cap.copyWith(color: p.ink2),
        ),
      ],
    );
    const info = InfoButton(
      title: OnboardingCopy.birthYearWhyTitle,
      lede: OnboardingCopy.birthYearWhyLede,
      semanticLabel: 'About birth year',
      children: [
        ExplainSection(
          title: OnboardingCopy.adultsTitle,
          body: OnboardingCopy.adultsBody,
        ),
        ExplainSection(
          title: OnboardingCopy.changeLaterTitle,
          body: OnboardingCopy.changeLaterBody,
        ),
      ],
    );
    final button = _YearButton(year: year, onTap: onEdit);
    const badge = ExcludeSemantics(
      child: IconBadge(icon: Icons.cake_outlined, size: 32),
    );
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(S.x4, S.x3, S.x3, S.x3),
      child: bigText(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    badge,
                    const SizedBox(width: S.x3),
                    Expanded(child: label),
                  ],
                ),
                const SizedBox(height: S.x2),
                Row(children: [info, const Spacer(), button]),
              ],
            )
          : Row(
              children: [
                badge,
                const SizedBox(width: S.x3),
                Expanded(child: label),
                info,
                const SizedBox(width: S.x1),
                button,
              ],
            ),
    );
  }
}

class _YearButton extends StatelessWidget {
  const _YearButton({required this.year, required this.onTap});
  final int? year;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final y = year;
    final Widget face = y == null
        ? Row(
            key: const ValueKey('add'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 18, color: p.ink),
              const SizedBox(width: S.x1),
              Text(
                OnboardingCopy.birthYearAdd,
                style: F.bodySm.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          )
        : DotMatrixNumber('$y', key: ValueKey(y), style: F.dot24);
    return Pressable(
      onTap: onTap,
      semanticLabel: y == null
          ? OnboardingCopy.birthYearAddLabel
          : OnboardingCopy.birthYearSetLabel(y),
      child: ExcludeSemantics(
        child: Container(
          constraints: const BoxConstraints(minHeight: S.tap, minWidth: 72),
          padding: const EdgeInsets.symmetric(horizontal: S.x4),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.card2, borderRadius: R.rPill),
          // A rare change: crossfade (fade only; kept under reduced motion).
          child: AnimatedSwitcher(
            duration: motion(context, Motion.base, fade: true),
            reverseDuration: motion(context, Motion.fast, fade: true),
            switchInCurve: Motion.enter,
            switchOutCurve: Motion.enter.flipped,
            child: face,
          ),
        ),
      ),
    );
  }
}
