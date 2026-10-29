import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../../state/channel_inclusion.dart';
import '../../state/channel_mapper.dart';
import '../../state/instrument_type.dart';
import '../instrument_visuals.dart';
import '../palette.dart';
import '../widgets/channel_actions.dart';

/// Canal sem nome na mesa ("" ou o "Ch 25" padrão do app).
bool isUnnamedChannel(ChannelInfo c) => ChannelMapper.isUnnamed(c.name);

/// "Mapear canais" — diz o que é cada canal de uma vez, em grupos, em vez de
/// segurar canal por canal no meio do culto. É o passo 2 do fluxo (mesa →
/// mapear → bus → meu instrumento): abre sozinha na primeira conexão a cada
/// mesa, e fica no menu ⋮ do mixer.
///
/// O tipo de instrumento e os **pares estéreo** valem pra mesa toda (todo
/// músico se beneficia); "No fone / Fora" vale pro bus escolhido (escondido
/// quando ainda não há bus). Canais sem nome ficam escondidos e nunca contam no
/// Equalizar até alguém dizer o que são. O ponto verde acende quando o canal tem
/// som: alguém fala no microfone e você vê qual é.
class ChannelMapScreen extends StatefulWidget {
  final MixerClient client;
  final ChannelActions actions;

  /// O seletor "Meu instrumento" do mixer (mesmo widget, mesma persistência).
  final Widget? ownPicker;

  const ChannelMapScreen({
    super.key,
    required this.client,
    required this.actions,
    this.ownPicker,
  });

  @override
  State<ChannelMapScreen> createState() => _ChannelMapScreenState();
}

class _ChannelMapScreenState extends State<ChannelMapScreen> {
  bool _showUnnamed = false;

  MixerClient get _client => widget.client;
  ChannelActions get _actions => widget.actions;

