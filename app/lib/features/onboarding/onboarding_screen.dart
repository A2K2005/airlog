// First launch, three short steps that show rather than tell:
//
//   1 · Welcome     a sample Recovery tile and the three scores (ⓘ each)
//   2 · Works with  device types → Health Connect, and two privacy promises
//   3 · Choose      birth year (optional, before the choices: they commit on
//                   tap), then "Use my tracker" or "Try sample data"
//   3b · Not connected, after a denial (still page 3 of 3)
//
// "Use my tracker" opens Android's Health Connect permission sheet directly
// (it lists every data type with its own switch); a denial lands on "Not
// connected" (3b). Health Connect's own "privacy policy" link opens the
// in-app /privacy route (MainActivity), never an onboarding step.
// Pages slide and fade in the direction of travel; tiles cascade in on the
// way forward. Everything goes through the reduced-motion gate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/repositories.dart' show HcAvailability;
import 'birth_year_sheet.dart';
import 'onboarding_copy.dart';
import 'onboarding_view_model.dart';
import 'onboarding_widgets.dart';

/// Android's Health Connect settings (after two denials the sheet no longer
/// shows, so the user grants there; QA-06).
final hcSettingsUri = Uri.parse(
  'intent:#Intent;action=android.health.connect.action.HEALTH_HOME_SETTINGS;end',
);

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

