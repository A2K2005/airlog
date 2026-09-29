// "Sample data": the watermark every screen carries while the app runs on
// the demo generator (PRODUCT_PLAN §7, "Demo data"). The app root provides
// the mode through [SampleDataScope]; components read it without touching a
// provider, and [ScreenHeader] and [SampleDataChip.action] place the chip.

import 'package:flutter/material.dart';

import '../tokens/tokens.dart';

class SampleDataScope extends InheritedWidget {
  const SampleDataScope({super.key, required this.demo, required super.child});

  final bool demo;

  /// True when the app is showing sample data (false with no scope).
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SampleDataScope>()?.demo ??
      false;

  @override
  bool updateShouldNotify(SampleDataScope old) => old.demo != demo;
}

/// The small "Sample data" chip. Not a button: it labels the screen.
class SampleDataChip extends StatelessWidget {
  const SampleDataChip({super.key, this.label = 'Sample data'});
  final String label;

  /// The chip for an AppBar's actions, or nothing outside sample data.
  static List<Widget> action(BuildContext context) =>
      SampleDataScope.of(context)
      ? const [Center(child: SampleDataChip()), SizedBox(width: S.x3)]
      : const [];

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Showing sample data',
    excludeSemantics: true,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x2 + 2, vertical: 3),
      decoration: BoxDecoration(
        color: P.of(context).wash(C.amber),
        borderRadius: R.rPill,
      ),
      child: Text(
        label,
        style: F.micro.copyWith(
          color: P.of(context).on(C.amber),
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
