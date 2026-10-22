import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../../state/channel_inclusion.dart';
import '../../state/instrument_type.dart';
import '../instrument_visuals.dart';
import '../palette.dart';

final _defaultName = RegExp(r'^ch\s*\d+$', caseSensitive: false);

/// Canal sem nome na mesa ("" ou o "Ch 25" padrão do app).
bool isUnnamedChannel(ChannelInfo c) =>
    c.name.trim().isEmpty || _defaultName.hasMatch(c.name.trim());

/// "Mapear canais" — diz o que é cada canal de uma vez, em grupos, em vez de
/// segurar canal por canal no meio do culto. Abre sozinha depois de escolher o
/// bus quando há canais com nome mas sem instrumento conhecido (Igor, Brenda,
/// DM…), e fica no menu ⋮ do mixer.
///
/// O tipo de instrumento vale pra **mesa toda** (todo músico se beneficia); "No
/// fone / Fora" vale pro **bus** escolhido. Canais sem nome ficam escondidos. O
/// ponto verde acende quando o canal tem som: alguém fala no microfone e você
/// vê qual é.
class ChannelMapScreen extends StatefulWidget {
  final MixerClient client;

  /// O seletor "Meu instrumento" do mixer (mesmo widget, mesma persistência).
  final Widget? ownPicker;

  /// Abre o editor completo do canal (tipo, reforço, no/fora do fone).
  final void Function(ChannelInfo ch) onEdit;

  final void Function(int ch, ChannelInclusion v) onInclusion;

  const ChannelMapScreen({
    super.key,
    required this.client,
    required this.onEdit,
    required this.onInclusion,
    this.ownPicker,
  });

  @override
  State<ChannelMapScreen> createState() => _ChannelMapScreenState();
}

class _ChannelMapScreenState extends State<ChannelMapScreen> {
  bool _showUnnamed = false;

  MixerClient get _client => widget.client;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _client,
      builder: (context, _) {
        final instr = _client.instruments;
        final visible = [
          for (final c in _client.channels)
            if (_showUnnamed || !isUnnamedChannel(c)) c,
        ];
        final hidden = _client.channels.length - visible.length;
        final unknown = [
          for (final c in visible)
            if (instr[c.ch - 1] == InstrumentType.unknown) c,
        ];
        final groups = <InstrumentGroup, List<ChannelInfo>>{};
        for (final c in visible) {
          final t = instr[c.ch - 1];
          if (t == InstrumentType.unknown) continue;
          groups.putIfAbsent(instrumentGroup(t), () => []).add(c);
        }

        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            backgroundColor: AppColors.panel,
            title: const Text('Mapear canais'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Pronto'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Diga o que é cada canal. Peça pra alguém falar ou tocar e veja '
                  'qual ponto acende. Toque no canal pra trocar o instrumento.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
              ),
              if (widget.ownPicker != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    const Text('Eu toco:',
                        style: TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(width: 8),
                    Flexible(child: widget.ownPicker!),
                  ]),
                ),
              if (unknown.isNotEmpty)
                _section(
                  'Sem instrumento (o Equalizar ignora)',
                  Icons.help_outline,
                  AppColors.amber,
                  unknown,
                ),
              for (final g in kInstrumentGroupOrder)
                if (groups[g] != null)
                  _section(g.label, g.icon, AppColors.blue, groups[g]!),
              if (hidden > 0 || _showUnnamed)
                TextButton(
                  onPressed: () => setState(() => _showUnnamed = !_showUnnamed),
                  child: Text(_showUnnamed
                      ? 'Esconder canais sem nome'
                      : 'Mostrar canais sem nome ($hidden)'),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(String title, IconData icon, Color color, List<ChannelInfo> chs) {
    final allOut =
        chs.every((c) => _client.inclusionOf(c.ch) == ChannelInclusion.exclude);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600, color: color)),
              ),
              // Em grupo: "tudo fora" (ex.: a bateria acústica que você já ouve
              // na sala) ou voltar tudo pro que a mesa tem.
              TextButton(
                onPressed: () {
                  for (final c in chs) {
                    widget.onInclusion(
                        c.ch, allOut ? ChannelInclusion.auto : ChannelInclusion.exclude);
                  }
                },
                child: Text(allOut ? 'Voltar todos' : 'Todos fora',
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        for (final c in chs) _row(c),
      ],
    );
  }

  Widget _row(ChannelInfo c) {
    final t = _client.instruments[c.ch - 1];
    final incl = _client.inclusionOf(c.ch);
    final parked = _client.isParkedAtMesa(c.ch);
    final signal = _client.meterDisplayDb(c.ch - 1) > -50;
    final out = incl == ChannelInclusion.exclude;

    return Opacity(
      opacity: out ? 0.5 : 1,
      child: ListTile(
        dense: true,
        onTap: () => widget.onEdit(c),
        leading: SizedBox(
          width: 44,
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: signal ? AppColors.green : AppColors.track,
                ),
              ),
              const SizedBox(width: 8),
              Icon(instrumentIcon(t),
                  size: 18,
                  color: t == InstrumentType.unknown ? AppColors.amber : Colors.white60),
            ],
          ),
        ),
        title: Text('${c.ch.toString().padLeft(2, '0')} · ${c.name}',
            overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            t == InstrumentType.unknown ? 'Toque pra dizer o que é' : t.label,
            if (_client.isOverridden(c.ch)) 'ajustado',
            if (parked && incl == ChannelInclusion.auto) 'desligado na mesa',
          ].join(' · '),
          style: TextStyle(
              fontSize: 11.5,
              color: t == InstrumentType.unknown ? AppColors.amber : Colors.white38),
        ),
        trailing: _InclusionMenu(
          value: incl,
          parked: parked,
          onChanged: (v) => widget.onInclusion(c.ch, v),
        ),
      ),
    );
  }
}

class _InclusionMenu extends StatelessWidget {
  final ChannelInclusion value;
  final bool parked;
  final ValueChanged<ChannelInclusion> onChanged;

  const _InclusionMenu({
    required this.value,
    required this.parked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (value) {
      ChannelInclusion.auto => parked
          ? ('Off na mesa', Icons.volume_off_outlined, Colors.white38)
          : ('Como na mesa', Icons.tune, AppColors.blue),
      ChannelInclusion.include => ('No fone', Icons.headphones, AppColors.green),
      ChannelInclusion.exclude => ('Fora', Icons.headset_off, AppColors.amber),
    };
    return PopupMenuButton<ChannelInclusion>(
      tooltip: 'No meu fone?',
      color: AppColors.elevated,
      onSelected: onChanged,
      itemBuilder: (_) => const [
        PopupMenuItem(value: ChannelInclusion.auto, child: Text('Como na mesa')),
        PopupMenuItem(
            value: ChannelInclusion.include,
            child: Text('No meu fone (mesmo desligado na mesa)')),
        PopupMenuItem(value: ChannelInclusion.exclude, child: Text('Fora do meu fone')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: ShapeDecoration(
          shape: StadiumBorder(side: BorderSide(color: color.withAlpha(140))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: color)),
          ],
        ),
      ),
    );
  }
}
