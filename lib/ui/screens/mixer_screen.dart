import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../../osc/osc_codec.dart';
import '../../state/genre_presets.dart';
import '../../state/instrument_type.dart';
import '../instrument_visuals.dart';
import '../palette.dart';
import '../widgets/bus_picker.dart';

class MixerScreen extends StatefulWidget {
  final MixerClient client;

  const MixerScreen({super.key, required this.client});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  MixerClient get _client => widget.client;

  // Active group filter (null = show all channels).
  InstrumentGroup? _group;

  @override
  void initState() {
    super.initState();
    _client.addListener(_onClientChange);
  }

  @override
  void dispose() {
    _client.removeListener(_onClientChange);
    super.dispose();
  }

  void _onClientChange() => setState(() {});

  String _busLabel() {
    final name = _client.busName;
    final base = 'Bus ${_client.busIndex}';
    return name != null ? '$base · $name' : base;
  }

  void _showBusPicker() => showBusPicker(context, _client);

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    // Which groups actually have channels right now (so we don't show empty tabs).
    final present = <InstrumentGroup>{
      for (final ch in _client.channels)
        instrumentGroup(_client.instruments[ch.ch - 1]),
    };
    if (_group != null && !present.contains(_group)) _group = null;

    final visible = _group == null
        ? _client.channels
        : _client.channels
            .where((c) => instrumentGroup(_client.instruments[c.ch - 1]) == _group)
            .toList();

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _AutoMixBar(client: _client),
          _GroupTabs(
            present: present,
            selected: _group,
            onSelected: (g) => setState(() => _group = g),
          ),
          Expanded(
            child: _FaderBoard(
              channels: visible,
              instruments: _client.instruments,
              muted: _client.isMuted,
              isLandscape: isLandscape,
              meterDb: _client.meterDisplayDb,
              onLevelChanged: (ch, v) => _client.setChannelSend(ch, v),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.panel,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _client.mixerName ?? 'Mixer',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          InkWell(
            onTap: _showBusPicker,
            borderRadius: BorderRadius.circular(4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    _busLabel(),
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
                const Icon(Icons.arrow_drop_down, size: 15, color: Colors.white38),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _client.isMuted ? Icons.volume_off : Icons.volume_up,
            color: _client.isMuted ? AppColors.red : Colors.white54,
          ),
          tooltip: _client.isMuted ? 'Restaurar volume' : 'Mute retorno',
          onPressed: _client.toggleMute,
        ),
        IconButton(
          icon: const Icon(Icons.link_off, color: Colors.white38),
          tooltip: 'Desconectar',
          onPressed: () async {
            await _client.disconnect();
            if (mounted) Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

// ── Auto-Mix bar ─────────────────────────────────────────────────────────────

class _AutoMixBar extends StatelessWidget {
  final MixerClient client;

  const _AutoMixBar({required this.client});

  @override
  Widget build(BuildContext context) {
    final active = client.autoMixActive;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.auto_fix_high,
            size: 16,
            color: active ? AppColors.green : Colors.white24,
          ),
          const SizedBox(width: 6),
          Text(
            'Auto-Mix',
            style: TextStyle(
              fontSize: 13,
              color: active ? AppColors.green : Colors.white38,
              fontWeight: FontWeight.w500,
            ),
          ),
          Switch(
            value: active,
            onChanged: (v) => v ? client.enableAutoMix() : client.disableAutoMix(),
            activeThumbColor: AppColors.green,
          ),
          IconButton(
            icon: const Icon(Icons.help_outline, size: 18, color: Colors.white24),
            tooltip: 'Pré-requisitos',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => _showChecklist(context),
          ),
          const Spacer(),
          _GenreDropdown(client: client),
        ],
      ),
    );
  }

  void _showChecklist(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _PrereqSheet(),
    );
  }
}

// ── Genre dropdown ────────────────────────────────────────────────────────────

class _GenreDropdown extends StatelessWidget {
  final MixerClient client;

  const _GenreDropdown({required this.client});

