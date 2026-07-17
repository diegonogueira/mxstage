// Pure Dart — zero Flutter, zero I/O. Testável headless.
import 'dart:math';
import '../osc/osc_codec.dart';
import '../state/instrument_type.dart';
import '../state/genre_presets.dart';

/// A send correction the engine wants applied to the mixer.
class SendCommand {
  final int ch; // 1-based channel number
  final double levelFloat; // 0..1 X32 fader value

  const SendCommand({required this.ch, required this.levelFloat});
}

/// Parameters controlling the correction loop.
class EngineParams {
  /// A channel counts as *silent* (send frozen, never opened) when its level is
  /// at or below this absolute floor (dB). Set well under any realistic gain
  /// staging so a conservatively-metered console still counts as "playing" —
  /// only the true noise / −∞ floor is excluded. Replaces the old fixed −45 dB
  /// gate, which assumed hot meters and starved the engine on quieter consoles
  /// (a real church session peaked at ~−30 dB, so almost nothing crossed −45).
  final double silenceFloorDb;

  /// A channel only participates in the mix if it is within this many dB of the
  /// loudest channel this tick. This makes the working window **relative** to
  /// whatever level the console actually produces, so the engine self-calibrates
  /// across gain-staging setups instead of trusting one absolute threshold. The
  /// effective per-channel gate each tick is
  /// `max(loudest − activeRangeDb, silenceFloorDb)`. Think of it as a
  /// "sensibilidade": larger = more channels ride along.
  final double activeRangeDb;

  /// Ignore send errors smaller than this (dB) — preserves musical dynamics.
  final double deadbandDb;

  /// Max send change per correction tick (dB) — slew limiter.
  final double maxStepDb;

  /// Max send increase above a channel's baseline (dB). Ducking is unbounded
  /// (always safe); *boosting* a quiet channel is capped. On in-ear / headphone
  /// monitoring (fones) there is no acoustic path back to the mics, so this is
  /// generous (24) — a source that drops a lot is brought most of the way back
  /// to its style target ("jogar no talo"). The remaining guard against
  /// amplifying hiss / mic bleed on a *near-silent* input is [boostRampDb], not
  /// this hard cap. For stage wedges / PA (feedback path present) drop this back
  /// to ~9–12 and the ceiling to 0.
  final double maxBoostDb;

  /// Adaptive-boost guard (dB above [silenceFloorDb]). The boost allowance
  /// ramps from 0 (channel sitting on the noise floor) up to the full
  /// [maxBoostDb] once the channel is this many dB above the floor. A
  /// clearly-playing source is pushed all the way to target while a near-silent
  /// one is held back — we never crank a channel's hiss / bleed into the ears
  /// just because it went quiet.
  final double boostRampDb;

  /// Absolute send floor / ceiling (dB), applied after per-channel bounds. The
  /// ceiling is +10 (the X32 send maximum) for in-ear monitoring — no feedback
  /// path, so pushing to the style target is safe. Lower it toward 0 (unity)
  /// before ever driving a stage wedge / PA.
  final double sendFloorDb;
  final double sendCeilingDb;

  /// Max downward shift of the whole mix (dB) to keep the loudest-target channel
  /// (normally the lead vocal) on top. When that channel's input drops so far
  /// that even the send ceiling can't boost it to target, boosting the *others*
  /// to their targets would bury it — so instead the reference ducks by the
  /// shortfall and the whole band comes down together, preserving the style
  /// balance ("cortar o resto quando não dá pra subir a estrela"). Bounded so one
  /// near-silent source can't nuke the mix — past this the star just sits capped.
  final double maxDuckDb;

  /// Robust-seed guard. The instant Auto-Mix is enabled the meters may not yet
  /// represent the playing band — a console/UI default level before the music
  /// really comes in shows up as an implausibly *uniform* picture (every channel
  /// at nearly the same level). Locking the reference C there seeds a bad balance
  /// that starves the whole mix (everyone wants huge boost, caps, "some"). So the
  /// seed is **deferred** while at least [seedMinChannels] channels are active but
  /// their spread (loudest − quietest active) is under [seedMinSpreadDb] — no real
  /// band is that flat. Give up and seed anyway after [seedMaxWarmupTicks] ticks
  /// so it never stalls. Fewer than [seedMinChannels] active ⇒ seed immediately
  /// (a solo/duo has no meaningful spread to judge).
  final int seedMinChannels;
  final double seedMinSpreadDb;
  final int seedMaxWarmupTicks;