int _order(OnboardingStep s) => switch (s) {
  OnboardingStep.what => 0,
  OnboardingStep.privacy => 1,
  OnboardingStep.choose ||
  OnboardingStep.requesting ||
  OnboardingStep.done => 2,
  OnboardingStep.denied => 3,
};

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late final AppLifecycleListener _life;

  /// The page on screen (done keeps the last one while the route pops).
  OnboardingStep _shown = OnboardingStep.what;

  /// +1 moving forward, −1 moving back: the slide's direction.
  int _dir = 1;

  @override
  void initState() {
    super.initState();
    // Back from Health Connect's settings or the app store: read the
    // permissions again (a grant made there finishes onboarding).
    _life = AppLifecycleListener(
      onResume: () =>
          ref.read(onboardingControllerProvider.notifier).recheckPermissions(),
    );
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(onboardingControllerProvider);
    final c = ref.read(onboardingControllerProvider.notifier);
    ref.listen(onboardingControllerProvider, (prev, next) {
      if (next.step == OnboardingStep.done &&
          prev?.step != OnboardingStep.done) {
        // PopScope must rebuild with canPop=true before completing the route.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.of(context).maybePop();
        });
      }
    });

    final done = s.step == OnboardingStep.done;
    // While the system sheet is open (requesting) or the route pops (done),
    // the page on screen stays: choose, or Not connected for "Try again".
    final requesting = s.step == OnboardingStep.requesting;
    final view = done || requesting ? _shown : s.step;
    if (view != _shown) {
      _dir = _order(view) >= _order(_shown) ? 1 : -1;
      _shown = view;
    }
    final forward = _dir > 0;

    Future<void> editBirthYear() async {
      final r = await showBirthYearSheet(
        context,
        range: c.birthYearRange(),
        current: s.birthYear,
      );
      if (r != null) c.setBirthYear(r.year);
    }

    final locked = done || requesting;
    final (Widget body, Widget actions) = switch (view) {
      OnboardingStep.what => (
        _Welcome(stagger: forward),
        AppButton(
          label: OnboardingCopy.getStarted,
          expand: true,
          onTap: done ? null : c.next,
        ),
      ),
      OnboardingStep.privacy => (
        _WorksWith(stagger: forward),
        _Pair(
          primary: AppButton(
            label: OnboardingCopy.next,
            expand: true,
            onTap: c.next,
          ),
          onBack: c.back,
        ),
      ),
      OnboardingStep.denied => (
        _Denied(state: s),
        _Pair(
          primary: AppButton(
            label: OnboardingCopy.trySampleInstead,
            expand: true,
            onTap: locked ? null : c.chooseDemo,
          ),
          // After two denials Android stops showing the sheet: offer its
          // settings instead of a "Try again" that does nothing (QA-06).
          secondary: s.permissions?.deniedTwice == true
              ? AppButton(
                  label: OnboardingCopy.openHcSettings,
                  kind: AppButtonKind.secondary,
                  expand: true,
                  onTap: () => ref.read(linkOpenerProvider)(hcSettingsUri),
                )
              : s.permissions?.availability == HcAvailability.available ||
                    s.permissions?.availability ==
                        HcAvailability.checkFailed ||
                    s.permissions == null
              ? AppButton(
                  label: requesting
                      ? OnboardingCopy.waitingForHc
                      : OnboardingCopy.tryAgain,
                  kind: AppButtonKind.secondary,
                  expand: true,
                  onTap: locked ? null : c.requestHealthConnect,
                )
              : null,
          onBack: c.back,
        ),
      ),
      OnboardingStep.choose ||
      OnboardingStep.requesting ||
      OnboardingStep.done => (
        _Choose(
          stagger: forward,
          state: s,
          waiting: requesting,
          onDemo: s.busy || locked ? null : c.chooseDemo,
          // Straight to Android's permission sheet: it lists each data type
          // with its own switch.
          onConnect: s.busy || locked ? null : c.requestHealthConnect,
          onBirthYear: s.busy || locked ? null : editBirthYear,
        ),
        _Pair(onBack: c.back),
      ),
    };

    // System Back steps back through onboarding (QA-05); from the first
    // step it leaves without a choice, so onboarding is offered again next
    // launch (it is marked seen only by a choice).
    final first = s.step == OnboardingStep.what || done;
    final p = P.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final currentKey = ValueKey(view);
    return PopScope(
      canPop: first,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(S.gutter, S.x4, S.gutter, 0),
                child: Row(
                  children: [
                    _Dots(page: s.page),
                    const Spacer(),
                    ExcludeSemantics(
                      child: Text(
                        OnboardingCopy.counter(s.page + 1, _Dots.n),
                        style: F.tab(F.cap).copyWith(color: p.ink3),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: motion(context, Motion.slow, fade: true),
                  reverseDuration: motion(context, Motion.exit, fade: true),
                  switchInCurve: Motion.enter,
                  // The outgoing page runs its curve backwards: flipped, so
                  // it leaves on an ease-out too.
                  switchOutCurve: Motion.enter.flipped,
                  transitionBuilder: (child, a) {
                    final fade = FadeTransition(opacity: a, child: child);
                    if (!Motion.enabled(context)) return fade;
                    // Incoming slides in from the side of travel; outgoing
                    // slides away to the other side. Mirrored in RTL.
                    final d = .06 * _dir * (rtl ? -1 : 1);
                    final incoming = child.key == currentKey;
                    return FadeTransition(
                      opacity: a,
                      child: SlideTransition(
                        position: Tween(
                          begin: Offset(incoming ? d : -d, 0),
                          end: Offset.zero,
                        ).animate(a),
                        child: child,
                      ),
                    );
                  },
                  child: KeyedSubtree(key: currentKey, child: body),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  S.gutter,
                  S.x2,
                  S.gutter,
                  S.x5,
                ),
                child: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step dots: the current step is a 22 px pill. The pill's move between
/// steps is PAINTED (one CustomPaint, fixed size), so it never re-lays out
/// the row the way an animated width would.
class _Dots extends StatelessWidget {
  const _Dots({required this.page});
  final int page;

  static const n = 3, dot = 6.0, pill = 22.0, gap = 6.0;
  static const width = pill + (n - 1) * (dot + gap);

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Semantics(
      label: 'Step ${page + 1} of $n',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(end: page.toDouble()),
          duration: motion(context, Motion.base),
          curve: Motion.move,
          builder: (context, t, _) => CustomPaint(
            size: const Size(width, dot),
            painter: _DotsPainter(t, p.ink, p.track),
          ),
        ),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.t, this.on, this.off);
  final double t;
  final Color on, off;

  @override
  void paint(Canvas cv, Size s) {
    var x = 0.0;
    for (var i = 0; i < _Dots.n; i++) {
      // 1 at the current step, falling to 0 one step away.
      final k = (1 - (i - t).abs()).clamp(0.0, 1.0);
      final w = _Dots.dot + (_Dots.pill - _Dots.dot) * k;
      final done = (t - i + 1).clamp(0.0, 1.0);
      cv.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 0, w, s.height),
          Radius.circular(s.height / 2),
        ),
        Paint()..color = Color.lerp(off, on, done)!,
      );
      x += w + _Dots.gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter o) =>
      o.t != t || o.on != on || o.off != off;
}

class _Pair extends StatelessWidget {
  const _Pair({this.primary, this.secondary, required this.onBack});
  final Widget? primary;
  final Widget? secondary;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ?primary,
      if (secondary != null) ...[const SizedBox(height: S.x2), secondary!],
      const SizedBox(height: S.x1),
      AppButton(
        label: OnboardingCopy.back,
        kind: AppButtonKind.quiet,
        expand: true,
        onTap: onBack,
      ),
    ],
  );
}

