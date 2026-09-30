// The birth-year picker: a wheel of the years the app accepts (adults, at
// most 100 years old), so an out-of-range year cannot be entered and no
// error is ever shown. The selected year is in dot-matrix numerals on a
// plate; screen readers get one adjustable control (swipe up / down).
//
// Motion: the sheet uses sheetMotion (a hard cut under reduced motion); the
// wheel scrolls with platform physics; assistive increase / decrease jump
// without animating.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design/design.dart';
import 'onboarding_copy.dart';
import 'onboarding_view_model.dart' show BirthYearRange;

/// What the sheet returned: a year to set, or a request to clear it.
class BirthYearResult {
  const BirthYearResult.set(int this.year);
  const BirthYearResult.clear() : year = null;

  /// Null means "remove the birth year".
  final int? year;
}

/// Resolves null when dismissed (scrim, drag, Back): nothing changes.
Future<BirthYearResult?> showBirthYearSheet(
  BuildContext context, {
  required BirthYearRange range,
  int? current,
}) => showModalBottomSheet<BirthYearResult>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  sheetAnimationStyle: sheetMotion(context),
  builder: (c) => BirthYearSheet(range: range, current: current),
);

class BirthYearSheet extends StatefulWidget {
  const BirthYearSheet({super.key, required this.range, this.current});
  final BirthYearRange range;
  final int? current;

  @override
  State<BirthYearSheet> createState() => _BirthYearSheetState();
}

class _BirthYearSheetState extends State<BirthYearSheet> {
  late int _year = _start;
  late final _wheel = FixedExtentScrollController(
    initialItem: _start - widget.range.min,
  );

  int get _start {
    final c = widget.current;
    return c != null && widget.range.contains(c) ? c : widget.range.initial;
  }

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  void _select(int index) {
    final y = widget.range.min + index;
    if (y == _year) return;
    HapticFeedback.selectionClick();
    setState(() => _year = y);
  }

  /// Assistive increase / decrease: one year, no animation.
  void _step(int delta) {
    final r = widget.range;
    final y = (_year + delta).clamp(r.min, r.max);
    if (y == _year) return;
    _wheel.jumpToItem(y - r.min);
    setState(() => _year = y);
  }

  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    final r = widget.range;
    final big = bigText(context);
    final extent = MediaQuery.textScalerOf(context).scale(40).clamp(48.0, 96.0);
    final rows = big ? 3 : 5;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .88,
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                S.gutter,
                S.x5,
                S.gutter,
                S.x4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      OnboardingCopy.sheetTitle,
                      style: F.t1.copyWith(color: p.ink),
                    ),
                  ),
                  const SizedBox(height: S.x2),
                  Text(
                    OnboardingCopy.sheetLede,
                    style: F.body.copyWith(color: p.ink2),
                  ),
                  const SizedBox(height: S.x4),
                  Semantics(
                    slider: true,
                    label: OnboardingCopy.birthYear,
                    value: '$_year',
                    increasedValue: _year < r.max ? '${_year + 1}' : null,
                    decreasedValue: _year > r.min ? '${_year - 1}' : null,
                    onIncrease: _year < r.max ? () => _step(1) : null,
                    onDecrease: _year > r.min ? () => _step(-1) : null,
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: extent * rows,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Container(
                              height: extent,
                              decoration: const BoxDecoration(
                                color: C.panel,
                                borderRadius: R.rPanel,
                              ),
                            ),
                            ListWheelScrollView.useDelegate(
                              controller: _wheel,
                              itemExtent: extent,
                              physics: const FixedExtentScrollPhysics(),
                              diameterRatio: 2.2,
                              onSelectedItemChanged: _select,
                              childDelegate: ListWheelChildBuilderDelegate(
                                childCount: r.count,
                                builder: (context, i) {
                                  final y = r.min + i;
                                  final on = y == _year;
                                  return Center(
                                    child: DotMatrixNumber(
                                      '$y',
                                      style: on ? F.dot32 : F.dot24,
                                      color: on ? p.ink : TileInk.tertiary,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(S.gutter, S.x2, S.gutter, S.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppButton(
                  label: OnboardingCopy.save,
                  expand: true,
                  onTap: () =>
                      Navigator.of(context).pop(BirthYearResult.set(_year)),
                ),
                if (widget.current != null) ...[
                  const SizedBox(height: S.x1),
                  AppButton(
                    label: OnboardingCopy.removeBirthYear,
                    kind: AppButtonKind.quiet,
                    expand: true,
                    onTap: () => Navigator.of(
                      context,
                    ).pop(const BirthYearResult.clear()),
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
