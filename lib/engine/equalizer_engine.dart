// Pure Dart — zero Flutter, zero I/O. Testável headless.
import 'dart:math';
import '../osc/osc_codec.dart';
import '../state/instrument_type.dart';
import '../state/genre_presets.dart';
import '../state/musician_roles.dart';
import 'auto_mix_engine.dart' show SendCommand;

/// Parameters of the on-demand equalizer ("Equalizar").
class EqualizerParams {
  /// Absolute noise floor (dB). A sample at/under it is "not playing".
  final double silenceFloorDb;

  /// A sample only counts as "playing" if it is within this many dB of the
  /// loudest channel in the same frame (relative gate — same idea as the
  /// Auto-Mix gate, keeps bleed on a closed mic out of the measurement).
  final double frameRangeDb;

  /// Per-channel gate: of a channel's own samples, only those within this many
  /// dB of its own peak (95th percentile) count. This is what makes the
  /// measurement **ignore pauses**: a vocalist who sang 8 of the 15 s is
  /// measured on those 8 s, not dragged down by the gaps (the root cause of
  /// "entra MUITO alto" in the continuous Auto-Mix).
  final double channelGateDb;

  /// Minimum fraction of the window a channel must be playing to be measured.
  /// Below it the channel is "não ouvido" and keeps its current send.
  final double minPlayingFraction;

  /// Normalization: after balancing, the whole mix is shifted so the highest
  /// send lands here (dB, 0 = unity). Pushes the monitor **up** to the most the
  /// bus can give without anything above unity, leaving the headroom to
  /// [sendCeilingDb] for the volume geral / reforço.
  final double topSendDb;

  final double sendFloorDb;
  final double sendCeilingDb;

  /// Proteção (duck-only). A channel is cut only when its live level is more
  /// than [protectTriggerDb] above the level measured at equalization; the cut
  /// brings it back to [protectKneeDb] above. Never boosts.
  final double protectTriggerDb;
  final double protectKneeDb;
  final double protectMaxCutDb;

  /// Slew of the protection cut per tick (dB): attack (cutting) and release
  /// (giving back). Release is slow so a returning loud passage doesn't pump.
  final double protectAttackDb;
  final double protectReleaseDb;

  /// Only send a command when the computed send moved at least this much (dB).
  final double minChangeDb;

  const EqualizerParams({
    this.silenceFloorDb = -65.0,
    this.frameRangeDb = 40.0,
    this.channelGateDb = 15.0,
    this.minPlayingFraction = 0.15,
    this.topSendDb = 0.0,
    this.sendFloorDb = -60.0,
    this.sendCeilingDb = 10.0,
    this.protectTriggerDb = 6.0,
    this.protectKneeDb = 3.0,
    this.protectMaxCutDb = 12.0,
    this.protectAttackDb = 2.0,
    this.protectReleaseDb = 0.5,
    this.minChangeDb = 0.25,
  });
}

/// Summary of one equalization, for the UI and the log.
class EqualizeResult {
  /// Channels (1-based) heard and measured in this equalization.
  final List<int> balanced;

  /// Channels balanced by a *previous* equalization but quiet this time: they
  /// keep the level the engine already knew (their balance is preserved, they
  /// never fall back to the pre-equalize send).
  final List<int> remembered;

  /// Channels that had some signal but too little to measure, and no previous
  /// measurement — they keep their send as it was.
  final List<int> unheard;

  /// Measured playing level per channel heard now (dB, gated RMS).
  final Map<int, double> levelDb;

  const EqualizeResult({
    required this.balanced,
    this.remembered = const [],
    required this.unheard,
    required this.levelDb,
  });

  bool get ok => balanced.isNotEmpty;
}

