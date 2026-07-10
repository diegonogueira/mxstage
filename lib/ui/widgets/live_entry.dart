import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../../state/app_settings.dart';
import '../palette.dart';
import 'bus_picker.dart';
import 'pin_gate.dart';

// Palavras que, no nome de um bus, indicam que ele é o da transmissão.
const _kLiveBusKeywords = ['live', 'transmiss', 'stream', 'broadcast', 'youtube'];

/// Fluxo de entrada no Live a partir do seletor de bus.
///
/// Pede o PIN e resolve qual bus é o da transmissão: o lembrado, senão um bus
/// nomeado "Live"/"Transmissão"/… na própria mesa, senão pede pra designar um
/// (uma vez). Retorna o bus a abrir no modo Live — que também fica lembrado —,
/// ou `null` se o usuário errou o PIN / cancelou.
Future<int?> enterLiveBus(BuildContext context, MixerClient client) async {
  final ok = await showPinGate(context);
  if (!ok || !context.mounted) return null;

  // Um bus nomeado "Live"/"Transmissão"/… na mesa é o sinal mais forte da
  // intenção do operador e ganha de uma escolha lembrada (que pode ter ficado
  // obsoleta — ex.: apontando pro monitor de um músico). Só cai na lembrada, e
  // por fim na designação manual, se não houver bus nomeado.
  var bus = _detectLiveBus(client) ?? await AppSettings.liveBus();
  if (!context.mounted) return null;
  bus ??= await _designateLiveBus(context, client);

  if (bus != null) await AppSettings.setLiveBus(bus);
  return bus;
}

/// Como [enterLiveBus], mas sempre abre a designação manual (ignora o lembrado)
/// — para trocar qual bus é o da transmissão.
Future<int?> changeLiveBus(BuildContext context, MixerClient client) async {
  final ok = await showPinGate(context);
  if (!ok || !context.mounted) return null;
  final bus = await _designateLiveBus(context, client);
  if (bus != null) await AppSettings.setLiveBus(bus);
  return bus;
}

/// Procura um bus nomeado como transmissão. Chamado só depois de conectar (os
/// nomes já chegaram), então uma varredura única basta.
int? _detectLiveBus(MixerClient client) {
  for (var i = 0; i < client.busNames.length; i++) {
    final name = client.busNames[i]?.toLowerCase() ?? '';
    if (_kLiveBusKeywords.any(name.contains)) return i + 1;
  }
  return null;
}

/// Setup único: pede pra escolher qual bus alimenta a transmissão. Retorna o
/// bus escolhido, ou `null` se cancelado.
Future<int?> _designateLiveBus(BuildContext context, MixerClient client) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(
              children: [
                Icon(Icons.podcasts, color: AppColors.red, size: 20),
                SizedBox(width: 8),
                Text(
                  'Qual bus é a transmissão?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const LiveSetupBanner(),
          Flexible(
            child: BusPickerList(
              client: client,
              shrinkWrap: true,
              onPick: (bus) => Navigator.of(sheetCtx).pop(bus),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Banner de orientação para a designação única do bus da transmissão.
class LiveSetupBanner extends StatelessWidget {
  const LiveSetupBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.red.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.red.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: AppColors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
                children: [
                  TextSpan(
                    text: 'Configuração única. ',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(text: 'Escolha o bus '),
                  TextSpan(
                    text: 'dedicado',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  TextSpan(
                    text: ' à transmissão — o que você roteou pra placa de '
                        'streaming na mesa. Não use o monitor de um músico. '
                        'Dica: nomeie esse bus como "Live" na X32 e o app passa a '
                        'reconhecê-lo sozinho.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
