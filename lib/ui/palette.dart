import 'package:flutter/material.dart';

/// Paleta única do app — estilo "GitHub dark" pastel, herdada do simulador web.
/// Tons suaves que não cansam os olhos no escuro do palco.
///
/// Semântica dos acentos:
///  - [blue]  controles e seleção — faders, valor, aba/bus selecionado, links
///  - [green] "ligado / sinal saudável" — Auto-Mix ativo, medidor na zona boa
///  - [amber] atenção — canal não identificado, medidor na zona média
///  - [red]   perigo/clip — nível alto, medidor no vermelho, mute
abstract final class AppColors {
  // Superfícies
  static const canvas = Color(0xFF0D1117); // fundo das telas
  static const panel = Color(0xFF161B22); // cards, app bar, bottom sheets
  static const elevated = Color(0xFF1C2128); // menus / dropdowns
  static const track = Color(0xFF2C333D); // trilho inativo de fader/medidor

  // Bordas
  static const border = Color(0xFF30363D);
  static const borderMuted = Color(0xFF21262D);

  // Texto
  static const textPrimary = Color(0xFFE6EDF3);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted = Color(0xFF6E7681);

  // Acentos pastel
  static const blue = Color(0xFF58A6FF);
  static const green = Color(0xFF3FB950);
  static const amber = Color(0xFFD29922);
  static const red = Color(0xFFF85149);

  // Marca — ciano do wordmark "Wise" (MXWise), mais elétrico que o [blue].
  static const cyan = Color(0xFF2BC4F2);
}
