// 0x2A37 Heart Rate Measurement vectors. The first three are Edge's own
// fixtures (OpenStrap/edge test/hrs_link_test.dart, MIT); the rest cover the
// remaining flag bits of the SIG Heart Rate Service 1.0 layout.

import 'package:airlog/data/services/ble/hrs_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uint8 HR, RR flag clear, contact not supported', () {
    final m = parseHeartRateMeasurement(const [0x00, 61])!;
    expect(m.bpm, 61);
    expect(m.contact, isNull);
    expect(m.rrMs, isEmpty);
    expect(m.energyKj, isNull);
  });

  test('contact supported + detected (bits 1-2 = 0b11)', () {
    final m = parseHeartRateMeasurement(const [0x06, 61])!;
    expect(m.contact, isTrue);
  });

  test(
    'contact supported, NOT detected (0b10) → contact false (caller drops it)',
    () {
      final m = parseHeartRateMeasurement(const [0x04, 45])!;
      expect(m.contact, isFalse);
    },
  );

  test('uint8 HR + two RR intervals in 1/1024 s (Edge vector)', () {
    final m = parseHeartRateMeasurement(const [
      0x16,
      120,
      0xF4,
      0x01,
      0x00,
      0x02,
    ])!;
    expect(m.bpm, 120);
    expect(m.contact, isTrue);
    expect(m.rrMs, hasLength(2));
    expect(m.rrMs[0], closeTo(488.28, 0.01)); // 500 ticks
    expect(m.rrMs[1], closeTo(500.0, 0.01)); // 512 ticks
  });

  test('uint16 HR (bit 0)', () {
    final m = parseHeartRateMeasurement(const [0x01, 0x2C, 0x01])!; // 300
    expect(m.bpm, 300);
  });

  test('energy expended (bit 3) precedes RR intervals', () {
    // flags: uint8 HR, energy, RR; HR 72; energy 0x0102 = 258 kJ; RR 1024 ticks = 1000 ms
    final m = parseHeartRateMeasurement(const [
      0x18,
      72,
      0x02,
      0x01,
      0x00,
      0x04,
    ])!;
    expect(m.bpm, 72);
    expect(m.energyKj, 258);
    expect(m.rrMs.single, closeTo(1000, 1e-9));
  });

  test('uint16 HR + energy + RR together', () {
    final m = parseHeartRateMeasurement(const [
      0x19,
      0x96,
      0x00,
      0x10,
      0x00,
      0x00,
      0x02,
      0xF4,
      0x01,
    ])!;
    expect(m.bpm, 150);
    expect(m.energyKj, 16);
    expect(m.rrMs.map((x) => x.round()), [500, 488]);
  });

  test('malformed frames return null', () {
    expect(parseHeartRateMeasurement(const []), isNull);
    expect(
      parseHeartRateMeasurement(const [0x01, 0x2C]),
      isNull,
    ); // uint16 cut short
    expect(
      parseHeartRateMeasurement(const [0x08, 70, 0x01]),
      isNull,
    ); // energy cut short
  });

  test('a dangling odd RR byte is ignored', () {
    final m = parseHeartRateMeasurement(const [0x10, 60, 0x00, 0x04, 0x07])!;
    expect(m.rrMs.single, closeTo(1000, 1e-9));
  });
}
