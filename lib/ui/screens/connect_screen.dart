import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../mixer/mixer_client.dart';
import 'mixer_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final MixerClient _client;
  final _ipController = TextEditingController();
  int _busIndex = 1;

  @override
  void initState() {
    super.initState();
    _client = MixerClient();
    _client.addListener(_onClientChange);
    _client.startDiscovery();
  }

  void _onClientChange() => setState(() {});

  @override
  void dispose() {
    _client.removeListener(_onClientChange);
    _client.dispose();
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _connectTo(String ip) async {
    await _client.connect(ip, busIndex: _busIndex);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MixerScreen(client: _client),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Bus selector
          _BusSelector(
            value: _busIndex,
            onChanged: (v) => setState(() => _busIndex = v),
          ),
          const SizedBox(height: 24),

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
                  leading: const Icon(Icons.router, color: Colors.tealAccent),
                  title: Text(m.name),
                  subtitle: Text('${m.model}  •  ${m.ip}  •  fw ${m.firmware}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _connectTo(m.ip),
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
                    if (v.isNotEmpty) _connectTo(v);
                  },
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                icon: const Icon(Icons.cable),
                label: const Text('Conectar'),
                onPressed: () {
                  final ip = _ipController.text.trim();
                  if (ip.isNotEmpty) _connectTo(ip);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BusSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _BusSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Meu bus de retorno',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Colors.white54,
              ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: 16,
            separatorBuilder: (context, index) => const SizedBox(width: 6),
            itemBuilder: (context, i) {
              final bus = i + 1;
              final selected = bus == value;
              return ChoiceChip(
                label: Text('$bus'),
                selected: selected,
                onSelected: (_) => onChanged(bus),
                selectedColor: Colors.tealAccent,
                labelStyle: TextStyle(
                  color: selected ? Colors.black : Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
