// Adapted from OpenStrap/edge lib/ui2/theme.dart (MIT, see third_party/edge/LICENSE).
// Changes: dark only (the design is dark; the light variant is gone); a full
// ThemeData (Edge set only the scaffold,
// seed scheme and page gate): an explicit near-monochrome ColorScheme (accents
// are for data, not chrome), DM Sans text theme, and component themes for
// NavigationBar, cards, sheets, dialogs, switches, sliders, segmented buttons,
// buttons, app bars, dividers, snack bars and progress indicators; page
// transitions are Airlog's own gated builder on every platform.

import 'package:flutter/material.dart';

import 'colors.dart';
import 'layout.dart';
import 'motion.dart';
import 'type.dart';

/// The app theme. Dark only, like the design: [requested] is accepted for
/// source compatibility and ignored.
ThemeData buildTheme([Brightness requested = Brightness.dark]) {
  const b = Brightness.dark;
  const p = P();

  final scheme = ColorScheme(
    brightness: b,
    primary: p.ink,
    onPrimary: p.inkInverse,
    primaryContainer: p.card2,
    onPrimaryContainer: p.ink,
    secondary: p.on(C.strain),
    onSecondary: p.onFill(C.strain),
    tertiary: p.on(C.health),
    onTertiary: p.onFill(C.health),
    error: p.on(C.recRed),
    onError: p.onFill(C.recRed),
    surface: p.card,
    onSurface: p.ink,
    onSurfaceVariant: p.ink2,
    surfaceContainerLowest: p.bg,
    surfaceContainerLow: p.card,
    surfaceContainer: p.card,
    surfaceContainerHigh: p.card2,
    surfaceContainerHighest: p.sheet,
    outline: p.line,
    outlineVariant: p.line,
    shadow: C.black,
    scrim: p.scrim,
    inverseSurface: p.ink,
    onInverseSurface: p.inkInverse,
    surfaceTint: C.clear,
  );

  TextStyle ink(TextStyle s, [Color? c]) => s.copyWith(color: c ?? p.ink);

  final text = TextTheme(
    displayLarge: ink(F.n64),
    displayMedium: ink(F.n44),
    displaySmall: ink(F.n32),
    headlineLarge: ink(F.display),
    headlineMedium: ink(F.t1),
    headlineSmall: ink(F.t2),
    titleLarge: ink(F.t2),
    titleMedium: ink(F.head),
    titleSmall: ink(F.bodySm.copyWith(fontWeight: FontWeight.w600)),
    bodyLarge: ink(F.body),
    bodyMedium: ink(F.bodySm),
    bodySmall: ink(F.cap, p.ink2),
    labelLarge: ink(F.head),
    labelMedium: ink(F.cap),
    labelSmall: ink(F.over, p.ink2),
  );

  const pill = RoundedRectangleBorder(borderRadius: R.rPill);
  const buttonText = WidgetStatePropertyAll(F.head);
  const buttonPad = WidgetStatePropertyAll(
    EdgeInsets.symmetric(horizontal: S.x5, vertical: S.x3),
  );
  const minSize = WidgetStatePropertyAll(Size(S.tap, S.tap));

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: F.ui,
    textTheme: text,
    primaryTextTheme: text,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    dividerColor: p.line,
    splashFactory: NoSplash.splashFactory,
    highlightColor: C.clear,
    splashColor: C.clear,
    hoverColor: p.ink.withValues(alpha: .04),
    focusColor: p.ink.withValues(alpha: .10),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconTheme: IconThemeData(color: p.ink2, size: 22),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: AirlogPageTransitions(),
        TargetPlatform.iOS: AirlogPageTransitions(),
        TargetPlatform.fuchsia: AirlogPageTransitions(),
        TargetPlatform.linux: AirlogPageTransitions(),
        TargetPlatform.macOS: AirlogPageTransitions(),
        TargetPlatform.windows: AirlogPageTransitions(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.ink,
      surfaceTintColor: C.clear,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: ink(F.head),
      iconTheme: IconThemeData(color: p.ink, size: 22),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: C.clear,
      elevation: 0,
      height: 68,
      indicatorColor: p.card2,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => F.cap.copyWith(
          color: s.contains(WidgetState.selected) ? p.ink : p.ink3,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 24,
          color: s.contains(WidgetState.selected) ? p.ink : p.ink3,
        ),
      ),
      overlayColor: const WidgetStatePropertyAll(C.clear),
    ),
    cardTheme: CardThemeData(
      color: p.card,
      surfaceTintColor: C.clear,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: const RoundedRectangleBorder(borderRadius: R.rCard),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.sheet,
      modalBackgroundColor: p.sheet,
      surfaceTintColor: C.clear,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: p.scrim,
      shape: const RoundedRectangleBorder(borderRadius: R.rSheet),
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.sheet,
      surfaceTintColor: C.clear,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: R.rCard),
      titleTextStyle: ink(F.t2),
      contentTextStyle: ink(F.body, p.ink2),
      barrierColor: p.scrim,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.inkInverse : p.ink3,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.ink : p.card2,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.ink : p.line,
      ),
      overlayColor: const WidgetStatePropertyAll(C.clear),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.ink,
      inactiveTrackColor: p.track,
      thumbColor: p.ink,
      overlayColor: p.ink.withValues(alpha: .08),
      valueIndicatorColor: p.ink,
      valueIndicatorTextStyle: F.tab(F.cap).copyWith(color: p.inkInverse),
      trackHeight: 4,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.card2 : p.card,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.ink : p.ink2,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.line)),
        textStyle: WidgetStatePropertyAll(
          F.bodySm.copyWith(fontWeight: FontWeight.w600),
        ),
        shape: const WidgetStatePropertyAll(pill),
        overlayColor: const WidgetStatePropertyAll(C.clear),
        minimumSize: minSize,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStatePropertyAll(p.ink),
        foregroundColor: WidgetStatePropertyAll(p.inkInverse),
        textStyle: buttonText,
        padding: buttonPad,
        shape: const WidgetStatePropertyAll(pill),
        minimumSize: minSize,
        elevation: const WidgetStatePropertyAll(0),
        overlayColor: const WidgetStatePropertyAll(C.clear),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(p.ink),
        side: WidgetStatePropertyAll(BorderSide(color: p.line)),
        textStyle: buttonText,
        padding: buttonPad,
        shape: const WidgetStatePropertyAll(pill),
        minimumSize: minSize,
        overlayColor: const WidgetStatePropertyAll(C.clear),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(p.ink),
        textStyle: buttonText,
        shape: const WidgetStatePropertyAll(pill),
        minimumSize: minSize,
        overlayColor: const WidgetStatePropertyAll(C.clear),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(p.ink),
        minimumSize: minSize,
        overlayColor: WidgetStatePropertyAll(p.ink.withValues(alpha: .06)),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.ink2,
      textColor: p.ink,
      titleTextStyle: ink(F.body),
      subtitleTextStyle: ink(F.cap, p.ink2),
      contentPadding: const EdgeInsets.symmetric(horizontal: S.gutter),
      minVerticalPadding: S.x3,
    ),
    dividerTheme: DividerThemeData(
      color: p.line,
      thickness: S.hair,
      space: S.hair,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: p.ink,
      linearTrackColor: p.track,
      circularTrackColor: p.track,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: F.bodySm.copyWith(color: p.inkInverse),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: R.rMd),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.ink, borderRadius: R.rSm),
      textStyle: F.cap.copyWith(color: p.inkInverse),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: p.ink,
      selectionColor: p.on(C.strain).withValues(alpha: .3),
      selectionHandleColor: p.ink,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.card2,
      border: const OutlineInputBorder(
        borderRadius: R.rMd,
        borderSide: BorderSide.none,
      ),
      hintStyle: F.body.copyWith(color: p.ink3),
      labelStyle: F.body.copyWith(color: p.ink2),
    ),
  );
}
