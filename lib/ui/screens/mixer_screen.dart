import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../engine/equalizer_engine.dart' show EqualizeResult;
import '../../mixer/mixer_client.dart';
import '../../osc/osc_codec.dart';
import '../../state/app_mode.dart';
import '../../state/app_settings.dart';
import '../../state/genre_presets.dart';
import '../../state/instrument_type.dart';
import '../../state/musician_roles.dart';
import '../instrument_visuals.dart';
import '../palette.dart';
import '../widgets/bus_picker.dart';
import '../widgets/instrument_picker.dart';
import '../widgets/live_entry.dart';
import '../widgets/mode_badge.dart';

class MixerScreen extends StatefulWidget {
  final MixerClient client;
  final AppMode mode;

  const MixerScreen({super.key, required this.client, required this.mode});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  MixerClient get _client => widget.client;

  // Active group filter (null = show all channels).
  InstrumentGroup? _group;

  // Designated broadcast bus — hidden from the in-mix switcher in Stage mode.
  int? _liveBus;

  @override
  void initState() {
    super.initState();
    _client.addListener(_onClientChange);
    _loadLiveBus();
    _loadGenre();
    _loadOverrides();
    _loadBoosts();
    _loadMaster();
    _loadProtection();
    _loadOwnChannel();
  }

  Future<void> _loadProtection() async {
    final on = await AppSettings.protection();
    if (mounted) _client.protectionEnabled = on;
  }

  // Último resultado do "Equalizar" já anunciado (snackbar uma vez só).
  EqualizeResult? _shownEqualize;

