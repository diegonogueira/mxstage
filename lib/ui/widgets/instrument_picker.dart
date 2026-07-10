import 'package:flutter/material.dart';

import '../../state/instrument_type.dart';
import '../instrument_visuals.dart';
import '../palette.dart';

/// Bottom-sheet para o músico dizer **o que um canal realmente é**, sobrepondo a
/// auto-detecção (que depende do nome que o operador pôs na mesa — muitas vezes o
/// nome da pessoa, indistinguível entre voz lead e backing).
///
/// A opção "Automático" no topo volta o canal ao tipo detectado. Espelha o estilo
/// de `showBusPicker` (`showModalBottomSheet`, painel arredondado).
///
/// [onSelected] recebe o tipo escolhido, ou `null` para voltar ao automático.
Future<void> showInstrumentPicker(
  BuildContext context, {
  required int ch,
  required String channelName,
  required InstrumentType current,
  required InstrumentType detected,
  required bool isOverridden,
  required void Function(InstrumentType? type) onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.panel,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetCtx) {
      void pick(InstrumentType? type) {
        Navigator.of(sheetCtx).pop();
        onSelected(type);
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetCtx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cabeçalho: NN · nome do canal
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    const Icon(Icons.category, color: AppColors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${ch.toString().padLeft(2, '0')} · $channelName',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'O que é este canal? O ajuste manual não depende do nome que o '
                  'operador colocou na mesa.',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AutoTile(
                        detected: detected,
                        selected: !isOverridden,
                        onTap: () => pick(null),
                      ),
                      const SizedBox(height: 8),
                      for (final group in kInstrumentGroupOrder)
                        _GroupSection(
                          group: group,
                          current: current,
                          isOverridden: isOverridden,
                          onPick: pick,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Tipos de instrumento de cada família, na ordem do enum (exclui `unknown`).
List<InstrumentType> _typesIn(InstrumentGroup group) => [
      for (final t in InstrumentType.values)
        if (t != InstrumentType.unknown && instrumentGroup(t) == group) t,
    ];

/// Tile "Automático" — volta o canal ao tipo detectado da mesa.
class _AutoTile extends StatelessWidget {
  final InstrumentType detected;
  final bool selected;
  final VoidCallback onTap;

  const _AutoTile({
    required this.detected,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final known = detected != InstrumentType.unknown;
    final subtitle =
        known ? 'detectado: ${detected.label}' : 'não identificado';
    return Material(
      color: selected ? AppColors.blue.withAlpha(28) : AppColors.elevated,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.blue : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.auto_fix_high,
                size: 18,
                color: selected ? AppColors.blue : Colors.white54,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Automático',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: selected ? AppColors.blue : Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle,
                    color: AppColors.blue, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Uma família (Vozes, Bateria, …) com seus chips de instrumento.
class _GroupSection extends StatelessWidget {
  final InstrumentGroup group;
  final InstrumentType current;
  final bool isOverridden;
  final void Function(InstrumentType) onPick;

  const _GroupSection({
    required this.group,
    required this.current,
    required this.isOverridden,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final types = _typesIn(group);
    if (types.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(group.icon, size: 13, color: Colors.white38),
              const SizedBox(width: 6),
              Text(
                group.label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in types)
                _InstrumentChip(
                  type: t,
                  // Só marca como selecionado quando é um override ativo — assim
                  // o chip não "concorre" com o tile Automático no modo detectado.
                  selected: isOverridden && t == current,
                  onTap: () => onPick(t),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstrumentChip extends StatelessWidget {
  final InstrumentType type;
  final bool selected;
  final VoidCallback onTap;

  const _InstrumentChip({
    required this.type,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            instrumentIcon(type),
            size: 14,
            color: selected ? Colors.black : Colors.white54,
          ),
          const SizedBox(width: 5),
          Text(type.label),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: false,
      backgroundColor: AppColors.elevated,
      selectedColor: AppColors.blue,
      side: BorderSide(color: selected ? Colors.transparent : AppColors.border),
      labelStyle: TextStyle(
        fontSize: 12.5,
        color: selected ? Colors.black : Colors.white70,
        fontWeight: FontWeight.w500,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
