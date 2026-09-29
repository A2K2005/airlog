// Domain value → pigment. The ONLY place a score, zone or stage becomes a
// colour, so two screens can never colour the same state differently.
//
// Thresholds are the domain's, never re-derived here: recovery zones come from
// `RecoveryResult.zoneFor`, training-load states from `LoadState`, band states
// from `BandState`. These return raw PIGMENT; pass it through `P.on` / `P.mark`
// / `P.fill` before painting (the components do this for you).

import 'package:flutter/painting.dart';

import '../../domain/models.dart' show SleepStage;
import '../../domain/results.dart';
import 'colors.dart';

abstract final class DomainColors {
  static Color recoveryZone(RecoveryZone z) => switch (z) {
    RecoveryZone.green => C.recGreen,
    RecoveryZone.yellow => C.recYellow,
    RecoveryZone.red => C.recRed,
  };

  /// Colour for a recovery score 0–100, using the domain's own zone cut-offs.
  static Color recovery(num score) =>
      recoveryZone(RecoveryResult.zoneFor(score.round()));

  static const strain = C.strain;
  static const sleep = C.sleep;
  static const health = C.health;

  /// Heart-rate zone 0 (rest) … 5.
  static Color hrZone(int zone) => C.zones[zone.clamp(0, C.zones.length - 1)];

  static Color sleepStage(SleepStage s) => switch (s) {
    SleepStage.awake => C.amber,
    SleepStage.rem => C.sky,
    SleepStage.light => C.lavender,
    SleepStage.deep => C.indigo,
    SleepStage.unknown => C.neutral,
  };

  static Color load(LoadState s) => switch (s) {
    LoadState.detraining => C.sky,
    LoadState.optimal => C.recGreen,
    LoadState.elevated => C.recYellow,
    LoadState.high => C.recRed,
  };

  /// In-range is calm (health teal); out-of-range is amber, never alarm red:
  /// a value outside YOUR usual band is a prompt to look, not a diagnosis.
  static Color band(BandState s) => switch (s) {
    BandState.inRange => C.health,
    BandState.above || BandState.below => C.amber,
    BandState.noData || BandState.calibrating => C.neutral,
  };
}
