import 'instrument_type.dart';

enum Genre { gospel, rock, jazz, acoustic }

extension GenreLabel on Genre {
  String get label => switch (this) {
        Genre.gospel => 'Gospel',
        Genre.rock => 'Rock',
        Genre.jazz => 'Jazz',
        Genre.acoustic => 'Acústico',
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
