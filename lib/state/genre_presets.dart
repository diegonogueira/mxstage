import 'instrument_type.dart';

enum Genre { gospel, worship, pop, rock, groove, jazz, blues, rb, acoustic }

extension GenreLabel on Genre {
  String get label => switch (this) {
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

/// Target balance for a genre — dB relative to lead vocal (0 dB anchor).
///
/// Negative = quieter than the lead vocal.
/// Calibrated for in-ear / personal monitor mixes (not FOH).
/// In IEMs, drums lose natural room bleed, so they need much more
/// attenuation than a studio mix reference would suggest.
class GenrePreset {
  final Genre genre;
  final Map<InstrumentType, double> relativeDb;

  const GenrePreset({required this.genre, required this.relativeDb});

  double targetFor(InstrumentType type) =>
      relativeDb[type] ?? relativeDb[InstrumentType.unknown] ?? -10.0;
}

const Map<Genre, GenrePreset> kGenrePresets = {
  Genre.worship: GenrePreset(
    genre: Genre.worship,
    // Contemporary worship (Hillsong / Bethel style):
    // vocal layers very prominent, ambient pads/keys essential, acoustic guitar
    // signature sound. Drums purely supportive — overheads nearly absent
    // (room bleed is lost in IEMs; at -13 they overwhelm the vocal).
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -4.0,
      InstrumentType.acoustic: -5.0,
      InstrumentType.keys: -5.0,
      InstrumentType.strings: -6.0,
      InstrumentType.piano: -6.0,
      InstrumentType.guitar: -7.0,
      InstrumentType.bass: -9.0,
      InstrumentType.kick: -17.0,
      InstrumentType.snare: -19.0,
      InstrumentType.drums: -18.0,
      InstrumentType.percussion: -16.0,
      InstrumentType.overhead: -24.0,
      InstrumentType.hihat: -23.0,
      InstrumentType.sax: -9.0,
      InstrumentType.brass: -10.0,
      InstrumentType.unknown: -9.0,
    },
  ),
  Genre.groove: GenrePreset(
    genre: Genre.groove,
    // Funk / Soul: bass and kick lock is the groove backbone — but in a
    // personal monitor the kick was nearly as loud as the vocal at -6 dB.
    // Guitar rhythmic chops, brass and percussion stay prominent.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -4.0,
      InstrumentType.bass: -5.0,
      InstrumentType.guitar: -6.0,
      InstrumentType.sax: -5.0,
      InstrumentType.brass: -5.0,
      InstrumentType.keys: -6.0,
      InstrumentType.percussion: -9.0,
      InstrumentType.snare: -13.0,
      InstrumentType.piano: -7.0,
      InstrumentType.kick: -13.0,
      InstrumentType.drums: -14.0,
      InstrumentType.acoustic: -9.0,
      InstrumentType.hihat: -16.0,
      InstrumentType.overhead: -20.0,
      InstrumentType.strings: -8.0,
      InstrumentType.unknown: -8.0,
    },
  ),
  Genre.blues: GenrePreset(
    genre: Genre.blues,
    // Blues: lead guitar shares the spotlight with the voice.
    // Blues piano and sax very present. Rhythm section supportive.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.guitar: -4.0,
      InstrumentType.acoustic: -4.0,
      InstrumentType.piano: -5.0,
      InstrumentType.sax: -5.0,
      InstrumentType.brass: -6.0,
      InstrumentType.backingVocal: -6.0,
      InstrumentType.bass: -7.0,
      InstrumentType.keys: -7.0,
      InstrumentType.kick: -14.0,
      InstrumentType.snare: -15.0,
      InstrumentType.drums: -15.0,
      InstrumentType.percussion: -17.0,
      InstrumentType.overhead: -21.0,
      InstrumentType.hihat: -19.0,
      InstrumentType.strings: -9.0,
      InstrumentType.unknown: -9.0,
    },
  ),
  Genre.rb: GenrePreset(
    genre: Genre.rb,
    // R&B: smooth blend, backing vocals very prominent (nearly co-lead),
    // bass and synths prominent. Kick at -6 was severely miscalibrated.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -3.0,
      InstrumentType.bass: -5.0,
      InstrumentType.keys: -5.0,
      InstrumentType.piano: -6.0,
      InstrumentType.sax: -6.0,
      InstrumentType.snare: -15.0,
      InstrumentType.guitar: -7.0,
      InstrumentType.brass: -7.0,
      InstrumentType.strings: -7.0,
      InstrumentType.percussion: -10.0,
      InstrumentType.kick: -14.0,
      InstrumentType.drums: -15.0,
      InstrumentType.acoustic: -9.0,
      InstrumentType.hihat: -19.0,
      InstrumentType.overhead: -21.0,
      InstrumentType.unknown: -8.0,
    },
  ),
  Genre.pop: GenrePreset(
    genre: Genre.pop,
    // Modern pop: vocal dominant, backing vocals close, clean production.
    // Drums present but not competing — kick at -8 was too high for IEM.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -4.0,
      InstrumentType.keys: -6.0,
      InstrumentType.bass: -8.0,
      InstrumentType.guitar: -7.0,
      InstrumentType.kick: -14.0,
      InstrumentType.snare: -15.0,
      InstrumentType.piano: -8.0,
      InstrumentType.strings: -7.0,
      InstrumentType.acoustic: -8.0,
      InstrumentType.sax: -8.0,
      InstrumentType.brass: -9.0,
      InstrumentType.drums: -15.0,
      InstrumentType.percussion: -13.0,
      InstrumentType.hihat: -20.0,
      InstrumentType.overhead: -21.0,
      InstrumentType.unknown: -9.0,
    },
  ),
  Genre.gospel: GenrePreset(
    genre: Genre.gospel,
    // Gospel: big choir and BGVs are critical, energetic but vocal-dominant.
    // Was the closest preset to correct; drum values moved down ~4 dB.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -5.0,
      InstrumentType.keys: -7.0,
      InstrumentType.piano: -7.0,
      InstrumentType.guitar: -9.0,
      InstrumentType.acoustic: -8.0,
      InstrumentType.bass: -9.0,
      InstrumentType.kick: -16.0,
      InstrumentType.snare: -18.0,
      InstrumentType.hihat: -22.0,
      InstrumentType.overhead: -20.0,
      InstrumentType.drums: -18.0,
      InstrumentType.percussion: -17.0,
      InstrumentType.sax: -7.0,
      InstrumentType.brass: -8.0,
      InstrumentType.strings: -8.0,
      InstrumentType.unknown: -10.0,
    },
  ),
  Genre.rock: GenrePreset(
    genre: Genre.rock,
    // Rock: guitars prominent, drums most present of all genres but still
    // below vocal. Smallest drum correction — rock energy is intentional.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -7.0,
      InstrumentType.guitar: -5.0,
      InstrumentType.bass: -7.0,
      InstrumentType.kick: -12.0,
      InstrumentType.snare: -12.0,
      InstrumentType.hihat: -17.0,
      InstrumentType.overhead: -16.0,
      InstrumentType.drums: -13.0,
      InstrumentType.keys: -10.0,
      InstrumentType.piano: -10.0,
      InstrumentType.acoustic: -10.0,
      InstrumentType.percussion: -12.0,
      InstrumentType.sax: -8.0,
      InstrumentType.brass: -8.0,
      InstrumentType.strings: -10.0,
      InstrumentType.unknown: -10.0,
    },
  ),
  Genre.jazz: GenrePreset(
    genre: Genre.jazz,
    // Jazz: ride cymbal via overhead IS the rhythmic pulse — overhead stays
    // more present than other genres (-12 vs -20+). Kick is barely audible
    // (brushed or feathered). Sax/piano/acoustic co-lead with the vocal.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.sax: -3.0,
      InstrumentType.acoustic: -4.0,
      InstrumentType.piano: -4.0,
      InstrumentType.brass: -4.0,
      InstrumentType.keys: -5.0,
      InstrumentType.bass: -5.0,
      InstrumentType.strings: -5.0,
      InstrumentType.guitar: -6.0,
      InstrumentType.backingVocal: -7.0,
      InstrumentType.overhead: -12.0,
      InstrumentType.hihat: -14.0,
      InstrumentType.kick: -18.0,
      InstrumentType.snare: -18.0,
      InstrumentType.drums: -16.0,
      InstrumentType.percussion: -12.0,
      InstrumentType.unknown: -8.0,
    },
  ),
  Genre.acoustic: GenrePreset(
    genre: Genre.acoustic,
    // Acoustic: voice / guitar / piano dominant, minimal or no drums.
    // Drums nearly inaudible — just enough to feel the pulse.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -5.0,
      InstrumentType.acoustic: -4.0,
      InstrumentType.strings: -4.0,
      InstrumentType.piano: -5.0,
      InstrumentType.guitar: -5.0,
      InstrumentType.keys: -6.0,
      InstrumentType.bass: -8.0,
      InstrumentType.sax: -6.0,
      InstrumentType.brass: -7.0,
      InstrumentType.kick: -18.0,
      InstrumentType.snare: -20.0,
      InstrumentType.overhead: -22.0,
      InstrumentType.drums: -20.0,
      InstrumentType.percussion: -17.0,
      InstrumentType.hihat: -24.0,
      InstrumentType.unknown: -8.0,
    },
  ),
};