  void _announceEqualize() {
    final r = _client.lastEqualizeResult;
    if (r == null || identical(r, _shownEqualize)) return;
    _shownEqualize = r;
    String names(List<int> chs) =>
        chs.map((c) => _client.channels[c - 1].name).join(', ');
    final msg = !r.ok
        ? 'Não ouvi a banda tocando. Equalize com todo mundo tocando.'
        : 'Equalizado: ${r.balanced.length} canais.'
            '${r.remembered.isEmpty ? '' : ' Calados agora (ajuste anterior mantido): ${names(r.remembered)}.'}'
            '${r.unheard.isEmpty ? '' : ' Não ouvidos (como estavam): ${names(r.unheard)}.'}';
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // Restaura o volume geral (masterDb) salvo para esta mesa+bus. Por bus, então
  // é rechamado ao trocar de bus (cada retorno tem o seu nível).
  Future<void> _loadMaster() async {
    final mixer = _client.mixerName;
    if (mixer == null || mixer.isEmpty) return;
    final db = await AppSettings.masterDb(mixer, _client.busIndex);
    if (!mounted) return;
    _client.restoreMasterVolume(db);
  }

  // Ajuste do usuário no volume geral: aplica no engine e persiste por mesa+bus.
  Future<void> _onMasterChanged(double db) async {
    _client.setMasterVolume(db);
    final mixer = _client.mixerName;
    if (mixer != null && mixer.isNotEmpty) {
      await AppSettings.setMasterDb(mixer, _client.busIndex, _client.masterDb);
    }
  }

  // Restaura as sobreposições manuais de instrumento salvas para esta mesa.
  Future<void> _loadOverrides() async {
    final mixer = _client.mixerName;
    if (mixer == null || mixer.isEmpty) return;
    final map = await AppSettings.instrumentOverrides(mixer);
    if (!mounted || map.isEmpty) return;
    _client.setInstrumentOverrides(map);
  }

  // Restaura os reforços (boost, dB) por canal salvos para esta mesa.
  Future<void> _loadBoosts() async {
    final mixer = _client.mixerName;
    if (mixer == null || mixer.isEmpty) return;
    final map = await AppSettings.channelBoosts(mixer);
    if (!mounted || map.isEmpty) return;
    _client.setChannelBoosts(map);
  }

  Future<void> _loadLiveBus() async {
    final bus = await AppSettings.liveBus();
    if (mounted) setState(() => _liveBus = bus);
  }

  // Estilo fixo em Worship por enquanto (o seletor saiu da tela — ver
  // MixerClient._genre). Ignora um gênero salvo de versões antigas.
  void _loadGenre() {
    if (_client.genre != Genre.worship) _client.setGenre(Genre.worship);
  }

  // "Meu canal" é por mesa+bus. Na Live (transmissão) não há papel: balanço de
  // plateia, voz como âncora. Sem escolha salva, tenta detectar pelo nome do bus
  // ([_tryDetectOwn], reexecutado conforme os nomes chegam da mesa).
  bool _detectOwnPending = false;

  Future<void> _loadOwnChannel() async {
    _detectOwnPending = false;
    if (widget.mode.isLive) {
      _client.ownChannel = null;
      return;
    }
    final mixer = _client.mixerName;
    if (mixer == null || mixer.isEmpty) return;
    final bus = _client.busIndex;
    final chosen = await AppSettings.hasOwnChannelChoice(mixer, bus);
    final ch = await AppSettings.ownChannel(mixer, bus);
    if (!mounted) return;
    _client.ownChannel = ch;
    _detectOwnPending = !chosen;
    _tryDetectOwn();
  }

  void _tryDetectOwn() {
    if (!_detectOwnPending || _client.ownChannel != null) return;
    final busName = _client.busName;
    if (busName == null) return; // nome do bus ainda não chegou
    final ch = ownChannelFromBusName(
      busName,
      [for (final c in _client.channels) c.name],
      _client.instruments,
    );
    if (ch == null) return;
    _detectOwnPending = false;
    _client.ownChannel = ch; // sugestão: não grava — a escolha manual é que fica
    final what = isDrumKit(_client.instruments[ch - 1])
        ? 'Bateria'
        : _client.channels[ch - 1].name;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text('Seu instrumento: $what (pelo nome do bus "$busName"). '
          'Toque em "Eu" pra mudar.'),
    ));
  }

  void _setOwnChannel(int? ch) {
    _detectOwnPending = false;
    _client.ownChannel = ch;
    final mixer = _client.mixerName;
    if (mixer != null && mixer.isNotEmpty) {
      AppSettings.setOwnChannel(mixer, _client.busIndex, ch);
    }
  }

  @override
  void dispose() {
    _client.removeListener(_onClientChange);
    super.dispose();
  }

  void _onClientChange() {
    setState(() {});
    _announceEqualize();
    _tryDetectOwn();
  }

  String _busLabel() {
    final name = _client.busName;
    final base = 'Bus ${_client.busIndex}';
    return name != null ? '$base · $name' : base;
  }

  Widget? _ownPicker() => widget.mode.isLive
      ? null
      : _OwnChannelPicker(client: _client, onChanged: _setOwnChannel);

  void _showBusPicker() {
    final mode = widget.mode;
    showBusPicker(
      context,
      _client,
      excludeBus: mode.isLive ? null : _liveBus,
      onLive: mode.isLive ? null : () => _switchToLive(enterLiveBus(context, _client)),
      onLiveEdit:
          mode.isLive ? null : () => _switchToLive(changeLiveBus(context, _client)),
      title: mode.busPickerTitle,
      subtitle: mode.busPickerSubtitle,
      icon: mode.icon,
      accent: mode.accent,
      onPicked: (bus) async {
        await _client.setBus(bus);
        await _loadMaster(); // volume geral é por bus — recarrega o do novo bus
        await _loadOwnChannel(); // meu canal também
        if (mode.isLive) {
          await AppSettings.setLiveBus(bus);
          if (mounted) setState(() => _liveBus = bus);
        }
      },
    );
  }

  // "Trocar → Live" a partir do mixer do Stage: [future] resolve o bus da
  // transmissão (entrar ou re-designar) e esta tela é substituída pela mix live.
  Future<void> _switchToLive(Future<int?> future) async {
    final bus = await future;
    if (bus == null || !mounted) return;
    await _client.setBus(bus);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MixerScreen(client: _client, mode: AppMode.live),
      ),
    );
  }

  // Segurar um canal abre o seletor do que ele realmente é (Voz Lead, Backing,
  // Guitarra…). A sobreposição vence a auto-detecção e é salva por mesa.
  void _editInstrument(ChannelInfo ch) {
    showInstrumentPicker(
      context,
      ch: ch.ch,
      channelName: ch.name,
      current: _client.instruments[ch.ch - 1],
      detected: _client.detectedInstrument(ch.ch),
      isOverridden: _client.isOverridden(ch.ch),
      onSelected: (type) async {
        _client.setInstrumentOverride(ch.ch, type);
        final mixer = _client.mixerName;
        if (mixer != null && mixer.isNotEmpty) {
          await AppSettings.setInstrumentOverride(mixer, ch.ch, type);
        }
      },
      boostDb: _client.channelBoostDb(ch.ch),
      onBoostChanged: (db) async {
        _client.setChannelBoost(ch.ch, db);
        final mixer = _client.mixerName;
        if (mixer != null && mixer.isNotEmpty) {
          await AppSettings.setChannelBoost(mixer, ch.ch, db);
        }
      },
    );
  }

  // Volta todos os canais à auto-detecção (limpa os overrides desta mesa).
  Future<void> _resetOverrides() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Restaurar detecção automática'),
        content: const Text(
          'Isto apaga todos os ajustes manuais de instrumento desta mesa e volta '
          'cada canal ao que foi detectado automaticamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    _client.clearInstrumentOverrides();
    final mixer = _client.mixerName;
    if (mixer != null && mixer.isNotEmpty) {
      await AppSettings.clearInstrumentOverrides(mixer);
    }
  }

  // Exporta o log de diagnóstico (JSONL) pelo share sheet — WhatsApp, Files,
  // Drive, e-mail. Mesmo caminho do PDF do manual.
  Future<void> _exportDiagnostic() async {
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;

    final path = await _client.exportSessionLog();
    if (path == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Nada gravado ainda — conecte, ligue o Auto-Mix e toque um pouco.',
          ),
        ),
      );
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'application/json')],
        subject: 'MXWise — diagnóstico da sessão',
        text: 'Log de diagnóstico do Auto-Mix (JSONL) para análise.',
        sharePositionOrigin: origin,
      ),
    );
  }

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
      appBar: _buildAppBar(isLandscape),
      body: Column(
        children: [
          // Landscape is short on height: fold the Auto-Mix row and the filter
          // tabs into one bar so the extra vertical space goes to fader throw.
          if (isLandscape) ...[
            _ControlBar(
              client: _client,
              ownPicker: _ownPicker(),
              present: present,
              selected: _group,
              onSelected: (g) => setState(() => _group = g),
            ),
            _MasterVolumeBar(
                client: _client, isLandscape: true, onChanged: _onMasterChanged),
          ] else ...[
            _AutoMixBar(client: _client, ownPicker: _ownPicker()),
            _MasterVolumeBar(
                client: _client, isLandscape: false, onChanged: _onMasterChanged),
            _GroupTabs(
              present: present,
              selected: _group,
              onSelected: (g) => setState(() => _group = g),
            ),
          ],
          Expanded(
            child: _FaderBoard(
              channels: visible,
              instruments: _client.instruments,
              muted: _client.isMuted,
              isLandscape: isLandscape,
              meterDb: _client.meterDisplayDb,
              onLevelChanged: (ch, v) => _client.setChannelSend(ch, v),
              isOverridden: _client.isOverridden,
              boostDb: _client.channelBoostDb,
              onEditInstrument: _editInstrument,
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar(bool isLandscape) {
    return AppBar(
      backgroundColor: AppColors.panel,
      toolbarHeight: isLandscape ? 50 : null,
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
        Center(child: ModeBadge(mode: widget.mode)),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 20),
          color: AppColors.elevated,
          tooltip: 'Mais opções',
          onSelected: (v) {
            if (v == 'reset_instruments') _resetOverrides();
            if (v == 'export_diagnostic') _exportDiagnostic();
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'reset_instruments',
              child: Row(
                children: [
                  Icon(Icons.auto_fix_high, size: 18, color: AppColors.blue),
                  SizedBox(width: 10),
                  Text('Restaurar detecção automática'),
                ],
              ),
            ),
            // Só com o Modo debug ligado (ver ConnectScreen).
            if (_client.debugLog)
              const PopupMenuItem(
                value: 'export_diagnostic',
                child: Row(
                  children: [
                    Icon(Icons.bug_report_outlined, size: 18, color: AppColors.amber),
                    SizedBox(width: 10),
                    Text('Exportar diagnóstico'),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Auto-Mix bar ─────────────────────────────────────────────────────────────

class _AutoMixBar extends StatelessWidget {
  final MixerClient client;
  final Widget? ownPicker;

  const _AutoMixBar({required this.client, this.ownPicker});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _EqualizeControls(client: client, ownPicker: ownPicker, spread: true),
          ),
        ],
      ),
    );
  }
}

// ── Equalizar (sob demanda) + Proteção + menu ────────────────────────────────
// O fluxo principal: "Equalizar" escuta ~15 s e ajusta todos de uma vez; depois
// o mix fica parado. A Proteção (escudo) só abaixa quem passar muito do ponto.
// O Auto-Mix contínuo (antigo) fica no menu, como opção avançada.

class _EqualizeControls extends StatelessWidget {
  final MixerClient client;
  // "Meu instrumento" fica colado no Equalizar: são as duas escolhas do fluxo.
  final Widget? ownPicker;

  // Retrato: escudo e menu vão pra direita da barra. Paisagem: tudo junto (o
  // resto da linha é das abas de filtro).
  final bool spread;

  const _EqualizeControls({required this.client, this.ownPicker, this.spread = false});

  @override
  Widget build(BuildContext context) {
    final measuring = client.isEqualizing;
    final eqOn = client.equalizerActive;
    final autoOn = client.autoMixActive;
    final enabled = client.isConnected;

    final Widget main;
    if (measuring) {
      final left =
          ((1 - client.equalizeProgress) * kEqualizeMeasureMs / 1000).ceil();
      main = OutlinedButton.icon(
        onPressed: client.cancelEqualize,
        style: _btnStyle(AppColors.amber),
        icon: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            value: client.equalizeProgress,
            strokeWidth: 2,
            color: AppColors.amber,
          ),
        ),
        label: Text('Ouvindo… ${left}s'),
      );
    } else {
      main = FilledButton.icon(
        onPressed: enabled ? client.equalize : null,
        style: FilledButton.styleFrom(
          backgroundColor: eqOn ? AppColors.green.withAlpha(40) : AppColors.green,
          foregroundColor: eqOn ? AppColors.green : Colors.black,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(eqOn ? Icons.refresh : Icons.equalizer, size: 16),
        label: Text(eqOn ? 'Reequalizar' : 'Equalizar'),
      );
    }

    return Row(
      mainAxisSize: spread ? MainAxisSize.max : MainAxisSize.min,
      children: [
        main,
        if (ownPicker != null) ...[
          const SizedBox(width: 8),
          Flexible(child: ownPicker!),
        ],
        if (spread) const Spacer(),
        if (eqOn && !measuring)
          IconButton(
            tooltip: client.protectionEnabled
                ? 'Proteção ligada: só abaixa quem passar muito do ponto'
                : 'Proteção desligada: mix 100% parado',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              final v = !client.protectionEnabled;
              client.protectionEnabled = v;
              AppSettings.setProtection(v);
            },
            icon: Icon(
              client.protectionEnabled ? Icons.shield : Icons.shield_outlined,
              size: 18,
              color: client.protectionEnabled ? AppColors.green : Colors.white38,
            ),
          ),
        // Auto-Mix contínuo (avançado) — ao lado do escudo, sempre visível.
        IconButton(
          tooltip: autoOn
              ? 'Auto-Mix contínuo ligado (toque pra desligar)'
              : 'Auto-Mix contínuo (avançado): corrige o tempo todo',
          visualDensity: VisualDensity.compact,
          onPressed: (enabled && !measuring)
              ? () => autoOn ? client.disableAutoMix() : client.enableAutoMix()
              : null,
          icon: Icon(
            Icons.auto_fix_high,
            size: 18,
            color: autoOn ? AppColors.green : Colors.white38,
          ),
        ),
        if (eqOn && !measuring)
          IconButton(
            tooltip: 'Desligar equalização (volta como estava)',
            visualDensity: VisualDensity.compact,
            onPressed: client.stopEqualizer,
            icon: const Icon(Icons.close, size: 18, color: Colors.white38),
          ),
      ],
    );
  }

  static ButtonStyle _btnStyle(Color c) => OutlinedButton.styleFrom(
        foregroundColor: c,
        side: BorderSide(color: c.withAlpha(150)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      );
}

// ── Meu canal ────────────────────────────────────────────────────────────────
// O instrumento do dono deste retorno: ele sobe ("mais eu") e os outros se
// ajustam ao papel dele (ver lib/state/musician_roles.dart). Por bus. Escondido
// na Live (transmissão = balanço de plateia).

class _OwnChannelPicker extends StatelessWidget {
  final MixerClient client;
  final ValueChanged<int?> onChanged;

  const _OwnChannelPicker({required this.client, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final own = client.ownChannel;
    final active = client.monitorActive;
    final color = own != null
        ? (active ? AppColors.green : AppColors.green.withAlpha(160))
        : Colors.white54;
    final label = own == null
        ? 'Meu instrumento'
        : 'Eu: ${isDrumKit(client.instruments[own - 1]) ? 'Bateria' : client.channels[own - 1].name}';

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => _pick(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          border: Border.all(color: color.withAlpha(own != null ? 140 : 60)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              own == null
                  ? Icons.person_outline
                  : instrumentIcon(client.instruments[own - 1]),
              size: 14,
              color: color,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.panel,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _OwnChannelSheet(client: client),
    );
    if (picked == null) return;
    onChanged(picked == 0 ? null : picked);
  }
}

// Lista do "Qual é o seu instrumento?": só canais com instrumento conhecido que
// já tiveram sinal (mudos/sem uso ficam escondidos — "Mostrar todos" revela), e a
// bateria como **uma** entrada (o kit todo), não peça por peça.
class _OwnChannelSheet extends StatefulWidget {
  final MixerClient client;

  const _OwnChannelSheet({required this.client});

  @override
  State<_OwnChannelSheet> createState() => _OwnChannelSheetState();
}

class _OwnChannelSheetState extends State<_OwnChannelSheet> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final client = widget.client;
    final own = client.ownChannel;
    final instr = client.instruments;
    final ownIsKit = own != null && isDrumKit(instr[own - 1]);

    bool known(int ch) => instr[ch - 1] != InstrumentType.unknown;
    final heardAny = client.channels.any((c) => known(c.ch) && client.channelHeard(c.ch));
    // Ninguém tocou ainda (antes do culto) → mostra todos os conhecidos.
    bool visible(int ch) =>
        _showAll || (known(ch) && (!heardAny || client.channelHeard(ch)));

    final kit = drumKitChannel(instr);
    final kitVisible = kit != null &&
        client.channels.any((c) => isDrumKit(instr[c.ch - 1]) && visible(c.ch));
    final others = [
      for (final c in client.channels)
        if (!isDrumKit(instr[c.ch - 1]) && visible(c.ch)) c,
    ];
    final hidden = client.channels.length - others.length -
        client.channels.where((c) => isDrumKit(instr[c.ch - 1])).length;

    Widget check(bool on) =>
        on ? const Icon(Icons.check, color: AppColors.green) : const SizedBox.shrink();

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Qual é o seu instrumento?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Ele sobe no seu fone e os outros se ajustam ao que você '
                'precisa ouvir pra tocar.',
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Nenhum (balanço geral, voz na frente)'),
              trailing: check(own == null),
              onTap: () => Navigator.pop(context, 0),
            ),
            if (kitVisible)
              ListTile(
                leading: Icon(instrumentIcon(InstrumentType.drums)),
                title: const Text('Bateria'),
                subtitle: const Text('O kit todo + baixo pra travar junto'),
                trailing: check(ownIsKit),
                onTap: () => Navigator.pop(context, kit),
              ),
            for (final ch in others)
              ListTile(
                leading: Icon(instrumentIcon(instr[ch.ch - 1])),
                title: Text(ch.name),
                subtitle: Text(
                  '${instr[ch.ch - 1].label} · ${roleFor(instr[ch.ch - 1]).label}',
                ),
                trailing: check(own == ch.ch),
                onTap: () => Navigator.pop(context, ch.ch),
              ),
            if (!_showAll && hidden > 0)
              TextButton(
                onPressed: () => setState(() => _showAll = true),
                child: Text('Mostrar todos os canais ($hidden escondidos)'),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Volume geral (master) ─────────────────────────────────────────────────────
// Desloca o monitor inteiro pra cima/baixo SEM mexer no balanço entre canais.
// Fica sempre visível (o músico mexe direto, ao vivo) e é lembrado por bus. Só
// tem efeito com o mix equalizado (ou o Auto-Mix) ligado; desligado, fica esmaecido mas ainda
// ajustável (pré-configura pra quando ligar). Um ajuste entra no monitor de
// forma suave (ramp pelo slew do engine), sem pulo.

class _MasterVolumeBar extends StatelessWidget {
  final MixerClient client;
  final bool isLandscape;
  final ValueChanged<double> onChanged;

  const _MasterVolumeBar({
    required this.client,
    required this.isLandscape,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = client.monitorActive;
    final db = client.masterDb.clamp(kMasterMinDb, kMasterMaxDb).toDouble();
    final accent = active ? AppColors.green : Colors.white38;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: isLandscape ? 0 : 2),
      child: Row(
        children: [
          Icon(Icons.volume_up, size: 15, color: accent),
          const SizedBox(width: 6),
          Text(
            'Volume geral',
            style: TextStyle(
              fontSize: 12.5,
              color: active ? Colors.white70 : Colors.white38,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: accent,
                inactiveTrackColor: AppColors.border,
                thumbColor: accent,
                overlayColor: accent.withAlpha(40),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: db,
                min: kMasterMinDb,
                max: kMasterMaxDb,
                divisions: ((kMasterMaxDb - kMasterMinDb) * 2).round(),
                onChanged: onChanged,
              ),
            ),
          ),
          // Toque no valor pra voltar ao 0 (nível semeado na ativação).
          GestureDetector(
            onTap: db == 0.0 ? null : () => onChanged(0.0),
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 72,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    '${db > 0 ? '+' : ''}${db.toStringAsFixed(1)} dB',
                    style: TextStyle(
                      fontSize: 12,
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (db != 0.0) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.refresh, size: 13, color: accent.withAlpha(150)),
                  ],
                ],
              ),
            ),
          ),
        ],
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
          _groupChip('Todos', Icons.apps, selected == null, () => onSelected(null)),
          for (final g in groups)
            _groupChip(g.label, g.icon, selected == g, () => onSelected(g)),
        ],
      ),
    );
  }
}

