import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../mixer/mixer_client.dart';
import '../widgets/bus_picker.dart';
import 'mixer_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _client = MixerClient();
    _client.addListener(_onClientChange);
    WidgetsBinding.instance.addObserver(this);
    _client.startDiscovery();
  }

  void _onClientChange() => setState(() {});

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

  Future<void> _openMixer(int bus) async {
    if (bus != _client.busIndex) await _client.setBus(bus);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MixerScreen(client: _client)),
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
        onPick: _openMixer,
      ),
    );
  }

  // ── Phase 1: discovery + manual IP ─────────────────────────────────────────

  Widget _buildDiscovery() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('mxstage'),
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
                      leading: const Icon(Icons.router, color: Color(0xFF2AAF8E)),
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
