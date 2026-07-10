// Anti-drift + sanidade de glifos do manual "Configurar a mesa".
//
// 1) Garante que o PDF compartilhável foi regenerado depois da última edição
//    em lib/state/manual_content.dart (compara a impressão digital gravada).
// 2) Barra caracteres que a fonte embutida (Noto Sans Latin) não tem — setas,
//    operadores matemáticos, símbolos, emoji — que virariam "tofu" (□) no PDF.

import 'dart:io';

import 'package:mxwise/state/manual_content.dart';
import 'package:test/test.dart';

void main() {
  const regenHint = 'Rode: dart run tools/gen_manual_pdf.dart';

  test('PDF do manual está em dia com manual_content.dart', () {
    final pdf = File('assets/manual/configurar-mesa.pdf');
    final fingerprint = File('assets/manual/configurar-mesa.pdf.fingerprint');

    expect(pdf.existsSync(), isTrue, reason: 'PDF ausente. $regenHint');
    expect(fingerprint.existsSync(), isTrue,
        reason: 'Fingerprint ausente. $regenHint');

    expect(
      fingerprint.readAsStringSync().trim(),
      manualContentFingerprint(),
      reason: 'O conteúdo do manual mudou mas o PDF não foi regenerado. '
          '$regenHint',
    );
  });

  test('conteúdo usa só glifos que a Noto Sans (Latin) tem', () {
    final texts = <String>[
      manualTitle,
      manualIntroTitle,
      manualClosing,
      ...manualIntro,
      for (final s in manualSteps) ...[s.title, s.why, s.check, s.adjust],
    ];

    final offenders = <String>[];
    for (final text in texts) {
      for (final rune in text.runes) {
        if (_unsupportedGlyph(rune)) {
          final hex = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
          offenders.add('U+$hex (${String.fromCharCode(rune)}) em "$text"');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'Estes caracteres não existem na Noto Sans e viram □ no PDF. '
          'Troque por texto/ASCII (ex.: "→" por vírgula, "−" por "-"):\n'
          '${offenders.join('\n')}',
    );
  });
}

/// Blocos Unicode que a Noto Sans Latin não cobre e que aparecem como tofu:
/// setas (2190–21FF), operadores matemáticos (2200–22FF), técnicos (2300–23FF),
/// box/blocos/formas/símbolos/dingbats (2500–27BF) e emoji/pictogramas (astral).
bool _unsupportedGlyph(int rune) {
  return (rune >= 0x2190 && rune <= 0x23FF) ||
      (rune >= 0x2500 && rune <= 0x27BF) ||
      rune >= 0x1F000;
}