/// A page: a title (a header), an optional lede, then its content.
class _Page extends StatelessWidget {
  const _Page({required this.title, this.lede, required this.children});
  final String title;
  final String? lede;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(
        S.gutter,
        S.x8,
        S.gutter,
        S.x4,
      ),
      children: [
        Semantics(
          header: true,
          child: Text(title, style: F.display.copyWith(color: p.ink)),
        ),
        if (lede != null) ...[
          const SizedBox(height: S.x3),
          Text(lede!, style: F.body.copyWith(color: p.ink2)),
        ],
        const SizedBox(height: S.x6),
        ...children,
      ],
    );
  }
}

/// A tile's entrance: slot 1, 2, 3… at [Motion.staggerTiles] apart, only on
/// the way forward (going back shows the page at once).
Widget _tile(bool stagger, int slot, Widget child) => EnterFade(
  index: slot,
  step: Motion.staggerTiles,
  enabled: stagger,
  child: child,
);

// ── 1 · welcome ─────────────────────────────────────────────────────────────

/// The sample week behind the hero tile (oldest first).
const _heroSteps = [
  ReadinessStep(value: 64, label: '64', delta: '+3'),
  ReadinessStep(value: 69, label: '69', delta: '+5'),
  ReadinessStep(value: 66, label: '66', delta: '−3'),
  ReadinessStep(value: 72, label: '72', delta: '+6'),
  ReadinessStep(value: 71, label: '71', delta: '−1'),
  ReadinessStep(value: 78, label: '78', delta: '+7'),
];

