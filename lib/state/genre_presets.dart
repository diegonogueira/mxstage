import 'instrument_type.dart';

enum Genre { general, gospel, worship, pop, rock, groove, jazz, blues, rb, acoustic }

extension GenreLabel on Genre {
  String get label => switch (this) {
        Genre.general => 'Geral',
        Genre.gospel => 'Gospel',
        Genre.worship => 'Worship',
        Genre.pop => 'Pop',
        Genre.rock => 'Rock',
        Genre.groove => 'Groove',
        Genre.jazz => 'Jazz',
        Genre.blues => 'Blues',
        Genre.acoustic => 'Acústico',
        Genre.rb => 'R&B',
      };
}

/// Neutral base balance — dB relative to the lead vocal (0 dB anchor).
///
/// This is the "nobody dominates" profile the Auto-Mix always levels toward.
/// Negative = quieter than the lead vocal. Calibrated for in-ear / personal
/// monitor mixes (not FOH): in IEMs drums lose natural room bleed, so they need
/// much more attenuation than a studio reference would suggest.
///
/// Genre presets never replace this profile — they only add a per-instrument
/// gain on top of it (see [kGenreDeltas]). So selecting a genre *flavours* the
/// neutral leveling; it never "marreta" (overrides) the whole balance.
const Map<InstrumentType, double> kBaseProfile = {
  InstrumentType.leadVocal: 0.0,
  InstrumentType.backingVocal: -5.0,
  InstrumentType.guitar: -7.0,
  InstrumentType.keys: -7.0,
  InstrumentType.piano: -7.0,
  InstrumentType.acoustic: -7.0,
  InstrumentType.strings: -7.0,
  InstrumentType.bass: -8.0,
  InstrumentType.sax: -8.0,
  InstrumentType.brass: -8.0,
  InstrumentType.kick: -15.0,
  InstrumentType.snare: -15.0,
  InstrumentType.drums: -15.0,
  InstrumentType.percussion: -13.0,
  InstrumentType.overhead: -20.0,
  InstrumentType.hihat: -20.0,
  InstrumentType.unknown: -9.0,
};

