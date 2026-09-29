// Coach text formatting, shared by the tool payloads, the offline templates,
// the facts-table fallback and the verifier (one representation for every
// unit, so what a tool shows is exactly what the verifier accepts).
//
// Canonical units for SourceRef.unit:
//   '%'      percent                    'ms'    milliseconds (HRV)
//   'bpm'    beats per minute           '/min'  breaths per minute
//   'min'    a DURATION in minutes      'clock' minutes since local midnight
//   '°C'     degrees Celsius (deltas)   'steps' step count
//   'strain' 0–21 strain score          'ratio' unitless ratio (ACWR)
//   'pts'    recovery points            'days' / 'nights' / 'count'
//   'kcal', 'km', 'ml/kg/min'
// Pure Dart.

import '../day_key.dart';

abstract final class CoachFormat {
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const months = [
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

  /// "Tue 29 Sep" for "2026-09-29".
  static String day(String key) {
    final d = DayKey.start(key);
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  /// "7h 12m", "45 min", "7h".
  static String duration(num minutes) {
    final m = minutes.round();
    if (m < 60) return '$m min';
    final h = m ~/ 60, r = m % 60;
    return r == 0 ? '${h}h' : '${h}h ${r}m';
  }

  /// "23:10" for 1390 (minutes since midnight; wraps).
  static String clock(num minutesSinceMidnight) {
    var m = minutesSinceMidnight.round() % 1440;
    if (m < 0) m += 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:'
        '${(m % 60).toString().padLeft(2, '0')}';
  }

  /// Minutes since local midnight of [t].
  static int minutesOfDay(DateTime t) {
    final l = t.toLocal();
    return l.hour * 60 + l.minute;
  }

  /// Rounds [v] to [decimals] (the display precision used everywhere).
  static double round(double v, int decimals) {
    if (!v.isFinite) return v;
    var f = 1.0;
    for (var i = 0; i < decimals; i++) {
      f *= 10;
    }
    return (v * f).roundToDouble() / f;
  }

  /// Number text without trailing ".0".
  static String number(num v, {int decimals = 0}) {
    final r = round(v.toDouble(), decimals);
    if (decimals == 0) return r.round().toString();
    final s = r.toStringAsFixed(decimals);
    return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
  }

  /// Thousands separators for step counts: 8432 → "8,432".
  static String grouped(num v) {
    final s = v.round().abs().toString();
    final b = StringBuffer(v < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// Display text of a value in a canonical [unit] (see the header).
  static String value(double v, String? unit) {
    switch (unit) {
      case '%':
        return '${number(v, decimals: _dec(v))}%';
      case 'ms':
        return '${number(v)} ms';
      case 'bpm':
        return '${number(v)} bpm';
      case '/min':
        return '${number(v, decimals: 1)} breaths/min';
      case 'min':
        return duration(v);
      case 'clock':
        return clock(v);
      case '°C':
        return '${v >= 0 ? '+' : ''}${number(v, decimals: 1)} °C';
      case 'steps':
        return '${grouped(v)} steps';
      case 'strain':
        return number(v, decimals: 1);
      case 'ratio':
        return number(v, decimals: 2);
      case 'pts':
        return '${number(v, decimals: 1)} points';
      case 'days':
        return '${number(v)} days';
      case 'nights':
        return '${number(v)} nights';
      case 'count':
        return number(v);
      case 'kcal':
        return '${number(v)} kcal';
      case 'km':
        return '${number(v, decimals: 1)} km';
      case 'ml/kg/min':
        return '${number(v, decimals: 1)} ml/kg/min';
      default:
        return number(v, decimals: _dec(v));
    }
  }

  static int _dec(double v) => (v - v.roundToDouble()).abs() < 1e-9 ? 0 : 1;

  /// Title for a new conversation from its first question.
  static String title(String question) {
    var t = question.trim().replaceAll(RegExp(r'\s+'), ' ');
    t = t.replaceFirst(RegExp(r'[?.!\s]+$'), '');
    if (t.isEmpty) return 'New chat';
    if (t.length > 48) {
      final cut = t.lastIndexOf(' ', 48);
      t = '${t.substring(0, cut > 20 ? cut : 48)}…';
    }
    return t[0].toUpperCase() + t.substring(1);
  }
}
