// DaySwitcher, TrendArrow and EmptyState.

import 'package:flutter/material.dart';

import '../../domain/day_key.dart';
import '../../domain/results.dart' show TrendDirection, TrendResult;
import '../tokens/tokens.dart';
import 'pressable.dart';
import 'skeleton.dart';
import 'surfaces.dart';

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _wdLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];
const _mo = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const _moLong = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// "Tue 28 Sep" for a DayKey.
String shortDay(String key) {
  final d = DayKey.start(key);
  return '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';
}

/// "Tuesday 28 September" (spoken form).
String longDay(String key) {
  final d = DayKey.start(key);
  return '${_wdLong[d.weekday - 1]} ${d.day} ${_moLong[d.month - 1]}';
}

/// "28 Sep" — for chart x labels.
String dayMonth(String key) {
  final d = DayKey.start(key);
  return '${d.day} ${_mo[d.month - 1]}';
}

/// ‹ Tue 28 Sep › — steps the day the day screens show. Stepping days is
/// done tens of times a day, so the label swaps instantly (no crossfade).
class DaySwitcher extends StatelessWidget {
  const DaySwitcher({
    super.key,
    required this.date,
    required this.onShift,
    this.latest,
    this.earliest,
    this.today,
    this.onTapDate,
  });

  /// DayKey ("yyyy-MM-dd") being shown.
  final String date;

  /// Called with −1 (previous) or +1 (next).
  final ValueChanged<int> onShift;

  /// Newest day with data: "next" is disabled at or after it.
  final String? latest;

  /// Oldest day with data: "previous" is disabled at or before it.
  final String? earliest;

  /// Today's DayKey, for the "Today" / "Yesterday" words. Pass it in (tests,
  /// goldens); null computes it from the clock.
  final String? today;
  final VoidCallback? onTapDate;

  String get _label {
    final t = today ?? DayKey.today();
    if (date == t) return 'Today';
    if (date == DayKey.add(t, -1)) return 'Yesterday';
    return shortDay(date);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final canNext = latest == null || date.compareTo(latest!) < 0;
    final canPrev = earliest == null || date.compareTo(earliest!) > 0;
    final label = _label;
    final sub = label == shortDay(date) ? null : shortDay(date);
    return Semantics(
      container: true,
      label:
          'Showing ${label == 'Today' || label == 'Yesterday' ? '$label, ' : ''}${longDay(date)}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppIconButton(
            icon: Icons.chevron_left_rounded,
            semanticLabel: 'Previous day',
            onTap: canPrev ? () => onShift(-1) : null,
            filled: true,
            size: 20,
          ),
          Flexible(
            child: Pressable(
              onTap: onTapDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x2),
                child: ExcludeSemantics(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        style: F
                            .tab(F.head)
                            .copyWith(
                              color: p.ink,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      if (sub != null)
                        Text(
                          sub,
                          maxLines: 1,
                          softWrap: false,
                          style: F.tab(F.cap).copyWith(color: p.ink3),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AppIconButton(
            icon: Icons.chevron_right_rounded,
            semanticLabel: 'Next day',
            onTap: canNext ? () => onShift(1) : null,
            filled: true,
            size: 20,
          ),
        ],
      ),
    );
  }
}

/// The DaySwitcher's footprint while the day is not known yet (loading, first
/// launch): same height, so the header does not grow when data arrives.
class DaySwitcherSkeleton extends StatelessWidget {
  const DaySwitcherSkeleton({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: S.tap,
    child: Align(
      alignment: Alignment.centerLeft,
      child: SkeletonBox(width: 168, height: 36, radius: R.rPill),
    ),
  );
}

/// An arrow that exists ONLY when the change is statistically significant
/// (the engine's TrendResult.significant). Otherwise it renders nothing: a
/// flat or noisy series never gets an arrow that implies a real change.
class TrendArrow extends StatelessWidget {
  const TrendArrow({
    super.key,
    required this.trend,
    required this.upIsGood,
    this.metric,
    this.size = 18,
    this.showLabel = false,
  });

  final TrendResult? trend;

  /// Which direction is good news for this metric. Null = neither (neutral
  /// ink, no verdict).
  final bool? upIsGood;

  /// For the spoken label ("HRV").
  final String? metric;
  final double size;

  /// Adds "Rising" / "Falling" after the glyph.
  final bool showLabel;

  static bool visible(TrendResult? t) =>
      t != null && t.significant && t.direction != TrendDirection.flat;

  @override
  Widget build(BuildContext context) {
    final t = trend;
    if (!visible(t)) return const SizedBox.shrink();
    final p = P.of(context);
    final up = t!.direction == TrendDirection.up;
    final good = upIsGood == null ? null : (up == upIsGood);
    final ink = good == null
        ? p.ink2
        : good
        ? p.on(C.health)
        : p.on(C.amber);
    final word = up ? 'Rising' : 'Falling';
    return Semantics(
      label:
          '${metric == null ? '' : '$metric '}${word.toLowerCase()}, '
          'a significant change over ${t.n} days',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              up ? Icons.north_east_rounded : Icons.south_east_rounded,
              size: size,
              color: ink,
            ),
            if (showLabel) ...[
              const SizedBox(width: 2),
              Text(
                word,
                style: F.cap.copyWith(color: ink, fontWeight: FontWeight.w700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A whole screen or section with nothing to show yet, and what to do.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x6, vertical: S.x8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: 26, color: p.ink2),
          ),
          const SizedBox(height: S.x4),
          Semantics(
            header: true,
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: F.t2.copyWith(color: p.ink),
            ),
          ),
          const SizedBox(height: S.x2),
          Text(
            body,
            textAlign: TextAlign.center,
            style: F.body.copyWith(color: p.ink2),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: S.x5),
            AppButton(label: actionLabel!, onTap: onAction),
          ],
        ],
      ),
    );
  }
}
