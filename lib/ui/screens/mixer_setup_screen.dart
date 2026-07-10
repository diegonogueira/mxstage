import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/manual_content.dart';
import '../palette.dart';

/// Guia de configuração da mesa (X32/M32).
///
/// Tela puramente informativa — não depende de conexão nem de cliente. O
/// conteúdo vem de `lib/state/manual_content.dart` (fonte de verdade única,
/// compartilhada com o gerador de PDF). O botão "compartilhar" envia o PDF já
/// pronto (`assets/manual/configurar-mesa.pdf`) pelo share sheet do celular.
class MixerSetupScreen extends StatelessWidget {
  const MixerSetupScreen({super.key});

  static const _pdfAsset = 'assets/manual/configurar-mesa.pdf';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.panel,
        title: const Text(
          manualTitle,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Compartilhar PDF',
            onPressed: () => _shareManual(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const _Intro(),
          const SizedBox(height: 16),
          for (var i = 0; i < manualSteps.length; i++) ...[
            _StepCard(step: manualSteps[i], number: i + 1),
            const SizedBox(height: 12),
          ],
          const _Closing(),
          const SizedBox(height: 20),
          _ShareButton(onTap: () => _shareManual(context)),
        ],
      ),
    );
  }

  // Copia o PDF (asset já gerado) para um arquivo temporário e abre o share
  // sheet nativo — WhatsApp, e-mail, etc. Sem geração em runtime.
  Future<void> _shareManual(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // Origem do popover (iPad) — no celular é ignorado.
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;

    try {
      final data = await rootBundle.load(_pdfAsset);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mxwise-configurar-a-mesa.pdf');
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'MXWise — Como configurar a mesa',
          text: 'Como configurar a mesa (X32) para o Auto-Mix ler o volume real.',
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Não foi possível compartilhar o PDF.')),
      );
    }
  }
}

// ── Introdução: por que a mesa precisa estar ajustada ────────────────────────

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights, color: AppColors.blue, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  manualIntroTitle,
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < manualIntro.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Text(
              manualIntro[i],
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Cartão de um passo ───────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final ManualStep step;
  final int number;

  const _StepCard({required this.step, required this.number});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho com faixa de destaque para o passo essencial
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: step.essential
                  ? AppColors.blue.withAlpha(24)
                  : Colors.transparent,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(_iconFor(step.iconKey), size: 20, color: AppColors.blue),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (step.essential)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withAlpha(38),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'essencial',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.blue,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Block(label: 'Por quê', color: AppColors.amber, text: step.why),
                const SizedBox(height: 12),
                _Block(
                  label: 'Como conferir na mesa',
                  color: AppColors.blue,
                  text: step.check,
                ),
                const SizedBox(height: 12),
                _Block(
                  label: 'Como ajustar',
                  color: AppColors.green,
                  text: step.adjust,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Um dos três blocos rotulados dentro de um passo (Por quê / Conferir / Ajustar).
class _Block extends StatelessWidget {
  final String label;
  final Color color;
  final String text;

  const _Block({required this.label, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 11.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 14.5,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

// ── Nota final ───────────────────────────────────────────────────────────────

class _Closing extends StatelessWidget {
  const _Closing();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.green.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.green.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline, color: AppColors.green, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              manualClosing,
              style: const TextStyle(
                fontSize: 14.5,
                height: 1.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Botão de compartilhar (no rodapé da tela) ────────────────────────────────

class _ShareButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ShareButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.ios_share, size: 18, color: AppColors.blue),
      label: const Text(
        'Enviar este guia para o operador (PDF)',
        style: TextStyle(color: AppColors.blue, fontWeight: FontWeight.w600),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: AppColors.blue.withAlpha(120)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

// ── Mapa de ícones (chave lógica do conteúdo → ícone Flutter) ────────────────

IconData _iconFor(String key) {
  switch (key) {
    case 'tune':
      return Icons.tune;
    case 'alt_route':
      return Icons.alt_route;
    case 'linear_scale':
      return Icons.linear_scale;
    case 'output':
      return Icons.output;
    case 'headphones':
      return Icons.headphones;
    case 'wifi':
      return Icons.wifi;
    default:
      return Icons.settings;
  }
}
