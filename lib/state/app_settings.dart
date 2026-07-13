import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'instrument_type.dart';

/// Persistência leve de preferências do app (`shared_preferences`).
///
/// Guarda:
///  - o bus da transmissão ("Live bus"), para o modo Stage ocultá-lo do picker;
///  - o último bus de retorno do Stage escolhido **por mesa** (reabre nele);
///  - o preset de gênero escolhido **por mesa**;
///  - as sobreposições manuais de canal→instrumento **por mesa** (o músico
///    corrige o que a mesa nomeou errado; ver [instrumentOverrides]).
///
/// O que NÃO guardamos de propósito: a auto-detecção de instrumentos (recalculada
/// da mesa a cada conexão — só o *override* manual sobre ela é persistido) e o
/// estado do Auto-Mix (sempre começa desligado).
/// Preferências por mesa são chaveadas pelo nome da mesa (`mixerName`).
class AppSettings {
  AppSettings._();

  static const _kLiveBus = 'live_bus';
  static const _kDebugMode = 'debug_mode';

  static String _stageBusKey(String mixer) => 'stage_bus:$mixer';
  static String _genreKey(String mixer) => 'genre:$mixer';
  static String _overrideKey(String mixer) => 'instr_override:$mixer';
  static String _boostKey(String mixer) => 'ch_boost:$mixer';

  /// Bus atualmente designado como o da transmissão, ou `null` se nunca definido.
  static Future<int?> liveBus() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_kLiveBus);
    return (v != null && v >= 1) ? v : null;
  }

  /// Marca [bus] como o bus da transmissão (chamado ao entrar/trocar no Live).
  static Future<void> setLiveBus(int bus) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLiveBus, bus);
  }

  /// Modo debug (global, por device). Desligado por padrão: sem ele o app **não
  /// grava** o log de diagnóstico e o botão de exportar fica escondido. Fora do
  /// [clearAll] de propósito — é um toggle de dev, não uma preferência de mesa.
  static Future<bool> debugMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kDebugMode) ?? false;
  }

  static Future<void> setDebugMode(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kDebugMode, on);
  }

  /// Último bus de retorno do Stage usado nesta [mixer], ou `null` se nunca.
  static Future<int?> stageBus(String mixer) async {
    if (mixer.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getInt(_stageBusKey(mixer));
    return (v != null && v >= 1) ? v : null;
  }

  /// Lembra [bus] como o último bus de retorno do Stage nesta [mixer].
  static Future<void> setStageBus(String mixer, int bus) async {
    if (mixer.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stageBusKey(mixer), bus);
  }

  /// Nome do preset de gênero salvo para esta [mixer] (`Genre.name`), ou `null`.
  static Future<String?> genreName(String mixer) async {
    if (mixer.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_genreKey(mixer));
  }

  /// Salva o preset de gênero (`Genre.name`) escolhido para esta [mixer].
  static Future<void> setGenreName(String mixer, String genreName) async {
    if (mixer.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_genreKey(mixer), genreName);
  }

  /// Sobreposições manuais de canal→instrumento desta [mixer]: canal (1-based) →
  /// tipo. Vazio se nunca ajustado. Parse tolerante — chaves não-numéricas e
  /// nomes de enum inválidos (ex.: de uma versão futura) são ignorados.
  static Future<Map<int, InstrumentType>> instrumentOverrides(
      String mixer) async {
    if (mixer.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_overrideKey(mixer));
    if (raw == null || raw.isEmpty) return {};
    final result = <int, InstrumentType>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final ch = int.tryParse(key.toString());
          if (ch == null || value is! String) return;
          try {
            result[ch] = InstrumentType.values.byName(value);
          } catch (_) {
            // nome de enum desconhecido — ignora
          }
        });
      }
    } catch (_) {
      return {};
    }
    return result;
  }

  /// Define (ou remove, com [type] `null`) o override do canal [ch] nesta
  /// [mixer]. Read-modify-write do blob JSON; apaga a chave se ficar vazio.
  static Future<void> setInstrumentOverride(
      String mixer, int ch, InstrumentType? type) async {
    if (mixer.isEmpty) return;
    final current = await instrumentOverrides(mixer);
    if (type == null) {
      current.remove(ch);
    } else {
      current[ch] = type;
    }
    final prefs = await SharedPreferences.getInstance();
    if (current.isEmpty) {
      await prefs.remove(_overrideKey(mixer));
      return;
    }
    final encoded = jsonEncode(
      {for (final e in current.entries) e.key.toString(): e.value.name},
    );
    await prefs.setString(_overrideKey(mixer), encoded);
  }

  /// Remove todos os overrides desta [mixer] (volta tudo à auto-detecção).
  static Future<void> clearInstrumentOverrides(String mixer) async {
    if (mixer.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_overrideKey(mixer));
  }

  // ── Reforço por canal (boost, dB) por mesa ─────────────────────────────────

  /// Reforços salvos desta [mixer] — ch (1-based) → dB. Vazio se não houver.
  static Future<Map<int, double>> channelBoosts(String mixer) async {
    if (mixer.isEmpty) return {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_boostKey(mixer));
    if (raw == null || raw.isEmpty) return {};
    final result = <int, double>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final ch = int.tryParse(key.toString());
          final db = (value is num) ? value.toDouble() : null;
          if (ch != null && db != null && db != 0) result[ch] = db;
        });
      }
    } catch (_) {
      return {};
    }
    return result;
  }

  /// Define (ou remove, com [db] `0`) o reforço do canal [ch] nesta [mixer].
  static Future<void> setChannelBoost(String mixer, int ch, double db) async {
    if (mixer.isEmpty) return;
    final current = await channelBoosts(mixer);
    if (db == 0) {
      current.remove(ch);
    } else {
      current[ch] = db;
    }
    final prefs = await SharedPreferences.getInstance();
    if (current.isEmpty) {
      await prefs.remove(_boostKey(mixer));
      return;
    }
    final encoded = jsonEncode(
      {for (final e in current.entries) e.key.toString(): e.value},
    );
    await prefs.setString(_boostKey(mixer), encoded);
  }

  /// Zera todos os reforços desta [mixer].
  static Future<void> clearChannelBoosts(String mixer) async {
    if (mixer.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_boostKey(mixer));
  }

  /// Apaga TODAS as preferências que o app grava (Live bus + bus/gênero/overrides
  /// por mesa). Remove só as nossas chaves — não toca em prefs de plugins.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final ours = prefs.getKeys().where(
          (k) =>
              k == _kLiveBus ||
              k.startsWith('stage_bus:') ||
              k.startsWith('genre:') ||
              k.startsWith('instr_override:') ||
              k.startsWith('ch_boost:'),
        );
    for (final k in ours.toList()) {
      await prefs.remove(k);
    }
  }
}
