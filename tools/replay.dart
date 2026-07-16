// Replay de sessão — roda o log de diagnóstico (JSONL) exportado do celular no
// MESMO AutoMixEngine (Dart puro), sem mesa e sem áudio, e explica por que cada
// canal subiu, desceu ou sumiu.
//
// O engine só reage ao nível (dB por canal) — nunca ao áudio — então isto
// reproduz a sessão ao vivo tick a tick. Para cada canal, recalcula o alvo que o
// engine perseguiu e sinaliza quando ele QUIS mexer mais mas bateu num limite
// (teto de boost, piso), que é a assinatura de "guitarra alta / teclado sumiu".
//
// Uso:  dart run tools/replay.dart <caminho-do-log.jsonl>
//
// Não tem Flutter nem I/O de socket — é só análise offline.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../lib/engine/auto_mix_engine.dart';
import '../lib/osc/osc_codec.dart';
import '../lib/state/genre_presets.dart';
import '../lib/state/instrument_type.dart';

const _params = EngineParams(); // mesmos defaults do app

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('uso: dart run tools/replay.dart <log.jsonl>');
    exit(64);
  }
  final file = File(args.first);
  if (!file.existsSync()) {
    stderr.writeln('arquivo não encontrado: ${args.first}');
    exit(66);
  }

  final records = <Map<String, dynamic>>[];
  for (final line in file.readAsLinesSync()) {
    final s = line.trim();
    if (s.isEmpty) continue;
    try {
      records.add(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      stderr.writeln('linha ignorada (JSON inválido): $s');
    }
  }

  final replay = _Replay();
  for (final r in records) {
    switch (r['type']) {
      case 'session':
        replay.onSession(r);
      case 'activate':
        replay.onActivate(r);
      case 'event':
        replay.onEvent(r);
      case 'tick':
        replay.onTick(r);
      case 'export':
        replay.onExport(r);
    }
  }
  replay.report();
}

InstrumentType _instr(String? name) {
  if (name == null) return InstrumentType.unknown;
  for (final t in InstrumentType.values) {
    if (t.name == name) return t;
  }
  return InstrumentType.unknown;
}

Genre _genre(String? name) {
  if (name == null) return Genre.general;
  for (final g in Genre.values) {
    if (g.name == name) return g;
  }
  return Genre.general;
}

/// Estatística acumulada por canal ao longo do replay.
class _ChStat {
  String name = '';
  InstrumentType detected = InstrumentType.unknown;
  InstrumentType effective = InstrumentType.unknown;
  double boost = 0;
  double baselineDb = 0;

  int ticksActive = 0;
  double meterMin = 999, meterMax = -999, meterSum = 0;
  double? sendFirstDb, sendLastDb;
  double sendMinDb = 999, sendMaxDb = -999;

  // Quantos ticks o engine QUIS ir além de um limite (revela o gargalo).
  int cappedHigh = 0; // queria subir mais, travou no teto de boost/0 dB
  int cappedLow = 0; // queria descer além do piso
  double wantedAboveCeilSum = 0; // quanto (dB) a mais queria, somado

  double get meterAvg => ticksActive == 0 ? -90 : meterSum / ticksActive;
}

class _Replay {
  final _engine = AutoMixEngine(params: _params);
  final _stats = <int, _ChStat>{};
  var _instruments = List<InstrumentType>.filled(32, InstrumentType.unknown);
  final _baselineDb = <int, double>{};
  Genre _genreSel = Genre.general;
  double _master = 0;
  int _tickCount = 0;
  bool _activated = false;

  void onSession(Map<String, dynamic> r) {
    print('══ Sessão ═══════════════════════════════════════════════════════');
    print('  mesa: ${r['mixer'] ?? '?'}   modelo: ${r['model'] ?? '?'}'
        '   bus: ${r['bus']}');
    print('  início: ${r['startedAt']}');
  }

