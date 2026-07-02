import 'dart:typed_data';
import 'package:test/test.dart';

import '../../lib/osc/osc_codec.dart';

void main() {
  group('encodeOsc / decodeOsc round-trip', () {
    test('/info — no args', () {
      final bytes = encodeOsc('/info', ',', []);
      final msg = decodeOsc(bytes);
      expect(msg.address, '/info');
      expect(msg.typetag, ',');
      expect(msg.args, isEmpty);
    });

    test('/ch/01/config/name — string arg', () {
      final bytes = encodeOsc('/ch/01/config/name', ',s', ['Voz Lead']);
      final msg = decodeOsc(bytes);
      expect(msg.address, '/ch/01/config/name');
      expect(msg.args.first, 'Voz Lead');
    });

    test('/ch/01/mix/01/level — float arg', () {
      final bytes = encodeOsc('/ch/01/mix/01/level', ',f', [0.75]);
      final msg = decodeOsc(bytes);
      expect(msg.address, '/ch/01/mix/01/level');
      expect((msg.args.first as double), closeTo(0.75, 0.0001));
    });

    test('/meters subscription — string arg', () {
      final bytes = encodeOsc('/meters', ',s', ['/meters/13']);
      final msg = decodeOsc(bytes);
      expect(msg.address, '/meters');
      expect(msg.args.first, '/meters/13');
    });

    test('OSC strings are padded to 4-byte boundary', () {
      final bytes = encodeOsc('/info', ',', []);
      // Total length must be multiple of 4
      expect(bytes.length % 4, 0);
    });
  });

  group('decodeMeterBlob', () {
    test('decodes count=3, floats [0.1, 0.5, 0.9] little-endian', () {
      final bd = ByteData(4 + 3 * 4);
      bd.setUint32(0, 3, Endian.little);
      bd.setFloat32(4, 0.1, Endian.little);
      bd.setFloat32(8, 0.5, Endian.little);
      bd.setFloat32(12, 0.9, Endian.little);
      final blob = bd.buffer.asUint8List();

      final levels = decodeMeterBlob(blob);
      expect(levels.length, 3);
      expect(levels[0], closeTo(0.1, 0.0001));
      expect(levels[1], closeTo(0.5, 0.0001));
      expect(levels[2], closeTo(0.9, 0.0001));
    });

    test('returns empty list for blob shorter than 4 bytes', () {
      expect(decodeMeterBlob(Uint8List(3)), isEmpty);
    });
  });

  group('floatToDb / dbToFloat', () {
    // Boundary values from PRD §8.7
    const cases = [
      (f: 0.0, db: -90.0),
      (f: 0.0625, db: -60.0),
      (f: 0.25, db: -30.0),
      (f: 0.5, db: -10.0),
      (f: 0.75, db: 0.0),
      (f: 1.0, db: 10.0),
    ];

    for (final c in cases) {
      test('floatToDb(${c.f}) == ${c.db} dB', () {
        expect(floatToDb(c.f), closeTo(c.db, 0.01));
      });

      test('dbToFloat(${c.db}) == ${c.f}', () {
        expect(dbToFloat(c.db), closeTo(c.f, 0.001));
      });
    }

    test('floatToDb ↔ dbToFloat round-trips at 0.3', () {
      const f = 0.3;
      expect(dbToFloat(floatToDb(f)), closeTo(f, 0.001));
    });
  });
}
