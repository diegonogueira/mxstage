// Persistência por mesa das sobreposições manuais de instrumento (AppSettings).
import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/state/app_settings.dart';
import 'package:mxwise/state/instrument_type.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mixer = 'X32-TEST';

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('sem overrides salvos retorna mapa vazio', () async {
    expect(await AppSettings.instrumentOverrides(mixer), isEmpty);
  });

  test('round-trip: grava e relê por número de canal', () async {
    await AppSettings.setInstrumentOverride(mixer, 5, InstrumentType.backingVocal);
    await AppSettings.setInstrumentOverride(mixer, 12, InstrumentType.guitar);

    final map = await AppSettings.instrumentOverrides(mixer);
    expect(map, {5: InstrumentType.backingVocal, 12: InstrumentType.guitar});
  });

  test('override é por mesa — outra mesa não enxerga', () async {
    await AppSettings.setInstrumentOverride(mixer, 5, InstrumentType.piano);
    expect(await AppSettings.instrumentOverrides('OUTRA'), isEmpty);
  });

  test('setInstrumentOverride(null) remove só aquele canal', () async {
    await AppSettings.setInstrumentOverride(mixer, 5, InstrumentType.piano);
    await AppSettings.setInstrumentOverride(mixer, 6, InstrumentType.bass);

    await AppSettings.setInstrumentOverride(mixer, 5, null);

    expect(await AppSettings.instrumentOverrides(mixer),
        {6: InstrumentType.bass});
  });

  test('remover o último override apaga a chave inteira', () async {
    await AppSettings.setInstrumentOverride(mixer, 5, InstrumentType.piano);
    await AppSettings.setInstrumentOverride(mixer, 5, null);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().any((k) => k.startsWith('instr_override:')), isFalse);
  });

  test('clearInstrumentOverrides limpa a mesa', () async {
    await AppSettings.setInstrumentOverride(mixer, 5, InstrumentType.piano);
    await AppSettings.clearInstrumentOverrides(mixer);
    expect(await AppSettings.instrumentOverrides(mixer), isEmpty);
  });

  test('clearAll remove a chave de overrides', () async {
    await AppSettings.setInstrumentOverride(mixer, 5, InstrumentType.piano);
    await AppSettings.clearAll();
    expect(await AppSettings.instrumentOverrides(mixer), isEmpty);
  });

  test('parse tolerante: nome de enum inválido é ignorado', () async {
    // Simula um blob salvo por uma versão futura com um tipo desconhecido.
    SharedPreferences.setMockInitialValues({
      'instr_override:$mixer':
          '{"5":"backingVocal","7":"theremin","x":"guitar"}',
    });
    expect(await AppSettings.instrumentOverrides(mixer),
        {5: InstrumentType.backingVocal});
  });

  test('parse tolerante: JSON inválido retorna vazio', () async {
    SharedPreferences.setMockInitialValues({
      'instr_override:$mixer': 'não é json',
    });
    expect(await AppSettings.instrumentOverrides(mixer), isEmpty);
  });
}
