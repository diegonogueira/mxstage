// Headless tests for AutoMixEngine — M3 acceptance criteria.
import 'package:test/test.dart';
import 'package:mxstage/engine/auto_mix_engine.dart';
import 'package:mxstage/osc/osc_codec.dart';
import 'package:mxstage/state/instrument_type.dart';
import 'package:mxstage/state/genre_presets.dart';

// 32 channels, all silent by default.
List<double> _meters({Map<int, double> active = const {}}) {
  return List.generate(32, (i) => active[i + 1] ?? -90.0);
}

List<InstrumentType> _instruments(Map<int, InstrumentType> map) {
  return List.generate(32, (i) => map[i + 1] ?? InstrumentType.unknown);
}

Map<int, double> _sendFloats(Map<int, double> map) => map;

void main() {
  final preset = kGenrePresets[Genre.gospel]!;

  group('gate', () {
    test('silent channel does not receive a correction', () {
      final engine = AutoMixEngine();
      engine.activate(_sendFloats({1: 0.75, 2: 0.75}));

      // ch1 = vocal active, ch2 = silent
      final meters = _meters(active: {1: -10.0}); // ch2 below gate
      final instrs = _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys});

      final cmds = engine.update(meters, instrs, preset);
      expect(cmds.any((c) => c.ch == 2), isFalse, reason: 'silent channel must be frozen');
    });
  });

  group('keyboard surge', () {
    test('keyboard louder than target receives a downward correction', () {
      final engine = AutoMixEngine();
      // Both channels start at 0 dB send (float 0.75)
      engine.activate({1: 0.75, 2: 0.75});

      // Gospel: vocal=0 dB anchor, keys target=-7 dB.
      // Simulate keys surging to same level as vocal → relative = 0 dB, target = -7 dB.
      // Deviation = 0 - (-7) = +7 → engine should push send DOWN.
      final meters = _meters(active: {1: -10.0, 2: -10.0}); // both at same level
      final instrs = _instruments({
        1: InstrumentType.leadVocal,
        2: InstrumentType.keys,
      });

      final cmds = engine.update(meters, instrs, preset);
      final keysCmd = cmds.firstWhere((c) => c.ch == 2, orElse: () => throw StateError('no cmd'));
      // Keys send should have decreased
      expect(keysCmd.levelFloat, lessThan(0.75));
    });
  });

  group('vocal rest — no gain opened', () {
    test('all channels below gate → no commands', () {
      final engine = AutoMixEngine();
      engine.activate({1: 0.75});

      // Everything silent
      final cmds = engine.update(_meters(), _instruments({}), preset);
      expect(cmds, isEmpty);
    });
  });

  group('clamp', () {
    test('correction never exceeds ±clampDb from starting send', () {
      const params = EngineParams(clampDb: 6.0, maxStepDb: 3.0, deadbandDb: 0.0);
      final engine = AutoMixEngine(params: params);
      final startFloat = 0.75; // 0 dB
      final startDb = floatToDb(startFloat);
      engine.activate({1: startFloat, 2: startFloat});

      final meters = _meters(active: {1: -10.0, 2: -10.0});
      final instrs = _instruments({
        1: InstrumentType.leadVocal,
        2: InstrumentType.keys, // target -7 dB → big deviation
      });

      // Run 20 cycles — the clamp should stop the correction
      double lastFloat = startFloat;
      for (var i = 0; i < 20; i++) {
        final cmds = engine.update(meters, instrs, preset);
        final cmd = cmds.where((c) => c.ch == 2).firstOrNull;
        if (cmd != null) lastFloat = cmd.levelFloat;
      }

      final lastDb = floatToDb(lastFloat);
      expect(lastDb, greaterThanOrEqualTo(startDb - params.clampDb - 0.1));
      expect(lastDb, lessThanOrEqualTo(startDb + params.clampDb + 0.1));
    });
  });

  group('deadband', () {
    test('small deviations within deadband produce no commands', () {
      const params = EngineParams(deadbandDb: 2.0, gateDb: -45.0);
      final engine = AutoMixEngine(params: params);
      engine.activate({1: 0.75, 2: 0.75});

      // Gospel keys target = -7 dB. Put keys at -6.5 dB relative → deviation = 0.5 < deadband.
      // anchor = vocal at -10 dB. keys = -10 - 6.5 = -16.5 dB absolute.
      final meters = _meters(active: {1: -10.0, 2: -16.5});
      final instrs = _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys});

      final cmds = engine.update(meters, instrs, preset);
      expect(cmds.any((c) => c.ch == 2), isFalse, reason: 'deviation within deadband');
    });
  });

  group('ChannelMapper', () {
    // Tested via integration with engine — mapper tests in separate file if needed.
  });
}
