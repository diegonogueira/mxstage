import 'package:flutter/material.dart';

import '../../state/app_mode.dart';

/// Chip compacto para a app bar mostrando o contexto atual (Stage/Live), para
/// que nunca haja dúvida sobre qual mix está sendo controlado. O ponto vermelho
/// no Live reforça a convenção "ON AIR".
class ModeBadge extends StatelessWidget {
  final AppMode mode;

  const ModeBadge({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: mode.accent.withAlpha(30),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: mode.accent.withAlpha(120)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (mode.isLive) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: mode.accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            mode.shortLabel,
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w700,
              color: mode.accent,
            ),
          ),
        ],
      ),
    );
  }
}
