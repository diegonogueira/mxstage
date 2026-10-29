import 'instrument_type.dart';

/// Identifies instrument type for an X32 channel using icon, name, and color.
///
/// Strategy (confidence descending):
///   1. Fuzzy name match PT-BR/EN  (what the operator typed — "Bumbo", "Bass")
///   2. Icon number → mapped type  (our icon table is unconfirmed on hardware)
///   3. Color category hint        (green=vocals, blue=keys, red=drums, etc.)
///   4. unknown                    (user corrects manually)
///
/// Name comes first since the 21/10 church log: on the real X32 the icon table
/// got almost every channel wrong ("Bumbo" → vocal, "Bass" → hi-hat, "Guitar" →
/// drums) while the names were plain. CONFIRM the icon IDs against hardware
/// before trusting them again.
class ChannelMapper {
  static InstrumentType identify({
    required String name,
    int? iconId,
    int? colorId,
  }) {
    // 0. No name = no instrument. 28/10: an unnamed input whose icon said
    //    "vocal" was a copy of the keys — the app put it on top as the lead
    //    voice and the piano came in three times. Unnamed channels only count
    //    once the musician says what they are (Mapear canais).
    if (isUnnamed(name)) return InstrumentType.unknown;

    // 1. Name fuzzy match — the operator's own label
    final fromName = _fromName(name);
    if (fromName != InstrumentType.unknown) return fromName;

    // 2. Icon
    if (iconId != null && iconId > 0) {
      final fromIcon = _fromIcon(iconId);
      if (fromIcon != InstrumentType.unknown) return fromIcon;
    }

    // 3. Color hint
    if (colorId != null) {
      final fromColor = _fromColor(colorId);
      if (fromColor != InstrumentType.unknown) return fromColor;
    }

    return InstrumentType.unknown;
  }

  // ── Icon map ───────────────────────────────────────────────────────────────
  // X32 icon IDs — CONFIRM AGAINST REAL HARDWARE (Maillot doc §icon table).
  // Numbers below are best-effort from community references.
  static InstrumentType _fromIcon(int id) => switch (id) {
        1 || 2 => InstrumentType.leadVocal, // mic types
        3 || 4 => InstrumentType.backingVocal,
        5 || 6 || 7 => InstrumentType.guitar,
        8 => InstrumentType.acoustic,
        9 || 10 => InstrumentType.bass,
        11 || 12 || 13 => InstrumentType.keys,
        14 => InstrumentType.piano,
        15 => InstrumentType.kick,
        16 => InstrumentType.snare,
        17 => InstrumentType.hihat,
        18 || 19 => InstrumentType.overhead,
        20 || 21 || 22 => InstrumentType.drums,
        23 || 24 => InstrumentType.sax,
        25 || 26 => InstrumentType.brass,
        27 || 28 => InstrumentType.strings,
        _ => InstrumentType.unknown,
      };

  // ── Name fuzzy match ───────────────────────────────────────────────────────
  static InstrumentType _fromName(String name) {
    final n = name.toLowerCase().trim();

    // Vocals — check before guitar to avoid "voz" matching nothing
    if (_any(n, ['lead', 'voz lead', 'vocal lead', 'voc lead', 'solo'])) {
      return InstrumentType.leadVocal;
    }
    if (_any(n, [
      'voz', 'voc', 'vox', 'vocal', 'voice', 'mic', 'microfone', 'canto',
    ])) {
      // Back vocals have BG / back / bg / backing in the name
      if (_any(n, ['bg', 'back', 'backing', 'bv', 'coro', 'choir', 'bgv'])) {
        return InstrumentType.backingVocal;
      }
      return InstrumentType.leadVocal;
    }

    // Drums — specific first, generic last
    if (_any(n, ['kick', 'bumbo', 'bd', 'bass drum'])) return InstrumentType.kick;
    if (_any(n, ['snare', 'caixa', 'sd'])) return InstrumentType.snare;
    if (_any(n, ['hihat', 'hi-hat', 'hh', 'hat'])) return InstrumentType.hihat;
    if (_any(n, ['overhead', 'over', 'oh ', ' oh', 'pratos', 'cymbal', 'cymb'])) {
      return InstrumentType.overhead;
    }
    if (_any(n, ['tom', 'floor', 'rack', 'surdo'])) return InstrumentType.percussion;
    if (_any(n, ['bat', 'drum', 'perc', 'room', 'ambience'])) return InstrumentType.drums;

    // Strings / guitar family
    if (_any(n, ['violao', 'violão', 'acoustic', 'nylon'])) {
      return InstrumentType.acoustic;
    }
    if (_any(n, ['bass', 'baixo', 'bx', 'bs'])) return InstrumentType.bass;
    if (_any(n, ['guitar', 'guitarra', 'gtr', 'gt', 'guita', 'git'])) {
      return InstrumentType.guitar;
    }

    // Keys
    if (_any(n, ['piano', 'grand'])) return InstrumentType.piano;
    if (_any(n, [
      'teclado', 'tecl', 'key', 'keys', 'kbd', 'synth', 'organ', 'orgao', 'órgão',
    ])) {
      return InstrumentType.keys;
    }

    // Winds / brass
    if (_any(n, ['sax', 'saxofone'])) return InstrumentType.sax;
    if (_any(n, ['trompete', 'trombone', 'trumpet', 'brass', 'metal', 'horn', 'flute', 'flauta'])) {
      return InstrumentType.brass;
    }
    if (_any(n, ['violino', 'violin', 'viola', 'cello', 'cordas', 'string'])) {
      return InstrumentType.strings;
    }

    return InstrumentType.unknown;
  }

  static final _defaultName = RegExp(r'^ch\s*\d+$', caseSensitive: false);

  /// Empty, or the app's placeholder "Ch 25".
  static bool isUnnamed(String name) =>
      name.trim().isEmpty || _defaultName.hasMatch(name.trim());

  static bool _any(String name, List<String> keywords) =>
      keywords.any((k) => name.contains(k));

  // ── Color hint ─────────────────────────────────────────────────────────────
  // X32 color IDs: 0=OFF, 1=RD, 2=GN, 3=YE, 4=BL, 5=MG, 6=CY, 7=WH
  // Common conventions (not universal):
  //   GN(2) = vocals, BL(4) = keys, RD(1) = drums/perc, YE(3) = guitars
  static InstrumentType _fromColor(int id) => switch (id) {
        2 => InstrumentType.leadVocal, // green → vocals
        4 => InstrumentType.keys, // blue → keys
        1 => InstrumentType.kick, // red → drums (weak signal)
        _ => InstrumentType.unknown,
      };
}
