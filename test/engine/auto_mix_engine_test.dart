// Headless tests for AutoMixEngine — compensation-model acceptance criteria.
//
// Model: send(ch) = C + target(instrument) + boost − meter(ch), so a louder
// input is ducked back to its target monitor level. C is a slow reference that
// tracks the loudest channel, so the whole mix rides the band's energy while a
// single-channel surge is tamed.
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

// A "frozen reference" so pure compensation can be asserted without the slow
// reference-follow drifting the result mid-test.
const _frozenRef = EngineParams(refFollowSeconds: 1e12);

void main() {
  final preset = kGenrePresets[Genre.gospel]!;

  group('gate', () {
    test('silent channel does not receive a correction', () {
      final engine = AutoMixEngine();
      engine.activate({1: 0.75, 2: 0.75});

      // ch1 = vocal active, ch2 = silent (below gate).
      final meters = _meters(active: {1: -10.0});
      final instrs =
          _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys});

      final cmds = engine.update(meters, instrs, preset);
      expect(cmds.any((c) => c.ch == 2), isFalse,
          reason: 'silent channel must be frozen');
    });

    test('all channels below gate → no commands (silence never opens a send)',
        () {
      final engine = AutoMixEngine();
      engine.activate({1: 0.75});
      final cmds = engine.update(_meters(), _instruments({}), preset);
      expect(cmds, isEmpty);
    });
  });

  group('keyboard surge', () {
    test('a channel that surges above its target is ducked back down', () {
      final engine = AutoMixEngine();
      engine.activate({1: 0.75, 2: 0.75});

      // Balanced start: vocal at -10 (send 0 dB → monitor -10); keys 7 dB below
      // at -17 (send 0 dB → monitor -17). Gospel keys target = -7 dB.
      final instrs =
          _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys});
      final balanced = _meters(active: {1: -10.0, 2: -17.0});

      // First tick seeds the reference; balanced input → no correction.
      final seedCmds = engine.update(balanced, instrs, preset);
      expect(seedCmds.where((c) => c.ch == 2), isEmpty,
          reason: 'already balanced → no jump on enable');

      // Keyboardist surges to the vocal's level (7 dB too loud for keys).
      final surged = _meters(active: {1: -10.0, 2: -10.0});
      double keysFloat = 0.75;
      for (var i = 0; i < 8; i++) {
        final cmds = engine.update(surged, instrs, preset);
        final k = cmds.where((c) => c.ch == 2).firstOrNull;
        if (k != null) keysFloat = k.levelFloat;
      }

      expect(keysFloat, lessThan(0.7),
          reason: 'keys send must duck (~-7 dB) as the input surged');
    });
  });

  group('compensation is ~1:1 in dB', () {
    test('input rising by 6 dB drops the send by ~6 dB (monitor held)', () {
      final engine = AutoMixEngine(params: _frozenRef);
      engine.activate({1: 0.75}); // vocal, baseline 0 dB
      final instrs = _instruments({1: InstrumentType.leadVocal});

      // Seed at -20; monitor = -20 + 0 = -20.
      engine.update(_meters(active: {1: -20.0}), instrs, preset);

      // Input rises 6 dB → -14.
      double sendFloat = 0.75;
      for (var i = 0; i < 12; i++) {
        final cmds = engine.update(_meters(active: {1: -14.0}), instrs, preset);
        final c = cmds.where((c) => c.ch == 1).firstOrNull;
        if (c != null) sendFloat = c.levelFloat;
      }

      final sendDb = floatToDb(sendFloat);
      expect(sendDb, closeTo(-6.0, 1.0),
          reason: 'send must drop ~6 dB to cancel the +6 dB input');
      final monitorDb = -14.0 + sendDb;
      expect(monitorDb, closeTo(-20.0, 1.5),
          reason: 'monitor level should stay on target');
    });
  });

  group('boost cap', () {
    test('a near-silent channel is boosted only up to baseline + maxBoostDb', () {
      const params = EngineParams(refFollowSeconds: 1e12, maxBoostDb: 9.0);
      final engine = AutoMixEngine(params: params);
      // ch1 loud vocal (baseline 0 dB); ch2 quiet backing vocal, baseline
      // 0.5 float = -10 dB.
      engine.activate({1: 0.75, 2: 0.5});
      final instrs = _instruments(
          {1: InstrumentType.leadVocal, 2: InstrumentType.backingVocal});

      // ch2 plays very quietly (just above the gate) → wants a large boost.
      double ch2Float = 0.5;
      for (var i = 0; i < 25; i++) {
        final cmds =
            engine.update(_meters(active: {1: -6.0, 2: -40.0}), instrs, preset);
        final c = cmds.where((c) => c.ch == 2).firstOrNull;
        if (c != null) ch2Float = c.levelFloat;
      }

      final ch2Db = floatToDb(ch2Float);
      // baseline (-10) + maxBoost (9) = -1 dB ceiling.
      expect(ch2Db, lessThanOrEqualTo(-1.0 + 0.3),
          reason: 'boost must be capped at baseline + maxBoostDb');
      expect(ch2Db, greaterThan(-9.0),
          reason: 'it should have boosted up from the -10 dB baseline');
    });
  });

  group('reference follows the band', () {
    test('a uniform whole-band rise returns sends to baseline (monitor rides up)',
        () {
      // Fast reference so it converges within the test horizon.
      const params = EngineParams(refFollowSeconds: 1.0);
      final engine = AutoMixEngine(params: params);
      engine.activate({1: 0.75, 2: 0.75});
      final instrs =
          _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys});

      // Balanced start.
      engine.update(_meters(active: {1: -10.0, 2: -17.0}), instrs, preset);

      // Entire band gets 6 dB louder, uniformly.
      double vocalFloat = 0.75, keysFloat = 0.75;
      for (var i = 0; i < 25; i++) {
        final cmds = engine.update(
            _meters(active: {1: -4.0, 2: -11.0}), instrs, preset);
        for (final c in cmds) {
          if (c.ch == 1) vocalFloat = c.levelFloat;
          if (c.ch == 2) keysFloat = c.levelFloat;
        }
      }

      // Balance unchanged → sends settle back near their baseline (0 dB / 0.75):
      // the monitor followed the band up instead of ducking anyone.
      expect(floatToDb(vocalFloat), closeTo(0.0, 1.5));
      expect(floatToDb(keysFloat), closeTo(0.0, 1.5));
    });
  });

  group('deadband', () {
    test('an already-balanced channel produces no command', () {
      final engine = AutoMixEngine();
      engine.activate({1: 0.75});
      // Single vocal: seed makes send target == baseline → within deadband.
      final cmds = engine.update(
          _meters(active: {1: -10.0}), _instruments({1: InstrumentType.leadVocal}),
          preset);
      expect(cmds.where((c) => c.ch == 1), isEmpty);
    });
  });
}
