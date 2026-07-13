import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Log de diagnóstico da sessão — JSONL, um registro por linha.
///
/// Grava **exatamente o que o Auto-Mix enxerga e decide**, tick a tick, mais os
/// eventos que moldam a decisão (remapeamento de instrumento, reforço/boost,
/// troca de gênero/bus). O engine só reage ao nível (dB por canal) — nunca ao
/// áudio — então reproduzir estes registros no mesmo engine (Dart puro) recria a
/// sessão ao vivo praticamente igual, sem mesa e sem áudio (ver `tools/replay.dart`).
///
/// O I/O de arquivo mora aqui (camada state); **nunca** no engine — o engine é
/// headless, zero I/O (invariante do projeto).
///
/// O buffer é mantido em memória e escrito num arquivo só na hora de exportar,
/// que aí vai pelo share sheet (WhatsApp/Files/Drive/e-mail).
class SessionLogger {
  SessionLogger({this.maxRecords = 30000});

  /// Teto rígido pra um culto longo não crescer o buffer sem limite
  /// (~8h a 1 Hz). Passou disso, para de acumular e marca truncado.
  final int maxRecords;

  final List<String> _lines = [];
  DateTime? _startedAt;
  bool _capped = false;

  /// Só grava quando ligado (espelha o Modo debug). Desligado = nada é
  /// acumulado, e [writeToFile] devolve `null`.
  bool enabled = false;

  bool get isRecording => enabled && _startedAt != null;
  int get recordCount => _lines.length;

  int _ms() => _startedAt == null
      ? 0
      : DateTime.now().difference(_startedAt!).inMilliseconds;

  /// Descarta tudo e para de gravar (chamado ao desligar o Modo debug).
  void reset() {
    _lines.clear();
    _startedAt = null;
    _capped = false;
  }

  void _add(Map<String, Object?> record) {
    if (!enabled || _startedAt == null) return;
    if (_lines.length >= maxRecords) {
      _capped = true;
      return;
    }
    _lines.add(jsonEncode(record));
  }

  /// Arredonda pra reduzir o tamanho do arquivo. 0.1 dB fica muito abaixo da
  /// zona morta (1 dB) e do passo (2 dB), então o replay decide igual.
  static double _r1(double v) => (v * 10).roundToDouble() / 10;
  static double _r4(double v) => (v * 10000).roundToDouble() / 10000;

  /// Inicia uma sessão nova (limpa o buffer anterior). No-op se desligado.
  void start({String? mixerName, String? model, required int bus}) {
    if (!enabled) return;
    _startedAt = DateTime.now();
    _lines.clear();
    _capped = false;
    _add({
      'type': 'session',
      't': 0,
      'startedAt': _startedAt!.toIso8601String(),
      'mixer': mixerName,
      'model': model,
      'bus': bus,
    });
  }

  /// Snapshot no momento em que o Auto-Mix é ligado: baseline de cada canal,
  /// instrumento **detectado vs efetivo** (mostra o remapeamento manual), boost,
  /// gênero e master. É a "foto da configuração" — auditoria da mesa de brinde.
  void activate({
    required Map<int, double> baseline,
    required List<Map<String, Object?>> channels,
    required String genre,
    required double master,
  }) {
    _add({
      'type': 'activate',
      't': _ms(),
      'genre': genre,
      'master': _r1(master),
      'baseline': {
        for (final e in baseline.entries) '${e.key}': _r4(e.value),
      },
      'channels': channels,
    });
  }

  /// Um tick de correção (1/s): os 32 níveis (dB) que entraram no engine, a
  /// referência C e os comandos enviados (ch → float). Gravado todo tick, mesmo
  /// sem comando, pra mostrar a trajetória do sinal.
  void tick({
    required List<double> meterDb,
    double? refC,
    required Map<int, double> cmds,
  }) {
    _add({
      'type': 'tick',
      't': _ms(),
      if (refC != null) 'C': _r1(refC),
      'm': [for (final v in meterDb) _r1(v)],
      if (cmds.isNotEmpty)
        'cmd': {for (final e in cmds.entries) '${e.key}': _r4(e.value)},
    });
  }

  /// Evento pontual do usuário/estado (boost, override, gênero, mute, bus…).
  void event(String name, [Map<String, Object?> data = const {}]) {
    _add({'type': 'event', 't': _ms(), 'event': name, ...data});
  }

  /// Escreve o buffer num arquivo temporário e devolve o caminho (pra o share
  /// sheet). Retorna `null` se nada foi gravado ainda.
  Future<String?> writeToFile() async {
    if (_startedAt == null || _lines.isEmpty) return null;

    final footer = jsonEncode({
      'type': 'export',
      't': _ms(),
      'records': _lines.length,
      'capped': _capped,
    });

    final dir = await getTemporaryDirectory();
    final stamp = _startedAt!
        .toIso8601String()
        .replaceAll(':', '')
        .replaceAll('.', '')
        .replaceAll('-', '');
    final file = File('${dir.path}/mxwise-diagnostico-$stamp.jsonl');
    await file.writeAsString('${_lines.join('\n')}\n$footer\n', flush: true);
    return file.path;
  }
}