/// On-demand equalizer — "ajusta todos de uma vez e depois fica quieto".
///
/// 1. [startMeasure] + [addSample] for ~15 s while the band plays (fast meter
///    frames, ~5 Hz).
/// 2. [finish] measures each channel's **playing** level (gated RMS: pauses and
///    bleed excluded) and fixes the balance:
///
///        send(ch) = K + alvo(instrumento) − nível(ch)
///
///    with `K` chosen so the highest send sits at [EqualizerParams.topSendDb].
/// 3. From then on the sends are **static**. Live changes only come from the
///    user (estilo, reforço, volume geral, fader manual) and from the optional
///    [protectionEnabled] guard, which can only *lower* a channel that got much
///    louder than it was at equalization. Nothing is ever raised automatically,
///    so a musician coming back from a pause never "entra estourado".
///
/// The measured levels are kept, so changing the style re-balances instantly
/// without measuring again. A re-equalization **merges**: channels heard now are
/// re-measured, channels quiet now keep their previous level (and trim). So a
/// musician who wasn't playing at the moment of "Reequalizar" neither loses
/// their balance nor makes the whole mix jump (the top normalization runs over
/// every remembered channel, not only the ones heard this time).
class EqualizerEngine {
  final EqualizerParams params;

  EqualizerEngine({this.params = const EqualizerParams()});

  // ── Measurement ───────────────────────────────────────────────────────────
  bool _measuring = false;
  bool get isMeasuring => _measuring;
  final List<List<double>> _frames = [];
  int get sampleCount => _frames.length;

  // ── Equalized state ───────────────────────────────────────────────────────
  bool _active = false;
  bool get isActive => _active;

  /// Measured playing level per balanced channel (1-based → dB).
  final Map<int, double> _levelDb = {};
  Map<int, double> get levelDb => Map.unmodifiable(_levelDb);

  /// Sends of channels *not* balanced (unheard / parked off): held as they were.
  final Map<int, double> _heldSendDb = {};

  /// Manual trim per channel (dB) — a fader drag while equalized becomes a
  /// trim on top of the balance instead of being fought.
  final Map<int, double> _trimDb = {};

  /// Current protection cut per channel (dB, ≤ 0).
  final Map<int, double> _cutDb = {};
  Map<int, double> get protectionCutDb => Map.unmodifiable(_cutDb);

  /// Last send written per channel (dB) — for change detection.
  final Map<int, double> _lastSentDb = {};

  bool protectionEnabled = true;

  /// "Meu canal" — o canal do músico dono deste retorno (1-based), ou null
  /// (sem papel: balanço de plateia, voz como âncora — ex. Live). Define o papel
  /// ([roleFor]) e aplica "mais eu" + referências ([roleOffsetDb]). Como os
  /// níveis medidos ficam guardados, trocar vale na hora, sem medir de novo.
  int? ownChannel;

  /// Per-channel user boost (dB), on top of the style target.
  Map<int, double> boostDb = {};

  /// Volume geral (dB). Down always works; up is bounded by the headroom to the
  /// send ceiling so the balance never breaks.
  double masterDb = 0.0;

  void startMeasure() {
    _frames.clear();
    _measuring = true;
  }

  void cancelMeasure() {
    _frames.clear();
    _measuring = false;
  }

  /// One fast-meter frame (dB per channel, index 0 = ch1).
  void addSample(List<double> meterDb) {
    if (!_measuring) return;
    _frames.add(List<double>.of(meterDb.take(32)));
  }

