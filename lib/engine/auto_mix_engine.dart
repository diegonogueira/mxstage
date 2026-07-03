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
  final double gateDb; // channels below this are frozen
  final double deadbandDb; // ignore deviations smaller than this
  final double correctionGain; // how aggressively to chase the target
  final double maxStepDb; // max dB change per cycle
  final double clampDb; // max deviation from starting send level

  const EngineParams({
    this.gateDb = -45.0,
    this.deadbandDb = 2.0,
    this.correctionGain = 0.25,
    this.maxStepDb = 1.0,
    this.clampDb = 3.0,
  });
}

/// Auto-Mix engine — pure Dart, no UI, no I/O.
///
/// Call [activate] when the user turns on Auto-Mix to snapshot starting sends.
/// Call [update] on each slow-meter tick to get the list of sends to apply.
/// Call [deactivate] to stop corrections.
class AutoMixEngine {
  final EngineParams params;

  AutoMixEngine({this.params = const EngineParams()});

  bool _active = false;
  bool get isActive => _active;

  // Send level (dB) at activation time — used as clamp center.
  final Map<int, double> _refSendDb = {}; // ch (1-based) → dB

  // Current send levels tracked by the engine (dB).
  final Map<int, double> _currentSendDb = {};

  // Per-channel user boost (dB), applied on top of preset target.
  Map<int, double> boostDb = {};

  /// Activate with the current send levels as the clamp reference.
  /// [currentSendFloats]: map of ch (1-based) → current fader float (0..1).
  void activate(Map<int, double> currentSendFloats) {
    _refSendDb.clear();
    _currentSendDb.clear();
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
  /// [preset]      — genre preset defining target relative balance.
  ///
  /// Returns the list of sends to write. Empty if engine is inactive.
  List<SendCommand> update(
    List<double> meterDb,
    List<InstrumentType> instruments,
    GenrePreset preset,
  ) {
    if (!_active) return const [];

    final commands = <SendCommand>[];

    // Find the loudest active channel — the anchor.
    final activeDbs = <double>[];
    for (var i = 0; i < meterDb.length && i < 32; i++) {
      if (meterDb[i] > params.gateDb) activeDbs.add(meterDb[i]);
    }
    if (activeDbs.isEmpty) return const [];
    final anchorDb = activeDbs.reduce(max);

    for (var i = 0; i < meterDb.length && i < 32; i++) {
      final ch = i + 1;
      final meter = meterDb[i];

      // Gate: channel is silent — freeze send, no correction.
      if (meter <= params.gateDb) continue;

      final instrument = i < instruments.length ? instruments[i] : InstrumentType.unknown;
      final targetRelDb = preset.targetFor(instrument);
      final boost = boostDb[ch] ?? 0.0;

      // Current relative level vs anchor
      final currentRelDb = meter - anchorDb;

      // Deviation from target (positive = too loud, negative = too quiet)
      final deviation = currentRelDb - (targetRelDb + boost);

      // Deadband: small deviations preserve musical dynamics
      if (deviation.abs() < params.deadbandDb) continue;

      // Proportional step, clamped to maxStepDb
      final step = (-deviation * params.correctionGain)
          .clamp(-params.maxStepDb, params.maxStepDb);

      // Apply step to current send
      final current = _currentSendDb[ch] ?? _refSendDb[ch] ?? 0.0;
      final ref = _refSendDb[ch] ?? current;

      final newDb = (current + step).clamp(ref - params.clampDb, ref + params.clampDb);
      _currentSendDb[ch] = newDb;

      commands.add(SendCommand(ch: ch, levelFloat: dbToFloat(newDb).clamp(0.0, 1.0)));
    }

    return commands;
  }
}
