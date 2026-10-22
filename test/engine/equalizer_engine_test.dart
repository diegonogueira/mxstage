import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/engine/equalizer_engine.dart';
import 'package:mxwise/osc/osc_codec.dart';
import 'package:mxwise/state/genre_presets.dart';
import 'package:mxwise/state/instrument_type.dart';

// Cenário de igreja: voz, teclado, guitarra, baixo, bumbo (ch1..5).
const _play = [-24.0, -28.0, -20.0, -26.0, -18.0];

List<InstrumentType> _instr() {
  final l = List.filled(32, InstrumentType.unknown);
  l[0] = InstrumentType.leadVocal;
  l[1] = InstrumentType.keys;
  l[2] = InstrumentType.guitar;
  l[3] = InstrumentType.bass;
  l[4] = InstrumentType.kick;
  l[5] = InstrumentType.piano; // só toca nos testes que pedem
  return l;
}

List<double> _frame(List<double> five) =>
    List.generate(32, (i) => i < five.length ? five[i] : -90.0);

Map<int, double> _sendsAt(double db) => {for (var c = 1; c <= 32; c++) c: db};

void main() {
  final preset = kGenrePresets[Genre.worship]!;
  final instr = _instr();

  EqualizerEngine equalized({List<double> Function(int t)? frameAt}) {
    final e = EqualizerEngine();
    e.startMeasure();
    for (var t = 0; t < 75; t++) {
      e.addSample(_frame(frameAt?.call(t) ?? _play));
    }
    expect(e.finish(_sendsAt(0.0), instruments: instr, preset: preset).ok, isTrue);
    return e;
  }

  test('equalizar crava o balanço do estilo e normaliza o topo em 0 dB', () {
    final e = equalized();
    final sends = e.targetSendsDb(instr, preset);
    // No fone: nível + send. Diferença entre canais = diferença de alvo.
    double ear(int ch) => _play[ch - 1] + sends[ch]!;
    for (var ch = 2; ch <= 5; ch++) {
      final want = preset.targetFor(instr[ch - 1]) - preset.targetFor(instr[0]);
      expect(ear(ch) - ear(1), closeTo(want, 0.01), reason: 'ch$ch');
    }
    final top = [for (var ch = 1; ch <= 5; ch++) sends[ch]!].reduce((a, b) => a > b ? a : b);
    expect(top, closeTo(0.0, 0.01));
  });

  test('pausa durante a medição não derruba o nível medido (gated)', () {
    // Voz canta só metade da janela; o resto é vazamento (−50).
    final e = equalized(frameAt: (t) => [t.isEven ? -24.0 : -50.0, ..._play.skip(1)]);
    expect(e.levelDb[1], closeTo(-24.0, 0.5));
  });

  test('canal pouco ouvido fica "não ouvido" e mantém o send', () {
    final e = EqualizerEngine()..startMeasure();
    for (var t = 0; t < 75; t++) {
      e.addSample(_frame([..._play, t == 3 ? -30.0 : -90.0])); // ch6: 1 frame só
    }
    final r = e.finish(_sendsAt(-5.0), instruments: instr, preset: preset);
    expect(r.unheard, contains(6));
    expect(e.targetSendsDb(instr, preset)[6], -5.0);
  });

  test('canal puxado pra baixo (off) nunca é aberto', () {
    final e = EqualizerEngine()..startMeasure();
    for (var t = 0; t < 75; t++) {
      e.addSample(_frame(_play));
    }
    final sends = _sendsAt(0.0)..[3] = -90.0;
    e.finish(sends, instruments: instr, preset: preset);
    expect(e.targetSendsDb(instr, preset)[3], -90.0);
  });

  test('ninguém tocando → não equaliza', () {
    final e = EqualizerEngine()..startMeasure();
    for (var t = 0; t < 75; t++) {
      e.addSample(_frame(const []));
    }
    expect(e.finish(_sendsAt(0.0), instruments: instr, preset: preset).ok, isFalse);
    expect(e.isActive, isFalse);
  });

  test('silêncio depois de equalizar nunca sobe nada (não entra estourado)', () {
    final e = equalized();
    e.tick(_frame(_play), instr, preset);
    final before = e.targetSendsDb(instr, preset);
    // Guitarra para por 40 s.
    for (var t = 0; t < 40; t++) {
      final f = List.of(_play)..[2] = -55.0;
      e.tick(_frame(f), instr, preset);
    }
    expect(e.targetSendsDb(instr, preset)[3], before[3]);
  });

  test('proteção só abaixa um canal que passou muito do ponto e devolve depois', () {
    final e = equalized();
    final base = e.targetSendsDb(instr, preset)[3]!;
    // Guitarra sobe 12 dB e fica assim.
    for (var t = 0; t < 10; t++) {
      final f = List.of(_play)..[2] = _play[2] + 12;
      e.tick(_frame(f), instr, preset);
    }
    // Corta até sobrar só o joelho (+1 dB).
    expect(e.targetSendsDb(instr, preset)[3], closeTo(base - 11, 0.01));
    // Volta ao normal → devolve devagar até o send equalizado, nunca acima.
    for (var t = 0; t < 30; t++) {
      e.tick(_frame(_play), instr, preset);
      expect(e.targetSendsDb(instr, preset)[3]! <= base + 1e-9, isTrue);
    }
    expect(e.targetSendsDb(instr, preset)[3], closeTo(base, 0.01));
  });

  test('proteção desligada = 100% estático', () {
    final e = equalized()..protectionEnabled = false;
    final base = e.targetSendsDb(instr, preset)[3]!;
    for (var t = 0; t < 10; t++) {
      e.tick(_frame(List.of(_play)..[2] = _play[2] + 12), instr, preset);
    }
    expect(e.targetSendsDb(instr, preset)[3], base);
  });

  test('volume geral: desce livre, sobe até o teto sem quebrar o balanço', () {
    final e = equalized();
    final base = e.targetSendsDb(instr, preset);
    e.masterDb = -6;
    expect(e.targetSendsDb(instr, preset)[1], closeTo(base[1]! - 6, 0.01));
    e.masterDb = 12; // topo em 0 dB → só +10 de folga
    final up = e.targetSendsDb(instr, preset);
    for (var ch = 1; ch <= 5; ch++) {
      expect(up[ch], closeTo(base[ch]! + 10, 0.01));
    }
    expect(e.masterHeadroomDb(instr, preset), closeTo(10, 0.01));
  });

  test('trocar o estilo rebalanceia sem medir de novo', () {
    final e = equalized();
    final rock = kGenrePresets[Genre.rock]!;
    final s = e.targetSendsDb(instr, rock);
    final dKick = (_play[4] + s[5]!) - (_play[0] + s[1]!);
    expect(dKick, closeTo(rock.targetFor(InstrumentType.kick), 0.01));
  });

  test('fader manual vira ajuste fino (não briga com o músico)', () {
    final e = equalized();
    final base = e.targetSendsDb(instr, preset)[2]!;
    e.setManualSend(2, base + 4, instr, preset);
    expect(e.targetSendsDb(instr, preset)[2], closeTo(base + 4, 0.01));
    expect(e.tick(_frame(_play), instr, preset).where((c) => c.ch == 2), isEmpty);
  });

  group('reequalizar com alguém calado', () {
    EqualizerEngine reequalized(EqualizerEngine e, int silentCh, {double shift = 0}) {
      e.startMeasure();
      for (var t = 0; t < 75; t++) {
        final f = [for (final v in _play) v + shift]..[silentCh - 1] = -90.0;
        e.addSample(_frame(f));
      }
      final r = e.finish(_sendsAt(0.0), instruments: instr, preset: preset);
      expect(r.remembered, [silentCh]);
      expect(r.unheard, isEmpty);
      return e;
    }

    test('o calado mantém o ajuste (não volta pro send de antes)', () {
      final e = equalized();
      final before = e.targetSendsDb(instr, preset);
      reequalized(e, 3); // guitarra calada
      expect(e.targetSendsDb(instr, preset)[3], closeTo(before[3]!, 0.01));
    });

    test('a voz calada não faz o mix inteiro saltar', () {
      final e = equalized();
      final before = e.targetSendsDb(instr, preset);
      reequalized(e, 1); // voz (canal que mais pede send) calada
      final after = e.targetSendsDb(instr, preset);
      for (var ch = 1; ch <= 5; ch++) {
        expect(after[ch], closeTo(before[ch]!, 0.01), reason: 'ch$ch');
      }
    });

    test('reequalizar não move o fone: re-medido rebalanceia, lembrado parado', () {
      final e = equalized();
      final before = e.targetSendsDb(instr, preset);
      // Banda tocando 4 dB mais forte (refrão); guitarra calada na hora.
      reequalized(e, 3, shift: 4);
      expect(e.levelDb[1], closeTo(_play[0] + 4, 0.01));
      expect(e.levelDb[3], closeTo(_play[2], 0.01)); // lembrado
      // A referência fica travada: quem está 4 dB mais forte desce 4 no send
      // (mesmo nível no fone) e a guitarra lembrada não se mexe — antes ela
      // subia junto e ficava alta quando voltava (log da igreja).
      final after = e.targetSendsDb(instr, preset);
      expect(after[2]! - before[2]!, closeTo(-4, 0.01));
      expect(after[3], closeTo(before[3]!, 0.01));
    });

    test('ajuste fino do calado é preservado; o do re-medido zera', () {
      final e = equalized();
      final b = e.targetSendsDb(instr, preset);
      e.setManualSend(3, b[3]! + 3, instr, preset);
      e.setManualSend(2, b[2]! + 3, instr, preset);
      reequalized(e, 3);
      final a = e.targetSendsDb(instr, preset);
      expect(a[3], closeTo(b[3]! + 3, 0.01));
      expect(a[2], closeTo(b[2]!, 0.01));
    });

    test('desligar e equalizar de novo começa do zero', () {
      final e = equalized()..deactivate();
      e.startMeasure();
      for (var t = 0; t < 75; t++) {
        e.addSample(_frame(List.of(_play)..[2] = -90.0));
      }
      final r = e.finish(_sendsAt(0.0), instruments: instr, preset: preset);
      expect(r.remembered, isEmpty);
      expect(e.targetSendsDb(instr, preset)[3], 0.0); // send original
    });
  });

  group('meu instrumento', () {
    double ear(Map<int, double> s, int ch) => _play[ch - 1] + s[ch]!;

    test('tecladista: o teclado sobe +6, guitarra desce, voz mantém', () {
      final e = equalized();
      final none = e.targetSendsDb(instr, preset);
      e.ownChannel = 2; // teclado
      final mine = e.targetSendsDb(instr, preset);
      // Relativo à voz (que não muda de papel pro tecladista):
      double rel(Map<int, double> s, int ch) => ear(s, ch) - ear(s, 1);
      expect(rel(mine, 2) - rel(none, 2), closeTo(6, 0.01));
      expect(rel(mine, 3) - rel(none, 3), closeTo(-3, 0.01)); // guitarra
      expect(rel(mine, 4) - rel(none, 4), closeTo(0, 0.01)); // baixo
      // O topo continua em 0 dB (agora é o teclado).
      expect(mine[2], closeTo(0, 0.01));
    });

    test('baterista: o kit todo e o baixo sobem', () {
      final e = equalized()..ownChannel = 5; // bumbo
      final none = (equalized()).targetSendsDb(instr, preset);
      final mine = e.targetSendsDb(instr, preset);
      double rel(Map<int, double> s, int ch) => ear(s, ch) - ear(s, 1);
      expect(rel(mine, 5) - rel(none, 5), closeTo(4, 0.01)); // bumbo = kit, sem extra
      expect(rel(mine, 4) - rel(none, 4), closeTo(4, 0.01)); // baixo
      expect(rel(mine, 2) - rel(none, 2), closeTo(-3, 0.01)); // teclado
    });

    test('sem meu canal = balanço de plateia (voz na frente)', () {
      final e = equalized()..ownChannel = null;
      final s = e.targetSendsDb(instr, preset);
      expect(ear(s, 2) - ear(s, 1), closeTo(preset.targetFor(InstrumentType.keys), 0.01));
    });

    test('trocar o meu canal vale na hora (sem medir de novo)', () {
      final e = equalized();
      e.tick(_frame(_play), instr, preset);
      e.ownChannel = 3;
      final cmds = e.tick(_frame(_play), instr, preset);
      expect(cmds, isNotEmpty);
    });
  });

  group('casos do culto (log 21/10)', () {
    EqualizerEngine measure(List<double> five, {Map<int, double>? sends,
        List<InstrumentType>? types, void Function(EqualizerEngine)? setup}) {
      final e = EqualizerEngine();
      setup?.call(e);
      e.startMeasure();
      for (var t = 0; t < 75; t++) {
        e.addSample(_frame(five));
      }
      e.finish(sends ?? _sendsAt(0.0), instruments: types ?? instr, preset: preset);
      return e;
    }

    test('canal desconhecido (DM com ruído) não é equalizado nem afunda o mix', () {
      final types = List.of(instr)..[5] = InstrumentType.unknown;
      final clean = measure(_play, types: types);
      final withDm = measure([..._play, -60.0], types: types);
      expect(withDm.levelDb.containsKey(6), isFalse);
      final a = clean.targetSendsDb(types, preset), b = withDm.targetSendsDb(types, preset);
      for (var ch = 1; ch <= 5; ch++) {
        expect(b[ch], closeTo(a[ch]!, 0.01), reason: 'ch$ch');
      }
      expect(b[6], 0.0); // fica como a mesa tinha
    });

    test('um mic muito baixo não puxa o mix inteiro pra baixo', () {
      final types = List.of(instr)..[5] = InstrumentType.backingVocal;
      final clean = measure(_play, types: types);
      final quiet = measure([..._play, -58.0], types: types); // 40 dB abaixo do bumbo
      final a = clean.targetSendsDb(types, preset), b = quiet.targetSendsDb(types, preset);
      expect(b[1], closeTo(a[1]!, 0.01)); // voz não afundou
      expect(b[6]! <= 10.0, isTrue); // o baixinho vai até o teto, no máximo
    });

    test('só o teclado tocando → avisa e não aplica', () {
      final e = EqualizerEngine()..startMeasure();
      for (var t = 0; t < 75; t++) {
        e.addSample(_frame([-90, -28, -90, -90, -90]));
      }
      final r = e.finish(_sendsAt(0.0), instruments: instr, preset: preset);
      expect(r.tooFew, isTrue);
      expect(r.ok, isFalse);
      expect(e.isActive, isFalse);
    });

    test('desligado na mesa: avisa, fica off; "No meu fone" inclui sem medir de novo', () {
      final sends = _sendsAt(0.0)..[3] = -66.0; // violão a 0,05 na mesa
      final e = measure(_play, sends: sends);
      expect(e.targetSendsDb(instr, preset)[3], -66.0);
      e.forcedIn = {3};
      final s2 = e.targetSendsDb(instr, preset);
      expect(_play[2] + s2[3]! - (_play[0] + s2[1]!),
          closeTo(preset.targetFor(InstrumentType.guitar), 0.01));
    });

    test('"Fora do meu fone": zera o canal e não é medido', () {
      final e = measure(_play, setup: (e) => e.excluded = {5});
      expect(e.levelDb.containsKey(5), isFalse);
      expect(e.targetSendsDb(instr, preset)[5], -90.0);
      e.excluded = {};
      expect(e.targetSendsDb(instr, preset)[5], 0.0); // volta ao da mesa
    });

    test('resultado lista desligados na mesa e desconhecidos', () {
      final types = List.of(instr)..[5] = InstrumentType.unknown;
      final e = EqualizerEngine()..startMeasure();
      for (var t = 0; t < 75; t++) {
        e.addSample(_frame([..._play, -40.0]));
      }
      final r = e.finish(_sendsAt(0.0)..[3] = -90.0, instruments: types, preset: preset);
      expect(r.parkedOff, [3]);
      expect(r.unknown, [6]);
      expect(r.balanced, isNot(contains(3)));
    });
  });

  test('tick só manda o que mudou', () {
    final e = equalized();
    final first = e.tick(_frame(_play), instr, preset);
    expect(first, isNotEmpty);
    expect(e.tick(_frame(_play), instr, preset), isEmpty);
    expect(floatToDb(first.firstWhere((c) => c.ch == 1).levelFloat),
        closeTo(e.targetSendsDb(instr, preset)[1]!, 0.05));
  });
}