  /// Ends the measurement and balances. [currentSendDb]: current send (dB) per
  /// channel (1-based) — channels parked at/under the floor stay off, unheard
  /// channels keep this value. Returns a result with `ok == false` (and leaves
  /// the engine inactive) when nobody was heard.
  EqualizeResult finish(Map<int, double> currentSendDb) {
    _measuring = false;
    final frames = List<List<double>>.of(_frames);
    _frames.clear();

    final levels = <int, double>{};
    final unheard = <int>[];
    if (frames.isNotEmpty) {
      final n = frames.map((f) => f.length).reduce(max);
      for (var i = 0; i < n; i++) {
        final ch = i + 1;
        // Samples where this channel is playing relative to the frame.
        final playing = <double>[];
        for (final f in frames) {
          if (i >= f.length) continue;
          final v = f[i];
          if (v <= params.silenceFloorDb) continue;
          final loudest = f.reduce(max);
          if (v <= loudest - params.frameRangeDb) continue;
          playing.add(v);
        }
        if (playing.isEmpty) continue; // never above the gate — truly silent
        playing.sort();
        final peak = playing[((playing.length - 1) * 0.95).round()];
        final gated = playing.where((v) => v >= peak - params.channelGateDb).toList();
        if (gated.length < frames.length * params.minPlayingFraction) {
          if (!_levelDb.containsKey(ch)) unheard.add(ch);
          continue;
        }
        // Gated RMS in the power domain (same reasoning as MeterStream).
        var pow = 0.0;
        for (final v in gated) {
          pow += _dbToPow(v);
        }
        final level = _powToDb(pow / gated.length);
        final send = currentSendDb[ch];
        if (send != null && send <= params.sendFloorDb) continue; // parked off
        levels[ch] = level;
      }
    }

    if (levels.isEmpty) {
      // Nobody heard: keep whatever was in place (a previous equalization, if
      // any, stays active untouched).
      return EqualizeResult(balanced: const [], unheard: unheard, levelDb: const {});
    }

    // Merge with what we already knew. Only an active engine has a memory — a
    // fresh equalization (or after [deactivate]) starts clean.
    if (!_active) {
      _levelDb.clear();
      _trimDb.clear();
    }
    // A channel the musician parked off since then is forgotten (never opened).
    _levelDb.removeWhere((ch, _) {
      final send = currentSendDb[ch];
      return send != null && send <= params.sendFloorDb;
    });
    final remembered = [
      for (final ch in _levelDb.keys)
        if (!levels.containsKey(ch)) ch,
    ]..sort();
    for (final ch in levels.keys) {
      _trimDb.remove(ch); // re-measured → fresh balance, no stale trim
      _cutDb.remove(ch);
      _lastSentDb.remove(ch);
    }
    _levelDb.addAll(levels);
    _heldSendDb.removeWhere((ch, _) => _levelDb.containsKey(ch));
    for (final e in currentSendDb.entries) {
      if (!_levelDb.containsKey(e.key)) _heldSendDb.putIfAbsent(e.key, () => e.value);
    }
    _active = true;
    return EqualizeResult(
      balanced: levels.keys.toList()..sort(),
      remembered: remembered,
      unheard: unheard,
      levelDb: Map.of(levels),
    );
  }

  void deactivate() {
    _active = false;
    _levelDb.clear();
    _heldSendDb.clear();
    _trimDb.clear();
    _cutDb.clear();
    _lastSentDb.clear();
  }

  /// Balance offset `K` so the highest balanced send (style target + boost +
  /// trim − level) sits at [EqualizerParams.topSendDb].
  double _k(List<InstrumentType> instruments, GenrePreset preset) {
    var top = double.negativeInfinity;
    for (final e in _levelDb.entries) {
      top = max(top, _rel(e.key, instruments, preset) - e.value);
    }
    return params.topSendDb - top;
  }

  double _rel(int ch, List<InstrumentType> instruments, GenrePreset preset) {
    InstrumentType typeOf(int c) =>
        (c >= 1 && c <= instruments.length) ? instruments[c - 1] : InstrumentType.unknown;
    final type = typeOf(ch);
    final own = ownChannel;
    return preset.targetFor(type) +
        roleOffsetDb(
          ch: ch,
          type: type,
          ownChannel: own,
          ownType: own == null ? InstrumentType.unknown : typeOf(own),
        );
  }

  /// Send (dB) of a balanced channel before master / protection.
  double _base(int ch, double k, List<InstrumentType> instruments, GenrePreset preset) =>
      k + _rel(ch, instruments, preset) - _levelDb[ch]! +
      (boostDb[ch] ?? 0.0) + (_trimDb[ch] ?? 0.0);