  /// Time constant (seconds) for the reference level C to follow the loudest
  /// channel. The default is effectively infinite → C stays **fixed** (holds
  /// the balance the musician set; a uniform whole-band rise is ducked, not
  /// ridden). A finite value makes C slowly ride the band's overall energy
  /// instead, ignoring momentary single-channel spikes (those still get ducked).
  final double refFollowSeconds;

  /// Correction tick interval (ms). Must match the caller's timer
  /// (kCorrectionIntervalMs). Used to derive the reference-follow smoothing.
  final int tickMs;

  const EngineParams({
    this.silenceFloorDb = -65.0,
    this.activeRangeDb = 40.0,
    this.deadbandDb = 1.0,
    this.maxStepDb = 4.0,
    this.maxBoostDb = 24.0,
    this.boostRampDb = 25.0,
    this.sendFloorDb = -60.0,
    this.sendCeilingDb = 10.0,
    this.maxDuckDb = 12.0,
    this.seedMinChannels = 3,
    this.seedMinSpreadDb = 5.0,
    this.seedMaxWarmupTicks = 15,
    this.refFollowSeconds = 1e12, // hold the reference fixed by default
    this.tickMs = 1000,
  });

  /// EMA alpha for the reference-follow envelope at [tickMs] cadence.
  double get refAlpha {
    if (refFollowSeconds <= 0) return 1.0;
    return 1 - exp(-tickMs / (refFollowSeconds * 1000));
  }
}

/// Auto-Mix engine — pure Dart, no UI, no I/O.
///
/// Model: hold a *balanced monitor* where every instrument sits at its preset
/// target relative to the lead vocal, so nothing drowns out anything else. The
/// send for each channel is computed as compensation:
///
///     send(ch) = C + master + target(instrument) + boost − meter(ch)
///
/// so when a musician plays louder (meter up) the send comes down by the same
/// amount, and when they play quieter it comes up (bounded by [maxBoostDb]) —
/// keeping every instrument at its target monitor level. `C` is the band's base
/// level, seeded at activation to preserve the current balance and then held
/// fixed: a stable personal-monitor reference. [masterDb] is the musician's
/// overall "volume geral" (shifts the whole monitor without touching the
/// balance). Set [EngineParams.refFollowSeconds] finite to instead let `C` ride
/// the band's own energy.
///
/// Call [activate] when the user turns on Auto-Mix to snapshot starting sends.
/// Call [update] on each slow-meter tick to get the list of sends to apply.
/// Call [deactivate] to stop corrections.
class AutoMixEngine {
  final EngineParams params;

  AutoMixEngine({this.params = const EngineParams()});

  bool _active = false;
  bool get isActive => _active;

  // Send level (dB) at activation time — baseline for the boost ceiling and
  // for restoring on deactivate.
  final Map<int, double> _refSendDb = {}; // ch (1-based) → dB

  // Current send levels tracked by the engine (dB).
  final Map<int, double> _currentSendDb = {};

  // Slow reference level C (dB). Null until seeded (deferred past a flat/pre-band
  // meter picture — see [_seedIsRepresentative]).
  double? _refLevelDb;

  // Ticks spent waiting for a representative meter picture before seeding C.
  int _seedWarmupTicks = 0;

  /// Referência lenta C (dB) do último tick, ou null antes do primeiro tick
  /// ativo. Só para diagnóstico/log — não afeta a correção.
  double? get refLevelDb => _refLevelDb;

  // Per-channel user boost (dB), applied on top of preset target.
  Map<int, double> boostDb = {};

  // Overall master level (dB) — the musician's "volume geral". Shifts the whole
  // monitor up/down without changing the balance between channels. 0 = the
  // level seeded at activation.
  double masterDb = 0.0;

  /// Activate with the current send levels as the baseline.
  /// [currentSendFloats]: map of ch (1-based) → current fader float (0..1).
  void activate(Map<int, double> currentSendFloats) {
    _refSendDb.clear();
    _currentSendDb.clear();
    _refLevelDb = null; // re-seed on the next representative tick
    _seedWarmupTicks = 0;
    for (final entry in currentSendFloats.entries) {
      final db = floatToDb(entry.value);
      _refSendDb[entry.key] = db;
      _currentSendDb[entry.key] = db;
    }
    _active = true;
  }

