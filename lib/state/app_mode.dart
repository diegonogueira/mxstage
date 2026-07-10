import 'package:flutter/material.dart';

import '../ui/palette.dart';

/// PIN fixo temporário que trava a **entrada** no modo Live.
///
/// TEMP — prevenção de acidente/curiosidade para teste, não segurança forte
/// (o X32 não autentica cliente na rede). Trocar por token assinado
/// provisionado por device. Ver plano de segurança.
const String kLivePin = '7733';

/// Contexto de uso do app.
///
/// **Não** altera o caminho de mixagem — o `MixerClient` continua agnóstico e
/// só dirige o bus selecionado. O modo muda apenas o *alvo* (qual bus), o
/// *portão* de entrada e a *apresentação* (rótulos, ícone, acento, badge).
enum AppMode {
  stage(
    label: 'Stage',
    shortLabel: 'STAGE',
    icon: Icons.headphones,
    accent: AppColors.blue,
    locked: false,
    busPickerTitle: 'Meu bus de retorno',
    busPickerSubtitle: 'Trocar de bus desliga o Auto-Mix por segurança.',
  ),
  live(
    label: 'Live',
    shortLabel: 'LIVE',
    icon: Icons.podcasts,
    accent: AppColors.red, // convenção "ON AIR"
    locked: true,
    busPickerTitle: 'Bus da transmissão',
    busPickerSubtitle: 'Escolha o bus que alimenta a live. Trocar desliga o Auto-Mix.',
  );

  const AppMode({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.accent,
    required this.locked,
    required this.busPickerTitle,
    required this.busPickerSubtitle,
  });

  final String label;
  final String shortLabel;
  final IconData icon;
  final Color accent;

  /// Exige PIN para entrar.
  final bool locked;

  final String busPickerTitle;
  final String busPickerSubtitle;

  bool get isLive => this == AppMode.live;
}
