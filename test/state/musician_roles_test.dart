import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/state/instrument_type.dart';
import 'package:mxwise/state/musician_roles.dart';

void main() {
  const names = ['Voz Lead', 'Voz Back 1', 'Guitarra', 'Guitarra 2', 'Baixo',
      'Teclado 1', 'Bat Kick', 'Bat Snare', 'Violao'];
  const types = [
    InstrumentType.leadVocal, InstrumentType.backingVocal, InstrumentType.guitar,
    InstrumentType.guitar, InstrumentType.bass, InstrumentType.keys,
    InstrumentType.kick, InstrumentType.snare, InstrumentType.acoustic,
  ];
  int? detect(String bus) => ownChannelFromBusName(bus, names, types);

  group('meu canal pelo nome do bus', () {
    test('tipo único', () {
      expect(detect('Teclado'), 6);
      expect(detect('Baixo'), 5);
      expect(detect('Violão'), 9);
    });
    test('bateria = o kit (representante: bumbo)', () => expect(detect('Bateria'), 7));
    test('ministro = voz principal única', () => expect(detect('Ministro'), 1));
    test('nome igual ao canal vence', () => expect(detect('Guitarra 2'), 4));
    test('ambíguo ou não-instrumento → null', () {
      expect(detect('Guita'), isNull); // duas guitarras
      expect(detect('Vocal 1'), isNull);
      expect(detect('Sidefill'), isNull);
      expect(detect('Live'), isNull);
      expect(detect(''), isNull);
    });
  });

  test('bateria: canal escolhido não ganha extra, segue o kit', () {
    final kick = roleOffsetDb(
        ch: 7, type: InstrumentType.kick, ownChannel: 7, ownType: InstrumentType.kick);
    final snare = roleOffsetDb(
        ch: 8, type: InstrumentType.snare, ownChannel: 7, ownType: InstrumentType.kick);
    expect(kick, kRoleDeltas[MusicianRole.drums]![InstrumentType.kick]);
    expect(snare, kRoleDeltas[MusicianRole.drums]![InstrumentType.snare]);
  });
}