  void deactivate() {
    _active = false;
  }

  /// Current send levels tracked by the engine (ch → float 0..1).
  /// Used by MixerClient to enforce engine state over manual fader changes.
  Map<int, double> get currentSendFloats {
    if (!_active) return {};
    return {
      for (final entry in _currentSendDb.entries)
        entry.key: dbToFloat(entry.value).clamp(0.0, 1.0),
    };
  }

  /// Compute corrections for one tick.
  ///
  /// [meterDb]     — slow-smoothed dB per channel, index 0 = ch1 (32 values).
  /// [instruments] — instrument type per channel, index 0 = ch1.
  /// [preset]      — genre preset defining the target relative balance.
  ///
  /// Returns the list of sends to write. Empty if engine is inactive or every
  /// channel is silent (silence never opens a send).
  List<SendCommand> update(
    List<double> meterDb,
    List<InstrumentType> instruments,
    GenrePreset preset,
  ) {
    if (!_active) return const [];

    final n = min(meterDb.length, 32);

    // Loudest channel above the absolute silence floor — "o maior volume de
    // toda a mixagem". Anything at/under the floor is noise / not playing.
    double? loudest;
    for (var i = 0; i < n; i++) {
      if (meterDb[i] > params.silenceFloorDb) {
        loudest = (loudest == null) ? meterDb[i] : max(loudest, meterDb[i]);
      }
    }
    if (loudest == null) return const []; // whole band silent — nothing opens

    // Effective gate is *relative* to the loudest channel (so the engine adapts
    // to the console's gain staging) but never dips below the absolute floor.
    final effectiveGate = max(loudest - params.activeRangeDb, params.silenceFloorDb);

    // Seed the reference once the meter picture is representative (preserves
    // overall loudness so enabling Auto-Mix snaps to balance without a jump);
    // thereafter follow the loudest channel slowly. Deferring the seed past a
    // flat/pre-band picture avoids locking a bad C that starves the whole mix.
    if (_refLevelDb == null && !_seedIsRepresentative(meterDb, n, effectiveGate)) {
      return const []; // warming up — hold, don't seed on non-band levels yet
    }
    final ref = _refLevelDb == null
        ? (_refLevelDb = _seedReference(meterDb, instruments, preset, n, effectiveGate))
        : (_refLevelDb = _refLevelDb! + params.refAlpha * (loudest - _refLevelDb!));

    // Keep the star on top. The channel with the highest target (normally the
    // lead vocal) is meant to sit at the top of the mix. If its input drops so
    // far that even the +[sendCeilingDb] send can't lift it to target, boosting
    // the others to *their* targets would bury it. Instead, duck the whole
    // reference by that shortfall so the band comes down together and the balance
    // (star on top) is preserved. Only a clearly-playing channel may anchor — we
    // won't duck the band to chase a near-silent input — and the shift is bounded
    // by [maxDuckDb]. `_refLevelDb` keeps the un-ducked C (seed/log continuity).
    var duck = 0.0;
    var anchorTargetRel = -1e9;
    for (var i = 0; i < n; i++) {
      final meter = meterDb[i];
      if (meter <= effectiveGate) continue;
      if (meter - params.silenceFloorDb < params.boostRampDb) continue;
      final instrument =
          i < instruments.length ? instruments[i] : InstrumentType.unknown;
      final targetRel = preset.targetFor(instrument) + (boostDb[i + 1] ?? 0.0);
      final desired = ref + masterDb + targetRel - meter;
      final deficit =
          (desired - params.sendCeilingDb).clamp(0.0, params.maxDuckDb).toDouble();
      if (targetRel > anchorTargetRel) {
        anchorTargetRel = targetRel;
        duck = deficit;
      } else if (targetRel == anchorTargetRel && deficit > duck) {
        duck = deficit;
      }
    }
    final effectiveRef = ref - duck;

    final commands = <SendCommand>[];

    for (var i = 0; i < n; i++) {
      final ch = i + 1;
      final meter = meterDb[i];

      // Gate: channel is silent / below the relative window — freeze, no fix.
      if (meter <= effectiveGate) continue;

      final instrument =
          i < instruments.length ? instruments[i] : InstrumentType.unknown;
      final targetRel = preset.targetFor(instrument) + (boostDb[ch] ?? 0.0);

      // Compensation: send needed so this channel sits at its target monitor
      // level. Louder meter → lower send; quieter meter → higher send.
      // [effectiveRef] folds in the keep-the-star-on-top duck.
      var sendTarget = effectiveRef + masterDb + targetRel - meter;

      // Safety bounds: duck freely; boost is bounded per channel and absolutely.
      final baseline = _refSendDb[ch] ?? _currentSendDb[ch] ?? params.sendFloorDb;
      // Adaptive boost allowance: full [maxBoostDb] once the channel sits well
      // above the noise floor, tapering to 0 near it — a source that's genuinely
      // playing is pushed to its target, but a near-silent one isn't amplified
      // into hiss / bleed (the only boost hazard left once there's no feedback
      // path on in-ear monitoring).
      final aboveFloor = meter - params.silenceFloorDb;
      final boostFrac = (aboveFloor / params.boostRampDb).clamp(0.0, 1.0);
      final ceiling =
          min(params.sendCeilingDb, baseline + params.maxBoostDb * boostFrac);

      // A channel parked below the usable floor (its send fader is effectively
      // off) has no valid range to write into — leave it off. Auto-Mix holds the
      // balance of what's already in the monitor; it never un-mutes a channel
      // the musician pulled down. (Also guards clamp() against ceiling < floor.)
      if (ceiling < params.sendFloorDb) continue;

      sendTarget = sendTarget.clamp(params.sendFloorDb, ceiling);

      final current = _currentSendDb[ch] ?? baseline;
      final err = sendTarget - current;

      // Deadband: small errors preserve musical dynamics and avoid churn.
      if (err.abs() < params.deadbandDb) continue;

      // Slew-limited step toward the target.
      final step = err.clamp(-params.maxStepDb, params.maxStepDb);
      final newDb = current + step;
      _currentSendDb[ch] = newDb;

      commands.add(SendCommand(ch: ch, levelFloat: dbToFloat(newDb).clamp(0.0, 1.0)));
    }

    return commands;
  }

