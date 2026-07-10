import 'package:shared_preferences/shared_preferences.dart';

/// Persistência leve de preferências do app (`shared_preferences`).
///
/// Guarda:
///  - o bus da transmissão ("Live bus"), para o modo Stage ocultá-lo do picker;
///  - o último bus de retorno do Stage escolhido **por mesa** (reabre nele);
///  - o preset de gênero escolhido **por mesa**.
///
/// O que NÃO guardamos de propósito: mapeamento de instrumentos (auto-detectado
/// da mesa a cada conexão) e o estado do Auto-Mix (sempre começa desligado).
/// Preferências por mesa são chaveadas pelo nome da mesa (`mixerName`).
class AppSettings {
  AppSettings._();

  static const _kLiveBus = 'live_bus';

  static String _stageBusKey(String mixer) => 'stage_bus:$mixer';
  static String _genreKey(String mixer) => 'genre:$mixer';

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

  /// Apaga TODAS as preferências que o app grava (Live bus + bus/gênero por
  /// mesa). Remove só as nossas chaves — não toca em prefs de plugins.
  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final ours = prefs.getKeys().where(
          (k) =>
              k == _kLiveBus ||
              k.startsWith('stage_bus:') ||
              k.startsWith('genre:'),
        );
    for (final k in ours.toList()) {
      await prefs.remove(k);
    }
  }
}
