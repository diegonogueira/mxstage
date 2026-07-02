import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../osc/osc_codec.dart';
import '../osc/x32_protocol.dart';

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

  ChannelInfo({required this.ch, required this.name, this.sendLevel = 0.75});
}

/// Handles all UDP/OSC communication with the X32.
///
/// I/O runs on dart:io async (not UI thread). Callers listen via ChangeNotifier.
class MixerClient extends ChangeNotifier {
  RawDatagramSocket? _socket;
  Timer? _renewTimer;
  Timer? _discoveryTimer;

  String? _mixerIp;
  String? _mixerName;
  String? _mixerModel;
  bool _connected = false;
  int _busIndex = 1; // 1..16
  bool _discovering = false;

  final List<DiscoveredMixer> discovered = [];
  final List<ChannelInfo> channels = List.generate(
    kInputChannelCount,
    (i) => ChannelInfo(ch: i + 1, name: 'Ch ${i + 1}'),
  );

  String? get mixerIp => _mixerIp;
  String? get mixerName => _mixerName;
  String? get mixerModel => _mixerModel;
  bool get isConnected => _connected;
  bool get isDiscovering => _discovering;
  int get busIndex => _busIndex;

  set busIndex(int v) {
    _busIndex = v.clamp(1, kMixBusCount);
    notifyListeners();
  }

  // ── Discovery ────────────────────────────────────────────────────────────

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

  // ── Connect ───────────────────────────────────────────────────────────────

  Future<void> connect(String ip, {int busIndex = 1}) async {
    await disconnect();

    _busIndex = busIndex;
    _mixerIp = ip;
    _connected = false;
    notifyListeners();

    _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

    // Request /xinfo to confirm connection and get mixer info
    _send(encodeOsc('/xinfo', ',', []));

    _socket!.listen(_onData);

    // Fetch channel names
    await _fetchChannelNames();

    _connected = true;
    notifyListeners();
  }

  Future<void> disconnect() async {
    _renewTimer?.cancel();
    _renewTimer = null;
    _socket?.close();
    _socket = null;
    _connected = false;
    _mixerIp = null;
    _mixerName = null;
    notifyListeners();
  }

  // ── Channel sends ────────────────────────────────────────────────────────

  void setChannelSend(int ch, double level) {
    if (!_connected || _socket == null) return;
    level = level.clamp(0.0, 1.0);

    final idx = ch - 1;
    if (idx >= 0 && idx < channels.length) {
      channels[idx].sendLevel = level;
    }

    final address = '/ch/${ch.toString().padLeft(2, '0')}/mix/${_busIndex.toString().padLeft(2, '0')}/level';
    _send(encodeOsc(address, ',f', [level]));
    notifyListeners();
  }

  // ── Meter subscription (called in M2; wired here for future use) ─────────

  void subscribeMeter() {
    if (_socket == null) return;
    _send(encodeOsc('/meters', ',s', [kMeterBank]));
    _renewTimer?.cancel();
    _renewTimer = Timer.periodic(
      Duration(milliseconds: kMeterRenewIntervalMs),
      (_) => _send(encodeOsc('/meters', ',s', [kMeterBank])),
    );
  }

  void unsubscribeMeter() {
    _renewTimer?.cancel();
    _renewTimer = null;
  }

  // ── Private ───────────────────────────────────────────────────────────────

  Future<void> _fetchChannelNames() async {
    if (_socket == null) return;
    for (var ch = 1; ch <= kInputChannelCount; ch++) {
      final address = '/ch/${ch.toString().padLeft(2, '0')}/config/name';
      _send(encodeOsc(address, ',', []));
      await Future.delayed(const Duration(milliseconds: 20));
    }
    // Allow responses to arrive
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

    final nameMatch = RegExp(r'^/ch/(\d{2})/config/name$').firstMatch(msg.address);
    if (nameMatch != null && msg.args.isNotEmpty) {
      final ch = int.parse(nameMatch.group(1)!);
      final idx = ch - 1;
      if (idx >= 0 && idx < channels.length) {
        channels[idx] = ChannelInfo(
          ch: ch,
          name: msg.args[0] as String,
          sendLevel: channels[idx].sendLevel,
        );
        notifyListeners();
      }
    }
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
