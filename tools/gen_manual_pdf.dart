// Gera o PDF compartilhável do manual "Configurar a mesa" a partir da fonte de
// verdade única em lib/state/manual_content.dart.
//
//   dart run tools/gen_manual_pdf.dart
//
// Saídas (commitadas no repo, embutidas no app como asset):
//   assets/manual/configurar-mesa.pdf
//   assets/manual/configurar-mesa.pdf.fingerprint
//
// Dart puro — usa apenas o pacote `pdf` (dev_dependency). Não depende de
// Flutter e não roda no device: o app só compartilha o asset já pronto.
//
// O layout é claro (tema claro, para impressão/compartilhamento). Fontes Noto
// Sans embutidas garantem acentos do português. Ao editar o conteúdo, rode este
// script de novo (ou a skill `gen-manual-pdf`); o teste anti-drift cobre o resto.

import 'dart:io';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:mxstage/state/manual_content.dart';

// Paleta do PDF — variantes escuras dos acentos do app, legíveis sobre branco.
final _title = PdfColor.fromHex('1F2328'); // quase preto
final _body = PdfColor.fromHex('3B424A'); // cinza escuro
final _muted = PdfColor.fromHex('6E7681');
final _border = PdfColor.fromHex('D0D7DE');
final _why = PdfColor.fromHex('9A6700'); // âmbar escuro — "Por quê"
final _check = PdfColor.fromHex('0969DA'); // azul — "Como conferir"
final _adjust = PdfColor.fromHex('1A7F37'); // verde — "Como ajustar"
final _essentialBg = PdfColor.fromHex('DDF4FF');
final _essentialFg = PdfColor.fromHex('0550AE');
final _closingBg = PdfColor.fromHex('DAFBE1');
final _closingBorder = PdfColor.fromHex('2DA44E');

Future<void> main() async {
  final scriptDir = File.fromUri(Platform.script).parent; // tools/
  final root = scriptDir.parent;

  final regular = pw.Font.ttf(
    File('${scriptDir.path}/fonts/NotoSans-Regular.ttf')
        .readAsBytesSync()
        .buffer
        .asByteData(),
  );
  final bold = pw.Font.ttf(
    File('${scriptDir.path}/fonts/NotoSans-Bold.ttf')
        .readAsBytesSync()
        .buffer
        .asByteData(),
  );

  // Logo opcional (wordmark preto para fundo claro).
  pw.MemoryImage? logo;
  final logoFile = File('${root.path}/assets/branding/wordmark_black.png');
  if (logoFile.existsSync()) {
    logo = pw.MemoryImage(logoFile.readAsBytesSync());
  }

  final theme = pw.ThemeData.withFont(base: regular, bold: bold);

  final doc = pw.Document(
    title: manualTitle,
    author: 'MXWise · mxstage',
    // Sem creator/producer variável → saída estável para o teste anti-drift.
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: theme,
      margin: const pw.EdgeInsets.fromLTRB(40, 40, 40, 44),
      footer: _footer,
      build: (context) => [
        _headerBlock(logo),
        // Inseparable: cada card fica inteiro numa página (se não couber no
        // resto, vai todo para a próxima) em vez de partir no meio.
        for (var i = 0; i < manualSteps.length; i++)
          pw.Inseparable(child: _stepBlock(manualSteps[i], i + 1)),
        pw.Inseparable(child: _closingBlock()),
      ],
    ),
  );

  final outPdf = File('${root.path}/assets/manual/configurar-mesa.pdf');
  outPdf.parent.createSync(recursive: true);
  outPdf.writeAsBytesSync(await doc.save());

  File('${root.path}/assets/manual/configurar-mesa.pdf.fingerprint')
      .writeAsStringSync('${manualContentFingerprint()}\n');

  stdout.writeln('✓ ${outPdf.path} (${outPdf.lengthSync()} bytes)');
  stdout.writeln('✓ fingerprint ${manualContentFingerprint()}');
}

pw.Widget _headerBlock(pw.MemoryImage? logo) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      if (logo != null) pw.Image(logo, height: 22),
      if (logo != null) pw.SizedBox(height: 12),
      pw.Text(
        manualTitle,
        style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: _title),
      ),
      pw.SizedBox(height: 10),
      pw.Text(
        manualIntroTitle,
        style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _check),
      ),
      pw.SizedBox(height: 6),
      for (final p in manualIntro)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(p, style: pw.TextStyle(fontSize: 10.5, color: _body, lineSpacing: 2.5)),
        ),
      pw.SizedBox(height: 4),
      pw.Divider(color: _border, thickness: 0.8),
      pw.SizedBox(height: 8),
    ],
  );
}

pw.Widget _stepBlock(ManualStep s, int number) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 14),
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: s.essential ? _essentialBg : PdfColors.white,
      border: pw.Border.all(color: _border, width: 0.8),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Text(
                '$number. ${s.title}',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: _title),
              ),
            ),
            if (s.essential) _badge('ESSENCIAL'),
          ],
        ),
        pw.SizedBox(height: 8),
        _labeledBlock('POR QUÊ', _why, s.why),
        pw.SizedBox(height: 7),
        _labeledBlock('COMO CONFERIR NA MESA', _check, s.check),
        pw.SizedBox(height: 7),
        _labeledBlock('COMO AJUSTAR', _adjust, s.adjust),
      ],
    ),
  );
}

pw.Widget _labeledBlock(String label, PdfColor color, String text) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: color,
          letterSpacing: 0.6,
        ),
      ),
      pw.SizedBox(height: 2),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 8),
        child: pw.Text(
          text,
          style: pw.TextStyle(fontSize: 10.5, color: _body, lineSpacing: 2.5),
        ),
      ),
    ],
  );
}

pw.Widget _badge(String text) {
  return pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: pw.BoxDecoration(
      color: _essentialFg,
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 7.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        letterSpacing: 0.5,
      ),
    ),
  );
}

pw.Widget _closingBlock() {
  return pw.Container(
    padding: const pw.EdgeInsets.all(12),
    decoration: pw.BoxDecoration(
      color: _closingBg,
      border: pw.Border.all(color: _closingBorder, width: 0.8),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Text(
      manualClosing,
      style: pw.TextStyle(fontSize: 11, color: _title, lineSpacing: 2.5),
    ),
  );
}

pw.Widget _footer(pw.Context context) {
  return pw.Container(
    alignment: pw.Alignment.centerRight,
    margin: const pw.EdgeInsets.only(top: 8),
    child: pw.Text(
      'MXWise · Auto-Mix de retorno    ·    página ${context.pageNumber}/${context.pagesCount}',
      style: pw.TextStyle(fontSize: 8, color: _muted),
    ),
  );
}
