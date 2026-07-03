import 'instrument_type.dart';

enum Genre { gospel, worship, rock, groove, jazz, blues, rb, acoustic }

extension GenreLabel on Genre {
  String get label => switch (this) {
        Genre.gospel => 'Gospel',
        Genre.worship => 'Worship',
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
/// These values are starting points calibrated for in-ear monitors.
/// Users adjust via per-channel boost in M4.
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
    // signature sound, drums supportive but not dominant.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -3.0,
      InstrumentType.acoustic: -5.0,
      InstrumentType.keys: -5.0,
      InstrumentType.strings: -6.0,
      InstrumentType.piano: -6.0,
      InstrumentType.guitar: -7.0,
      InstrumentType.bass: -8.0,
      InstrumentType.kick: -10.0,
      InstrumentType.snare: -12.0,
      InstrumentType.overhead: -13.0,
      InstrumentType.drums: -12.0,
      InstrumentType.hihat: -16.0,
      InstrumentType.percussion: -13.0,
      InstrumentType.sax: -9.0,
      InstrumentType.brass: -10.0,
      InstrumentType.unknown: -9.0,
    },
  ),
  Genre.groove: GenrePreset(
    genre: Genre.groove,
    // Funk / Soul: o baixo e o kick formam a espinha dorsal.
    // Guitarra rítmica, seção de metais e percussão ganham destaque.
    // Voz mantém o topo mas divide espaço com o groove da seção rítmica.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -4.0,
      InstrumentType.bass: -4.0,
      InstrumentType.kick: -6.0,
      InstrumentType.guitar: -5.0,
      InstrumentType.sax: -5.0,
      InstrumentType.brass: -5.0,
      InstrumentType.keys: -6.0,
      InstrumentType.percussion: -7.0,
      InstrumentType.snare: -7.0,
      InstrumentType.piano: -7.0,
      InstrumentType.drums: -8.0,
      InstrumentType.acoustic: -9.0,
      InstrumentType.hihat: -10.0,
      InstrumentType.overhead: -11.0,
      InstrumentType.strings: -8.0,
      InstrumentType.unknown: -8.0,
    },
  ),
  Genre.blues: GenrePreset(
    genre: Genre.blues,
    // Blues: guitarra solo ocupa quase o mesmo espaço que a voz.
    // Piano de blues e sax muito presentes. Bateria e baixo discretos.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.guitar: -4.0,
      InstrumentType.acoustic: -4.0,
      InstrumentType.piano: -5.0,
      InstrumentType.sax: -5.0,
      InstrumentType.brass: -6.0,
      InstrumentType.backingVocal: -6.0,
      InstrumentType.bass: -6.0,
      InstrumentType.keys: -6.0,
      InstrumentType.kick: -9.0,
      InstrumentType.snare: -10.0,
      InstrumentType.overhead: -12.0,
      InstrumentType.drums: -10.0,
      InstrumentType.hihat: -13.0,
      InstrumentType.strings: -9.0,
      InstrumentType.percussion: -13.0,
      InstrumentType.unknown: -9.0,
    },
  ),
  Genre.rb: GenrePreset(
    genre: Genre.rb,
    // R&B contemporâneo: groove eletrônico/híbrido, backing vocals em destaque,
    // baixo e synths proeminentes, guitarra mais sutil que no groove clássico.
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -3.0,
      InstrumentType.bass: -4.0,
      InstrumentType.keys: -5.0,
      InstrumentType.kick: -6.0,
      InstrumentType.piano: -6.0,
      InstrumentType.sax: -6.0,
      InstrumentType.snare: -7.0,
      InstrumentType.guitar: -7.0,
      InstrumentType.brass: -7.0,
      InstrumentType.strings: -7.0,
      InstrumentType.percussion: -8.0,
      InstrumentType.drums: -8.0,
      InstrumentType.acoustic: -9.0,
      InstrumentType.hihat: -10.0,
      InstrumentType.overhead: -11.0,
      InstrumentType.unknown: -8.0,
    },
  ),
  Genre.gospel: GenrePreset(
    genre: Genre.gospel,
    relativeDb: {
      InstrumentType.leadVocal: 0.0, // anchor
      InstrumentType.backingVocal: -5.0,
      InstrumentType.keys: -7.0,
      InstrumentType.piano: -7.0,
      InstrumentType.guitar: -9.0,
      InstrumentType.acoustic: -8.0,
      InstrumentType.bass: -9.0,
      InstrumentType.kick: -12.0,
      InstrumentType.snare: -14.0,
      InstrumentType.hihat: -18.0,
      InstrumentType.overhead: -16.0,
      InstrumentType.drums: -14.0,
      InstrumentType.percussion: -15.0,
      InstrumentType.sax: -7.0,
      InstrumentType.brass: -8.0,
      InstrumentType.strings: -8.0,
      InstrumentType.unknown: -10.0,
    },
  ),
  Genre.rock: GenrePreset(
    genre: Genre.rock,
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -8.0,
      InstrumentType.guitar: -5.0,
      InstrumentType.bass: -7.0,
      InstrumentType.kick: -8.0,
      InstrumentType.snare: -9.0,
      InstrumentType.hihat: -14.0,
      InstrumentType.overhead: -12.0,
      InstrumentType.drums: -10.0,
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
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -7.0,
      InstrumentType.acoustic: -4.0,
      InstrumentType.piano: -4.0,
      InstrumentType.keys: -5.0,
      InstrumentType.bass: -5.0,
      InstrumentType.guitar: -6.0,
      InstrumentType.kick: -10.0,
      InstrumentType.snare: -11.0,
      InstrumentType.hihat: -12.0,
      InstrumentType.overhead: -9.0,
      InstrumentType.drums: -10.0,
      InstrumentType.sax: -3.0,
      InstrumentType.brass: -4.0,
      InstrumentType.strings: -5.0,
      InstrumentType.percussion: -12.0,
      InstrumentType.unknown: -8.0,
    },
  ),
  Genre.acoustic: GenrePreset(
    genre: Genre.acoustic,
    relativeDb: {
      InstrumentType.leadVocal: 0.0,
      InstrumentType.backingVocal: -6.0,
      InstrumentType.acoustic: -4.0,
      InstrumentType.piano: -5.0,
      InstrumentType.keys: -6.0,
      InstrumentType.bass: -7.0,
      InstrumentType.guitar: -5.0,
      InstrumentType.strings: -4.0,
      InstrumentType.kick: -12.0,
      InstrumentType.snare: -14.0,
      InstrumentType.hihat: -18.0,
      InstrumentType.overhead: -14.0,
      InstrumentType.drums: -14.0,
      InstrumentType.percussion: -14.0,
      InstrumentType.sax: -6.0,
      InstrumentType.brass: -7.0,
      InstrumentType.unknown: -8.0,
    },
  ),
};
