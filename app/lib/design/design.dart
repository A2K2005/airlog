// The Airlog design system. Screens import this one file:
//
//   import 'package:airlog/design/design.dart';
//
// tokens/      colour (C, P), type (F), spacing (S), radii (R), motion
//              (Motion, motion()), DomainColors, buildTheme
// charts/      AxisSpec, ChartFrame, painters, and the widget charts
// components/  Pressable, AppCard, GlowTile, DotMatrixNumber, StatusCard, …
// tiles/       the design tiles (one per design PNG), and their marks
// format.dart  plain-words formatters (durationWords, clockSeconds, signed…)
//
// design/ imports only Flutter and domain/ value types (ARCHITECTURE.md §2).

export 'charts/charts.dart';
export 'components/components.dart';
export 'format.dart';
export 'tiles/tiles.dart';
export 'tokens/tokens.dart';
