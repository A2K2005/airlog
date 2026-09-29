// Bluetooth SIG Heart Rate Measurement (0x2A37) decoder.
//
// Semantics follow OpenStrap/edge `lib/ble/adapters/ble_hrs.dart` (MIT, see
// third_party/edge/LICENSE): the sensor's "no skin contact" is a REFUSAL
// (drop the sample, never store it as a low reading), RR intervals arrive
// in 1/1024 s ticks, and the RR flag is optional (many optical bands never
// set it). Edge's actual decode function lives in its separate
// `openstrap_protocol` package, which is not in our reference clone, so this
// implementation is written from the SIG Heart Rate Service 1.0 layout and
// pinned with Edge's own test vectors (test/data/hrs_parser_test.dart).
//
// Flags byte:
//   bit 0    HR format: 0 = uint8, 1 = uint16 (little-endian)
//   bits 1-2 sensor contact: 0b10 = supported, not detected; 0b11 = detected
//            (0b00/0b01 = contact feature not supported → null)
//   bit 3    Energy Expended present (uint16, kJ)
//   bit 4    RR-Interval(s) present (uint16 each, 1/1024 s)

class HrMeasurement {
  const HrMeasurement({
    required this.bpm,
    this.contact,
    this.energyKj,
    this.rrMs = const [],
  });
  final int bpm;

  /// null = the sensor does not report contact.
  final bool? contact;
  final int? energyKj;
  final List<double> rrMs;
}

/// Returns null for malformed frames.
HrMeasurement? parseHeartRateMeasurement(List<int> data) {
  if (data.isEmpty) return null;
  final flags = data[0];
  var i = 1;
  int? u8() => i < data.length ? data[i++] & 0xFF : null;
  int? u16() {
    if (i + 1 >= data.length) return null;
    final v = (data[i] & 0xFF) | ((data[i + 1] & 0xFF) << 8);
    i += 2;
    return v;
  }

  final bpm = (flags & 0x01) != 0 ? u16() : u8();
  if (bpm == null) return null;
  final contactBits = (flags >> 1) & 0x03;
  final bool? contact = switch (contactBits) {
    0x02 => false,
    0x03 => true,
    _ => null,
  };
  int? energy;
  if ((flags & 0x08) != 0) {
    energy = u16();
    if (energy == null) return null;
  }
  final rr = <double>[];
  if ((flags & 0x10) != 0) {
    while (i + 1 < data.length) {
      final ticks = u16()!;
      rr.add(ticks * 1000 / 1024);
    }
  }
  return HrMeasurement(bpm: bpm, contact: contact, energyKj: energy, rrMs: rr);
}
