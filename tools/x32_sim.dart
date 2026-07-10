/// X32 Simulator — fake Behringer X32 for development without hardware.
///
/// Usage:
///   dart run tools/x32_sim.dart              # auto-sim scenario (scripted)
///   dart run tools/x32_sim.dart --interactive # manual stdin control
///   dart run tools/x32_sim.dart --web         # web faders at http://localhost:8080
///   dart run tools/x32_sim.dart --web 9000    # web control on a custom port
///
/// Supports:
///   /info, /xinfo        → discovery responses
///   /ch/NN/config/name   → synthetic channel names
///   /bus/NN/config/name  → synthetic mix-bus (monitor) names
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
///
/// Web mode (--web): a mixing-console page with one fader per instrument.
/// Dragging a fader sets that channel's input meter level in real time, so you
/// can simulate the band playing louder/softer and watch the app correct the
/// monitor sends live. Enabling --web disables the scripted auto-scenario.

import 'dart:convert';
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

// Synthetic mix-bus (monitor) names — buses 1..16. Names as a worship team
// would actually label them on the console (X32 caps names at 12 chars).
// Trailing empty strings mimic buses the engineer never named, so the app
// can show its "Bus N" fallback.
const _busNames = [
  'Ministro',  'Vocal 1',   'Vocal 2',    'Baixo',
  'Guita',     'Violao',    'Teclado',    'Bateria',
  'Metais',    'Sidefill',  '',           '',
  '',          '',          '',           '',
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

// Latest monitor send level written by the app per channel (any bus), for
// display in the web UI. null = the app never wrote a send for this channel.
final _lastSendPerCh = List<double?>.filled(32, null);

// Connected web-control clients (--web mode).
final _webClients = <WebSocket>[];

var _tick = 0;
var _autoSimEnabled = true;

void main(List<String> args) async {
  final interactive = args.contains('--interactive') || args.contains('-i');
  final (web, webPort) = _parseWebArgs(args);

  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, kX32Port);
  print('[SIM] X32 Simulator running on UDP port $kX32Port');
  if (web) {
    _autoSimEnabled = false;
    await _startWebServer(webPort);
    print('[SIM] Mode: WEB — mixing console at http://localhost:$webPort');
  } else if (interactive) {
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
      _resetLevels();
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

      final busNameMatch = RegExp(r'^/bus/(\d{2})/config/name$').firstMatch(msg.address);
      if (busNameMatch != null && msg.args.isEmpty) {
        final bus = int.parse(busNameMatch.group(1)!) - 1;
        final name = bus >= 0 && bus < _busNames.length ? _busNames[bus] : '';
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
          final chNum = int.parse(ch);
          if (chNum >= 1 && chNum <= 32) _lastSendPerCh[chNum - 1] = val;
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

      _broadcastWeb();

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

// Reset all channels to their initial (randomised) resting levels.
void _resetLevels() {
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
}

// ---------------------------------------------------------------------------
// Web control server (--web) — mixing console with one fader per instrument
// ---------------------------------------------------------------------------

(bool, int) _parseWebArgs(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--web' || a == '-w') {
      final next = i + 1 < args.length ? int.tryParse(args[i + 1]) : null;
      return (true, next ?? 8080);
    }
    if (a.startsWith('--web=')) {
      return (true, int.tryParse(a.substring('--web='.length)) ?? 8080);
    }
  }
  return (false, 8080);
}

Future<void> _startWebServer(int port) async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
  server.listen((req) async {
    if (req.uri.path == '/ws') {
      try {
        final ws = await WebSocketTransformer.upgrade(req);
        _webClients.add(ws);
        ws.add(jsonEncode({'type': 'config', 'names': _channelNames}));
        ws.listen(
          _handleWebMessage,
          onDone: () => _webClients.remove(ws),
          onError: (_) => _webClients.remove(ws),
        );
      } catch (_) {
        // upgrade failed — ignore
      }
    } else {
      req.response.headers.contentType = ContentType.html;
      req.response.write(_kIndexHtml);
      await req.response.close();
    }
  });
}

void _handleWebMessage(dynamic data) {
  try {
    final msg = jsonDecode(data as String) as Map<String, dynamic>;
    switch (msg['type']) {
      case 'set':
        final ch = (msg['ch'] as num).toInt();
        final level = (msg['level'] as num).toDouble();
        if (ch >= 1 && ch <= 32) {
          _rampTargets[ch - 1] = null;
          _levels[ch - 1] = level.clamp(0.0, 1.0);
        }
      case 'reset':
        _resetLevels();
    }
  } catch (_) {
    // malformed message — ignore
  }
}

void _broadcastWeb() {
  if (_webClients.isEmpty) return;
  final payload = jsonEncode({
    'type': 'levels',
    'levels': [
      for (var i = 0; i < 32; i++) double.parse(_levels[i].toStringAsFixed(4)),
    ],
    'sends': _lastSendPerCh,
  });
  for (final ws in List<WebSocket>.of(_webClients)) {
    try {
      ws.add(payload);
    } catch (_) {
      _webClients.remove(ws);
    }
  }
}