class _Welcome extends StatelessWidget {
  const _Welcome({required this.stagger});
  final bool stagger;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return _Page(
      title: OnboardingCopy.welcomeTitle,
      children: [
        // One 348 column shares the tile's edges, and scales with the grid
        // on a phone narrower than the design.
        BentoGrid(
          children: [
            SizedBox(
              width: S.tileWideW,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _tile(
                    stagger,
                    1,
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Explicit: a fresh install is live, so the scope's
                        // chip would not show. This tile is always sample.
                        Semantics(
                          container: true,
                          child: const SampleDataChip(),
                        ),
                        const SizedBox(height: S.x2),
                        ReadinessTile(
                          title: OnboardingCopy.heroTitle,
                          score: OnboardingCopy.heroScore,
                          status: OnboardingCopy.heroStatus,
                          statA: OnboardingCopy.heroStatA,
                          valueA: OnboardingCopy.heroValueA,
                          statB: OnboardingCopy.heroStatB,
                          valueB: OnboardingCopy.heroValueB,
                          steps: _heroSteps,
                          usual: 70,
                          semanticLabel: OnboardingCopy.heroLabel,
                          onTap: () =>
                              showScoreSheet(context, ScoreKind.recovery),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  _tile(
                    stagger,
                    2,
                    const Wrap(
                      spacing: S.x2,
                      runSpacing: S.x2,
                      children: [
                        ScoreChip(ScoreKind.recovery),
                        ScoreChip(ScoreKind.strain),
                        ScoreChip(ScoreKind.sleep),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  _tile(
                    stagger,
                    3,
                    Text(
                      OnboardingCopy.notMedical,
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── 2 · works with ──────────────────────────────────────────────────────────

class _WorksWith extends StatelessWidget {
  const _WorksWith({required this.stagger});
  final bool stagger;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return _Page(
      title: OnboardingCopy.worksTitle,
      children: [
        _tile(stagger, 1, const WorksWithPanel()),
        const SizedBox(height: S.tileGap),
        _tile(
          stagger,
          2,
          SideBySide(
            builder: (_) => const [
              PromiseTile(
                icon: Icons.phone_android_rounded,
                title: OnboardingCopy.phoneTitle,
                body: OnboardingCopy.phoneBody,
                glow: GlowRecipes.s9,
              ),
              PromiseTile(
                icon: Icons.visibility_outlined,
                title: OnboardingCopy.readOnlyTitle,
                body: OnboardingCopy.readOnlyBody,
                glow: GlowRecipes.s8,
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x5),
        _tile(
          stagger,
          3,
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                OnboardingCopy.coachCaveat,
                style: F.cap.copyWith(color: p.ink3),
              ),
              const SizedBox(height: S.x1),
              AppButton(
                label: OnboardingCopy.privacyPolicy,
                kind: AppButtonKind.quiet,
                icon: Icons.lock_outline_rounded,
                onTap: () => Navigator.of(context).pushNamed(Routes.privacy),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 3 · choose ──────────────────────────────────────────────────────────────

class _Choose extends StatelessWidget {
  const _Choose({
    required this.stagger,
    required this.state,
    required this.waiting,
    required this.onDemo,
    required this.onConnect,
    required this.onBirthYear,
  });
  final bool stagger;
  final OnboardingState state;

  /// Android's permission sheet is open.
  final bool waiting;
  final VoidCallback? onDemo;
  final VoidCallback? onConnect;
  final VoidCallback? onBirthYear;

  @override
  Widget build(BuildContext context) {
    final busy = state.busy;
    return _Page(
      title: OnboardingCopy.chooseTitle,
      lede: OnboardingCopy.chooseLede,
      children: [
        if (state.error != null) ...[
          EnterFade(
            child: Semantics(
              liveRegion: true,
              child: StatusCard(
                title: OnboardingCopy.errorTitle,
                body: state.error!,
                tone: StatusTone.warning,
              ),
            ),
          ),
          const SizedBox(height: S.x3),
        ],
        // Before the choices: they commit on tap.
        _tile(
          stagger,
          1,
          BirthYearRow(year: state.birthYear, onEdit: onBirthYear),
        ),
        const SizedBox(height: S.tileGap),
        _tile(
          stagger,
          2,
          SideBySide(
            builder: (side) => [
              ChoiceTile(
                icon: Icons.favorite_rounded,
                accent: C.health,
                title: OnboardingCopy.trackerTitle,
                body: waiting
                    ? OnboardingCopy.waitingForHc
                    : OnboardingCopy.trackerBody,
                marker: const StatePill(
                  label: OnboardingCopy.healthConnect,
                  color: C.health,
                ),
                glow: GlowRecipes.m20,
                onTap: onConnect,
                semanticLabel: waiting
                    ? OnboardingCopy.waitingForHc
                    : '${OnboardingCopy.trackerTitle}. '
                          '${OnboardingCopy.trackerBody}',
                fill: side,
              ),
              ChoiceTile(
                icon: Icons.science_outlined,
                accent: C.amber,
                title: OnboardingCopy.sampleTitle,
                body: busy
                    ? OnboardingCopy.sampleBusy
                    : OnboardingCopy.sampleBody,
                // The real chip: the exact label every screen will carry.
                marker: const SampleDataChip(),
                glow: GlowRecipes.m19,
                onTap: onDemo,
                semanticLabel: busy
                    ? OnboardingCopy.sampleBusy
                    : OnboardingCopy.sampleLabel,
                fill: side,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── 3b · denied ─────────────────────────────────────────────────────────────

class _Denied extends StatelessWidget {
  const _Denied({required this.state});
  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final a = state.permissions?.availability;
    final (String title, String body) = switch (a) {
      HcAvailability.notInstalled => (
        OnboardingCopy.notInstalledTitle,
        OnboardingCopy.notInstalledBody,
      ),
      HcAvailability.updateRequired => (
        OnboardingCopy.updateTitle,
        OnboardingCopy.updateBody,
      ),
      HcAvailability.unsupported => (
        OnboardingCopy.unsupportedTitle,
        OnboardingCopy.unsupportedBody,
      ),
      HcAvailability.checkFailed => (
        OnboardingCopy.checkFailedTitle,
        OnboardingCopy.checkFailedBody,
      ),
      _ when state.error != null => (
        OnboardingCopy.noAnswerTitle,
        OnboardingCopy.noAnswerBody,
      ),
      _ when state.permissions?.deniedTwice == true => (
        OnboardingCopy.nothingSharedTitle,
        OnboardingCopy.deniedTwiceBody,
      ),
      _ => (
        OnboardingCopy.nothingSharedTitle,
        OnboardingCopy.nothingSharedBody,
      ),
    };
    return _Page(
      title: OnboardingCopy.deniedTitle,
      children: [
        Semantics(
          liveRegion: true,
          child: StatusCard(title: title, body: body, tone: StatusTone.warning),
        ),
      ],
    );
  }
}
