import 'dart:math' as math;

import '../osc/x32_protocol.dart';

/// Smooths raw meter floats from the X32 into dB values.
///
/// Averaging is done in the **power domain** (mean of amplitude², i.e. true RMS)
/// and converted to dB only on read — NOT by averaging dB values. This matters
/// for choppy / percussive sources (a reggae guitar skank, drum hits): they are
/// loud for a short slice and near-silent between, so a dB-domain average gets
/// dragged toward the silent gaps and reads 15–20 dB below how loud the source
/// actually is → the engine under-ducks it and it sits too loud in the ears. An
/// RMS (power) average is dominated by the loud slices, matching perceived
/// loudness, so the engine ducks such sources correctly. Sustained sources read
/// identically either way (constant level ⇒ 10·log₁₀(L²) = 20·log₁₀(L)).
///
/// Two parallel windows:
///   display — fast (~300ms), drives VU meters in the UI
///   engine  — slow (~3s), drives the Auto-Mix correction loop (M3)
class MeterStream {
  // EMA alpha for ~300ms display at 50ms update interval: 1 - exp(-50/300) ≈ 0.15
  static const _displayAlpha = 0.15;
  // EMA alpha for ~3s engine smoothing at 50ms update interval: 1 - exp(-50/3000) ≈ 0.016
  static const _engineAlpha = 0.016;

  final List<double> _rawDb = List.filled(48, -90.0);
  // Smoothed POWER (amplitude², linear), converted to dB on read. Averaging
  // power and not dB is what makes an RMS — see the class doc.
  final List<double> _displayPow = List.filled(48, 0.0);
  final List<double> _enginePow = List.filled(48, 0.0);

  static double _linToDb(double f) {
    if (f <= 1e-9) return -90.0;
    return (20.0 * math.log(f) / math.ln10).clamp(-90.0, 0.0);
  }

  static double _powToDb(double p) {
    if (p <= 1e-9) return -90.0;
    return (10.0 * math.log(p) / math.ln10).clamp(-90.0, 0.0);
  }

  void update(List<double> linearFloats) {
    for (var i = 0; i < linearFloats.length && i < 48; i++) {
      final f = linearFloats[i].clamp(0.0, 1.0);
      final p = f * f; // instantaneous power (amplitude²)
      _rawDb[i] = _linToDb(f);
      _displayPow[i] = _displayAlpha * p + (1 - _displayAlpha) * _displayPow[i];
      _enginePow[i] = _engineAlpha * p + (1 - _engineAlpha) * _enginePow[i];
    }
  }

  /// Fast-smoothed dB (~300ms RMS) for UI display (index = channel - 1, 0-based).
  double displayDb(int channelIndex) => channelIndex < _displayPow.length
      ? _powToDb(_displayPow[channelIndex])
      : -90.0;

  /// Slow-smoothed dB (~3s RMS) for the Auto-Mix engine (index = channel - 1).
  double engineDb(int channelIndex) => channelIndex < _enginePow.length
      ? _powToDb(_enginePow[channelIndex])
      : -90.0;

  /// Snapshot of all 32 slow-smoothed (~3s RMS) input channel dB values — the
  /// levels the Auto-Mix engine corrects on.
  List<double> get engineSnapshot =>
      List.generate(kInputChannelCount, (i) => _powToDb(_enginePow[i]),
          growable: false);

  /// Snapshot of all 32 fast-smoothed (~300ms RMS) input channel dB values —
  /// what the on-screen VU bars show. Logged next to [engineSnapshot] for
  /// diagnosis: both are RMS now, so for a steady source they track closely; a
  /// large gap means the source is very dynamic within the 3s window.
  List<double> get displaySnapshot =>
      List.generate(kInputChannelCount, (i) => _powToDb(_displayPow[i]),
          growable: false);

  /// Snapshot of all 32 raw (unsmoothed, instantaneous) input channel dB values.
  /// Logged for diagnosis: if even this sits low, the meter bank/scale itself is
  /// low — not the smoothing.
  List<double> get rawSnapshot =>
      List.unmodifiable(_rawDb.sublist(0, kInputChannelCount));
}
