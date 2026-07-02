/// X32 Simulator — fake Behringer X32 for development without hardware.
///
/// Usage: dart run tools/x32_sim.dart
///
/// Supports:
///   /info, /xinfo        → discovery responses
///   /ch/NN/config/name   → synthetic channel names
///   /meters ,s "/meters/13"  → subscription; emits meter blobs every 50ms
///   /ch/NN/mix/MM/level  → logs received send writes to stdout
///
/// Run probe.dart in another terminal to verify.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../lib/osc/osc_codec.dart';
import '../lib/osc/x32_protocol.dart';

const _simIp = '127.0.0.1';
const _simName = 'X32-SIM';
const _simModel = 'X32';
const _simFirmware = '4.07';

// Synthetic channel names (band scenario)
const _channelNames = [
  'Voz Lead', 'Voz Back 1', 'Voz Back 2', 'Voz Back 3',
  'Guitarra', 'Guitarra 2', 'Baixo', 'Teclado 1',
  'Teclado 2', 'Piano', 'Violao', 'Sax',
  'Bateria Kick', 'Bateria Snare', 'Bateria HiHat', 'Bateria OH L',
  'Bateria OH R', 'Tom 1', 'Tom 2', 'Tom 3',
  'Overhead L', 'Overhead R', 'Room', 'Metais',
  'Ch 25', 'Ch 26', 'Ch 27', 'Ch 28',
  'Ch 29', 'Ch 30', 'Ch 31', 'Ch 32',
];

void main() async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kX32Port);
  print('[SIM] X32 Simulator running on UDP port $kX32Port');
  print('[SIM] Ctrl+C to stop\n');

  // Meter subscription state: map port → InternetAddress
  final subscribers = <int, InternetAddress>{};

  // Start meter emission loop
  _emitMetersLoop(socket, subscribers);

  await for (final event in socket) {
    if (event != RawSocketEvent.read) continue;
    final dg = socket.receive();
    if (dg == null) continue;

    final msg = decodeOsc(dg.data);
    _handleMessage(socket, dg.address, dg.port, msg, subscribers);
  }
}

void _handleMessage(
  RawDatagramSocket socket,
  InternetAddress src,
  int srcPort,
  OscMessage msg,
  Map<int, InternetAddress> subscribers,
) {
  switch (msg.address) {
    case '/info':
      _send(socket, src, srcPort,
          encodeOsc('/info', ',ssss', ['1.0', _simName, _simModel, _simFirmware]));

    case '/xinfo':
      _send(socket, src, srcPort,
          encodeOsc('/xinfo', ',ssss', [_simIp, _simName, _simModel, _simFirmware]));

    case '/meters':
      // /meters ,s "/meters/13"  — subscribe
      if (msg.args.isNotEmpty && msg.args[0] == kMeterBank) {
        subscribers[srcPort] = src;
        print('[SIM] Meter subscription from ${src.address}:$srcPort');
      }

    default:
      // /ch/NN/config/name (GET — no args)
      final nameMatch = RegExp(r'^/ch/(\d{2})/config/name$').firstMatch(msg.address);
      if (nameMatch != null && msg.args.isEmpty) {
        final ch = int.parse(nameMatch.group(1)!) - 1;
        final name = ch < _channelNames.length ? _channelNames[ch] : 'Ch ${ch + 1}';
        _send(socket, src, srcPort, encodeOsc(msg.address, ',s', [name]));
        return;
      }

      // /ch/NN/mix/MM/level ,f <val>
      final sendMatch = RegExp(r'^/ch/(\d{2})/mix/(\d{2})/level$').firstMatch(msg.address);
      if (sendMatch != null && msg.args.isNotEmpty) {
        final ch = sendMatch.group(1);
        final bus = sendMatch.group(2);
        final val = msg.args[0] as double;
        print('[SIM] SEND ch=$ch bus=$bus float=${val.toStringAsFixed(4)}');
        return;
      }
  }
}

// Synthetic meter scenario: simulates a band with varying dynamics.
final _rng = Random();
final _levels = List.generate(48, (i) {
  // Active channels have a base level; inactive ones stay quiet.
  if (i < 12) return 0.3 + _rng.nextDouble() * 0.3; // band channels
  if (i < 20) return 0.05 + _rng.nextDouble() * 0.1; // drums
  return 0.0;
});
var _tick = 0;

void _emitMetersLoop(
  RawDatagramSocket socket,
  Map<int, InternetAddress> subscribers,
) {
  // Timer.periodic alternative using async loop
  Future.delayed(Duration(milliseconds: kMeterUpdateIntervalMs), () async {
    while (true) {
      _tick++;
      _updateSyntheticLevels();

      if (subscribers.isNotEmpty) {
        final blob = _buildMeterBlob(_levels);
        final packet = encodeOsc(kMeterBank, ',b', [blob]);
        for (final entry in subscribers.entries) {
          _send(socket, entry.value, entry.key, packet);
        }
      }

      await Future.delayed(Duration(milliseconds: kMeterUpdateIntervalMs));
    }
  });
}

void _updateSyntheticLevels() {
  // Simulate: keyboard surge at tick 100, drop at tick 200
  // Vocal rests at tick 150, returns at tick 250
  final t = _tick;

  // Keyboard (ch 8, idx 7): surges
  if (t >= 100 && t < 200) {
    _levels[7] = (_levels[7] + 0.05).clamp(0.0, 0.95);
  } else {
    _levels[7] = (_levels[7] - 0.01).clamp(0.05, 0.95);
  }

  // Lead vocal (ch 1, idx 0): rests
  if (t >= 150 && t < 250) {
    _levels[0] = (_levels[0] - 0.05).clamp(0.0, 0.95);
  } else {
    _levels[0] = (_levels[0] + 0.02).clamp(0.0, 0.6);
  }

  // Natural fluctuation for all active channels
  for (var i = 0; i < 12; i++) {
    _levels[i] += (_rng.nextDouble() - 0.5) * 0.02;
    _levels[i] = _levels[i].clamp(0.01, 0.98);
  }
}

Uint8List _buildMeterBlob(List<double> levels) {
  // Interior: [uint32 LE count][N × float32 LE]
  final bd = ByteData(4 + levels.length * 4);
  bd.setUint32(0, levels.length, Endian.little);
  for (var i = 0; i < levels.length; i++) {
    bd.setFloat32(4 + i * 4, levels[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

void _send(RawDatagramSocket socket, InternetAddress addr, int port, Uint8List data) {
  try {
    socket.send(data, addr, port);
  } catch (_) {}
}
