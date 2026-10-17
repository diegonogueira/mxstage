import 'instrument_type.dart';

/// Papel do músico dono do retorno — define "como cada um precisa se ouvir".
///
/// O balanço neutro ([kBaseProfile]) é de *plateia*: voz como âncora pra todo
/// mundo. No retorno, cada músico quer "mais eu" + as referências que ele usa
/// pra tocar (o baixista trava no bumbo, o tecladista acompanha a voz e não quer
/// brigar com guitarra/piano…). O papel é uma **terceira camada** sobre
/// base + estilo — só desloca alguns canais, nunca redefine o balanço.
enum MusicianRole { vocal, keys, drums, bass, guitar, melody, other }

extension MusicianRoleLabel on MusicianRole {
  String get label => switch (this) {
        MusicianRole.vocal => 'Voz',
        MusicianRole.keys => 'Teclas',
        MusicianRole.drums => 'Bateria',
        MusicianRole.bass => 'Baixo',
        MusicianRole.guitar => 'Guitarra/Violão',
        MusicianRole.melody => 'Sopros/Cordas',
        MusicianRole.other => 'Outro',
      };
}

/// Papel a partir do instrumento do **meu canal**.
MusicianRole roleFor(InstrumentType t) => switch (t) {
      InstrumentType.leadVocal || InstrumentType.backingVocal => MusicianRole.vocal,
      InstrumentType.keys || InstrumentType.piano => MusicianRole.keys,
      InstrumentType.kick ||
      InstrumentType.snare ||
      InstrumentType.hihat ||
      InstrumentType.overhead ||
      InstrumentType.drums ||
      InstrumentType.percussion =>
        MusicianRole.drums,
      InstrumentType.bass => MusicianRole.bass,
      InstrumentType.guitar || InstrumentType.acoustic => MusicianRole.guitar,
      InstrumentType.sax || InstrumentType.brass || InstrumentType.strings =>
        MusicianRole.melody,
      InstrumentType.unknown => MusicianRole.other,
    };

/// Quanto o **meu canal** sobe (dB) sobre o alvo dele — o "mais eu". Bateria
/// sobe menos no canal escolhido porque o kit inteiro já sobe em
/// [kRoleDeltas] (o baterista escolhe um mic, mas quer ouvir a bateria toda).
const Map<MusicianRole, double> kOwnChannelBoostDb = {
  MusicianRole.vocal: 6.0,
  MusicianRole.keys: 6.0,
  MusicianRole.drums: 2.0,
  MusicianRole.bass: 6.0,
  MusicianRole.guitar: 6.0,
  MusicianRole.melody: 6.0,
  MusicianRole.other: 6.0,
};

/// Deslocamento (dB) dos **outros** canais conforme o papel. Ausente = 0.
/// Valores de partida (prática de monitor), ajustáveis com o reforço por canal.
const Map<MusicianRole, Map<InstrumentType, double>> kRoleDeltas = {
  // Cantor: a própria voz no topo; teclas/violão como referência de tom;
  // bateria atrás.
  MusicianRole.vocal: {
    InstrumentType.backingVocal: -2.0,
    InstrumentType.keys: 2.0,
    InstrumentType.piano: 2.0,
    InstrumentType.acoustic: 2.0,
    InstrumentType.kick: -2.0,
    InstrumentType.snare: -3.0,
    InstrumentType.drums: -3.0,
    InstrumentType.hihat: -3.0,
    InstrumentType.overhead: -3.0,
    InstrumentType.percussion: -2.0,
  },
  // Tecladista: voz mantida (deixas do ministro), baixo/bumbo como base; quem
  // briga na mesma faixa (guitarra, piano/outro teclado, violão) desce.
  MusicianRole.keys: {
    InstrumentType.guitar: -3.0,
    InstrumentType.keys: -3.0,
    InstrumentType.piano: -3.0,
    InstrumentType.acoustic: -2.0,
    InstrumentType.backingVocal: -2.0,
    InstrumentType.drums: -1.0,
    InstrumentType.overhead: -2.0,
    InstrumentType.hihat: -2.0,
  },
  // Baterista: o kit todo e o baixo (pra travar juntos); harmonia atrás.
  MusicianRole.drums: {
    InstrumentType.kick: 4.0,
    InstrumentType.snare: 4.0,
    InstrumentType.drums: 3.0,
    InstrumentType.hihat: 3.0,
    InstrumentType.overhead: 3.0,
    InstrumentType.percussion: 2.0,
    InstrumentType.bass: 4.0,
    InstrumentType.keys: -3.0,
    InstrumentType.piano: -3.0,
    InstrumentType.guitar: -3.0,
    InstrumentType.acoustic: -2.0,
    InstrumentType.backingVocal: -2.0,
  },
  // Baixista: bumbo forte (trava com o baterista); pratos e guitarra atrás.
  MusicianRole.bass: {
    InstrumentType.kick: 4.0,
    InstrumentType.snare: 1.0,
    InstrumentType.hihat: -2.0,
    InstrumentType.overhead: -3.0,
    InstrumentType.guitar: -2.0,
    InstrumentType.keys: -1.0,
    InstrumentType.backingVocal: -2.0,
  },
  // Guitarrista/violonista: baixo e bumbo como base; teclas (mesma faixa) atrás.
  MusicianRole.guitar: {
    InstrumentType.bass: 2.0,
    InstrumentType.kick: 2.0,
    InstrumentType.keys: -3.0,
    InstrumentType.piano: -2.0,
    InstrumentType.guitar: -3.0,
    InstrumentType.acoustic: -2.0,
    InstrumentType.backingVocal: -2.0,
  },
  // Sopros/cordas: harmonia (teclas) como referência; bateria um pouco atrás.
  MusicianRole.melody: {
    InstrumentType.keys: 1.0,
    InstrumentType.piano: 1.0,
    InstrumentType.drums: -2.0,
    InstrumentType.snare: -2.0,
    InstrumentType.overhead: -2.0,
    InstrumentType.hihat: -2.0,
  },
  MusicianRole.other: {},
};

/// Deslocamento (dB) do canal [ch] do tipo [type] no retorno de quem toca o
/// canal [ownChannel] (do tipo [ownType]). `ownChannel == null` ⇒ 0 (sem papel:
/// balanço de plateia, ex. Live/transmissão).
double roleOffsetDb({
  required int ch,
  required InstrumentType type,
  required int? ownChannel,
  required InstrumentType ownType,
}) {
  if (ownChannel == null) return 0.0;
  final role = roleFor(ownType);
  if (ch == ownChannel) return kOwnChannelBoostDb[role] ?? 0.0;
  return kRoleDeltas[role]?[type] ?? 0.0;
}
