import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../engine/auto_mix_engine.dart';
import '../osc/osc_codec.dart';
import '../osc/x32_protocol.dart';
import '../platform/background_keepalive.dart';
import '../state/channel_mapper.dart';
import '../state/genre_presets.dart';
import '../state/instrument_type.dart';
import '../state/session_log.dart';
import 'meter_stream.dart';

class DiscoveredMixer {
  final String ip;
  final String name;
  final String model;
  final String firmware;

  const DiscoveredMixer({
    required this.ip,
    required this.name,
    required this.model,
    required this.firmware,
  });
}

class ChannelInfo {
  final int ch; // 1..32
  final String name;
  double sendLevel; // 0..1 X32 float
  int? iconId;
  int? colorId;

  ChannelInfo({
    required this.ch,
    required this.name,
    this.sendLevel = 0.75,
    this.iconId,
    this.colorId,
  });
}

/// Handles all UDP/OSC communication with the X32.
///
/// Meter updates arrive at ~20 Hz but notifyListeners() is throttled to
/// 10 Hz via [_meterNotifyTimer] so the UI stays smooth without rebuilding
/// at full packet rate.
///
/// Auto-Mix runs on a separate 1-second tick using slow-smoothed meters.
class MixerClient extends ChangeNotifier {
  RawDatagramSocket? _socket;
  Timer? _renewTimer;
  Timer? _discoveryTimer;
  Timer? _meterNotifyTimer;
  Timer? _engineTimer;

  String? _mixerIp;
  String? _mixerName;
  String? _mixerModel;
  bool _connected = false;
  int _busIndex = 1;
  bool _discovering = false;
  bool _hasPendingMeterUpdate = false;

  final _meters = MeterStream();
  final _engine = AutoMixEngine();
  final _log = SessionLogger();
  Genre _genre = Genre.general;

  // Baseline send levels read from the mixer at connect time.
  // Used as the engine's clamp reference to prevent drift each time
  // auto-mix is toggled or the genre preset is changed.
  final Map<int, double> _baselineLevels = {};
  bool _muted = false;
  final Map<int, double> _preMuteLevels = {};

  final List<DiscoveredMixer> discovered = [];
  final List<ChannelInfo> channels = List.generate(
    kInputChannelCount,
    (i) => ChannelInfo(ch: i + 1, name: 'Ch ${i + 1}'),
  );
  /// Instrumento **efetivo** por canal (índice 0 = ch1): o detectado, ou o
  /// override manual quando houver. É esta lista que o engine e a UI leem.
  final List<InstrumentType> instruments =
      List.filled(kInputChannelCount, InstrumentType.unknown);

  /// Resultado puro da auto-detecção (`ChannelMapper`), sem override. Usado para
  /// mostrar "detectado: …" no seletor e para voltar ao padrão.
  final List<InstrumentType> _detected =
      List.filled(kInputChannelCount, InstrumentType.unknown);

  /// Sobreposições manuais canal (1-based) → tipo escolhido pelo músico. Vencem
  /// a auto-detecção. Persistidas por mesa pela UI (`AppSettings`).
  final Map<int, InstrumentType> _overrides = {};

  /// Mix bus names read from the mixer (`/bus/NN/config/name`). Index 0 = bus 1.
  final List<String?> busNames = List.filled(kMixBusCount, null);

  static final _reChName = RegExp(r'^/ch/(\d{2})/config/name$');
  static final _reChIcon = RegExp(r'^/ch/(\d{2})/config/icon$');
  static final _reChColor = RegExp(r'^/ch/(\d{2})/config/color$');
  static final _reChSendLevel = RegExp(r'^/ch/(\d{2})/mix/(\d{2})/level$');
  static final _reBusName = RegExp(r'^/bus/(\d{2})/config/name$');

  String? get mixerIp => _mixerIp;
  String? get mixerName => _mixerName;
  String? get mixerModel => _mixerModel;
  bool get isConnected => _connected;
  bool get isDiscovering => _discovering;
  int get busIndex => _busIndex;

