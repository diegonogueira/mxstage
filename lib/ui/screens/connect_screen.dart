import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../mixer/mixer_client.dart';
import '../../osc/x32_protocol.dart';
import '../../state/app_mode.dart';
import '../../state/app_settings.dart';
import '../../state/genre_presets.dart';
import '../palette.dart';
import '../widgets/brand.dart';
import '../widgets/bus_picker.dart';
import '../widgets/live_entry.dart';
import 'mixer_screen.dart';
import 'mixer_setup_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen>
    with WidgetsBindingObserver {
  late final MixerClient _client;
  final _ipController = TextEditingController();
  bool _connecting = false;
  int? _liveBus;
  // Guarda para reabrir o último bus do Stage só uma vez por conexão.
  bool _autoOpened = false;

  @override
  void initState() {
    super.initState();
    _client = MixerClient();
    _client.addListener(_onClientChange);
    WidgetsBinding.instance.addObserver(this);
    _client.startDiscovery();
    _loadLiveBus();
  }

  void _onClientChange() {
    // Nova conexão reabilita o auto-open; desconectar reseta.
    if (!_client.isConnected) _autoOpened = false;
    setState(() {});
    _maybeAutoOpenLastBus();
  }

  // Ao conectar, se esta mesa tem um bus de retorno do Stage lembrado, pula o
  // seletor e abre direto nele (o back volta ao seletor). Só uma vez por
  // conexão; nunca abre o bus da transmissão.
  Future<void> _maybeAutoOpenLastBus() async {
    if (_autoOpened || !_client.isConnected) return;
    final mixer = _client.mixerName;
    if (mixer == null || mixer.isEmpty) return; // espera o /xinfo chegar
    _autoOpened = true;
    final bus = await AppSettings.stageBus(mixer);
    if (bus == null || bus < 1 || bus > kMixBusCount || bus == _liveBus) return;
    if (!mounted || !_client.isConnected) return;
    await _openMixer(bus);
  }

  // Zera tudo que o app lembra (bus do Stage por mesa, gênero por mesa e o bus
  // da Live). Pede confirmação; não altera nada na mesa.
  Future<void> _confirmClearSettings() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Zerar configurações salvas?'),
        content: const Text(
          'Apaga o bus de retorno lembrado, o gênero por mesa e o bus da '
          'transmissão (Live). Não altera nada na mesa.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.35),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Zerar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppSettings.clearAll();
    if (!mounted) return;
    // Apagar a preferência não basta: o cliente ainda guarda o gênero em
    // memória. Volta o preset ao padrão de fábrica (Geral) aqui e agora.
    _client.setGenre(Genre.general);
    setState(() {
      _liveBus = null;
      _autoOpened = true; // não reabre um bus lembrado que acabou de ser apagado
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Configurações salvas apagadas.')),
    );
  }

  // Which bus is designated as the broadcast (Live) bus. In Stage mode it is
  // hidden from the bus picker so a musician can't grab the transmission mix.
  Future<void> _loadLiveBus() async {
    final bus = await AppSettings.liveBus();
    if (mounted) setState(() => _liveBus = bus);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground: if the OS suspended us (background
    // execution not granted), the meter subscription may have expired, so
    // restart it immediately rather than waiting for the next renew tick.
    if (state == AppLifecycleState.resumed) {
      _client.resyncAfterResume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _client.removeListener(_onClientChange);
    _client.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connectTo(String ip) async {
    setState(() => _connecting = true);
    try {
      await _client.connect(ip);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  // Entrada "Live" no seletor de bus: pede o PIN e resolve qual é o bus da
  // transmissão (lembrado → nomeado na mesa → designado na hora), depois abre a
  // mix da live. Ver [enterLiveBus].
  Future<void> _enterLive() async {
    final bus = await enterLiveBus(context, _client);
    if (bus == null || !mounted) return;
    setState(() => _liveBus = bus);
    await _openMixer(bus, mode: AppMode.live);
  }

  // Botão "trocar" na entrada Live: força a re-designação do bus da transmissão.
  Future<void> _changeLiveBus() async {
    final bus = await changeLiveBus(context, _client);
    if (bus == null || !mounted) return;
    setState(() => _liveBus = bus);
    await _openMixer(bus, mode: AppMode.live);
  }

  Future<void> _openMixer(int bus, {AppMode mode = AppMode.stage}) async {
    if (bus != _client.busIndex) await _client.setBus(bus);
    // Lembra o bus do Stage por mesa para reabrir nele na próxima conexão.
    if (mode == AppMode.stage) {
      final mixer = _client.mixerName;
      if (mixer != null && mixer.isNotEmpty) {
        await AppSettings.setStageBus(mixer, bus);
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MixerScreen(client: _client, mode: mode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Once connected, the initial screen becomes the bus picker (by name).
    if (_client.isConnected) return _buildBusPick();
    return _buildDiscovery();
  }

  // ── Phase 2: pick your return bus by name ──────────────────────────────────

  Widget _buildBusPick() {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Desconectar',
          onPressed: () => _client.disconnect(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_client.mixerName ?? 'Mixer',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const Text('Escolha o seu bus de retorno',
                style: TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
      ),
      body: BusPickerList(
        client: _client,
        excludeBus: _liveBus,
        onLive: _enterLive,
        onLiveEdit: _changeLiveBus,
        onPick: (bus) => _openMixer(bus),
      ),
    );
  }

  // ── Phase 1: discovery + manual IP ─────────────────────────────────────────

  Widget _buildDiscovery() {
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Buscar novamente',
            onPressed: _client.isDiscovering ? null : _client.startDiscovery,
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 22),
                child: Center(child: BrandHero()),
              ),

              // Auto-discovered mixers
              Text(
                'Mesas encontradas na rede',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white54,
                    ),
              ),
              const SizedBox(height: 8),

              if (_client.isDiscovering)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 12),
                        Text('Procurando...'),
                      ],
                    ),
                  ),
                )
              else if (_client.discovered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'Nenhuma mesa encontrada. Use IP manual abaixo.',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              else
                ...(_client.discovered.map(
                  (m) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.router, color: AppColors.blue),
                      title: Text(m.name),
                      subtitle: Text('${m.model}  •  ${m.ip}  •  fw ${m.firmware}'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: _connecting ? null : () => _connectTo(m.ip),
                    ),
                  ),
                )),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Manual IP entry
              Text(
                'IP manual',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white54,
                    ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ipController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                      ],
                      decoration: const InputDecoration(
                        hintText: '192.168.1.100',
                        prefixIcon: Icon(Icons.lan),
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) {
                        if (v.isNotEmpty && !_connecting) _connectTo(v);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.cable),
                    label: const Text('Conectar'),
                    onPressed: _connecting
                        ? null
                        : () {
                            final ip = _ipController.text.trim();
                            if (ip.isNotEmpty) _connectTo(ip);
                          },
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Preparar a mesa — leva ao guia de configuração da X32.
              _SetupGuideButton(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MixerSetupScreen()),
                ),
              ),

              const SizedBox(height: 20),
              Center(
                child: TextButton.icon(
                  onPressed: _confirmClearSettings,
                  icon: const Icon(Icons.settings_backup_restore,
                      size: 18, color: AppColors.textMuted),
                  label: const Text(
                    'Zerar configurações salvas',
                    style: TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ),
            ],
          ),

          // Connecting overlay
          if (_connecting)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xCC000000),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Conectando...', style: TextStyle(color: Colors.white70)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Botão para o guia de configuração da mesa ────────────────────────────────

class _SetupGuideButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SetupGuideButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.blue.withAlpha(90)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.blue.withAlpha(30),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.tune, color: AppColors.blue, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Como configurar a mesa',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'O que ajustar na X32 para o Auto-Mix ler o volume real',
                      style: TextStyle(fontSize: 12, color: Colors.white54, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.blue),
            ],
          ),
        ),
      ),
    );
  }
}