/// Per-genre gain over [kBaseProfile] (dB). Positive = emphasise this
/// instrument for the style, negative = pull it back. Absent = 0 (use the base
/// value unchanged). These deltas were derived from the previously hand-tuned
/// per-genre profiles, so the effective target ([GenrePreset.targetFor]) is
/// identical to the old calibration — just re-expressed as "flavour over
/// neutral" so a preset only nudges the mix instead of redefining it.
const Map<Genre, Map<InstrumentType, double>> kGenreDeltas = {
  Genre.general: {}, // the neutral base itself — no flavour.
  Genre.worship: {
    // Vocal layers prominent, ambient pads/keys and acoustic guitar signature;
    // drums purely supportive (overheads nearly absent in IEMs).
    InstrumentType.backingVocal: 1.0,
    InstrumentType.acoustic: 2.0,
    InstrumentType.keys: 2.0,
    InstrumentType.strings: 1.0,
    InstrumentType.piano: 1.0,
    InstrumentType.bass: -1.0,
    InstrumentType.kick: -2.0,
    InstrumentType.snare: -4.0,
    InstrumentType.drums: -3.0,
    InstrumentType.percussion: -3.0,
    InstrumentType.overhead: -4.0,
    InstrumentType.hihat: -3.0,
    InstrumentType.sax: -1.0,
    InstrumentType.brass: -2.0,
  },
  Genre.groove: {
    // Funk / Soul: bass + kick lock is the backbone; guitar chops, brass and
    // percussion stay prominent.
    InstrumentType.backingVocal: 1.0,
    InstrumentType.bass: 3.0,
    InstrumentType.guitar: 1.0,
    InstrumentType.sax: 3.0,
    InstrumentType.brass: 3.0,
    InstrumentType.keys: 1.0,
    InstrumentType.percussion: 4.0,
    InstrumentType.snare: 2.0,
    InstrumentType.kick: 2.0,
    InstrumentType.drums: 1.0,
    InstrumentType.acoustic: -2.0,
    InstrumentType.hihat: 4.0,
    InstrumentType.strings: -1.0,
    InstrumentType.unknown: 1.0,
  },
  Genre.blues: {
    // Lead guitar shares the spotlight with the voice; piano and sax present.
    InstrumentType.guitar: 3.0,
    InstrumentType.acoustic: 3.0,
    InstrumentType.piano: 2.0,
    InstrumentType.sax: 3.0,
    InstrumentType.brass: 2.0,
    InstrumentType.backingVocal: -1.0,
    InstrumentType.bass: 1.0,
    InstrumentType.kick: 1.0,
    InstrumentType.percussion: -4.0,
    InstrumentType.overhead: -1.0,
    InstrumentType.hihat: 1.0,
    InstrumentType.strings: -2.0,
  },
  Genre.rb: {
    // Smooth blend, backing vocals nearly co-lead, bass and synths prominent.
    InstrumentType.backingVocal: 2.0,
    InstrumentType.bass: 3.0,
    InstrumentType.keys: 2.0,
    InstrumentType.piano: 1.0,
    InstrumentType.sax: 2.0,
    InstrumentType.brass: 1.0,
    InstrumentType.percussion: 3.0,
    InstrumentType.kick: 1.0,
    InstrumentType.acoustic: -2.0,
    InstrumentType.hihat: 1.0,
    InstrumentType.overhead: -1.0,
    InstrumentType.unknown: 1.0,
  },
  Genre.pop: {
    // Vocal dominant, backing vocals close, clean production.
    InstrumentType.backingVocal: 1.0,
    InstrumentType.keys: 1.0,
    InstrumentType.kick: 1.0,
    InstrumentType.piano: -1.0,
    InstrumentType.acoustic: -1.0,
    InstrumentType.brass: -1.0,
    InstrumentType.overhead: -1.0,
  },
  Genre.gospel: {
    // Big choir and BGVs critical, energetic but vocal-dominant.
    InstrumentType.guitar: -2.0,
    InstrumentType.acoustic: -1.0,
    InstrumentType.bass: -1.0,
    InstrumentType.kick: -1.0,
    InstrumentType.snare: -3.0,
    InstrumentType.hihat: -2.0,
    InstrumentType.drums: -3.0,
    InstrumentType.percussion: -4.0,
    InstrumentType.sax: 1.0,
    InstrumentType.strings: -1.0,
    InstrumentType.unknown: -1.0,
  },
  Genre.rock: {
    // Guitars prominent, drums most present of all genres (intentional energy).
    InstrumentType.backingVocal: -2.0,
    InstrumentType.guitar: 2.0,
    InstrumentType.bass: 1.0,
    InstrumentType.kick: 3.0,
    InstrumentType.snare: 3.0,
    InstrumentType.hihat: 3.0,
    InstrumentType.overhead: 4.0,
    InstrumentType.drums: 2.0,
    InstrumentType.keys: -3.0,
    InstrumentType.piano: -3.0,
    InstrumentType.acoustic: -3.0,
    InstrumentType.percussion: 1.0,
    InstrumentType.strings: -3.0,
    InstrumentType.unknown: -1.0,
  },
  Genre.jazz: {
    // Ride cymbal (overhead) is the rhythmic pulse; kick barely audible.
    // Sax/piano/acoustic co-lead with the vocal.
    InstrumentType.sax: 5.0,
    InstrumentType.acoustic: 3.0,
    InstrumentType.piano: 3.0,
    InstrumentType.brass: 4.0,
    InstrumentType.keys: 2.0,
    InstrumentType.bass: 3.0,
    InstrumentType.strings: 2.0,
    InstrumentType.guitar: 1.0,
    InstrumentType.backingVocal: -2.0,
    InstrumentType.overhead: 8.0,
    InstrumentType.hihat: 6.0,
    InstrumentType.kick: -3.0,
    InstrumentType.snare: -3.0,
    InstrumentType.drums: -1.0,
    InstrumentType.percussion: 1.0,
    InstrumentType.unknown: 1.0,
  },
  Genre.acoustic: {
    // Voice / guitar / piano dominant, minimal drums.
    InstrumentType.acoustic: 3.0,
    InstrumentType.strings: 3.0,
    InstrumentType.piano: 2.0,
    InstrumentType.guitar: 2.0,
    InstrumentType.keys: 1.0,
    InstrumentType.sax: 2.0,
    InstrumentType.brass: 1.0,
    InstrumentType.kick: -3.0,
    InstrumentType.snare: -5.0,
    InstrumentType.overhead: -2.0,
    InstrumentType.drums: -5.0,
    InstrumentType.percussion: -4.0,
    InstrumentType.hihat: -4.0,
    InstrumentType.unknown: 1.0,
  },
};

/// Target balance for a genre — neutral base plus a per-instrument flavour.
///
/// [targetFor] returns dB relative to the lead vocal (0 dB anchor). The engine
/// levels every channel toward this profile; the genre only shifts the base.
class GenrePreset {
  final Genre genre;

  /// Per-instrument gain over [kBaseProfile] (dB). Absent = 0.
  final Map<InstrumentType, double> deltaDb;

  const GenrePreset({required this.genre, this.deltaDb = const {}});

  /// Effective target = neutral base + genre delta. dB relative to lead vocal.
  double targetFor(InstrumentType type) {
    final base = kBaseProfile[type] ?? kBaseProfile[InstrumentType.unknown] ?? -10.0;
    return base + deltaFor(type);
  }

  /// Genre flavour for [type] (dB over the neutral base). For UI display —
  /// e.g. a "+3" chip on the guitar in Rock. 0 = neutral.
  double deltaFor(InstrumentType type) => deltaDb[type] ?? 0.0;
}

/// All presets, built from [kBaseProfile] + [kGenreDeltas].
final Map<Genre, GenrePreset> kGenrePresets = {
  for (final genre in Genre.values)
    genre: GenrePreset(genre: genre, deltaDb: kGenreDeltas[genre] ?? const {}),
};
