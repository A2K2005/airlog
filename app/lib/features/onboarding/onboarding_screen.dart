// First launch, three calm steps: what Airlog is (and is not), where your
// data lives, and how to start — demo data, or Health Connect with the
// reason for each data type shown BEFORE the system permission sheet.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/platform_services.dart';
import '../../app/route_names.dart';
import '../../design/design.dart';
import '../../domain/repositories.dart' show HcAvailability;
import '../../app/hc_rationale.dart';
import 'onboarding_view_model.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    final p = P.of(context);
    final (Widget body, Widget actions) = switch (s.step) {
      OnboardingStep.what => (
        const _What(),
        AppButton(label: 'Next', expand: true, onTap: c.next),
      ),
      OnboardingStep.privacy => (
        const _Privacy(),
        _Pair(
          primary: AppButton(label: 'Next', expand: true, onTap: c.next),
          onBack: c.back,
        ),
      ),
      OnboardingStep.choose || OnboardingStep.done => (
        _Choose(
          onDemo: s.busy ? null : c.chooseDemo,
          onConnect: s.busy ? null : c.showRationale,
          onBirthYear: c.setBirthYear,
          state: s,
        ),
        _Pair(onBack: c.back),
      ),
      OnboardingStep.rationale || OnboardingStep.requesting => (
        const _Rationale(),
        _Pair(
          primary: AppButton(
            label: s.step == OnboardingStep.requesting
                ? 'Waiting for Health Connect…'
                : 'Continue to Health Connect',
            expand: true,
            onTap: s.step == OnboardingStep.requesting
                ? null
                : c.requestHealthConnect,
          ),
          onBack: c.back,
        ),
      ),
      OnboardingStep.denied => (
        _Denied(state: s),
        _Pair(
          primary: AppButton(
            label: 'Try with sample data instead',
            expand: true,
            onTap: c.chooseDemo,
          ),
          // After two denials Android stops showing the sheet: offer its
          // settings instead of a "Try again" that does nothing (QA-06).
          secondary: s.permissions?.deniedTwice == true
              ? AppButton(
                  label: 'Open Health Connect settings',
                  kind: AppButtonKind.secondary,
                  expand: true,
                  onTap: () => ref.read(linkOpenerProvider)(
                    Uri.parse(
                      'intent:#Intent;action=android.health.connect.action.HEALTH_HOME_SETTINGS;end',
                    ),
                  ),
                )
              : s.permissions?.availability == HcAvailability.available ||
                    s.permissions == null
              ? AppButton(
                  label: 'Try again',
                  kind: AppButtonKind.secondary,
                  expand: true,
                  onTap: c.requestHealthConnect,
                )
              : null,
          onBack: c.back,
        ),
      ),
    };
    // System Back steps back through onboarding (QA-05); from the first
    // step it leaves without a choice, so onboarding is offered again next
    // launch (it is marked seen only by a choice).
    final first =
        s.step == OnboardingStep.what || s.step == OnboardingStep.done;
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
                    Text(
                      '${s.page + 1} of 3',
                      style: F.tab(F.cap).copyWith(color: p.ink3),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: AnimatedSwitcher(
                  duration: motion(context, Motion.slow, fade: true),
                  reverseDuration: motion(context, Motion.exit, fade: true),
                  switchInCurve: Motion.enter,
                  switchOutCurve: Motion.enter.flipped,
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: Motion.enabled(context)
                        ? SlideTransition(
                            position: Tween(
                              begin: const Offset(0, .02),
                              end: Offset.zero,
                            ).animate(a),
                            child: child,
                          )
                        : child,
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(
                      s.step == OnboardingStep.requesting
                          ? OnboardingStep.rationale
                          : s.step,
                    ),
                    child: body,
                  ),
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
        label: 'Back',
        kind: AppButtonKind.quiet,
        expand: true,
        onTap: onBack,
      ),
    ],
  );
}

class _Page extends StatelessWidget {
  const _Page({required this.title, this.lede, required this.children});
  final String title;
  final String? lede;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(S.gutter, S.x8, S.gutter, S.x4),
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

class _What extends StatelessWidget {
  const _What();

  @override
  Widget build(BuildContext context) {
    return const _Page(
      title: 'Airlog',
      lede:
          'Recovery, strain and sleep from your tracker, computed on this '
          'phone and explained in full.',
      children: [
        OverLabel('What it is'),
        SizedBox(height: S.x3),
        BulletLine(
          'How ready you are, each morning, from HRV, resting heart '
          'rate, sleep and breathing against your own baseline.',
          icon: Icons.wb_twilight_rounded,
          strong: 'Recovery.',
        ),
        BulletLine(
          'How hard your heart worked across the day, by '
          'heart-rate zone.',
          icon: Icons.bolt_rounded,
          strong: 'Strain.',
        ),
        BulletLine(
          'What you needed, what you got, and the debt carried '
          'forward.',
          icon: Icons.bedtime_rounded,
          strong: 'Sleep.',
        ),
        SizedBox(height: S.x5),
        OverLabel('What it isn’t'),
        SizedBox(height: S.x3),
        BulletLine(
          'It notices patterns against your own normal; it does not '
          'diagnose anything.',
          icon: Icons.medical_services_outlined,
          strong: 'Not medical.',
        ),
        BulletLine(
          'Published methods, every formula on view. Numbers will '
          'differ from WHOOP’s and Fitbit’s.',
          icon: Icons.functions_rounded,
          strong: 'Not WHOOP’s formula.',
        ),
        BulletLine(
          'Not affiliated with Google, Fitbit or WHOOP.',
          icon: Icons.link_off_rounded,
          strong: 'Independent.',
        ),
      ],
    );
  }
}

class _Privacy extends StatelessWidget {
  const _Privacy();

