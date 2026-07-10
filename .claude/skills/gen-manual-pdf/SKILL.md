---
name: gen-manual-pdf
description: >-
  Regenera o PDF compartilhável do manual "Configurar a mesa" a partir de
  lib/state/manual_content.dart. USE SEMPRE que editar o conteúdo do manual —
  título, introdução, passos (title/why/check/adjust/essential) ou nota final —
  para o PDF embutido no app não envelhecer e o teste anti-drift continuar verde.
  Também aplica se mexer nas fontes em tools/fonts/ ou no layout do gerador.
---

# Regenerar o PDF do manual

O manual "Configurar a mesa" tem **uma fonte de verdade**:
`lib/state/manual_content.dart` (Dart puro). Dela saem dois consumidores:

- a tela `lib/ui/screens/mixer_setup_screen.dart` (mostra o conteúdo);
- o PDF `assets/manual/configurar-mesa.pdf`, **pré-gerado** e embutido como
  asset, que o botão "compartilhar" envia pelo share sheet do celular.

O PDF **não** é gerado em runtime. Ele é um artefato commitado, produzido por
`tools/gen_manual_pdf.dart`. Se o conteúdo mudar e o PDF não for regenerado,
o arquivo compartilhado fica desatualizado — por isso existe um teste que trava.

## Quando rodar esta skill

Sempre que uma edição tocar em qualquer um destes:

- `lib/state/manual_content.dart` (qualquer texto ou passo)
- `tools/gen_manual_pdf.dart` (layout/estilo do PDF)
- `tools/fonts/*.ttf` (fontes embutidas)

## Passos

1. Regenerar o PDF e a impressão digital:

   ```bash
   dart run tools/gen_manual_pdf.dart
   ```

   Saída esperada: caminho do PDF, tamanho em bytes e o `fingerprint`. Isso
   reescreve `assets/manual/configurar-mesa.pdf` e
   `assets/manual/configurar-mesa.pdf.fingerprint`.

2. Confirmar que o teste anti-drift passou:

   ```bash
   flutter test test/manual_pdf_fresh_test.dart
   ```

   Ele compara o `fingerprint` gravado com o conteúdo atual. Verde = em dia.

3. (Opcional) Conferir o conteúdo do PDF:

   ```bash
   pdftotext assets/manual/configurar-mesa.pdf - | head -40
   ```

4. Lembrar de **commitar os dois arquivos regenerados** junto com a mudança de
   conteúdo:
   - `assets/manual/configurar-mesa.pdf`
   - `assets/manual/configurar-mesa.pdf.fingerprint`

## Notas

- O gerador é Dart puro e usa o pacote `pdf` (dev_dependency) — não vai para o
  app. O app só carrega o asset já pronto via `share_plus`.
- As fontes Noto Sans (`tools/fonts/`) são embutidas no PDF para garantir os
  acentos do português; não precisam estar nos assets do app.
- Não editar o `.fingerprint` à mão: ele é derivado do conteúdo pelo gerador.
