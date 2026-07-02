import 'instrument_type.dart';

/// Identifies instrument type for an X32 channel using icon, name, and color.
///
/// Strategy (confidence descending):
///   1. Icon number → mapped type  (engineer-set, reliable)
///   2. Fuzzy name match PT-BR/EN  (covers abbreviations and typos)
///   3. Color category hint        (green=vocals, blue=keys, red=drums, etc.)
///   4. unknown                    (user corrects manually)
class ChannelMapper {
  static InstrumentType identify({
    required String name,
    int? iconId,
    int? colorId,
  }) {
    // 1. Icon — most reliable
    if (iconId != null && iconId > 0) {
      final fromIcon = _fromIcon(iconId);
      if (fromIcon != InstrumentType.unknown) return fromIcon;
    }

    // 2. Name fuzzy match
    final fromName = _fromName(name);
    if (fromName != InstrumentType.unknown) return fromName;

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
    if (_any(n, ['overhead', 'oh ', ' oh', 'pratos', 'cymbal', 'cymb'])) {
      return InstrumentType.overhead;
    }
    if (_any(n, ['tom', 'floor', 'rack'])) return InstrumentType.percussion;
    if (_any(n, ['bat', 'drum', 'perc', 'room', 'ambience'])) return InstrumentType.drums;

    // Strings / guitar family
    if (_any(n, ['violao', 'violão', 'acoustic', 'viol', 'nylon'])) {
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