  /// Name of the currently selected bus, or null if the mixer hasn't sent one
  /// (or the bus has no name configured).
  String? get busName {
    final n = busNames[(_busIndex - 1).clamp(0, kMixBusCount - 1)];
    return (n != null && n.isNotEmpty) ? n : null;
  }

  Genre get genre => _genre;
  bool get autoMixActive => _engine.isActive;
  bool get isMuted => _muted;

  /// Quantos registros de diagnóstico já foram gravados nesta sessão.
  int get diagnosticRecordCount => _log.recordCount;

  /// Escreve o log de diagnóstico da sessão num arquivo e devolve o caminho
  /// (pra o share sheet). `null` se nada foi gravado ainda.
  Future<String?> exportSessionLog() => _log.writeToFile();

  /// Fast-smoothed dB for display (~300ms EMA). 0-based channel index.
  double meterDisplayDb(int channelIndex) => _meters.displayDb(channelIndex);

  // ── Override de instrumento ────────────────────────────────────────────────
  // Camada de sobreposição manual sobre a auto-detecção. Não toca no engine nem
  // no I/O — apenas re-mistura a lista efetiva `instruments` que ambos já leem.

  /// Instrumento auto-detectado do canal [ch] (1-based), ignorando override.
  InstrumentType detectedInstrument(int ch) {
    final idx = ch - 1;
    return (idx >= 0 && idx < _detected.length)
        ? _detected[idx]
        : InstrumentType.unknown;
  }

  /// `true` se o canal [ch] (1-based) tem uma sobreposição manual ativa.
  bool isOverridden(int ch) => _overrides.containsKey(ch);

  /// Recompõe `instruments[idx]` a partir de `_detected` ⊕ `_overrides`.
  void _applyEffective(int idx) {
    instruments[idx] = _overrides[idx + 1] ?? _detected[idx];
  }

  /// Define (ou remove, com [type] `null`) o override do canal [ch] (1-based).
  /// O engine relê `instruments` a cada tick, então o novo alvo entra sozinho no
  /// próximo ciclo — não precisa re-anchorar o clamp.
  void setInstrumentOverride(int ch, InstrumentType? type) {
    final idx = ch - 1;
    if (idx < 0 || idx >= instruments.length) return;
    if (type == null) {
      _overrides.remove(ch);
    } else {
      _overrides[ch] = type;
    }
    _applyEffective(idx);
    _log.event('override', {
      'ch': ch,
      'type': type?.name,
      'detected': _detected[idx].name,
      'effective': instruments[idx].name,
    });
    notifyListeners();
  }

  /// Carga em lote dos overrides (chamada no connect, com o mapa da mesa).
  void setInstrumentOverrides(Map<int, InstrumentType> map) {
    _overrides
      ..clear()
      ..addAll(map);
    for (var idx = 0; idx < instruments.length; idx++) {
      _applyEffective(idx);
    }
    notifyListeners();
  }

  /// Remove todos os overrides desta mesa — todos os canais voltam ao detectado.
  void clearInstrumentOverrides() {
    if (_overrides.isEmpty) return;
    _overrides.clear();
    for (var idx = 0; idx < instruments.length; idx++) {
      _applyEffective(idx);
    }
    notifyListeners();
  }

  // ── Reforço por canal (boost) ──────────────────────────────────────────────
  // Deslocamento manual (dB) sobre o alvo do preset, por canal ("mais/menos
  // este"). Vai direto no engine (`boostDb`), que o relê a cada tick — como o
  // override, não precisa re-anchorar o clamp.

  /// Reforço atual (dB) do canal [ch] (1-based). 0 = neutro.
  double channelBoostDb(int ch) => _engine.boostDb[ch] ?? 0.0;