  void onActivate(Map<String, dynamic> r) {
    _activated = true;
    _genreSel = _genre(r['genre'] as String?);
    _master = (r['master'] as num?)?.toDouble() ?? 0;

    final baseline = <int, double>{};
    final baseMap = (r['baseline'] as Map).cast<String, dynamic>();
    baseMap.forEach((k, v) {
      baseline[int.parse(k)] = (v as num).toDouble();
    });

    _instruments = List<InstrumentType>.filled(32, InstrumentType.unknown);
    final channels = (r['channels'] as List).cast<Map<String, dynamic>>();
    for (final c in channels) {
      final ch = c['ch'] as int;
      final st = _stats.putIfAbsent(ch, () => _ChStat());
      st.name = (c['name'] as String?) ?? 'Ch $ch';
      st.detected = _instr(c['detected'] as String?);
      st.effective = _instr(c['effective'] as String?);
      st.boost = (c['boost'] as num?)?.toDouble() ?? 0;
      final bl = baseline[ch] ?? 0.0;
      st.baselineDb = floatToDb(bl);
      _baselineDb[ch] = st.baselineDb;
      if (ch >= 1 && ch <= 32) _instruments[ch - 1] = st.effective;
    }

    _engine.activate(baseline);
    _engine.masterDb = _master;
    _engine.boostDb = {
      for (final e in _stats.entries)
        if (e.value.boost != 0) e.key: e.value.boost,
    };

    print('\n── Ativação do Auto-Mix ─────────────────────────────────────────');
    print('  gênero: ${_genreSel.label}   master: ${_master.toStringAsFixed(1)} dB');
    print('  (detecção vs efetivo — "→" marca canal remapeado na mão)');
    final chs = _stats.keys.toList()..sort();
    for (final ch in chs) {
      final st = _stats[ch]!;
      if (st.detected == InstrumentType.unknown &&
          st.effective == InstrumentType.unknown &&
          st.name.startsWith('Ch ')) {
        continue; // canal sem nome e sem detecção — provavelmente vazio
      }
      final remap = st.detected != st.effective ? '  →' : '   ';
      final boost = st.boost != 0
          ? '  boost ${st.boost > 0 ? '+' : ''}${st.boost.toStringAsFixed(1)}'
          : '';
      final tgt = kGenrePresets[_genreSel]!.targetFor(st.effective) + st.boost;
      print('  ${_pad('ch$ch', 5)} ${_pad(st.name, 14)} '
          '${_pad(st.detected.label, 12)}$remap ${_pad(st.effective.label, 12)}'
          '  alvo ${_fmt(tgt)} dB$boost');
    }
  }

  void onEvent(Map<String, dynamic> r) {
    switch (r['event']) {
      case 'genre':
        _genreSel = _genre(r['genre'] as String?);
      case 'boost':
        final ch = r['ch'] as int;
        final db = (r['db'] as num).toDouble();
        if (db == 0) {
          _engine.boostDb.remove(ch);
        } else {
          _engine.boostDb[ch] = db;
        }
        _stats.putIfAbsent(ch, () => _ChStat()).boost = db;
      case 'override':
        final ch = r['ch'] as int;
        final eff = _instr(r['effective'] as String?);
        if (ch >= 1 && ch <= 32) _instruments[ch - 1] = eff;
        _stats.putIfAbsent(ch, () => _ChStat()).effective = eff;
    }
  }

