/// Conteúdo do manual "Configurar a mesa" — fonte de verdade única.
///
/// **Dart puro, sem Flutter.** É consumido por dois lados:
///  - a tela [MixerSetupScreen] (`lib/ui/screens/mixer_setup_screen.dart`),
///    que mapeia [ManualStep.iconKey] para um `IconData`;
///  - o gerador de PDF `tools/gen_manual_pdf.dart`, que ignora o ícone.
///
/// ⚠️ Ao editar este arquivo, regenere o PDF compartilhável:
///     dart run tools/gen_manual_pdf.dart
/// (ou use a skill `gen-manual-pdf`). O teste `test/manual_pdf_fresh_test.dart`
/// falha se o PDF estiver desatualizado.
library;

class ManualStep {
  /// Chave lógica do ícone; a UI traduz para `IconData`, o PDF ignora.
  final String iconKey;
  final String title;
  final String why;
  final String check;
  final String adjust;

  /// Passo essencial para o "volume real" — ganha destaque na UI e no PDF.
  final bool essential;

  const ManualStep({
    required this.iconKey,
    required this.title,
    required this.why,
    required this.check,
    required this.adjust,
    this.essential = false,
  });
}

const String manualTitle = 'Configurar a mesa';

const String manualIntroTitle = 'Por que a mesa precisa estar ajustada';

const List<String> manualIntro = [
  'O Auto-Mix não "ouve" o palco. Ele lê os medidores de entrada de cada '
      'canal da mesa e usa esse nível como o volume real do instrumento. A '
      'partir do equilíbrio que você captura ao ligá-lo, ele mexe apenas nos '
      'sends do seu bus de retorno para manter esse balanço.',
  'Se a mesa não estiver ajustada, os medidores mentem: um ganho baixo faz um '
      'instrumento forte parecer fraco, e o app corrige para o lado errado. Os '
      'passos abaixo garantem que o número que o app lê seja o volume que você '
      'realmente escuta.',
];

const String manualClosing =
    'Com a mesa assim, ligue o Auto-Mix com a banda tocando no volume de show. '
    'É nesse momento que ele "tira a foto" do equilíbrio — e é esse balanço '
    'que ele vai manter durante o culto.';