  /// Effective master: lowering always works, raising stops at the headroom of
  /// the hottest balanced send to the ceiling (keeps the balance intact).
  double _masterEff(double k, List<InstrumentType> instruments, GenrePreset preset) {
    if (masterDb <= 0) return masterDb;
    var top = double.negativeInfinity;
    for (final ch in _levelDb.keys) {
      top = max(top, _base(ch, k, instruments, preset));
    }
    return min(masterDb, max(0.0, params.sendCeilingDb - top));
  }

  /// How much the volume geral can still go up (dB) — for the UI.
  double masterHeadroomDb(List<InstrumentType> instruments, GenrePreset preset) {
    if (!_active || _levelDb.isEmpty) return 0.0;
    final k = _k(instruments, preset);
    var top = double.negativeInfinity;
    for (final ch in _levelDb.keys) {
      top = max(top, _base(ch, k, instruments, preset));
    }
    return max(0.0, params.sendCeilingDb - top);
  }

  /// Target send (dB) for every known channel right now.
  Map<int, double> targetSendsDb(List<InstrumentType> instruments, GenrePreset preset) {
    if (!_active) return const {};
    final k = _k(instruments, preset);
    final m = _masterEff(k, instruments, preset);
    final out = <int, double>{};
    for (final ch in _levelDb.keys) {
      final v = _base(ch, k, instruments, preset) + m + (_cutDb[ch] ?? 0.0);
      out[ch] = v.clamp(params.sendFloorDb, params.sendCeilingDb).toDouble();
    }
    out.addAll(_heldSendDb);
    return out;
  }

  /// A manual fader move on [ch] while equalized: keep it as a trim, so the
  /// engine never fights the musician. Unbalanced channels are simply held at
  /// the new value.
  void setManualSend(
      int ch, double sendDb, List<InstrumentType> instruments, GenrePreset preset) {
    if (!_active) return;
    if (!_levelDb.containsKey(ch)) {
      _heldSendDb[ch] = sendDb;
      _lastSentDb[ch] = sendDb;
      return;
    }
    final current = targetSendsDb(instruments, preset)[ch]!;
    _trimDb[ch] = (_trimDb[ch] ?? 0.0) + (sendDb - current);
    _lastSentDb[ch] = sendDb;
  }

  /// One tick: updates the protection from the live (slow) meter and returns
  /// the sends that changed. Silence never raises anything — the protection
  /// only releases a cut it made.
  List<SendCommand> tick(
    List<double> meterDb,
    List<InstrumentType> instruments,
    GenrePreset preset,
  ) {
    if (!_active) return const [];
    for (final ch in _levelDb.keys) {
      final i = ch - 1;
      final meter = i < meterDb.length ? meterDb[i] : -90.0;
      final excess = meter - _levelDb[ch]!;
      final cur = _cutDb[ch] ?? 0.0;
      // Trigger above [protectTriggerDb]; once cutting, hold (hysteresis) while
      // still above the knee.
      final engaged = protectionEnabled &&
          (excess > params.protectTriggerDb ||
              (cur < 0 && excess > params.protectKneeDb));
      final want =
          engaged ? -min(excess - params.protectKneeDb, params.protectMaxCutDb) : 0.0;
      final step = (want - cur).clamp(-params.protectAttackDb, params.protectReleaseDb);
      final next = min(0.0, cur + step);
      if (next == 0.0) {
        _cutDb.remove(ch);
      } else {
        _cutDb[ch] = next;
      }
    }
    final cmds = <SendCommand>[];
    final targets = targetSendsDb(instruments, preset);
    final keys = targets.keys.toList()..sort();
    for (final ch in keys) {
      final db = targets[ch]!;
      final last = _lastSentDb[ch];
      if (last != null && (db - last).abs() < params.minChangeDb) continue;
      _lastSentDb[ch] = db;
      cmds.add(SendCommand(ch: ch, levelFloat: dbToFloat(db).clamp(0.0, 1.0)));
    }
    return cmds;
  }

  static double _dbToPow(double db) => pow(10, db / 10).toDouble();
  static double _powToDb(double p) => p <= 1e-12 ? -120.0 : 10 * log(p) / ln10;
}