  /// True once the meter picture looks like a real playing band, so it's safe to
  /// seed C. A still-settling or pre-band console default shows up as an
  /// implausibly flat picture — many active channels at nearly the same level —
  /// which would seed a bad reference and starve the mix. Fewer than
  /// [EngineParams.seedMinChannels] active channels ⇒ representative (a solo/duo
  /// has no meaningful spread). Gives up and seeds anyway after
  /// [EngineParams.seedMaxWarmupTicks] so it never stalls.
  bool _seedIsRepresentative(List<double> meterDb, int n, double gate) {
    _seedWarmupTicks++;
    if (_seedWarmupTicks >= params.seedMaxWarmupTicks) return true;
    var lo = double.infinity, hi = double.negativeInfinity, count = 0;
    for (var i = 0; i < n; i++) {
      if (meterDb[i] > gate) {
        count++;
        lo = min(lo, meterDb[i]);
        hi = max(hi, meterDb[i]);
      }
    }
    if (count < params.seedMinChannels) return true;
    return (hi - lo) >= params.seedMinSpreadDb;
  }

  /// Choose the reference level C so the *current* sends are preserved as
  /// closely as possible at activation — each active channel implies
  /// `C_i = meter_i + baseline_i − target_i`; we take the median for robustness.
  /// This makes enabling Auto-Mix a gentle "snap to balance" rather than a jump.
  double _seedReference(
    List<double> meterDb,
    List<InstrumentType> instruments,
    GenrePreset preset,
    int n,
    double effectiveGate,
  ) {
    final candidates = <double>[];
    for (var i = 0; i < n; i++) {
      final meter = meterDb[i];
      if (meter <= effectiveGate) continue;
      final ch = i + 1;
      final baseline = _refSendDb[ch] ?? 0.0;
      // A channel parked off carries no balance information — leaving it in
      // would drag C toward a −90 dB outlier and skew everyone's target.
      if (baseline <= params.sendFloorDb) continue;
      final instrument =
          i < instruments.length ? instruments[i] : InstrumentType.unknown;
      final targetRel = preset.targetFor(instrument) + (boostDb[ch] ?? 0.0);
      candidates.add(meter + baseline - targetRel);
    }
    if (candidates.isEmpty) return meterDb.isEmpty ? 0.0 : meterDb[0];
    candidates.sort();
    return candidates[candidates.length ~/ 2]; // median
  }
}
