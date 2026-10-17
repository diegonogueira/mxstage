// Headless tests for AutoMixEngine — compensation-model acceptance criteria.
//
// Model: send(ch) = C + target(instrument) + boost − meter(ch), so a louder
// input is ducked back to its target monitor level. C is a slow reference that
// tracks the loudest channel, so the whole mix rides the band's energy while a
// single-channel surge is tamed.
import 'package:test/test.dart';
import 'package:mxwise/engine/auto_mix_engine.dart';
import 'package:mxwise/osc/osc_codec.dart';
import 'package:mxwise/state/instrument_type.dart';
import 'package:mxwise/state/genre_presets.dart';

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
      // Tolerance reflects the 2 dB deadband: the send settles within a deadband
      // of the ideal −6 (it can stop one slew step short by design).
      expect(sendDb, closeTo(-6.0, 2.5),
          reason: 'send must drop ~6 dB to cancel the +6 dB input');
      final monitorDb = -14.0 + sendDb;
      expect(monitorDb, closeTo(-20.0, 2.5),
          reason: 'monitor level should stay on target (within the deadband)');
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

    test('in-ear headroom: a source that drops far is boosted back toward target',
        () {
      // Fones (no feedback path): the default config has a +10 dB ceiling and a
      // generous boost, so a vocal that drops 20 dB is pushed back to its target
      // instead of staying "nitidamente baixa". The old 0 dB ceiling / 12 dB cap
      // could only recover half of this.
      final engine = AutoMixEngine(); // default fones tuning
      engine.activate({1: 0.5}); // lead vocal, baseline -10 dB
      final instrs = _instruments({1: InstrumentType.leadVocal});

      // Seed balanced at -10 → monitor -20 (send -10). Then the singer drops
      // 20 dB to -30; the engine must boost the send well past unity. Recovery is
      // deliberately slow now (maxBoostStepDb), so give it enough ticks to settle.
      engine.update(_meters(active: {1: -10.0}), instrs, preset);

      double sendFloat = 0.5;
      for (var i = 0; i < 40; i++) {
        final cmds = engine.update(_meters(active: {1: -30.0}), instrs, preset);
        final c = cmds.where((c) => c.ch == 1).firstOrNull;
        if (c != null) sendFloat = c.levelFloat;
      }

      final sendDb = floatToDb(sendFloat);
      expect(sendDb, greaterThan(2.0),
          reason: 'send must climb past the old 0 dB ceiling (in-ear headroom)');
      final monitorDb = -30.0 + sendDb;
      expect(monitorDb, closeTo(-20.0, 2.0),
          reason: 'the dropped vocal is brought back to its seeded target');
    });
  });

  group('keep the star on top', () {
    test('vocal capped at the ceiling → the band ducks to stay under it', () {
      // The user's screenshot case: the singer drops so far that even the +10 dB
      // ceiling can't lift the vocal to target. Boosting everyone else to *their*
      // targets would bury the vocal — instead the whole band ducks so the vocal
      // stays on top and the style balance holds.
      final engine = AutoMixEngine(); // default fones tuning
      final gTarget = preset.targetFor(InstrumentType.guitar); // gospel: -9 dB
      // Balanced start: vocal -10 / guitar -19 (gTarget below), sends -10 dB.
      engine.activate({1: dbToFloat(-10.0), 5: dbToFloat(-10.0)});
      final instrs =
          _instruments({1: InstrumentType.leadVocal, 5: InstrumentType.guitar});
      engine.update(
          _meters(active: {1: -10.0, 5: -10.0 + gTarget}), instrs, preset);

      // Singer collapses to -35 (needs > +10 dB send → caps); guitar cranks up.
      double vSend = dbToFloat(-10.0), gSend = dbToFloat(-10.0);
      for (var i = 0; i < 100; i++) {
        final cmds =
            engine.update(_meters(active: {1: -35.0, 5: 0.0}), instrs, preset);
        for (final c in cmds) {
          if (c.ch == 1) vSend = c.levelFloat;
          if (c.ch == 5) gSend = c.levelFloat;
        }
      }

      final vMon = -35.0 + floatToDb(vSend);
      final gMon = 0.0 + floatToDb(gSend);
      // Within a deadband of the +10 ceiling — the slow boost settles just under it.
      expect(floatToDb(vSend), closeTo(10.0, 2.5),
          reason: 'the starved vocal rides near the +10 dB ceiling');
      expect(vMon - gMon, closeTo(-gTarget, 3.0),
          reason: 'the band ducked so the guitar stays ~${-gTarget} dB under the '
              'vocal (style balance kept, vocal not buried)');
    });
  });

  group('robust seed (ignore a non-representative meter picture)', () {
    test('holds instead of seeding on a flat pre-band picture, seeds on spread',
        () {
      // The real-log failure: Auto-Mix was enabled before the band was really
      // playing, so every channel read the same (console/UI default) level. C
      // locked too high and the whole mix starved. The engine must WAIT.
      final engine = AutoMixEngine();
      engine.activate({
        1: dbToFloat(-10.0), 5: dbToFloat(-10.0), 7: dbToFloat(-10.0),
        13: dbToFloat(-10.0), 15: dbToFloat(-10.0),
      });
      final instrs = _instruments({
        1: InstrumentType.leadVocal, 5: InstrumentType.guitar,
        7: InstrumentType.bass, 13: InstrumentType.kick,
        15: InstrumentType.hihat,
      });

      // Pre-band: five active channels, all at the same level (flat) → hold.
      for (var i = 0; i < 4; i++) {
        final cmds = engine.update(
            _meters(active: {1: -6.0, 5: -6.0, 7: -6.0, 13: -6.0, 15: -6.0}),
            instrs, preset);
        expect(cmds, isEmpty, reason: 'flat picture → hold, do not correct');
      }
      expect(engine.refLevelDb, isNull,
          reason: 'C must not lock on a flat pre-band picture');

      // Band comes in with a real spread → now it seeds and balances.
      double vSend = dbToFloat(-10.0), gSend = dbToFloat(-10.0);
      for (var i = 0; i < 60; i++) {
        final cmds = engine.update(
            _meters(active: {1: -25.0, 5: -22.0, 7: -19.0, 13: -30.0, 15: -20.0}),
            instrs, preset);
        for (final c in cmds) {
          if (c.ch == 1) vSend = c.levelFloat;
          if (c.ch == 5) gSend = c.levelFloat;
        }
      }
      expect(engine.refLevelDb, isNotNull, reason: 'real spread → seeds');
      final vMon = -25.0 + floatToDb(vSend);
      final gMon = -22.0 + floatToDb(gSend);
      final gTarget = preset.targetFor(InstrumentType.guitar);
      expect(vMon - gMon, closeTo(-gTarget, 2.5),
          reason: 'seeded on real levels → guitar sits ~$gTarget dB under the '
              'vocal (not starved by a bad early seed)');
    });
  });

  group('volume geral (master) shifts the monitor', () {
    // Reproduce the sim-log scenario: the lead vocal (star) is driven into the
    // +10 send ceiling by a low meter, so the keep-the-star duck is active. In
    // the old code the duck included master and cancelled it (master 10 vs 0 gave
    // identical sends). Fixed engine (no follow) so C stays where seeded.
    AutoMixEngine cappedStarEngine() {
      final engine = AutoMixEngine(params: _frozenRef);
      engine.activate({1: 0.75, 5: 0.75}); // vocal, guitar — baseline 0 dB
      final instrs = _instruments(
          {1: InstrumentType.leadVocal, 5: InstrumentType.guitar});
      // Seed with a hot vocal (C ≈ −8), then the vocal drops to −22 and caps.
      engine.update(_meters(active: {1: -8.0, 5: -20.0}), instrs, preset);
      for (var i = 0; i < 20; i++) {
        engine.update(_meters(active: {1: -22.0, 5: -20.0}), instrs, preset);
      }
      return engine;
    }

    final instrs =
        _instruments({1: InstrumentType.leadVocal, 5: InstrumentType.guitar});
    final capMeters = _meters(active: {1: -22.0, 5: -20.0});

    double settle(AutoMixEngine e, int ch, {int ticks = 20}) {
      double last = 0.0;
      for (var i = 0; i < ticks; i++) {
        final cmds = e.update(capMeters, instrs, preset);
        final c = cmds.where((x) => x.ch == ch).firstOrNull;
        if (c != null) last = floatToDb(c.levelFloat);
      }
      // If no command this run, read the tracked level.
      final f = e.currentSendFloats[ch];
      return f != null ? floatToDb(f) : last;
    }

    test('lowering master lowers the band — the duck no longer cancels it', () {
      final engine = cappedStarEngine();
      final guitarAt0 = settle(engine, 5);

      engine.masterDb = -6.0;
      final guitarAtMinus6 = settle(engine, 5);

      expect(guitarAtMinus6, lessThan(guitarAt0 - 4.0),
          reason: 'master −6 must actually pull the band down (~6 dB), not be '
              'absorbed by the keep-the-star duck');
    });

    test('a master change applies instantly, not slewed in over many ticks', () {
      final engine = cappedStarEngine();
      final guitarAt0 = settle(engine, 5);

      engine.masterDb = -6.0;
      // A single tick: the instant apply must move it most of the way, unlike the
      // 0.75–2 dB/s slew which would move only ~2 dB in one tick.
      final cmds = engine.update(capMeters, instrs, preset);
      final g = cmds.where((c) => c.ch == 5).firstOrNull;
      final guitarAfter1Tick = g != null
          ? floatToDb(g.levelFloat)
          : floatToDb(engine.currentSendFloats[5]!);

      expect(guitarAfter1Tick, lessThan(guitarAt0 - 4.0),
          reason: 'the knob must respond now (instant), not crawl in at the slew');
    });

    test('raising master stops at the star ceiling — it never buries the star', () {
      // Star NOT initially capped: it has ~1 dB of headroom. Cranking master to
      // +12 must lift the band only until the vocal hits the ceiling, then stop —
      // the guitar rises ~1 dB, not +12, so the vocal stays on top.
      final engine = AutoMixEngine(params: _frozenRef);
      engine.activate({1: 0.75, 5: 0.75});
      final meters = _meters(active: {1: -15.0, 5: -15.0});
      for (var i = 0; i < 20; i++) {
        engine.update(meters, instrs, preset);
      }
      final gBefore = floatToDb(engine.currentSendFloats[5]!);

      engine.masterDb = 12.0;
      double vSend = 0, gSend = 0;
      for (var i = 0; i < 20; i++) {
        engine.update(meters, instrs, preset);
      }
      vSend = floatToDb(engine.currentSendFloats[1]!);
      gSend = floatToDb(engine.currentSendFloats[5]!);

      expect(vSend, closeTo(10.0, 1.5),
          reason: 'the vocal rides up to the +10 ceiling');
      expect(gSend, lessThan(gBefore + 2.5),
          reason: 'the guitar only rose ~1 dB (star headroom), not +12 — not buried');
      final vMon = -15.0 + vSend, gMon = -15.0 + gSend;
      final gTarget = preset.targetFor(InstrumentType.guitar); // gospel −9
      expect(vMon - gMon, closeTo(-gTarget, 2.5),
          reason: 'balance preserved: vocal stays ~${-gTarget} dB over the guitar');
    });
  });

  group('seed anchor (ignore near-silent channels)', () {
    test('a few channels sitting on the floor do not drag the seed low', () {
      // The real church log: at activation only five channels cleared the gate,
      // and THREE of them sat just above the −65 silence floor (bleed / a
      // barely-open mic). Their candidates dragged the plain median ~22 dB below
      // the two channels actually carrying the mix, so C locked far too low and
      // the whole monitor was starved (musician forced to max the headphone box).
      // The seed must anchor on the loud channels and ignore the near-floor ones.
      final engine = AutoMixEngine();
      engine.activate({
        1: dbToFloat(-9.0), // lead vocal, really playing
        2: dbToFloat(-9.0), // bass, really playing
        7: dbToFloat(-25.0), 8: dbToFloat(-25.0), 9: dbToFloat(-25.0), // on floor
      });
      final instrs = _instruments({
        1: InstrumentType.leadVocal, 2: InstrumentType.bass,
        7: InstrumentType.overhead, 8: InstrumentType.overhead,
        9: InstrumentType.overhead,
      });

      // Two loud channels (~−37) + three sitting just above the −65 floor.
      engine.update(
          _meters(active: {1: -37.0, 2: -38.0, 7: -60.0, 8: -61.0, 9: -62.0}),
          instrs, preset);

      // Anchored on the real band (~−38/−46), NOT on the −60s that would pull a
      // plain median down toward −68.
      expect(engine.refLevelDb, isNotNull);
      expect(engine.refLevelDb!, greaterThan(-52.0),
          reason: 'seed must not be dragged toward the floor by near-silent '
              'channels (would starve the whole monitor)');
      expect(engine.refLevelDb!, lessThan(-30.0),
          reason: 'seed still reflects the band, not an outlier-high anchor');
    });
  });

  group('reference holds by default', () {
    test('a uniform whole-band rise is ducked back (holds the mix)', () {
      // Default engine now holds the reference fixed (refFollowSeconds → ∞).
      final engine = AutoMixEngine();
      engine.activate({1: 0.5, 2: 0.5}); // baseline -10 dB → room to move
      final instrs =
          _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys});

      // Balanced start (keys 7 dB under the vocal), seeds the fixed reference.
      engine.update(_meters(active: {1: -10.0, 2: -17.0}), instrs, preset);

      // Entire band gets 6 dB louder, uniformly.
      double vocalFloat = 0.5, keysFloat = 0.5;
      for (var i = 0; i < 25; i++) {
        final cmds =
            engine.update(_meters(active: {1: -4.0, 2: -11.0}), instrs, preset);
        for (final c in cmds) {
          if (c.ch == 1) vocalFloat = c.levelFloat;
          if (c.ch == 2) keysFloat = c.levelFloat;
        }
      }

      // Held reference → both ducked ~6 dB to keep the monitor on target
      // (the mix is held, not ridden up with the band).
      expect(floatToDb(vocalFloat), lessThan(floatToDb(0.5) - 3.0),
          reason: 'vocal must duck as the band rose (mix held)');
      expect(floatToDb(keysFloat), lessThan(floatToDb(0.5) - 3.0),
          reason: 'keys must duck too');
    });
  });

  group('reference rides the band (opt-in)', () {
    test('a uniform whole-band rise returns sends to baseline (monitor rides up)',
        () {
      // Opt-in: a finite time constant makes the reference ride the band.
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
      // the monitor followed the band up instead of ducking anyone. Tolerance
      // covers the 2 dB deadband.
      expect(floatToDb(vocalFloat), closeTo(0.0, 2.5));
      expect(floatToDb(keysFloat), closeTo(0.0, 2.5));
    });
  });

  group('adaptive gate (scale-independent)', () {
    test('a quiet console still corrects a channel a fixed −45 gate would freeze',
        () {
      // Real church meters sit far below −45 dB. The old fixed gate froze the
      // whole band; the relative gate must still engage a channel at −47.
      final engine = AutoMixEngine(); // reference held by default
      engine.activate({1: 0.5}); // keys, baseline −10 dB
      final instrs = _instruments({1: InstrumentType.keys});

      // Seed at −55 (well under the old −45 gate) → balanced, no jump.
      final seed = engine.update(_meters(active: {1: -55.0}), instrs, preset);
      expect(seed, isEmpty, reason: 'seed on a quiet channel must not jump');

      // Keys get 8 dB louder → −47, still under −45. A fixed gate would freeze
      // this; the adaptive gate keeps it in the window and ducks it.
      double keysFloat = 0.5;
      var gotCmd = false;
      for (var i = 0; i < 8; i++) {
        final cmds = engine.update(_meters(active: {1: -47.0}), instrs, preset);
        final k = cmds.where((c) => c.ch == 1).firstOrNull;
        if (k != null) {
          keysFloat = k.levelFloat;
          gotCmd = true;
        }
      }
      expect(gotCmd, isTrue,
          reason: 'a −47 dB channel must be corrected, not frozen');
      expect(keysFloat, lessThan(0.5),
          reason: 'the louder input must duck the send');
    });

    test('a channel far below the loudest stays frozen (relative window)', () {
      // Hot console: loudest −6 → window floor −46. A −55 dB channel is >40 dB
      // down, so it reads as bleed/noise and is never opened, even though its
      // level is nowhere near the target.
      final engine = AutoMixEngine();
      engine.activate({1: 0.75, 2: 0.5});
      final instrs = _instruments(
          {1: InstrumentType.leadVocal, 2: InstrumentType.backingVocal});

      var touched = false;
      for (var i = 0; i < 10; i++) {
        final cmds =
            engine.update(_meters(active: {1: -6.0, 2: -55.0}), instrs, preset);
        if (cmds.any((c) => c.ch == 2)) touched = true;
      }
      expect(touched, isFalse,
          reason: 'a channel 49 dB under the loudest must stay frozen');
    });

    test('a channel parked off (baseline send at 0) is left off, never opened',
        () {
      // Regression: with the adaptive gate opening more channels, a channel
      // whose baseline send is 0.0 (fader off → −90 dB) now clears the gate.
      // It must be skipped, not crash (ceiling < floor) or get un-muted.
      final engine = AutoMixEngine();
      engine.activate({1: 0.75, 2: 0.0}); // ch2 parked fully off
      final instrs =
          _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys});

      List<SendCommand> cmds = const [];
      for (var i = 0; i < 10; i++) {
        cmds = engine.update(_meters(active: {1: -30.0, 2: -48.0}), instrs, preset);
      }
      expect(cmds.any((c) => c.ch == 2), isFalse,
          reason: 'a channel the musician turned off must stay off');
    });

    test('whole band under the silence floor → no commands', () {
      final engine = AutoMixEngine();
      engine.activate({1: 0.75, 2: 0.75});
      final cmds = engine.update(
          _meters(active: {1: -70.0, 2: -75.0}),
          _instruments({1: InstrumentType.leadVocal, 2: InstrumentType.keys}),
          preset);
      expect(cmds, isEmpty,
          reason: 'everything under the −65 floor is noise — nothing opens');
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