  @override
  Widget build(BuildContext context) {
    final active = client.autoMixActive;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(
          color: active
              ? AppColors.green.withAlpha(120)
              : AppColors.green.withAlpha(40),
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<Genre>(
          value: client.genre,
          isDense: true,
          icon: const Icon(Icons.arrow_drop_down, size: 16, color: AppColors.green),
          dropdownColor: AppColors.elevated,
          onChanged: (g) {
            if (g != null) client.setGenre(g);
          },
          items: Genre.values
              .map(
                (g) => DropdownMenuItem(
                  value: g,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_note, size: 13, color: AppColors.green),
                      const SizedBox(width: 4),
                      Text(
                        g.label,
                        style: const TextStyle(fontSize: 12, color: AppColors.green),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

// ── Group filter tabs ─────────────────────────────────────────────────────────

class _GroupTabs extends StatelessWidget {
  final Set<InstrumentGroup> present;
  final InstrumentGroup? selected;
  final ValueChanged<InstrumentGroup?> onSelected;

  const _GroupTabs({
    required this.present,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final groups = kInstrumentGroupOrder.where(present.contains).toList();
    // Only one family present — nothing meaningful to filter by.
    if (groups.length < 2) return const SizedBox.shrink();

    Widget chip(String label, IconData icon, bool sel, VoidCallback onTap) {
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: sel ? Colors.black : Colors.white54),
              const SizedBox(width: 4),
              Text(label),
            ],
          ),
          selected: sel,
          onSelected: (_) => onTap(),
          showCheckmark: false,
          backgroundColor: AppColors.panel,
          selectedColor: AppColors.blue,
          side: BorderSide(
            color: sel ? Colors.transparent : AppColors.border,
          ),
          labelStyle: TextStyle(
            fontSize: 12,
            color: sel ? Colors.black : Colors.white70,
            fontWeight: FontWeight.w500,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(bottom: BorderSide(color: AppColors.borderMuted)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        children: [
          chip('Todos', Icons.apps, selected == null, () => onSelected(null)),
          for (final g in groups)
            chip(g.label, g.icon, selected == g, () => onSelected(g)),
        ],
      ),
    );
  }
}

// ── Checklist de pré-requisitos ───────────────────────────────────────────────

class _PrereqSheet extends StatefulWidget {
  const _PrereqSheet();

  @override
  State<_PrereqSheet> createState() => _PrereqSheetState();
}

class _PrereqSheetState extends State<_PrereqSheet> {
  final _checked = List.filled(_prereqs.length, false);

  @override
  Widget build(BuildContext context) {
    final allOk = _checked.every((v) => v);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rtl, color: AppColors.green, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Antes de ligar o Auto-Mix',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (allOk)
                  const Icon(Icons.check_circle, color: AppColors.green, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Confirme estes pontos com o engenheiro de som.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
            const SizedBox(height: 16),
            ..._prereqs.asMap().entries.map((e) => _PrereqTile(
                  item: e.value,
                  checked: _checked[e.key],
                  onTap: () => setState(() => _checked[e.key] = !_checked[e.key]),
                )),
            const SizedBox(height: 8),
            if (allOk)
              Center(
                child: Text(
                  'Tudo certo — pode ligar o Auto-Mix.',
                  style: TextStyle(fontSize: 13, color: AppColors.green.withAlpha(200)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PrereqTile extends StatelessWidget {
  final _PrereqItem item;
  final bool checked;
  final VoidCallback onTap;

  const _PrereqTile({required this.item, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              color: checked ? AppColors.green : Colors.white24,
              size: 20,
            ),
            const SizedBox(width: 12),
            Icon(item.icon, size: 18, color: checked ? Colors.white70 : Colors.white38),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: checked ? Colors.white : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.detail,
                    style: const TextStyle(fontSize: 11, color: Colors.white38, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrereqItem {
  final IconData icon;
  final String title;
  final String detail;

  const _PrereqItem({required this.icon, required this.title, required this.detail});
}

const _prereqs = [
  _PrereqItem(
    icon: Icons.settings_input_component,
    title: 'Sends pré-fader',
    detail:
        'O send de cada canal para o seu bus deve ser pré-fader. '
        'Assim o engenheiro pode mexer no PA sem afetar o seu retorno. '
        'Na X32: Ch → Sends → selecione o bus → Pre.',
  ),
  _PrereqItem(
    icon: Icons.tune,
    title: 'Ganho/preamp configurado',
    detail:
        'Os gains dos canais devem estar ajustados pelo engenheiro antes de usar o Auto-Mix. '
        'Se o ganho estiver muito baixo, o app vai tentar compensar mas o canal vai continuar fraco.',
  ),
  _PrereqItem(
    icon: Icons.linear_scale,
    title: 'Bus master em unidade',
    detail:
        'O fader master do seu mix bus deve estar em 0 dB (≈ 75% na X32). '
        'Um bus master zerado faz o Auto-Mix parecer que não está funcionando.',
  ),
  _PrereqItem(
    icon: Icons.headphones,
    title: 'Volume do IEM em nível médio',
    detail:
        'Coloque o volume físico do transmissor ou amplificador no ponto médio. '
        'O Auto-Mix trabalha nos sends — o volume físico é sua margem de segurança.',
  ),
  _PrereqItem(
    icon: Icons.wifi,
    title: 'Mesa e celular na mesma rede Wi-Fi',
    detail:
        'O app se comunica via UDP na rede local. '
        'Certifique-se de que o celular não está em dados móveis.',
  ),
];

// ── Fader board ───────────────────────────────────────────────────────────────

class _FaderBoard extends StatelessWidget {
  final List<ChannelInfo> channels;
  final List<InstrumentType> instruments; // full list, indexed by ch-1
  final bool muted;
  final bool isLandscape;
  final double Function(int channelIndex) meterDb;
  final void Function(int ch, double level) onLevelChanged;

  const _FaderBoard({
    required this.channels,
    required this.instruments,
    required this.muted,
    required this.isLandscape,
    required this.meterDb,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final stripW = isLandscape ? 78.0 : 86.0;

    return ScrollConfiguration(
      behavior: const _NoGlowScroll(),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: channels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final ch = channels[i];
          final chIdx = ch.ch - 1;
          return _ChannelStrip(
            channel: ch,
            instrument: chIdx >= 0 && chIdx < instruments.length
                ? instruments[chIdx]
                : InstrumentType.unknown,
            width: stripW,
            muted: muted,
            meterDb: meterDb(chIdx),
            onLevelChanged: (v) => onLevelChanged(ch.ch, v),
          );
        },
      ),
    );
  }
}

class _ChannelStrip extends StatelessWidget {
  final ChannelInfo channel;
  final InstrumentType instrument;
  final double width;
  final bool muted;
  final double meterDb;
  final ValueChanged<double> onLevelChanged;

  const _ChannelStrip({
    required this.channel,
    required this.instrument,
    required this.width,
    required this.muted,
    required this.meterDb,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final db = floatToDb(channel.sendLevel);
    final dbLabel = db <= -89 ? '-∞' : db.toStringAsFixed(1);
    final active = !muted && channel.sendLevel > 0.001;

    final known = instrument != InstrumentType.unknown;
    final idColor = muted
        ? Colors.white12
        : known
            ? AppColors.blue
            : AppColors.amber;

    return SizedBox(
      width: width,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Header: channel number + mixer name + what the app identified
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
              child: Column(
                children: [
                  Text(
                    channel.ch.toString().padLeft(2, '0'),
                    style: const TextStyle(fontSize: 10, color: Colors.white24, letterSpacing: 1),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    channel.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: muted ? Colors.white12 : Colors.white,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                // Identified instrument — amber flags an unrecognised channel
                // whose auto-mix target is falling back to the generic default.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(instrumentIcon(instrument), size: 11, color: idColor),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        known ? instrument.label : '?',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.1,
                          color: idColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Fader + VU meter side by side
          Expanded(
            child: Row(
              children: [
                // Vertical fader (most of the width)
                Expanded(
                  child: _VerticalFader(
                    value: channel.sendLevel,
                    muted: muted,
                    onChanged: muted ? null : onLevelChanged,
                  ),
                ),
                // VU meter bar (thin strip on the right)
                _VuMeterBar(
                  db: muted ? -90 : meterDb,
                  width: 7,
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),

          // Footer: dB label + activity dot
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 2),
            child: Column(
              children: [
                Text(
                  dbLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted ? Colors.white12 : _dbColor(db),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? AppColors.blue : AppColors.border,
                  ),
                ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }

  Color _dbColor(double db) {
    if (db > 0) return AppColors.red;
    if (db > -6) return AppColors.amber;
    return AppColors.blue;
  }
}

// ── Vertical fader ────────────────────────────────────────────────────────────

class _VerticalFader extends StatelessWidget {
  final double value;
  final bool muted;
  final ValueChanged<double>? onChanged;

  const _VerticalFader({required this.value, required this.muted, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 3,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: muted ? AppColors.borderMuted : _trackColor(value),
          inactiveTrackColor: AppColors.track,
          thumbColor: muted ? AppColors.border : Colors.white,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
          trackHeight: 6,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
          overlayColor: AppColors.blue.withAlpha(38),
        ),
        child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
      ),
    );
  }

  Color _trackColor(double v) {
    if (v > 0.88) return AppColors.red;
    if (v > 0.75) return AppColors.amber;
    return AppColors.blue;
  }
}

// ── VU meter bar ──────────────────────────────────────────────────────────────

class _VuMeterBar extends StatelessWidget {
  final double db;
  final double width;

  const _VuMeterBar({required this.db, required this.width});

  @override
  Widget build(BuildContext context) {
    // Map db (-60..+6) to fill fraction 0..1
    final fill = ((db + 60) / 66).clamp(0.0, 1.0);
    final emptyFlex = ((1 - fill) * 100).round().clamp(0, 100);
    final filledFlex = (fill * 100).round().clamp(1, 100);

    return SizedBox(
      width: width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Column(
          children: [
            Expanded(flex: emptyFlex, child: const ColoredBox(color: AppColors.borderMuted)),
            Expanded(flex: filledFlex, child: ColoredBox(color: _barColor(db))),
          ],
        ),
      ),
    );
  }

  Color _barColor(double db) {
    if (db > 0) return AppColors.red;
    if (db > -6) return AppColors.amber;
    if (db > -18) return AppColors.green;
    return const Color(0xFF1F5A34);
  }
}

class _NoGlowScroll extends ScrollBehavior {
  const _NoGlowScroll();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
