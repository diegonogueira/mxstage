import 'dart:math';
import '../osc/x32_protocol.dart';

/// A captured reference balance — the "good mix" snapshot.
///
/// Stores each active channel's level relative to the anchor (loudest active
/// channel at capture time). The engine uses these relative targets to correct
/// drift. Channels below [gateDb] at capture time are stored as null (inactive).
class Reference {
  final DateTime capturedAt;

  /// dB value of the loudest active channel at capture time (the anchor).
  final double anchorDb;

  /// Per-channel relative target: chDb - anchorDb. Null = inactive at capture.
  /// Indexed 0-based (index = channelNumber - 1). Length = kInputChannelCount.
  final List<double?> relativeDb;

  const Reference({
    required this.capturedAt,
    required this.anchorDb,
    required this.relativeDb,
  });

  /// Captures the current [engineSnapshot] (slow-smoothed dB per channel).
  ///
  /// Channels at or below [gateDb] are treated as inactive and stored as null.
  /// Returns null if no channel is active (nothing to capture).
  static Reference? capture(List<double> engineSnapshot, {double gateDb = -45}) {
    assert(engineSnapshot.length >= kInputChannelCount);

    final activeDbs = engineSnapshot
        .take(kInputChannelCount)
        .where((db) => db > gateDb)
        .toList();

    if (activeDbs.isEmpty) return null;

    final anchor = activeDbs.reduce(max);

    final relative = List<double?>.generate(kInputChannelCount, (i) {
      final db = engineSnapshot[i];
      return db > gateDb ? db - anchor : null;
    });

    return Reference(
      capturedAt: DateTime.now(),
      anchorDb: anchor,
      relativeDb: relative,
    );
  }

  /// Number of active channels captured.
  int get activeCount => relativeDb.where((v) => v != null).length;

  String get capturedAtLabel {
    final h = capturedAt.hour.toString().padLeft(2, '0');
    final m = capturedAt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
