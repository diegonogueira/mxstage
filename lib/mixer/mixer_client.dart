import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../engine/auto_mix_engine.dart';
import '../osc/osc_codec.dart';
import '../osc/x32_protocol.dart';
import '../state/channel_mapper.dart';
import '../state/genre_presets.dart';
import '../state/instrument_type.dart';
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
  Genre _genre = Genre.gospel;

  final List<DiscoveredMixer> discovered = [];
  final List<ChannelInfo> channels = List.generate(
    kInputChannelCount,
    (i) => ChannelInfo(ch: i + 1, name: 'Ch ${i + 1}'),
  );
  final List<InstrumentType> instruments =
      List.filled(kInputChannelCount, InstrumentType.unknown);

  String? get mixerIp => _mixerIp;
  String? get mixerName => _mixerName;
  String? get mixerModel => _mixerModel;
  bool get isConnected => _connected;
  bool get isDiscovering => _discovering;
  int get busIndex => _busIndex;
  Genre get genre => _genre;
  bool get autoMixActive => _engine.isActive;

  /// Fast-smoothed dB for display (~300ms EMA). 0-based channel index.
  double meterDisplayDb(int channelIndex) => _meters.displayDb(channelIndex);

  set busIndex(int v) {
    _busIndex = v.clamp(1, kMixBusCount);
    notifyListeners();
  }

  void setGenre(Genre g) {
    _genre = g;
    notifyListeners();
  }

  void enableAutoMix() {
    final sends = {for (final ch in channels) ch.ch: ch.sendLevel};
    _engine.activate(sends);
    _engineTimer?.cancel();
    _engineTimer = Timer.periodic(
      Duration(milliseconds: kCorrectionIntervalMs),
      _engineTick,
    );
    notifyListeners();
  }

  void disableAutoMix() {
    _engine.deactivate();
    _engineTimer?.cancel();
    _engineTimer = null;
    notifyListeners();
  }

  void _engineTick(Timer _) {
    final preset = kGenrePresets[_genre]!;
    final meterDb = _meters.engineSnapshot;
    final cmds = _engine.update(meterDb, instruments, preset);
    for (final cmd in cmds) {
      setChannelSend(cmd.ch, cmd.levelFloat);
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

    // Subscribe to meters and start throttled UI refresh
    _subscribeMeter();
    _meterNotifyTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_hasPendingMeterUpdate) {
        _hasPendingMeterUpdate = false;
        notifyListeners();
      }
    });

    _connected = true;
    notifyListeners();
  }

  Future<void> disconnect() async {
    disableAutoMix();
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

  // ── Channel sends ──────────────────────────────────────────────────────────

  void setChannelSend(int ch, double level) {
    if (!_connected || _socket == null) return;
    level = level.clamp(0.0, 1.0);

    final idx = ch - 1;
    if (idx >= 0 && idx < channels.length) {
      channels[idx].sendLevel = level;
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
    for (var ch = 1; ch <= kInputChannelCount; ch++) {
      final pad = ch.toString().padLeft(2, '0');
      _send(encodeOsc('/ch/$pad/config/name', ',', []));
      _send(encodeOsc('/ch/$pad/config/icon', ',', []));
      _send(encodeOsc('/ch/$pad/config/color', ',', []));
      await Future.delayed(const Duration(milliseconds: 20));
    }
    await Future.delayed(const Duration(milliseconds: 500));
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

    // Channel name response
    final nameMatch = RegExp(r'^/ch/(\d{2})/config/name$').firstMatch(msg.address);
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
    final iconMatch = RegExp(r'^/ch/(\d{2})/config/icon$').firstMatch(msg.address);
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
    final colorMatch = RegExp(r'^/ch/(\d{2})/config/color$').firstMatch(msg.address);
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
    instruments[idx] = ChannelMapper.identify(
      name: ch.name,
      iconId: ch.iconId,
      colorId: ch.colorId,
    );
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
