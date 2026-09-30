// Plain-words formatters shared by screens (chart-axis formatters such as
// axisHm / clockOf live in charts/axis.dart; day names in
// components/navigation_bits.dart).

import '../domain/models.dart' show SourceKind;
import 'charts/axis.dart' show clockOf;

/// "1h 05m", "37 min", "0 min".
String durationWords(num minutes) {
  final m = minutes.round();
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '${h}h' : '${h}h ${r.toString().padLeft(2, '0')}m';
}

/// "0:42", "12:07", "1:02:33" for an elapsed number of seconds.
String clockSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, r = s % 60;
  final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
  return '${h > 0 ? '$h:' : ''}$mm:${r.toString().padLeft(2, '0')}';
}

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

/// "28 Sep 07:12" for a timestamp.
String dayTime(DateTime t) => '${t.day} ${_mo[t.month - 1]} ${clockOf(t)}';

/// "5.21 km" from 1 km up, "820 m" below; null for a missing or
/// non-positive distance.
String? distanceText(double? meters) {
  if (meters == null || !meters.isFinite || meters <= 0) return null;
  return meters >= 1000
      ? '${(meters / 1000).toStringAsFixed(2)} km'
      : '${meters.round()} m';
}

/// "412 kcal"; null for a missing or non-positive value.
String? kcalText(double? kcal) {
  if (kcal == null || !kcal.isFinite || kcal <= 0) return null;
  return '${kcal.round()} kcal';
}

/// "50–60 %", "90–100 %" for the display heart-rate zones, from their lower
/// bounds as fractions of reserve (the last zone runs to 100 %); index 0 of
/// the result is "< 50 %" when [withRest] is set.
List<String> zoneRanges(List<double> lowerBounds, {bool withRest = false}) {
  String p(double f) => '${(f * 100).round()}';
  return [
    if (withRest && lowerBounds.isNotEmpty) '< ${p(lowerBounds.first)} %',
    for (var i = 0; i < lowerBounds.length; i++)
      '${p(lowerBounds[i])}–'
          '${i + 1 < lowerBounds.length ? p(lowerBounds[i + 1]) : '100'} %',
  ];
}

/// A constant as written in prose: 8 (not "8.0"), 0.03, 1.65.
String numText(num v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// A signed number with a real minus sign (U+2212), rounded to [decimals]
/// FIRST so the sign always matches the digits: 0.04 → "0.0" (no sign),
/// 0.06 → "+0.1", −0.3 → "−0.3". [plus] = false drops the "+".
String signed(double v, int decimals, {bool plus = true}) {
  final text = v.abs().toStringAsFixed(decimals);
  final zero = double.parse(text) == 0;
  if (zero) return text;
  return v < 0 ? '−$text' : (plus ? '+$text' : text);
}

/// A source's name as the app shows it. The optional cloud source is
/// "Enhanced mode" everywhere in the UI (never a provider's API name);
/// SourceKind.label stays as the data layer's and the coach's name.
String sourceName(SourceKind k) => switch (k) {
  SourceKind.googleHealthApi => 'Enhanced mode',
  SourceKind.ble => 'Bluetooth',
  _ => k.label,
};
