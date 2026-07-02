import '../osc/osc_codec.dart';
import '../osc/x32_protocol.dart';

/// Smooths raw meter floats from the X32 into dB values via EMA.
///
/// Two parallel smoothing windows:
///   display — fast (~300ms), drives VU meters in the UI
///   engine  — slow (~3s), drives the Auto-Mix correction loop (M3)
class MeterStream {
  // EMA alpha for ~300ms display at 50ms update interval: 1 - exp(-50/300) ≈ 0.15
  static const _displayAlpha = 0.15;
  // EMA alpha for ~3s engine smoothing: 1 - exp(-50/3000) ≈ 0.016
  static const _engineAlpha = 0.016;

  final List<double> _displayDb = List.filled(48, -90.0);
  final List<double> _engineDb = List.filled(48, -90.0);

  void update(List<double> linearFloats) {
    for (var i = 0; i < linearFloats.length && i < 48; i++) {
      final db = floatToDb(linearFloats[i].clamp(0.0, 1.0));
      _displayDb[i] = _displayAlpha * db + (1 - _displayAlpha) * _displayDb[i];
      _engineDb[i] = _engineAlpha * db + (1 - _engineAlpha) * _engineDb[i];
    }
  }

  /// Fast-smoothed dB for UI display (index = channel - 1, 0-based).
  double displayDb(int channelIndex) =>
      channelIndex < _displayDb.length ? _displayDb[channelIndex] : -90.0;

  /// Slow-smoothed dB for the Auto-Mix engine (index = channel - 1, 0-based).
  double engineDb(int channelIndex) =>
      channelIndex < _engineDb.length ? _engineDb[channelIndex] : -90.0;

  /// Snapshot of all 32 slow-smoothed input channel dB values.
  List<double> get engineSnapshot =>
      List.unmodifiable(_engineDb.sublist(0, kInputChannelCount));
}