  /// `true` se o canal [ch] tem reforço diferente de zero.
  bool isBoosted(int ch) => (_engine.boostDb[ch] ?? 0.0) != 0.0;

  /// Define o reforço (dB) do canal [ch] (1-based). 0 remove.
  void setChannelBoost(int ch, double db) {
    if (db == 0.0) {
      _engine.boostDb.remove(ch);
    } else {
      _engine.boostDb[ch] = db;
    }
    _log.event('boost', {'ch': ch, 'db': db});
    notifyListeners();
  }

  /// Carga em lote dos reforços (no connect, com o mapa salvo da mesa).
  void setChannelBoosts(Map<int, double> map) {
    _engine.boostDb
      ..clear()
      ..addAll(map);
    notifyListeners();
  }

  /// Zera todos os reforços desta mesa.
  void clearChannelBoosts() {
    if (_engine.boostDb.isEmpty) return;
    _engine.boostDb.clear();
    notifyListeners();
  }

  set busIndex(int v) {
    _busIndex = v.clamp(1, kMixBusCount);
    notifyListeners();
  }

  /// Switch the return bus at runtime. Restores the previous bus to its
  /// baseline first (via [disableAutoMix]), then re-reads the send levels for
  /// the new bus. Auto-mix is turned off for safety so no stale corrections
  /// leak onto the newly selected bus.
  Future<void> setBus(int index) async {
    final next = index.clamp(1, kMixBusCount);
    if (next == _busIndex) return;
    if (_engine.isActive) disableAutoMix();
    if (_muted) {
      _muted = false;
      _preMuteLevels.clear();
    }
    _busIndex = next;
    _baselineLevels.clear();
    _log.event('bus', {'bus': next});
    notifyListeners();
    await _fetchSendLevels();
  }

  void setGenre(Genre g) {
    _genre = g;
    if (_engine.isActive) {
      // Re-anchor clamp so all genre targets are reachable from baseline.
      final ref = {for (final ch in channels) ch.ch: _baselineLevels[ch.ch] ?? ch.sendLevel};
      _engine.activate(ref);
    }
    _log.event('genre', {'genre': g.name});
    notifyListeners();
  }

  void enableAutoMix() {
    final ref = {for (final ch in channels) ch.ch: _baselineLevels[ch.ch] ?? ch.sendLevel};
    _engine.activate(ref);
    _log.activate(
      baseline: ref,
      genre: _genre.name,
      master: _engine.masterDb,
      channels: [
        for (final ch in channels)
          {
            'ch': ch.ch,
            'name': ch.name,
            'detected': _detected[ch.ch - 1].name,
            'effective': instruments[ch.ch - 1].name,
            'boost': _engine.boostDb[ch.ch] ?? 0.0,
          },
      ],
    );
    _engineTimer?.cancel();
    _engineTimer = Timer.periodic(
      Duration(milliseconds: kCorrectionIntervalMs),
      _engineTick,
    );
    notifyListeners();
  }

  void disableAutoMix() {
    if (_engine.isActive && _connected && !_muted) {
      // Restore all channels to pre-auto-mix baseline so the mixer state stays
      // clean. Without this, future reconnects read engine-modified values as
      // the new baseline and compound the drift each activation cycle.
      for (final entry in _baselineLevels.entries) {
        setChannelSend(entry.key, entry.value);
      }
    }
    _engine.deactivate();
    _engineTimer?.cancel();
    _engineTimer = null;
    _log.event('autoMixOff');
    notifyListeners();
  }

  void toggleMute() {
    if (_muted) {
      for (final ch in channels) {
        final saved = _preMuteLevels[ch.ch];
        if (saved != null) setChannelSend(ch.ch, saved);
      }
      _preMuteLevels.clear();
    } else {
      for (final ch in channels) {
        _preMuteLevels[ch.ch] = ch.sendLevel;
        setChannelSend(ch.ch, 0.0);
      }
    }
    _muted = !_muted;
    _log.event('mute', {'muted': _muted});
    notifyListeners();
  }