const _kIndexHtml = r'''<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>X32 SIM — Mesa de Instrumentos</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; font-family: system-ui, -apple-system, sans-serif; background:#0d1117; color:#e6edf3; }
  header { position:sticky; top:0; background:#161b22; padding:12px 16px; border-bottom:1px solid #30363d;
           display:flex; align-items:center; gap:14px; flex-wrap:wrap; z-index:10; }
  header h1 { font-size:16px; margin:0; font-weight:600; }
  .hint { font-size:12px; color:#8b949e; }
  .status { font-size:13px; padding:3px 10px; border-radius:12px; background:#21262d; font-weight:600; }
  .status.ok { color:#3fb950; }
  .status.bad { color:#f85149; }
  button { background:#21262d; color:#e6edf3; border:1px solid #30363d; border-radius:6px;
           padding:6px 12px; cursor:pointer; font-size:13px; }
  button:hover { background:#30363d; }
  .board { display:flex; flex-wrap:wrap; gap:10px; padding:16px; }
  .ch { width:76px; background:#161b22; border:1px solid #30363d; border-radius:8px;
        padding:8px 6px; display:flex; flex-direction:column; align-items:center; gap:6px; }
  .ch .name { font-size:11px; text-align:center; height:26px; line-height:13px; overflow:hidden; color:#c9d1d9; }
  .ch .val { font-size:13px; font-variant-numeric:tabular-nums; color:#58a6ff; font-weight:600; }
  .ch .send { font-size:10px; color:#8b949e; height:13px; font-variant-numeric:tabular-nums; }
  .fader-row { display:flex; gap:7px; height:210px; align-items:stretch; }
  .meter { width:9px; background:#21262d; border-radius:3px; position:relative; overflow:hidden; }
  .meter .fill { position:absolute; bottom:0; left:0; right:0;
                 background:linear-gradient(to top,#3fb950,#3fb950 60%,#d29922 82%,#f85149);
                 height:0%; transition:height .05s linear; }
  input[type=range] { writing-mode:vertical-lr; direction:rtl; width:24px; height:210px;
                      accent-color:#58a6ff; cursor:pointer; }
</style>
</head>
<body>
<header>
  <h1>&#127899; X32 SIM &mdash; Mesa de Instrumentos</h1>
  <span id="status" class="status bad">desconectado</span>
  <button id="reset">Reset</button>
  <span class="hint">Arraste os faders para simular os m&uacute;sicos tocando &mdash; a barra colorida &eacute; o n&iacute;vel captado; &ldquo;&rarr;&rdquo; &eacute; o retorno que o app est&aacute; enviando.</span>
</header>
<div class="board" id="board"></div>
<script>
  var board = document.getElementById("board");
  var statusEl = document.getElementById("status");
  var faders = [], fills = [], vals = [], sends = [];
  var initialized = false;
  var ws;

  function buildBoard(names) {
    board.innerHTML = "";
    faders = []; fills = []; vals = []; sends = [];
    for (var i = 0; i < 32; i++) {
      var card = document.createElement("div");
      card.className = "ch";

      var name = document.createElement("div");
      name.className = "name";
      name.textContent = (i + 1) + ". " + (names[i] || ("Ch " + (i + 1)));

      var val = document.createElement("div");
      val.className = "val";
      val.textContent = "0%";

      var row = document.createElement("div");
      row.className = "fader-row";
      var meter = document.createElement("div");
      meter.className = "meter";
      var fill = document.createElement("div");
      fill.className = "fill";
      meter.appendChild(fill);
      var fader = document.createElement("input");
      fader.type = "range";
      fader.min = "0"; fader.max = "1"; fader.step = "0.01"; fader.value = "0";
      (function (idx, f, v) {
        f.addEventListener("input", function () {
          v.textContent = Math.round(f.value * 100) + "%";
          send({ type: "set", ch: idx + 1, level: parseFloat(f.value) });
        });
      })(i, fader, val);
      row.appendChild(meter);
      row.appendChild(fader);

      var snd = document.createElement("div");
      snd.className = "send";
      snd.textContent = "";

      card.appendChild(name);
      card.appendChild(val);
      card.appendChild(row);
      card.appendChild(snd);
      board.appendChild(card);

      faders.push(fader); fills.push(fill); vals.push(val); sends.push(snd);
    }
  }

  function send(obj) {
    if (ws && ws.readyState === 1) ws.send(JSON.stringify(obj));
  }

  function connect() {
    ws = new WebSocket("ws://" + location.host + "/ws");
    ws.onopen = function () { statusEl.textContent = "conectado"; statusEl.className = "status ok"; };
    ws.onclose = function () {
      statusEl.textContent = "desconectado"; statusEl.className = "status bad";
      setTimeout(connect, 1000);
    };
    ws.onmessage = function (ev) {
      var m = JSON.parse(ev.data);
      if (m.type === "config") {
        initialized = false;
        buildBoard(m.names);
      } else if (m.type === "levels") {
        for (var i = 0; i < 32; i++) {
          var lv = m.levels[i];
          if (fills[i]) fills[i].style.height = Math.round(lv * 100) + "%";
          if (!initialized && faders[i]) {
            faders[i].value = lv;
            vals[i].textContent = Math.round(lv * 100) + "%";
          }
          if (sends[i]) {
            sends[i].textContent = (m.sends[i] == null)
              ? "" : ("→ " + Math.round(m.sends[i] * 100) + "%");
          }
        }
        initialized = true;
      }
    };
  }

  document.getElementById("reset").addEventListener("click", function () {
    initialized = false;
    send({ type: "reset" });
  });

  connect();
</script>
</body>
</html>''';
