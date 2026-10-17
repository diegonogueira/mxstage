import 'channel_mapper.dart';
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

/// Quanto o **meu canal** sobe (dB) sobre o alvo dele — o "mais eu". A bateria
/// não tem entrada aqui: o baterista escolhe a **bateria como conjunto** (o
/// canal guardado é só um representante do kit) e o kit inteiro sobe por
/// [kRoleDeltas] — nenhuma peça é tratada à parte.
const Map<MusicianRole, double> kOwnChannelBoostDb = {
  MusicianRole.vocal: 6.0,
  MusicianRole.keys: 6.0,
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
  if (ch == ownChannel && role != MusicianRole.drums) {
    return kOwnChannelBoostDb[role] ?? 0.0;
  }
  return kRoleDeltas[role]?[type] ?? 0.0;
}

/// Peça da bateria (kit) — no seletor, o kit aparece como **uma** entrada.
bool isDrumKit(InstrumentType t) => roleFor(t) == MusicianRole.drums;

/// Representante do kit pra guardar como "meu canal" (prefere o bumbo), ou null
/// se não há bateria. Qual peça é guardada não muda o resultado.
int? drumKitChannel(List<InstrumentType> instruments) {
  int? first;
  for (var i = 0; i < instruments.length; i++) {
    if (instruments[i] == InstrumentType.kick) return i + 1;
    if (first == null && isDrumKit(instruments[i])) first = i + 1;
  }
  return first;
}

String _norm(String s) => s
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c')
    .replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Sugere o "meu canal" pelo **nome do bus** (o retorno costuma levar o nome do
/// músico/instrumento: "Teclado", "Baixo", "Bateria", "Ministro"…). Devolve null
/// quando não dá pra ter certeza — aí o músico escolhe na mão.
///
/// 1. Nome do bus igual ao nome de um canal → esse canal.
/// 2. Bateria → o kit (como conjunto).
/// 3. Senão, o tipo reconhecido no nome do bus, se houver **um único** canal
///    desse tipo. Vozes só pelo passo 1 (há vários canais de voz e "Vocal 1"
///    não diz qual é).
int? ownChannelFromBusName(
  String busName,
  List<String> channelNames,
  List<InstrumentType> instruments,
) {
  final bus = _norm(busName);
  if (bus.isEmpty) return null;
  for (var i = 0; i < channelNames.length; i++) {
    if (_norm(channelNames[i]) == bus) return i + 1;
  }
  final InstrumentType type;
  if (const ['ministro', 'pastor', 'lider', 'levita'].any(bus.contains)) {
    type = InstrumentType.leadVocal;
  } else {
    type = ChannelMapper.identify(name: busName);
  }
  if (type == InstrumentType.unknown) return null;
  final role = roleFor(type);
  if (role == MusicianRole.drums) return drumKitChannel(instruments);
  if (role == MusicianRole.vocal && type != InstrumentType.leadVocal) return null;
  final hits = [
    for (var i = 0; i < instruments.length; i++)
      if (instruments[i] == type) i + 1,
  ];
  if (role == MusicianRole.vocal) {
    // Ministro/líder: só se houver um único canal de voz principal.
    return hits.length == 1 && !bus.contains(RegExp(r'[0-9]')) ? hits.first : null;
  }
  return hits.length == 1 ? hits.first : null;
}
