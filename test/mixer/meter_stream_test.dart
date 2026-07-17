// Pure-Dart test (no Flutter): MeterStream must average in the POWER domain
// (true RMS), so a choppy source (reggae skank / drum hits) reads at its real
// loudness instead of being dragged down toward the silent gaps between hits.
// Run: dart test test/mixer/meter_stream_test.dart
import 'package:test/test.dart';
import 'package:mxwise/mixer/meter_stream.dart';

void main() {
  group('MeterStream RMS (power-domain averaging)', () {
    test('a sustained source reads at its level', () {
      final ms = MeterStream();
      for (var t = 0; t < 400; t++) {
        ms.update([0.5]); // 0.5 amplitude → 20·log10(0.5) = -6.02 dB
      }
      expect(ms.engineDb(0), closeTo(-6.0, 0.5));
    });

    test('a choppy source reads its RMS, not the silent gaps', () {
      // Choppy: 0.5 amplitude at 25% duty → power-RMS = 0.5²·0.25 = 0.0625
      // → -12.0 dB. A (wrong) dB-domain average would read ~20 dB lower.
      // A sustained 0.25-amplitude source has the SAME power (0.25² = 0.0625),
      // so both must read the same — that's the whole point of RMS.
      final chop = MeterStream();
      final sustained = MeterStream();
      for (var t = 0; t < 800; t++) {
        chop.update([t % 4 == 0 ? 0.5 : 0.0]); // loud 1 tick in 4 (25% duty)
        sustained.update([0.25]);
      }
      expect(chop.engineDb(0), closeTo(-12.0, 1.5),
          reason: 'choppy source must read its true RMS (~-12), not the gaps');
      expect(chop.engineDb(0), closeTo(sustained.engineDb(0), 1.5),
          reason: 'same power-RMS ⇒ same reading, choppy or sustained');
    });
  });
}
