import 'package:flutter/material.dart';

import '../palette.dart';

/// Marca **MXWise** — logo (monograma MX sobre barras de equalizador) e wordmark.
///
/// O wordmark é desenhado como texto ("MX" branco + "Wise" ciano) para ficar
/// nítido em qualquer tamanho sobre o fundo escuro do palco; a logo usa o ícone
/// real do app (`assets/branding/app_icon.png`).

/// Ícone do app (monograma MX + barras), com cantos arredondados.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset(
        'assets/branding/app_icon.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Wordmark "MXWise": "MX" em branco, "Wise" no ciano da marca.
class BrandWordmark extends StatelessWidget {
  final double fontSize;
  const BrandWordmark({super.key, this.fontSize = 24});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'MXWise',
      child: ExcludeSemantics(
        child: RichText(
          text: TextSpan(
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.0,
            ),
            children: const [
              TextSpan(
                text: 'MX',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              TextSpan(
                text: 'Wise',
                style: TextStyle(color: AppColors.cyan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Logo + wordmark lado a lado — para app bars e cabeçalhos compactos.
class BrandLockup extends StatelessWidget {
  final double logoSize;
  final double fontSize;
  const BrandLockup({super.key, this.logoSize = 26, this.fontSize = 19});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogo(size: logoSize),
        SizedBox(width: logoSize * 0.4),
        BrandWordmark(fontSize: fontSize),
      ],
    );
  }
}

/// Bloco de marca centralizado (logo + wordmark + tagline) para o topo da
/// tela principal.
class BrandHero extends StatelessWidget {
  const BrandHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: const [
        AppLogo(size: 76),
        SizedBox(height: 14),
        BrandWordmark(fontSize: 34),
        SizedBox(height: 7),
        Text(
          'Mix inteligente. Equilíbrio automático.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            color: AppColors.textSecondary,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}