  String _label(int ch) =>
      '${ch.toString().padLeft(2, '0')} ${_client.channels[ch - 1].name.trim().isEmpty ? '(sem nome)' : _client.channels[ch - 1].name}';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _client,
      builder: (context, _) {
        final instr = _client.instruments;
        // O lado "de trás" de um par não ganha linha própria.
        bool secondOfPair(ChannelInfo c) {
          final p = _client.partnerOf(c.ch);
          return p != null && p < c.ch;
        }

        final visible = [
          for (final c in _client.channels)
            if ((_showUnnamed || !isUnnamedChannel(c)) && !secondOfPair(c)) c,
        ];
        final hidden = _client.channels
            .where((c) => isUnnamedChannel(c) && !secondOfPair(c))
            .length;
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
        final suggestions = _actions.pairSuggestions();
        final dups = [
          for (final d in _client.lastEqualizeResult?.duplicates ?? const <List<int>>[])
            if (_client.partnerOf(d[0]) != d[1]) d,
        ];

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
                  'Diga o que é cada canal (vale pra mesa toda). Peça pra alguém '
                  'falar ou tocar e veja qual ponto acende. Toque no canal pra '
                  'trocar o instrumento; ⋮ pra juntar como estéreo.',
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
              if (suggestions.isNotEmpty || dups.isNotEmpty)
                _suggestionsCard(suggestions, dups),
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

  // Pares sugeridos (link da mesa, nomes L/R) e canais que parecem cópia um do
  // outro (mesmo som na última equalização — o "teclado em três canais").
  Widget _suggestionsCard(List<List<int>> pairs, List<List<int>> dups) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.call_split, size: 16, color: AppColors.green),
            SizedBox(width: 6),
            Text('Estéreo e duplicados',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          for (final p in pairs)
            _suggestion(
              '${_label(p[0])} + ${_label(p[1])}',
              'parece um par estéreo',
              [
                TextButton(
                  onPressed: () => _actions.link(p[0], p[1]),
                  child: const Text('Juntar'),
                ),
              ],
            ),
          for (final d in dups)
            _suggestion(
              '${_label(d[1])} = ${_label(d[0])}',
              'mesmo som — parece cópia (conta dobrado)',
              [
                TextButton(
                  onPressed: () => _actions.link(d[0], d[1]),
                  child: const Text('Juntar'),
                ),
                TextButton(
                  onPressed: () => _actions.setInclusion(d[1], ChannelInclusion.exclude),
                  child: Text('Tirar o ${d[1]}'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _suggestion(String title, String why, List<Widget> actions) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13)),
                Text(why,
                    style: const TextStyle(fontSize: 11, color: Colors.white38)),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }

  Widget _section(String title, IconData icon, Color color, List<ChannelInfo> chs) {
    final withIncl = _actions.withInclusion;
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
              if (withIncl)
                TextButton(
                  onPressed: () {
                    for (final c in chs) {
                      _actions.setInclusion(c.ch,
                          allOut ? ChannelInclusion.auto : ChannelInclusion.exclude);
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
    final partner = _client.partnerOf(c.ch);
    final incl = _client.inclusionOf(c.ch);
    final parked = _client.isParkedAtMesa(c.ch);
    bool signalOn(int ch) => _client.meterDisplayDb(ch - 1) > -50;
    final signal = signalOn(c.ch) || (partner != null && signalOn(partner));
    final out = incl == ChannelInclusion.exclude;
    final withIncl = _actions.withInclusion;
    final title = partner == null
        ? _label(c.ch)
        : '${_label(c.ch)} + ${_client.channels[partner - 1].name}';

    return Opacity(
      opacity: out ? 0.5 : 1,
      child: ListTile(
        dense: true,
        onTap: () => _actions.edit(context, c),
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
        title: Text(title, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [
            t == InstrumentType.unknown ? 'Toque pra dizer o que é' : t.label,
            if (partner != null) 'estéreo',
            if (_client.isOverridden(c.ch)) 'ajustado',
            if (withIncl && parked && incl == ChannelInclusion.auto) 'desligado na mesa',
          ].join(' · '),
          style: TextStyle(
              fontSize: 11.5,
              color: t == InstrumentType.unknown ? AppColors.amber : Colors.white38),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (withIncl) _InclusionChip(value: incl, parked: parked),
            PopupMenuButton<String>(
              tooltip: 'Opções do canal',
              color: AppColors.elevated,
              icon: const Icon(Icons.more_vert, size: 18, color: Colors.white54),
              onSelected: (v) {
                switch (v) {
                  case 'auto':
                    _actions.setInclusion(c.ch, ChannelInclusion.auto);
                  case 'include':
                    _actions.setInclusion(c.ch, ChannelInclusion.include);
                  case 'exclude':
                    _actions.setInclusion(c.ch, ChannelInclusion.exclude);
                  case 'unpair':
                    _actions.unlink(c.ch);
                  default:
                    if (v.startsWith('pair:')) {
                      _actions.link(c.ch, int.parse(v.substring(5)));
                    }
                }
              },
              itemBuilder: (_) => [
                if (withIncl) ...const [
                  PopupMenuItem(value: 'auto', child: Text('Como na mesa')),
                  PopupMenuItem(
                      value: 'include',
                      child: Text('No meu fone (mesmo desligado na mesa)')),
                  PopupMenuItem(value: 'exclude', child: Text('Fora do meu fone')),
                  PopupMenuDivider(),
                ],
                if (partner != null)
                  const PopupMenuItem(value: 'unpair', child: Text('Separar o estéreo'))
                else
                  for (final n in [c.ch - 1, c.ch + 1])
                    if (n >= 1 && n <= _client.channels.length && _client.partnerOf(n) == null)
                      PopupMenuItem(
                        value: 'pair:$n',
                        child: Text('Juntar como estéreo com ${_label(n)}'),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InclusionChip extends StatelessWidget {
  final ChannelInclusion value;
  final bool parked;

  const _InclusionChip({required this.value, required this.parked});

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (value) {
      ChannelInclusion.auto => parked
          ? ('Off na mesa', Icons.volume_off_outlined, Colors.white38)
          : ('Como na mesa', Icons.tune, AppColors.blue),
      ChannelInclusion.include => ('No fone', Icons.headphones, AppColors.green),
      ChannelInclusion.exclude => ('Fora', Icons.headset_off, AppColors.amber),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: color.withAlpha(140))),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11.5, color: color)),
        ],
      ),
    );
  }
}
