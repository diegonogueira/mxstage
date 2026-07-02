/// X32 Probe — discovers a mixer (or simulator) and shows live meters.
///
/// Usage: dart run tools/probe.dart [ip]
///   ip  optional target IP (default: broadcast + localhost)
///
/// Acceptance criterion for M0:
///   Discovers X32-SIM, reads 32 channel names, shows scrolling meter bars.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../lib/osc/osc_codec.dart';
import '../lib/osc/x32_protocol.dart';

void main(List<String> args) async {
  final targetIp = args.isNotEmpty ? args[0] : null;

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;

  print('[PROBE] Listening on port ${socket.port}');

  String? mixerIp;
  String? mixerName;

  // Discovery targets
  final targets = <String>['127.0.0.1'];
  if (targetIp != null) targets.insert(0, targetIp);
  if (targetIp == null) targets.add('255.255.255.255');

  // Send /xinfo to all targets
  final xinfoPacket = encodeOsc('/xinfo', ',', []);
  for (final ip in targets) {
    try {
      socket.send(xinfoPacket, InternetAddress(ip), kX32Port);
    } catch (_) {}
  }

  // Also try /info
  final infoPacket = encodeOsc('/info', ',', []);
  for (final ip in targets) {
    try {
      socket.send(infoPacket, InternetAddress(ip), kX32Port);
    } catch (_) {}
  }

  // Wait for discovery response (up to 3s)
  print('[PROBE] Searching for mixer...');
  final discoveryTimer = Timer(const Duration(seconds: 3), () {
    if (mixerIp == null) {
      print('[PROBE] No mixer found. Is the simulator running?');
      socket.close();
      exit(1);
    }
  });

  // Receive loop
  socket.listen((event) async {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;

    final msg = decodeOsc(dg.data);

    if ((msg.address == '/xinfo' || msg.address == '/info') && mixerIp == null) {
      discoveryTimer.cancel();
      if (msg.address == '/xinfo' && msg.args.length >= 3) {
        mixerIp = msg.args[0] as String;
        mixerName = msg.args[1] as String;
        final model = msg.args[2] as String;
        final fw = msg.args.length > 3 ? msg.args[3] as String : '';
        print('[PROBE] Found: $mixerName ($model fw=$fw) at $mixerIp\n');
      } else if (msg.args.length >= 2) {
        mixerIp = dg.address.address;
        mixerName = msg.args[1] as String;
        print('[PROBE] Found: $mixerName at $mixerIp\n');
      }

      // Read channel names
      await _readChannelNames(socket, dg.address);

      // Subscribe to meters
      print('[PROBE] Subscribing to meters (Ctrl+C to stop)...\n');
      _subscribeMeters(socket, dg.address);
      return;
    }

    // Channel name response
    final nameMatch = RegExp(r'^/ch/(\d{2})/config/name$').firstMatch(msg.address);
    if (nameMatch != null && msg.args.isNotEmpty) {
      final ch = nameMatch.group(1);
      final name = msg.args[0] as String;
      print('  ch $ch: $name');
      return;
    }

    // Meter blob
    if (msg.address == kMeterBank && msg.args.isNotEmpty) {
      final raw = msg.args[0];
      final blob = raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
      _printMeters(decodeMeterBlob(blob));
    }
  });
}

Future<void> _readChannelNames(RawDatagramSocket socket, InternetAddress addr) async {
  print('[PROBE] Reading channel names...');
  for (var ch = 1; ch <= kInputChannelCount; ch++) {
    final address = '/ch/${ch.toString().padLeft(2, '0')}/config/name';
    socket.send(encodeOsc(address, ',', []), addr, kX32Port);
    await Future.delayed(const Duration(milliseconds: 20));
  }
  await Future.delayed(const Duration(milliseconds: 200));
  print('');
}

Timer? _renewTimer;

void _subscribeMeters(RawDatagramSocket socket, InternetAddress addr) {
  _renewTimer?.cancel();
  final sub = encodeOsc('/meters', ',s', [kMeterBank]);
  socket.send(sub, addr, kX32Port);

  _renewTimer = Timer.periodic(Duration(milliseconds: kMeterRenewIntervalMs), (_) {
    socket.send(sub, addr, kX32Port);
  });
}

var _lastPrintMs = 0;

void _printMeters(List<double> levels) {
  final nowMs = DateTime.now().millisecondsSinceEpoch;
  if (nowMs - _lastPrintMs < 500) return; // throttle display to 2 Hz
  _lastPrintMs = nowMs;

  final sb = StringBuffer();
  sb.write('\r');
  for (var i = 0; i < 16 && i < levels.length; i++) {
    final bars = (levels[i] * 20).round().clamp(0, 20);
    final ch = (i + 1).toString().padLeft(2);
    sb.write('$ch[${'|' * bars}${' ' * (20 - bars)}] ');
    if (i == 7) sb.write('\n   ');
  }
  stdout.write(sb.toString());
}