  void _engineTick(Timer _) {
    final preset = kGenrePresets[_genre]!;
    final meterDb = _meters.engineSnapshot;
    final cmds = _engine.update(meterDb, instruments, preset);
    _log.tick(
      meterDb: meterDb,
      refC: _engine.refLevelDb,
      cmds: {for (final c in cmds) c.ch: c.levelFloat},
    );
    for (final cmd in cmds) {
      setChannelSend(cmd.ch, cmd.levelFloat);
    }

    // Enforce engine state: if user dragged a fader manually, the engine's
    // _currentSendDb wasn't updated, so the channel deviation may be within
    // the deadband and get no correction command. We still need to restore the
    // fader to the engine's tracked level so the manual drag doesn't "stick".
    if (!_muted) {
      for (final entry in _engine.currentSendFloats.entries) {
        final idx = entry.key - 1;
        if (idx >= 0 && idx < channels.length) {
          if ((entry.value - channels[idx].sendLevel).abs() > 0.005) {
            setChannelSend(entry.key, entry.value);
          }
        }
      }
    }
  }

  // ── Discovery ─────────────────────────────────────────────────────────────

  Future<void> startDiscovery() async {
    discovered.clear();
    _discovering = true;
    notifyListeners();

    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    sock.broadcastEnabled = true;

    final xinfoPacket = encodeOsc('/xinfo', ',', []);
    for (final ip in ['255.255.255.255', '127.0.0.1']) {
      try {
        sock.send(xinfoPacket, InternetAddress(ip), kX32Port);
      } catch (_) {}
    }

    _discoveryTimer?.cancel();
    _discoveryTimer = Timer(const Duration(seconds: 3), () {
      _discovering = false;
      sock.close();
      notifyListeners();
    });

    sock.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      final msg = decodeOsc(dg.data);
      if (msg.address == '/xinfo' && msg.args.length >= 3) {
        final mixer = DiscoveredMixer(
          ip: msg.args[0] as String,
          name: msg.args[1] as String,
          model: msg.args[2] as String,
          firmware: msg.args.length > 3 ? msg.args[3] as String : '',
        );
        if (!discovered.any((d) => d.ip == mixer.ip)) {
          discovered.add(mixer);
          notifyListeners();
        }
      }
    });
  }

  // ── Connect / disconnect ───────────────────────────────────────────────────

  Future<void> connect(String ip, {int busIndex = 1}) async {
    await disconnect();

    _busIndex = busIndex;
    _mixerIp = ip;
    _connected = false;
    notifyListeners();

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    _send(encodeOsc('/xinfo', ',', []));
    _socket!.listen(_onData);

    await _fetchChannelConfig();
    await _fetchBusNames();

    // Subscribe to meters and start throttled UI refresh
    _subscribeMeter();
    _meterNotifyTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_hasPendingMeterUpdate) {
        _hasPendingMeterUpdate = false;
        notifyListeners();
      }
    });

    _connected = true;
    _log.start(mixerName: _mixerName, model: _mixerModel, bus: _busIndex);
    notifyListeners();

    // Keep the process alive in the background so the meter subscription and
    // the auto-mix loop don't freeze when the phone locks or the musician
    // opens a chord-sheet app. Fire-and-forget: the first call may show a
    // battery-optimization permission dialog, and connect must not block on it.
    unawaited(BackgroundKeepAlive.enable());
  }

  Future<void> disconnect() async {
    unawaited(BackgroundKeepAlive.disable());
    // Log kept in memory so a diagnostic can still be exported after the service.
    _log.event('disconnect');
    disableAutoMix();
    _baselineLevels.clear();
    _overrides.clear();
    _engine.boostDb.clear();
    _muted = false;
    _preMuteLevels.clear();
    _meterNotifyTimer?.cancel();
    _meterNotifyTimer = null;
    _renewTimer?.cancel();
    _renewTimer = null;
    _socket?.close();
    _socket = null;
    _connected = false;
    _mixerIp = null;
    _mixerName = null;
    notifyListeners();
  }

  /// Re-subscribe to meters after the app returns to the foreground.
  ///
  /// Safety net for when background execution wasn't actually granted (e.g. the
  /// user denied battery-optimization) and the OS suspended the process: the
  /// meter subscription expires after ~10s, so on resume we restart it
  /// immediately instead of waiting up to a full renew interval for the feed.
  void resyncAfterResume() {
    if (!_connected) return;
    _subscribeMeter();
  }

  // ── Channel sends ──────────────────────────────────────────────────────────

  void setChannelSend(int ch, double level) {
    if (!_connected || _socket == null) return;
    level = level.clamp(0.0, 1.0);

    final idx = ch - 1;
    if (idx >= 0 && idx < channels.length) {
      channels[idx].sendLevel = level;
    }

    // Manual fader adjustments (made while auto-mix is OFF) update the
    // baseline so the next auto-mix activation uses the user's intent as ref.
    if (!_engine.isActive) {
      _baselineLevels[ch] = level;
    }

    final address =
        '/ch/${ch.toString().padLeft(2, '0')}/mix/${_busIndex.toString().padLeft(2, '0')}/level';
    _send(encodeOsc(address, ',f', [level]));
    notifyListeners();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  void _subscribeMeter() {
    if (_socket == null) return;
    _send(encodeOsc('/meters', ',s', [kMeterBank]));
    _renewTimer?.cancel();
    _renewTimer = Timer.periodic(
      Duration(milliseconds: kMeterRenewIntervalMs),
      (_) => _send(encodeOsc('/meters', ',s', [kMeterBank])),
    );
  }

  Future<void> _fetchChannelConfig() async {
    if (_socket == null) return;
    final busPad = _busIndex.toString().padLeft(2, '0');
    for (var ch = 1; ch <= kInputChannelCount; ch++) {
      final pad = ch.toString().padLeft(2, '0');
      _send(encodeOsc('/ch/$pad/config/name', ',', []));
      _send(encodeOsc('/ch/$pad/config/icon', ',', []));
      _send(encodeOsc('/ch/$pad/config/color', ',', []));
      _send(encodeOsc('/ch/$pad/mix/$busPad/level', ',', []));
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await Future.delayed(const Duration(milliseconds: 500));
  }

  /// Request the names of all mix buses so the UI can label the bus picker.
  /// `/bus/NN/config/name` — CONFIRM AGAINST REAL HARDWARE.
  Future<void> _fetchBusNames() async {
    if (_socket == null) return;
    for (var bus = 1; bus <= kMixBusCount; bus++) {
      final pad = bus.toString().padLeft(2, '0');
      _send(encodeOsc('/bus/$pad/config/name', ',', []));
      await Future.delayed(const Duration(milliseconds: 15));
    }
  }

  /// Re-read send levels for the current bus (used after [setBus]).
  Future<void> _fetchSendLevels() async {
    if (_socket == null) return;
    final busPad = _busIndex.toString().padLeft(2, '0');
    for (var ch = 1; ch <= kInputChannelCount; ch++) {
      final pad = ch.toString().padLeft(2, '0');
      _send(encodeOsc('/ch/$pad/mix/$busPad/level', ',', []));
      await Future.delayed(const Duration(milliseconds: 15));
    }
  }

  void _onData(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null) return;

    final msg = decodeOsc(dg.data);

    if (msg.address == '/xinfo' && msg.args.length >= 3) {
      _mixerName = msg.args[1] as String;
      _mixerModel = msg.args[2] as String;
      notifyListeners();
      return;
    }

    // Bus name response — /bus/NN/config/name ,s <name>
    final busNameMatch = _reBusName.firstMatch(msg.address);
    if (busNameMatch != null && msg.args.isNotEmpty) {
      final bus = int.parse(busNameMatch.group(1)!);
      final idx = bus - 1;
      if (idx >= 0 && idx < busNames.length) {
        busNames[idx] = (msg.args[0] as String).trim();
        notifyListeners();
      }
      return;
    }

    // Channel name response
    final nameMatch = _reChName.firstMatch(msg.address);
    if (nameMatch != null && msg.args.isNotEmpty) {
      final ch = int.parse(nameMatch.group(1)!);
      final idx = ch - 1;
      if (idx >= 0 && idx < channels.length) {
        final prev = channels[idx];
        channels[idx] = ChannelInfo(
          ch: ch,
          name: msg.args[0] as String,
          sendLevel: prev.sendLevel,
          iconId: prev.iconId,
          colorId: prev.colorId,
        );
        _reidentify(idx);
        notifyListeners();
      }
      return;
    }

    // Icon response (int)
    final iconMatch = _reChIcon.firstMatch(msg.address);
    if (iconMatch != null && msg.args.isNotEmpty) {
      final ch = int.parse(iconMatch.group(1)!);
      final idx = ch - 1;
      if (idx >= 0 && idx < channels.length) {
        final prev = channels[idx];
        final iconId = (msg.args[0] as num).toInt();
        channels[idx] = ChannelInfo(
          ch: ch,
          name: prev.name,
          sendLevel: prev.sendLevel,
          iconId: iconId,
          colorId: prev.colorId,
        );
        _reidentify(idx);
        notifyListeners();
      }
      return;
    }

    // Color response (int 0-7)
    final colorMatch = _reChColor.firstMatch(msg.address);
    if (colorMatch != null && msg.args.isNotEmpty) {
      final ch = int.parse(colorMatch.group(1)!);
      final idx = ch - 1;
      if (idx >= 0 && idx < channels.length) {
        final prev = channels[idx];
        final colorId = (msg.args[0] as num).toInt();
        channels[idx] = ChannelInfo(
          ch: ch,
          name: prev.name,
          sendLevel: prev.sendLevel,
          iconId: prev.iconId,
          colorId: colorId,
        );
        _reidentify(idx);
        notifyListeners();
      }
      return;
    }

    // Send level response — /ch/NN/mix/MM/level ,f <val>
    final sendLevelMatch = _reChSendLevel.firstMatch(msg.address);
    if (sendLevelMatch != null && msg.args.isNotEmpty) {
      final ch = int.parse(sendLevelMatch.group(1)!);
      final bus = int.parse(sendLevelMatch.group(2)!);
      if (bus == _busIndex) {
        final idx = ch - 1;
        if (idx >= 0 && idx < channels.length) {
          final level = (msg.args[0] as double).clamp(0.0, 1.0);
          channels[idx].sendLevel = level;
          if (!_engine.isActive) {
            _baselineLevels[ch] = level;
          }
          notifyListeners();
        }
      }
      return;
    }

    // Meter blob
    if (msg.address == kMeterBank && msg.args.isNotEmpty) {
      final raw = msg.args[0];
      final blob = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
      final floats = decodeMeterBlob(blob);
      if (floats.isNotEmpty) {
        _meters.update(floats);
        _hasPendingMeterUpdate = true;
      }
    }
  }

  void _reidentify(int idx) {
    final ch = channels[idx];
    _detected[idx] = ChannelMapper.identify(
      name: ch.name,
      iconId: ch.iconId,
      colorId: ch.colorId,
    );
    // Override manual (se houver) vence a re-detecção — o operador troca o nome
    // do canal, não o que o músico marcou ali.
    _applyEffective(idx);
  }

  void _send(Uint8List data) {
    if (_socket == null || _mixerIp == null) return;
    try {
      _socket!.send(data, InternetAddress(_mixerIp!), kX32Port);
    } catch (_) {}
  }

  @override
  void dispose() {
    disconnect();
    _discoveryTimer?.cancel();
    super.dispose();
  }
}
