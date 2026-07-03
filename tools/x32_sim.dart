/// X32 Simulator — fake Behringer X32 for development without hardware.
///
/// Usage:
///   dart run tools/x32_sim.dart              # auto-sim scenario (scripted)
///   dart run tools/x32_sim.dart --interactive # manual stdin control
///
/// Supports:
///   /info, /xinfo        → discovery responses
///   /ch/NN/config/name   → synthetic channel names
///   /meters ,s "/meters/13"  → subscription; emits meter blobs every 50ms
///   /ch/NN/mix/MM/level  → logs received send writes to stdout
///
/// Interactive commands (--interactive mode):
///   set <ch> <level>   — set channel ch (1-32) to level 0.0–1.0  e.g. "set 1 0.8"
///   ramp <ch> <level>  — smoothly ramp channel to target over ~2s
///   list               — show current levels for all active channels
///   reset              — reset all channels to initial levels
///   auto on|off        — enable/disable the scripted auto-scenario
///   help               — show this command list

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
  'Voz Lead',    'Voz Back 1', 'Voz Back 2', 'Voz Back 3',
  'Guitarra',    'Guitarra 2', 'Baixo',       'Teclado 1',
  'Teclado 2',   'Piano',      'Violao',      'Sax',
  'Bat Kick',    'Bat Snare',  'Bat HiHat',   'Bat OH L',
  'Bat OH R',    'Tom 1',      'Tom 2',        'Tom 3',
  'Overhead L',  'Overhead R', 'Room',         'Metais',
  'Ch 25', 'Ch 26', 'Ch 27', 'Ch 28',
  'Ch 29', 'Ch 30', 'Ch 31', 'Ch 32',
];

final _rng = Random();

// Current meter levels (indices 0..47 → channels 1..32 at [0..31], rest unused)
final _levels = List.generate(48, (i) {
  if (i < 12) return 0.3 + _rng.nextDouble() * 0.3; // band channels
  if (i < 20) return 0.05 + _rng.nextDouble() * 0.1; // drums
  return 0.0;
});

// Ramp targets: index → target level (null = no ramp active)
final _rampTargets = List<double?>.filled(48, null);

var _tick = 0;
var _autoSimEnabled = true;

void main(List<String> args) async {
  final interactive = args.contains('--interactive') || args.contains('-i');

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kX32Port);
  print('[SIM] X32 Simulator running on UDP port $kX32Port');
  if (interactive) {
    _autoSimEnabled = false;
    print('[SIM] Mode: INTERACTIVE — type "help" for commands');
  } else {
    print('[SIM] Mode: AUTO-SCENARIO — scripted level changes');
  }
  print('[SIM] Ctrl+C to stop\n');

  final subscribers = <int, InternetAddress>{};

  _emitMetersLoop(socket, subscribers);

  if (interactive) {
    _startStdinLoop();
  }

  await for (final event in socket) {
    if (event != RawSocketEvent.read) continue;
    final dg = socket.receive();
    if (dg == null) continue;
    final msg = decodeOsc(dg.data);
    _handleMessage(socket, dg.address, dg.port, msg, subscribers);
  }
}

// ---------------------------------------------------------------------------
// Interactive stdin command loop
// ---------------------------------------------------------------------------

void _startStdinLoop() {
  stdin.lineMode = true;
  stdin.echoMode = true;
  _printPrompt();

  stdin.transform(SystemEncoding().decoder).listen((line) {
    _handleCommand(line.trim());
    _printPrompt();
  });
}

void _printPrompt() => stdout.write('[SIM]> ');

void _handleCommand(String line) {
  if (line.isEmpty) return;
  final parts = line.split(RegExp(r'\s+'));
  final cmd = parts[0].toLowerCase();

  switch (cmd) {
    case 'set':
      if (parts.length < 3) {
        print('Usage: set <ch 1-32> <level 0.0-1.0>');
        return;
      }
      final ch = int.tryParse(parts[1]);
      final val = double.tryParse(parts[2]);
      if (ch == null || ch < 1 || ch > 32 || val == null) {
        print('Invalid args. ch=1-32, level=0.0-1.0');
        return;
      }
      _rampTargets[ch - 1] = null; // cancel any ramp
      _levels[ch - 1] = val.clamp(0.0, 1.0);
      final name = _channelNames[ch - 1];
      print('[SIM] ch $ch ($name) → ${val.toStringAsFixed(3)}');

    case 'ramp':
      if (parts.length < 3) {
        print('Usage: ramp <ch 1-32> <target 0.0-1.0>');
        return;
      }
      final ch = int.tryParse(parts[1]);
      final val = double.tryParse(parts[2]);
      if (ch == null || ch < 1 || ch > 32 || val == null) {
        print('Invalid args. ch=1-32, target=0.0-1.0');
        return;
      }
      _rampTargets[ch - 1] = val.clamp(0.0, 1.0);
      final name = _channelNames[ch - 1];
      print('[SIM] ramp ch $ch ($name) → ${val.toStringAsFixed(3)} (over ~2s)');

    case 'list':
      print('--- Channel levels ---');
      for (var i = 0; i < 32; i++) {
        final bar = _levelBar(_levels[i]);
        final ramp = _rampTargets[i] != null ? ' → ${_rampTargets[i]!.toStringAsFixed(2)}' : '';
        print('  ch ${(i + 1).toString().padLeft(2)} ${_channelNames[i].padRight(12)} '
            '${_levels[i].toStringAsFixed(3)} $bar$ramp');
      }
      print('----------------------');

    case 'reset':
      for (var i = 0; i < 48; i++) {
        _rampTargets[i] = null;
        if (i < 12) {
          _levels[i] = 0.3 + _rng.nextDouble() * 0.3;
        } else if (i < 20) {
          _levels[i] = 0.05 + _rng.nextDouble() * 0.1;
        } else {
          _levels[i] = 0.0;
        }
      }
      print('[SIM] Levels reset to initial values');

    case 'auto':
      if (parts.length < 2) {
        print('Usage: auto on|off');
        return;
      }
      _autoSimEnabled = parts[1].toLowerCase() == 'on';
      print('[SIM] Auto-scenario: ${_autoSimEnabled ? "ON" : "OFF"}');

    case 'help':
      print('''
Commands:
  set <ch> <level>   — set channel level (ch=1-32, level=0.0-1.0)
  ramp <ch> <level>  — smoothly ramp channel to target over ~2s
  list               — show current levels
  reset              — reset all to initial values
  auto on|off        — enable/disable scripted scenario
  help               — this message
''');

    default:
      print('Unknown command: $cmd  (type "help" for list)');
  }
}

