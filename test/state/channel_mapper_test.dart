import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/state/channel_mapper.dart';
import 'package:mxwise/state/instrument_type.dart';

void main() {
  // Nomes e ícones reais da mesa do culto de 21/10: os ícones davam quase tudo
  // errado; o nome que o operador digitou é que acerta.
  test('nome vence o ícone (mesa real)', () {
    const cases = {
      'Bumbo': (InstrumentType.kick, 3),
      'Caixa cima': (InstrumentType.snare, 4),
      'Caixa baixo': (InstrumentType.snare, 5),
      'Hi - Hat': (InstrumentType.hihat, 9),
      'Tom': (InstrumentType.percussion, 6),
      'Surdo': (InstrumentType.percussion, 8),
      'Over L': (InstrumentType.overhead, 0),
      'Drums': (InstrumentType.drums, 10),
      'Bass': (InstrumentType.bass, 17),
      'Guitar': (InstrumentType.guitar, 20),
      'AcousticGtr': (InstrumentType.acoustic, 23),
      'Keys L': (InstrumentType.keys, 11),
    };
    cases.forEach((name, c) {
      expect(ChannelMapper.identify(name: name, iconId: c.$2), c.$1, reason: name);
    });
  });

  test('talkback/PC continuam desconhecidos', () {
    expect(ChannelMapper.identify(name: 'DM'), InstrumentType.unknown);
    expect(ChannelMapper.identify(name: 'PC'), InstrumentType.unknown);
  });
}