// A single filter chip, shared by the portrait tab bar and the landscape
// combined control bar.
Widget _groupChip(String label, IconData icon, bool sel, VoidCallback onTap) {
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
      side: BorderSide(color: sel ? Colors.transparent : AppColors.border),
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

// ── Landscape combined control bar ────────────────────────────────────────────
// Auto-Mix toggle + genre + filter tabs in a single row. Portrait keeps the two
// separate bars (_AutoMixBar + _GroupTabs); landscape is too short for both.

class _ControlBar extends StatelessWidget {
  final MixerClient client;
  final Widget? ownPicker;
  final Set<InstrumentGroup> present;
  final InstrumentGroup? selected;
  final ValueChanged<InstrumentGroup?> onSelected;

  const _ControlBar({
    required this.client,
    this.ownPicker,
    required this.present,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final groups = kInstrumentGroupOrder.where(present.contains).toList();
    final showTabs = groups.length >= 2;

    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.only(left: 12, right: 8),
      child: Row(
        children: [
          Flexible(child: _EqualizeControls(client: client, ownPicker: ownPicker)),
          if (showTabs) ...[
            const SizedBox(width: 10),
            Container(width: 1, height: 22, color: AppColors.border),
            const SizedBox(width: 8),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 7),
                children: [
                  _groupChip(
                      'Todos', Icons.apps, selected == null, () => onSelected(null)),
                  for (final g in groups)
                    _groupChip(g.label, g.icon, selected == g, () => onSelected(g)),
                ],
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }
}

// ── Fader board ───────────────────────────────────────────────────────────────

class _FaderBoard extends StatelessWidget {
  final List<ChannelInfo> channels;
  final List<InstrumentType> instruments; // full list, indexed by ch-1
  final bool muted;
  final bool isLandscape;
  final double Function(int channelIndex) meterDb;
  final void Function(int ch, double level) onLevelChanged;
  final bool Function(int ch) isOverridden;
  final double Function(int ch) boostDb;
  final void Function(ChannelInfo ch) onEditInstrument;

  const _FaderBoard({
    required this.channels,
    required this.instruments,
    required this.muted,
    required this.isLandscape,
    required this.meterDb,
    required this.onLevelChanged,
    required this.isOverridden,
    required this.boostDb,
    required this.onEditInstrument,
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
            overridden: isOverridden(ch.ch),
            width: stripW,
            compact: isLandscape,
            muted: muted,
            meterDb: meterDb(chIdx),
            boostDb: boostDb(ch.ch),
            onLevelChanged: (v) => onLevelChanged(ch.ch, v),
            onEditInstrument: () => onEditInstrument(ch),
          );
        },
      ),
    );
  }
}

class _ChannelStrip extends StatelessWidget {
  final ChannelInfo channel;
  final InstrumentType instrument;
  final bool overridden;
  final double width;
  final bool compact;
  final bool muted;
  final double meterDb;
  final double boostDb;
  final ValueChanged<double> onLevelChanged;
  final VoidCallback onEditInstrument;

  const _ChannelStrip({
    required this.channel,
    required this.instrument,
    required this.overridden,
    required this.width,
    required this.compact,
    required this.muted,
    required this.meterDb,
    required this.boostDb,
    required this.onLevelChanged,
    required this.onEditInstrument,
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

    // Reforço manual deste canal (dB): verde = +, âmbar = −.
    final boosted = boostDb != 0 && !muted;
    final boostColor = boostDb > 0 ? AppColors.green : AppColors.amber;

    return SizedBox(
      width: width,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: compact ? 4 : 8),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: boosted ? boostColor.withAlpha(160) : AppColors.border,
          ),
        ),
        child: Column(
          children: [
            // Header: number + name + what the app identified. Long-press to
            // manually set what this channel really is (overrides detection).
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: onEditInstrument,
              child: Padding(
                padding: EdgeInsets.fromLTRB(4, compact ? 5 : 8, 4, compact ? 3 : 6),
                child: Column(
                  children: [
                    Text(
                      channel.ch.toString().padLeft(2, '0'),
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white24, letterSpacing: 1),
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
                    // Identified instrument. Amber flags an unrecognised channel
                    // (auto-mix falls back to the generic default); a pencil marks
                    // a manual override the musician set by long-pressing.
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
                        if (overridden && !muted) ...[
                          const SizedBox(width: 3),
                          const Icon(Icons.edit, size: 9, color: AppColors.blue),
                        ],
                        if (boosted) ...[
                          const SizedBox(width: 3),
                          Text(
                            '${boostDb > 0 ? '+' : ''}${boostDb.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: boostColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
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
            padding: EdgeInsets.only(bottom: compact ? 4 : 8, top: 2),
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
