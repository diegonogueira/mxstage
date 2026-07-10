import 'package:flutter/material.dart';

import '../state/instrument_type.dart';

/// UI-only visuals for instrument types. Kept out of lib/state so the model
/// layer stays Flutter-free (the identification logic never needs an IconData).

/// Best-effort Material icon for each instrument. Material has no real drum/
/// brass glyphs, so a few are approximations chosen for at-a-glance reading.
IconData instrumentIcon(InstrumentType t) => switch (t) {
      InstrumentType.leadVocal => Icons.mic,
      InstrumentType.backingVocal => Icons.mic_none,
      InstrumentType.guitar => Icons.music_note,
      InstrumentType.acoustic => Icons.music_note_outlined,
      InstrumentType.bass => Icons.graphic_eq,
      InstrumentType.keys => Icons.piano,
      InstrumentType.piano => Icons.piano,
      InstrumentType.kick => Icons.album,
      InstrumentType.snare => Icons.album_outlined,
      InstrumentType.hihat => Icons.blur_circular,
      InstrumentType.overhead => Icons.blur_on,
      InstrumentType.drums => Icons.album,
      InstrumentType.percussion => Icons.grain,
      InstrumentType.sax => Icons.audiotrack,
      InstrumentType.brass => Icons.audiotrack,
      InstrumentType.strings => Icons.queue_music,
      InstrumentType.unknown => Icons.help_outline,
    };

/// Instrument families for the fader-board group filter.
enum InstrumentGroup { vozes, bateria, cordas, teclas, metais, outros }

/// Fixed display order for the filter chips.
const List<InstrumentGroup> kInstrumentGroupOrder = [
  InstrumentGroup.vozes,
  InstrumentGroup.bateria,
  InstrumentGroup.cordas,
  InstrumentGroup.teclas,
  InstrumentGroup.metais,
  InstrumentGroup.outros,
];

extension InstrumentGroupVisuals on InstrumentGroup {
  String get label => switch (this) {
        InstrumentGroup.vozes => 'Vozes',
        InstrumentGroup.bateria => 'Bateria',
        InstrumentGroup.cordas => 'Cordas',
        InstrumentGroup.teclas => 'Teclas',
        InstrumentGroup.metais => 'Metais',
        InstrumentGroup.outros => 'Outros',
      };

  IconData get icon => switch (this) {
        InstrumentGroup.vozes => Icons.mic,
        InstrumentGroup.bateria => Icons.album,
        InstrumentGroup.cordas => Icons.music_note,
        InstrumentGroup.teclas => Icons.piano,
        InstrumentGroup.metais => Icons.audiotrack,
        InstrumentGroup.outros => Icons.more_horiz,
      };
}

/// Maps an instrument to its family. `unknown` lands in [InstrumentGroup.outros].
InstrumentGroup instrumentGroup(InstrumentType t) => switch (t) {
      InstrumentType.leadVocal ||
      InstrumentType.backingVocal =>
        InstrumentGroup.vozes,
      InstrumentType.kick ||
      InstrumentType.snare ||
      InstrumentType.hihat ||
      InstrumentType.overhead ||
      InstrumentType.drums ||
      InstrumentType.percussion =>
        InstrumentGroup.bateria,
      InstrumentType.guitar ||
      InstrumentType.acoustic ||
      InstrumentType.bass ||
      InstrumentType.strings =>
        InstrumentGroup.cordas,
      InstrumentType.keys || InstrumentType.piano => InstrumentGroup.teclas,
      InstrumentType.sax || InstrumentType.brass => InstrumentGroup.metais,
      InstrumentType.unknown => InstrumentGroup.outros,
    };