  @override
  Widget build(BuildContext context) {
    return _Page(
      title: 'It stays on this phone',
      lede: 'Every score is computed here. There is nothing to sign up for.',
      children: [
        const BulletLine(
          'Scores are computed on the phone, from data already '
          'on the phone.',
          icon: Icons.phone_android_rounded,
        ),
        const BulletLine(
          'No Airlog server and no account.',
          icon: Icons.cloud_off_rounded,
        ),
        const BulletLine(
          'No analytics, no ads, no tracking.',
          icon: Icons.visibility_off_outlined,
        ),
        const BulletLine(
          'Export readings and scores, or delete local data, whenever you like.',
          icon: Icons.ios_share_rounded,
        ),
        const BulletLine(
          'If you opt in to a cloud coach, your questions and permitted '
          'context are sent to the provider you choose. On-device coaching '
          'does not send them.',
          icon: Icons.chat_bubble_outline_rounded,
        ),
        const SizedBox(height: S.x4),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Read the privacy policy',
            kind: AppButtonKind.quiet,
            icon: Icons.lock_outline_rounded,
            onTap: () => Navigator.of(context).pushNamed(Routes.privacy),
          ),
        ),
      ],
    );
  }
}

class _Choose extends StatelessWidget {
  const _Choose({
    required this.onDemo,
    required this.onConnect,
    required this.onBirthYear,
    required this.state,
  });
  final VoidCallback? onDemo;
  final VoidCallback? onConnect;
  final ValueChanged<String> onBirthYear;
  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    Widget option(
      IconData icon,
      Color accent,
      String title,
      String body,
      VoidCallback? onTap,
    ) => AppCard(
      onTap: onTap,
      semanticLabel: '$title. $body',
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: p.wash(accent),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 20, color: p.on(accent)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: F.head.copyWith(color: p.ink)),
                  const SizedBox(height: 2),
                  Text(body, style: F.bodySm.copyWith(color: p.ink2)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.ink3),
          ],
        ),
      ),
    );
    return _Page(
      title: 'How do you want to start?',
      lede:
          'You can switch at any time in Settings. Sample and real data are '
          'kept apart.',
      children: [
        if (state.error != null) ...[
          StatusCard(
            title: 'Check your setup',
            body: state.error!,
            tone: StatusTone.warning,
          ),
          const SizedBox(height: S.x3),
        ],
        option(
          Icons.favorite_border_rounded,
          C.health,
          'Connect Health Connect',
          'We’ll find the apps you already use. You choose each data type.',
          onConnect,
        ),
        const SizedBox(height: S.x3),
        option(
          Icons.science_outlined,
          C.amber,
          'Try with sample data',
          '90 days of sample data, labelled “Sample data” everywhere. Good '
              'for a look around first.',
          onDemo,
        ),
        const SizedBox(height: S.x5),
        TextFormField(
          initialValue: state.birthYear,
          enabled: !state.busy,
          keyboardType: TextInputType.number,
          maxLength: 4,
          onChanged: onBirthYear,
          decoration: const InputDecoration(
            labelText: 'Birth year (optional)',
            helperText: 'For adults 18+. Used to estimate maximum heart rate.',
            helperMaxLines: 2,
            counterText: '',
          ),
        ),
      ],
    );
  }
}

class _Rationale extends StatelessWidget {
  const _Rationale();

  @override
  Widget build(BuildContext context) => const _Page(
    title: 'What Airlog will read',
    lede:
        'Health Connect asks you type by type next. Each one powers one '
        'feature; anything you leave off shows as missing, never '
        'guessed. Read only: Airlog writes nothing back.',
    children: [HcRationaleList()],
  );
}

class _Denied extends StatelessWidget {
  const _Denied({required this.state});
  final OnboardingState state;

  @override
  Widget build(BuildContext context) {
    final a = state.permissions?.availability;
    final (String title, String body) = switch (a) {
      HcAvailability.notInstalled => (
        'Health Connect isn’t installed',
        'Install Health Connect from Google Play, turn on sync in your '
            'tracker’s app, then connect from Settings → Sources.',
      ),
      HcAvailability.updateRequired => (
        'Health Connect needs an update',
        'Update it from Google Play, then connect from Settings → Sources.',
      ),
      HcAvailability.unsupported => (
        'Health Connect isn’t available here',
        'This device cannot run Health Connect. You can still explore '
            'everything with sample data.',
      ),
      _ => (
        'No access granted',
        state.error == null
            ? 'Airlog cannot read your data without at least one data type. '
                  'Nothing was changed.'
            : 'Health Connect did not answer. Try again in a moment.',
      ),
    };
    return _Page(
      title: 'Not connected',
      children: [
        StatusCard(title: title, body: body, tone: StatusTone.warning),
      ],
    );
  }
}