  void onTick(Map<String, dynamic> r) {
    if (!_activated) return;
    _tickCount++;
    final meter = (r['m'] as List).map((e) => (e as num).toDouble()).toList();
    final c = (r['C'] as num?)?.toDouble();

    // Reproduz a decisão do engine com as MESMAS entradas.
    _engine.update(meter, _instruments, kGenrePresets[_genreSel]!);
    final sends = _engine.currentSendFloats; // ch → float

    // Mesmo gate adaptativo do engine: relativo ao canal mais alto, com piso
    // absoluto de silêncio.
    double? loudest;
    for (var i = 0; i < meter.length && i < 32; i++) {
      if (meter[i] > _params.silenceFloorDb) {
        loudest = (loudest == null) ? meter[i] : max(loudest, meter[i]);
      }
    }
    final effectiveGate = loudest == null
        ? _params.silenceFloorDb
        : max(loudest - _params.activeRangeDb, _params.silenceFloorDb);

    for (var i = 0; i < meter.length && i < 32; i++) {
      final ch = i + 1;
      final m = meter[i];
      if (m <= effectiveGate) continue; // silêncio / fora da janela — congela
      final st = _stats.putIfAbsent(ch, () => _ChStat());
      st.ticksActive++;
      st.meterMin = min(st.meterMin, m);
      st.meterMax = max(st.meterMax, m);
      st.meterSum += m;

      final sendF = sends[ch];
      if (sendF != null) {
        final sdb = floatToDb(sendF);
        st.sendFirstDb ??= sdb;
        st.sendLastDb = sdb;
        st.sendMinDb = min(st.sendMinDb, sdb);
        st.sendMaxDb = max(st.sendMaxDb, sdb);
      }

      // Onde o engine QUERIA colocar o send (antes do clamp) e o que travou.
      if (c != null) {
        final tgt = kGenrePresets[_genreSel]!.targetFor(_instruments[i]) +
            (_engine.boostDb[ch] ?? 0);
        final desired = c + _master + tgt - m;
        final baselineDb = _baselineDb[ch] ?? _params.sendFloorDb;
        final ceil = min(_params.sendCeilingDb, baselineDb + _params.maxBoostDb);
        if (desired > ceil + 1.0) {
          st.cappedHigh++;
          st.wantedAboveCeilSum += desired - ceil;
        } else if (desired < _params.sendFloorDb - 1.0) {
          st.cappedLow++;
        }
      }
    }
  }

  void onExport(Map<String, dynamic> r) {
    print('\n  (log com ${r['records']} registros'
        '${r['capped'] == true ? ', TRUNCADO no teto' : ''})');
  }

  void report() {
    print('\n══ Análise ($_tickCount ticks de correção ≈ ${_tickCount}s) ══════════');
    if (_tickCount == 0) {
      print('  Nenhum tick — o Auto-Mix não chegou a rodar nesta sessão.');
      return;
    }
    final chs = _stats.keys.where((ch) => _stats[ch]!.ticksActive > 0).toList()
      ..sort();

    print('  canal          instrumento    meter(mín/méd/máx)  send(dB)   observação');
    for (final ch in chs) {
      final st = _stats[ch]!;
      final flags = <String>[];
      if (st.effective == InstrumentType.unknown) {
        flags.add('NÃO IDENTIFICADO (alvo genérico)');
      }
      final capHiPct = 100 * st.cappedHigh / st.ticksActive;
      final capLoPct = 100 * st.cappedLow / st.ticksActive;
      if (capHiPct > 20) {
        final avgWant = st.wantedAboveCeilSum / max(1, st.cappedHigh);
        flags.add('queria +${avgWant.toStringAsFixed(0)}dB mas TRAVOU no teto '
            '(${capHiPct.toStringAsFixed(0)}% do tempo) → tende a SUMIR');
      }
      if (capLoPct > 20) {
        flags.add('empurrado pro PISO (${capLoPct.toStringAsFixed(0)}% do tempo) '
            '→ tende a ESTOURAR');
      }
      final obs = flags.isEmpty ? 'ok' : flags.join('; ');
      print('  ${_pad('ch$ch ${st.name}', 14)} '
          '${_pad(st.effective.label, 13)} '
          '${_fmt(st.meterMin)}/${_fmt(st.meterAvg)}/${_fmt(st.meterMax)}   '
          '${_pad(st.sendLastDb == null ? '—' : _fmt(st.sendLastDb!), 7)}  $obs');
    }

    print('\n  Leitura rápida:');
    print('  • "NÃO IDENTIFICADO" ou instrumento errado → conferir NOME/ÍCONE do');
    print('    canal na mesa (é daí que sai o alvo). Este é o suspeito nº 1.');
    print('  • "TRAVOU no teto" = o canal tocou baixo demais; o engine só sobe');
    print('    até baseline+${_params.maxBoostDb.toStringAsFixed(0)}dB (maxBoostDb) e não alcança → o instrumento some.');
    print('  • "empurrado pro PISO" = alvo baixo demais p/ esse canal no gênero.');
  }

  static String _pad(String s, int n) =>
      s.length >= n ? s.substring(0, n) : s.padRight(n);
  static String _fmt(double db) =>
      db <= -90 ? '-inf' : db.toStringAsFixed(1);
}