/// Impressão digital determinística de todo o conteúdo do manual.
///
/// O gerador grava este valor em `assets/manual/configurar-mesa.pdf.fingerprint`
/// e o teste `test/manual_pdf_fresh_test.dart` compara com o valor atual. Se
/// você editar o conteúdo acima e esquecer de regenerar o PDF, os valores
/// divergem e o teste falha — evitando que o PDF compartilhado envelheça.
///
/// FNV-1a 32-bit sobre uma serialização canônica; sem timestamps, então o
/// mesmo conteúdo sempre produz a mesma impressão.
String manualContentFingerprint() {
  final buf = StringBuffer()
    ..writeln(manualTitle)
    ..writeln(manualIntroTitle)
    ..writeAll(manualIntro, '')
    ..writeln()
    ..writeln(manualClosing);
  for (final s in manualSteps) {
    buf
      ..writeln(s.iconKey)
      ..writeln(s.title)
      ..writeln(s.essential)
      ..writeln(s.why)
      ..writeln(s.check)
      ..writeln(s.adjust);
  }
  var hash = 0x811c9dc5; // FNV offset basis (32-bit)
  for (final unit in buf.toString().codeUnits) {
    hash = (hash ^ unit) & 0xFFFFFFFF;
    hash = (hash * 0x01000193) & 0xFFFFFFFF; // FNV prime
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

const List<ManualStep> manualSteps = [
  ManualStep(
    iconKey: 'tune',
    title: 'Ganho / preamp bem ajustado',
    essential: true,
    why:
        'É o passo mais importante. O medidor de cada canal só reflete o '
        'volume real se o ganho de entrada (preamp) estiver bem ajustado. '
        'Ganho baixo demais: o medidor fica perto do fundo, o app acha que o '
        'instrumento está quase em silêncio e não corrige. Ganho alto demais: '
        'o medidor "gruda" no topo e clipa, e o app perde a referência de '
        'quanto o nível variou. Com o ganho certo, uma variação real de '
        'volume no palco vira uma variação real no medidor.',
    check:
        'Selecione o canal (SELECT) e olhe o medidor de entrada na tela Home. '
        'Com o instrumento tocando no volume de show, a média deve ficar em '
        'torno de -18 dBFS e os picos não podem acender o vermelho (OL/clip).',
    adjust:
        'Com o canal selecionado, gire o encoder Gain (seção Config/Preamp, '
        'logo abaixo da tela). Suba até os picos ficarem logo abaixo do '
        'vermelho e recue um pouco. Faça isso com o músico tocando forte, '
        'nunca num teste baixinho.',
  ),
  ManualStep(
    iconKey: 'alt_route',
    title: 'Sends pré-fader',
    essential: true,
    why:
        'O envio de cada canal para o seu bus de retorno deve ser pré-fader. '
        'Assim, quando o engenheiro mexe no fader do canal para ajustar o som '
        'da casa (PA), o seu retorno não muda junto. Se o send for pós-fader, '
        'cada ajuste da casa entra no seu monitor e o app fica "brigando" com '
        'o engenheiro — corrigindo algo que não é drift do palco. Pré-fader '
        'isola o seu mix: o app passa a ser o único dono do nível do send.',
    check:
        'Selecione o canal, aperte o botão SENDS, ache a linha do seu bus e '
        'veja o ponto de captação (tap). Deve estar PRE, não POST.',
    adjust:
        'Na mesma página SENDS, toque no tap do seu bus e mude para PRE. '
        'Repita em todos os canais que você escuta. (Dá para definir o padrão '
        'do bus em Setup, mas confirme canal a canal.)',
  ),
  ManualStep(
    iconKey: 'linear_scale',
    title: 'Fader master do bus em 0 dB',
    essential: true,
    why:
        'O app escreve os sends numa escala de 0 a 100%, mas quem manda tudo '
        'isso para fora é o fader master do seu bus. Se esse master estiver '
        'abaixado, todo o mix sai atenuado e parece que o Auto-Mix "não faz '
        'nada" — ele até corrige, mas o master engole o resultado. Em unidade '
        '(0 dB), o que o app calcula chega ao seu ouvido sem surpresa.',
    check:
        'Vá na camada Bus Masters (botão Bus 1-16), selecione o fader do seu '
        'bus e leia o dB na tela. Deve marcar 0.0 dB.',
    adjust:
        'Mova o fader do seu bus para 0 dB. Na X32 fica por volta de 75% do '
        'curso; a tela mostra o valor exato enquanto o fader está selecionado.',
  ),
  ManualStep(
    iconKey: 'output',
    title: 'Bus roteado para o seu monitor',
    why:
        'De nada adianta o app ajustar os sends se o bus não estiver saindo '
        'para o seu IEM ou caixa de retorno. Este passo não muda o volume '
        'real que o app lê, mas é o que garante que você escute o resultado. '
        'Confirme uma vez e esqueça.',
    check:
        'Em ROUTING, ache a saída (Out 1-16 / XLR / P16) que vai para o seu '
        'transmissor de IEM ou amplificador: a fonte deve ser o seu MixBus.',
    adjust:
        'Ajuste a saída física que vai para o seu monitor para ter como fonte '
        'o seu MixBus. Se não tiver certeza de qual saída é a sua, peça ajuda '
        'ao técnico da casa.',
  ),
  ManualStep(
    iconKey: 'headphones',
    title: 'Volume físico do retorno no meio',
    why:
        'O Auto-Mix trabalha no mundo digital dos sends. O volume físico do '
        'belt-pack (IEM) ou do amplificador do retorno é a sua margem de '
        'segurança manual. Deixe no meio: assim você tem espaço para subir ou '
        'descer no susto sem depender do app, e o app não precisa forçar os '
        'sends para os extremos só para você se ouvir.',
    check:
        'Olhe o botão de volume do belt-pack / amplificador do seu retorno.',
    adjust:
        'Coloque em aproximadamente 50% (meio do curso) antes do show e faça '
        'ajuste fino só se precisar.',
  ),
  ManualStep(
    iconKey: 'wifi',
    title: 'Mesa e celular na mesma rede Wi-Fi',
    why:
        'O app fala com a mesa por UDP na rede local. Se o celular estiver nos '
        'dados móveis, ou numa rede/SSID diferente da mesa, não há conexão — e '
        'sem os medidores o Auto-Mix não tem o que ler. É o pré-requisito '
        'para todo o resto funcionar.',
    check:
        'No celular, confirme que o Wi-Fi está ligado e conectado à mesma rede '
        'da mesa, com os dados móveis desligados. A mesa costuma entrar por '
        'cabo no mesmo roteador/AP.',
    adjust:
        'Conecte o celular ao Wi-Fi do palco/mesa. Se a mesa não aparecer '
        'sozinha, use o IP manual na tela inicial.',
  ),
];