String _levelBar(double v) {
  final filled = (v * 20).round().clamp(0, 20);
  return '[' + '█' * filled + '░' * (20 - filled) + ']';
}

// ---------------------------------------------------------------------------
// UDP message handling
// ---------------------------------------------------------------------------

// Tracked send levels per channel/bus: key = 'ch_bus', value = 0.0..1.0
final _sendLevels = <String, double>{};

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
      if (msg.args.isNotEmpty && msg.args[0] == kMeterBank) {
        subscribers[srcPort] = src;
        print('\n[SIM] Meter subscription from ${src.address}:$srcPort');
        _printPrompt();
      }

    default:
      final nameMatch = RegExp(r'^/ch/(\d{2})/config/name$').firstMatch(msg.address);
      if (nameMatch != null && msg.args.isEmpty) {
        final ch = int.parse(nameMatch.group(1)!) - 1;
        final name = ch < _channelNames.length ? _channelNames[ch] : 'Ch ${ch + 1}';
        _send(socket, src, srcPort, encodeOsc(msg.address, ',s', [name]));
        return;
      }

      final sendMatch = RegExp(r'^/ch/(\d{2})/mix/(\d{2})/level$').firstMatch(msg.address);
      if (sendMatch != null) {
        final ch = sendMatch.group(1)!;
        final bus = sendMatch.group(2)!;
        final key = '${ch}_$bus';

        if (msg.args.isEmpty) {
          // GET — return current tracked level (default 0.75)
          final level = _sendLevels[key] ?? 0.75;
          _send(socket, src, srcPort, encodeOsc(msg.address, ',f', [level]));
        } else {
          // SET — update and log
          final val = msg.args[0] as double;
          _sendLevels[key] = val;
          print('\n[SIM] SEND ch=$ch bus=$bus float=${val.toStringAsFixed(4)}');
          _printPrompt();
        }
        return;
      }
  }
}

// ---------------------------------------------------------------------------
// Meter emission loop
// ---------------------------------------------------------------------------

void _emitMetersLoop(
  RawDatagramSocket socket,
  Map<int, InternetAddress> subscribers,
) {
  Future.delayed(Duration(milliseconds: kMeterUpdateIntervalMs), () async {
    while (true) {
      _tick++;
      _updateLevels();

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

void _updateLevels() {
  // Apply ramps (step ~0.01 per tick at 50ms = ~0.2/s → ~5s full sweep)
  for (var i = 0; i < 48; i++) {
    final target = _rampTargets[i];
    if (target != null) {
      final diff = target - _levels[i];
      if (diff.abs() < 0.005) {
        _levels[i] = target;
        _rampTargets[i] = null;
      } else {
        _levels[i] += diff * 0.05; // exponential approach
      }
    }
  }

  if (!_autoSimEnabled) {
    // Only add tiny noise to non-zero channels for realism
    for (var i = 0; i < 32; i++) {
      if (_levels[i] > 0.01 && _rampTargets[i] == null) {
        _levels[i] += (_rng.nextDouble() - 0.5) * 0.005;
        _levels[i] = _levels[i].clamp(0.0, 1.0);
      }
    }
    return;
  }

  // Scripted scenario: keyboard surge at tick 100-200, vocal rest at 150-250
  final t = _tick;
  if (t >= 100 && t < 200) {
    _levels[7] = (_levels[7] + 0.05).clamp(0.0, 0.95);
  } else {
    _levels[7] = (_levels[7] - 0.01).clamp(0.05, 0.95);
  }
  if (t >= 150 && t < 250) {
    _levels[0] = (_levels[0] - 0.05).clamp(0.0, 0.95);
  } else {
    _levels[0] = (_levels[0] + 0.02).clamp(0.0, 0.6);
  }

  for (var i = 0; i < 12; i++) {
    _levels[i] += (_rng.nextDouble() - 0.5) * 0.02;
    _levels[i] = _levels[i].clamp(0.01, 0.98);
  }
}

Uint8List _buildMeterBlob(List<double> levels) {
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
