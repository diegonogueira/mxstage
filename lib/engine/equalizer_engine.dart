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

  /// Normalization anchor window (dB): only channels whose measured level is
  /// within this much of the loudest measured channel define the top (`K`). A
  /// quiet mic further down still gets its balanced send (bounded by the
  /// ceiling) but can't drag the whole mix down — same lesson as the Auto-Mix
  /// `seedAnchorRangeDb`. A real church log: a noise channel ~30 dB under the
  /// keys became the top and pushed everyone ~25 dB down ("MUITO baixo").
  final double anchorRangeDb;

  /// Range of the per-channel correction (reforço / fader drag), dB. Wide on the
  /// cut side: the mesa's meter can under-read a channel (28/10: a violão read
  /// ~13 dB under the keys but was heard far above) and the musician must be
  /// able to pull it all the way down.
  final double boostMinDb;
  final double boostMaxDb;

  /// Below this many distinct musician roles (voz, teclas, bateria, baixo…)
  /// heard, the equalization still applies but is flagged [EqualizeResult.partial]
  /// — a musician who arrives early must be able to hear himself; the UI asks
  /// to Reequalizar when the band comes in (the locked reference keeps him where
  /// he is and the others land around him).
  final int partialBelowRoles;

  const EqualizerParams({
    this.silenceFloorDb = -65.0,
    this.frameRangeDb = 40.0,
    // Stricter since the 28/10 log: a violão playing little in the window was
    // measured anywhere from −44 to −61 dB and then blew up when strummed. Gate
    // nearer the loud part (10 dB) and demand more playing time (35%) — a
    // channel that barely played keeps what it had instead of a wrong level.
    this.channelGateDb = 10.0,
    this.minPlayingFraction = 0.35,
    this.topSendDb = 0.0,
    this.sendFloorDb = -60.0,
    this.sendCeilingDb = 10.0,
    // Firmer since the church log: a guitar measured in a soft passage sat
    // 3–5 dB over target in the chorus with trigger 6 / knee 3.
    this.protectTriggerDb = 4.0,
    this.protectKneeDb = 1.0,
    this.protectMaxCutDb = 18.0,
    this.protectAttackDb = 2.0,
    this.protectReleaseDb = 0.5,
    this.minChangeDb = 0.25,
    this.anchorRangeDb = 20.0,
    this.partialBelowRoles = 2,
    this.boostMinDb = -18.0,
    this.boostMaxDb = 12.0,
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

  /// Heard, but its send to this bus is off **at the mesa** — kept off (the app
  /// never opens a channel on its own). The musician can include it ("No meu
  /// fone"), which uses this measurement without equalizing again.
  final List<int> parkedOff;

  /// Heard, but the instrument is unknown (talkback/DM, PC, a stray mic) — not
  /// balanced, kept as the mesa had it.
  final List<int> unknown;

  /// No known instrument heard — nothing applied.
  final bool tooFew;

  /// Pairs of channels that carried the *same* signal the whole window (e.g. an
  /// unnamed input that is a copy of Keys L) and aren't linked as a stereo pair
  /// — counting both doubles that instrument. The UI suggests linking/removing.
  final List<List<int>> duplicates;

  /// The base channel ("meu instrumento") has never been heard — the balance
  /// fell back to the loudest channels; ask the musician to play a bit.
  final bool baseUnheard;

  /// Applied, but fewer than [EqualizerParams.partialBelowRoles] roles were
  /// heard (e.g. only the keys warming up) — re-equalize when the band enters.
  final bool partial;

  const EqualizeResult({
    required this.balanced,
    this.remembered = const [],
    required this.unheard,
    required this.levelDb,
    this.parkedOff = const [],
    this.unknown = const [],
    this.tooFew = false,
    this.partial = false,
    this.duplicates = const [],
    this.baseUnheard = false,
  });

  bool get ok => balanced.isNotEmpty && !tooFew;
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


  /// Current protection cut per channel (dB, ≤ 0).
  final Map<int, double> _cutDb = {};
  Map<int, double> get protectionCutDb => Map.unmodifiable(_cutDb);

  /// Last send written per channel (dB) — for change detection.
  final Map<int, double> _lastSentDb = {};

  /// Channels whose send was off at the mesa when equalized (never opened
  /// unless [forcedIn]).
  final Set<int> _parkedOff = {};

  /// Shift (dB) added to the formula `K` **when there is no base channel**, so
  /// a re-equalization keeps the monitor where it was (the band playing louder
  /// in the chorus doesn't move the reference — remembered ones don't move). 0
  /// on a fresh equalization. With a base ("meu instrumento") the base itself is
  /// the reference and this stays 0.
  double _kShift = 0.0;

  /// Stereo pairs (symmetric: a→b and b→a), per mesa, owned by the client. A
  /// pair is one instrument: measured together (the louder side), same send,
  /// counted once. 28/10: the keys came in through three inputs and were
  /// counted three times.
  Map<int, int> links = {};

  /// "Fora do meu fone": channels the musician took out — send off, never
  /// measured or balanced. Per mesa+bus, owned by the client.
  Set<int> excluded = {};

  /// "No meu fone": channels the musician wants even though their send is off
  /// at the mesa (e.g. a violão the operator left at 0).
  Set<int> forcedIn = {};

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
  /// channel (1-based) — channels parked at/under the floor stay off unless
  /// [forcedIn], unheard channels keep this value. [instruments] (index 0 = ch1)
  /// decides which channels are known instruments; unknown ones are never
  /// balanced. Returns `ok == false` (and changes nothing) when too few
  /// instruments were heard.
  EqualizeResult finish(
    Map<int, double> currentSendDb, {
    List<InstrumentType> instruments = const [],
    GenrePreset? preset,
  }) {
    _measuring = false;
    final frames = List<List<double>>.of(_frames);
    _frames.clear();
    InstrumentType typeOf(int ch) =>
        ch - 1 < instruments.length ? instruments[ch - 1] : InstrumentType.unknown;
    bool parked(int ch) {
      final send = currentSendDb[ch];
      return send != null && send <= params.sendFloorDb;
    }

    final levels = <int, double>{};
    final unheard = <int>[];
    final unknown = <int>[];
    final parkedOff = <int>[];
    if (frames.isNotEmpty) {
      final n = frames.map((f) => f.length).reduce(max);
      for (var i = 0; i < n; i++) {
        final ch = i + 1;
        if (excluded.contains(ch)) continue;
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
          if (!_levelDb.containsKey(ch) && typeOf(ch) != InstrumentType.unknown) {
            unheard.add(ch);
          }
          continue;
        }
        if (typeOf(ch) == InstrumentType.unknown) {
          unknown.add(ch); // DM/talkback, PC… — never balanced
          continue;
        }
        // Gated RMS in the power domain (same reasoning as MeterStream).
        var pow = 0.0;
        for (final v in gated) {
          pow += _dbToPow(v);
        }
        levels[ch] = _powToDb(pow / gated.length);
        if (parked(ch) && !forcedIn.contains(ch)) parkedOff.add(ch);
      }
    }

    // Stereo pairs: one instrument → both sides take the louder measurement.
    for (final e in links.entries) {
      final a = e.key, b = e.value;
      if (a > b) continue;
      final la = levels[a], lb = levels[b];
      if (la == null && lb == null) continue;
      final l = max(la ?? double.negativeInfinity, lb ?? double.negativeInfinity);
      if (!excluded.contains(a) && typeOf(a) != InstrumentType.unknown) levels[a] = l;
      if (!excluded.contains(b) && typeOf(b) != InstrumentType.unknown) levels[b] = l;
      unheard.removeWhere((c) => c == a || c == b);
    }
    // Any channel with signal, named or not: the 28/10 copy of the keys came in
    // on an unnamed input.
    final duplicates = _findDuplicates(frames, [
      for (var c = 1; c <= (frames.isEmpty ? 0 : frames.first.length); c++)
        if (!excluded.contains(c)) c,
    ]);

    final roles = {
      for (final ch in levels.keys)
        if (!parkedOff.contains(ch)) roleFor(typeOf(ch)),
    };
    final tooFew = roles.isEmpty;
    if (tooFew) {
      // Keep whatever was in place (a previous equalization stays untouched).
      return EqualizeResult(
        balanced: levels.keys.where((c) => !parkedOff.contains(c)).toList()..sort(),
        unheard: unheard,
        levelDb: Map.of(levels),
        parkedOff: parkedOff,
        unknown: unknown,
        tooFew: true,
      );
    }

    // Merge with what we already knew. Only an active engine has a memory — a
    // fresh equalization (or after [deactivate]) starts clean.
    final merging = _active && preset != null;
    final kBefore = merging ? _k(instruments, preset) : 0.0;
    if (!_active) {
      _levelDb.clear();
      _kShift = 0.0;
    }
    // A channel that became unknown, or excluded, is forgotten.
    _levelDb.removeWhere((ch, _) =>
        typeOf(ch) == InstrumentType.unknown || excluded.contains(ch));
    final remembered = [
      for (final ch in _levelDb.keys)
        if (!levels.containsKey(ch) && _isBalanced(ch)) ch,
    ]..sort();
    for (final ch in levels.keys) {
      _cutDb.remove(ch);
      _lastSentDb.remove(ch);
    }
    _levelDb.addAll(levels);
    _parkedOff
      ..removeWhere((ch) => levels.containsKey(ch))
      ..addAll([for (final ch in levels.keys) if (parked(ch)) ch]);
    _heldSendDb.removeWhere((ch, _) => _levelDb.containsKey(ch));
    for (final e in currentSendDb.entries) {
      _heldSendDb.putIfAbsent(e.key, () => e.value);
    }
    _active = true;
    _kShift = 0.0;
    if (merging && _baseChannels(instruments).isEmpty) {
      // No base: keep the reference where it was (see [_kShift]).
      _kShift = kBefore - _k(instruments, preset);
    }
    final baseUnheard = ownChannel != null && _baseChannels(instruments).isEmpty;
    return EqualizeResult(
      balanced: [for (final ch in levels.keys) if (_isBalanced(ch)) ch]..sort(),
      remembered: remembered,
      unheard: unheard,
      levelDb: Map.of(levels),
      parkedOff: parkedOff,
      unknown: unknown,
      partial: roles.length < params.partialBelowRoles,
      duplicates: duplicates,
      baseUnheard: baseUnheard,
    );
  }

  /// Channels that moved together, same level, the whole window — a copy of
  /// one source on two inputs. Linked pairs are expected and skipped.
  List<List<int>> _findDuplicates(List<List<double>> frames, List<int> chs) {
    final out = <List<int>>[];
    for (var x = 0; x < chs.length; x++) {
      for (var y = x + 1; y < chs.length; y++) {
        final a = chs[x], b = chs[y];
        if (links[a] == b) continue;
        var both = 0, sum = 0.0;
        for (final f in frames) {
          if (a > f.length || b > f.length) continue;
          final va = f[a - 1], vb = f[b - 1];
          if (va <= params.silenceFloorDb || vb <= params.silenceFloorDb) continue;
          both++;
          sum += (va - vb).abs();
        }
        if (both >= frames.length * 0.5 && sum / both < 1.0) out.add([a, b]);
      }
    }
    return out;
  }

  /// The base channels: "meu instrumento" plus its stereo partner — or, for a
  /// drummer, the whole kit — that are balanced and measured.
  List<int> _baseChannels(List<InstrumentType> instruments) {
    final own = ownChannel;
    if (own == null) return const [];
    InstrumentType typeOf(int c) =>
        (c >= 1 && c <= instruments.length) ? instruments[c - 1] : InstrumentType.unknown;
    final Iterable<int> set = isDrumKit(typeOf(own))
        ? [for (var c = 1; c <= instruments.length; c++) if (isDrumKit(typeOf(c))) c]
        : [own, if (links[own] != null) links[own]!];
    return [for (final c in set) if (_isBalanced(c)) c];
  }

  /// A measured channel is balanced unless excluded, or parked off at the mesa
  /// without being forced in.
  bool _isBalanced(int ch) =>
      _levelDb.containsKey(ch) &&
      !excluded.contains(ch) &&
      (!_parkedOff.contains(ch) || forcedIn.contains(ch));

  Iterable<int> get _balancedChannels => _levelDb.keys.where(_isBalanced);

  void deactivate() {
    _active = false;
    _levelDb.clear();
    _heldSendDb.clear();
    _cutDb.clear();
    _lastSentDb.clear();
    _parkedOff.clear();
    _kShift = 0.0;
  }

  /// Balance offset `K` so the highest balanced send (style target + boost +
  /// trim − level) sits at [EqualizerParams.topSendDb].
  double _k(List<InstrumentType> instruments, GenrePreset preset) {
    // Base ("meu instrumento"): it sits at the top send and everyone else is
    // placed relative to it — even when it isn't playing now (its remembered
    // level is used). 28/10: without a fixed base the top hopped between
    // whoever was loudest and the keys came out right one time, too loud the
    // next.
    final chs = _balancedChannels.toList();
    if (chs.isEmpty) return params.topSendDb + _kShift;
    final loudest = chs.map((c) => _levelDb[c]!).reduce(max);
    var top = double.negativeInfinity;
    for (final ch in chs) {
      final level = _levelDb[ch]!;
      if (level < loudest - params.anchorRangeDb) continue; // can't anchor K
      top = max(top, _rel(ch, instruments, preset) - level);
    }
    final base = _baseChannels(instruments);
    if (base.isNotEmpty) {
      var baseTop = double.negativeInfinity;
      for (final ch in base) {
        baseTop = max(baseTop, _rel(ch, instruments, preset) - _levelDb[ch]!);
      }
      // The base sits at the top send and **doesn't move** (28/10 replay: a
      // quiet vocal pulled the keys down 8 dB) — someone who'd need more than
      // the ceiling just caps there. Only a drummer's kit, whose targets sit
      // far under the voice, comes down enough to keep the voice reachable.
      final kBase = params.topSendDb - baseTop;
      final own = ownChannel!;
      final kitBase = own <= instruments.length && isDrumKit(instruments[own - 1]);
      return kitBase ? min(kBase, params.sendCeilingDb - top) : kBase;
    }
    return params.topSendDb - top + _kShift;
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

  /// Send (dB) of a balanced channel before master / protection. The physical
  /// bounds apply to the *balance* first and the musician's correction comes on
  /// top — 28/10: a −9 reforço on a violão whose balance wanted +27 was eaten by
  /// the +10 ceiling and did nothing.
  double _base(int ch, double k, List<InstrumentType> instruments, GenrePreset preset) =>
      (k + _rel(ch, instruments, preset) - _levelDb[ch]!)
          .clamp(params.sendFloorDb, params.sendCeilingDb)
          .toDouble() +
      (boostDb[ch] ?? 0.0);

  /// Effective master: lowering always works, raising stops at the headroom of
  /// the hottest balanced send to the ceiling (keeps the balance intact).
  double _masterEff(double k, List<InstrumentType> instruments, GenrePreset preset) {
    if (masterDb <= 0) return masterDb;
    var top = double.negativeInfinity;
    for (final ch in _balancedChannels) {
      top = max(top, _base(ch, k, instruments, preset));
    }
    return min(masterDb, max(0.0, params.sendCeilingDb - top));
  }

  /// How much the volume geral can still go up (dB) — for the UI.
  double masterHeadroomDb(List<InstrumentType> instruments, GenrePreset preset) {
    if (!_active || _balancedChannels.isEmpty) return 0.0;
    final k = _k(instruments, preset);
    var top = double.negativeInfinity;
    for (final ch in _balancedChannels) {
      top = max(top, _base(ch, k, instruments, preset));
    }
    return max(0.0, params.sendCeilingDb - top);
  }

  /// Target send (dB) for every known channel right now.
  Map<int, double> targetSendsDb(List<InstrumentType> instruments, GenrePreset preset) {
    if (!_active) return const {};
    final k = _k(instruments, preset);
    final m = _masterEff(k, instruments, preset);
    final out = <int, double>{..._heldSendDb};
    for (final ch in _balancedChannels) {
      final v = _base(ch, k, instruments, preset) + m + (_cutDb[ch] ?? 0.0);
      out[ch] = v.clamp(params.sendFloorDb, params.sendCeilingDb).toDouble();
    }
    for (final ch in excluded) {
      out[ch] = _kOffDb; // fora do meu fone
    }
    return out;
  }

  /// A manual fader move on [ch] while equalized becomes this channel's
  /// **reforço** (kept per mesa by the client), so the engine never fights the
  /// musician and the correction survives re-equalizing and the next service.
  /// Unbalanced channels are simply held at the new value. A stereo partner
  /// follows.
  void setManualSend(
      int ch, double sendDb, List<InstrumentType> instruments, GenrePreset preset) {
    if (!_active) return;
    if (excluded.contains(ch)) return;
    if (!_isBalanced(ch)) {
      _heldSendDb[ch] = sendDb;
      _lastSentDb[ch] = sendDb;
      return;
    }
    final current = targetSendsDb(instruments, preset)[ch]!;
    final next = ((boostDb[ch] ?? 0.0) + (sendDb - current))
        .clamp(params.boostMinDb, params.boostMaxDb)
        .toDouble();
    final partner = links[ch];
    for (final c in [ch, ?partner]) {
      if (next == 0.0) {
        boostDb.remove(c);
      } else {
        boostDb[c] = next;
      }
    }
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
    for (final ch in _balancedChannels) {
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

  /// Send level for "fora do meu fone" (fader all the way down).
  static const double _kOffDb = -90.0;

  static double _dbToPow(double db) => pow(10, db / 10).toDouble();
  static double _powToDb(double p) => p <= 1e-12 ? -120.0 : 10 * log(p) / ln10;
}
