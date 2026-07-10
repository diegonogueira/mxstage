import 'package:shared_preferences/shared_preferences.dart';

/// Persistência leve de preferências do app (`shared_preferences`).
///
/// Hoje guarda apenas qual bus é o da transmissão ("Live bus"), para que o
/// modo Stage possa ocultá-lo do bus picker e o músico não o selecione.
class AppSettings {
  AppSettings._();

  static const _kLiveBus = 'live_bus';

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
}
