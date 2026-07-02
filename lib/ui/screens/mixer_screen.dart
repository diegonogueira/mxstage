import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../../osc/osc_codec.dart';

class MixerScreen extends StatefulWidget {
  final MixerClient client;

  const MixerScreen({super.key, required this.client});

  @override
  State<MixerScreen> createState() => _MixerScreenState();
}

class _MixerScreenState extends State<MixerScreen> {
  MixerClient get _client => widget.client;

  bool _muted = false;
  // Levels saved before mute so we can restore them
  final Map<int, double> _preMuteLevels = {};

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

  void _toggleMute() {
    if (_muted) {
      // Restore saved levels
      for (final ch in _client.channels) {
        final saved = _preMuteLevels[ch.ch];
        if (saved != null) _client.setChannelSend(ch.ch, saved);
      }
      _preMuteLevels.clear();
    } else {
      // Save current levels, then zero everything
      for (final ch in _client.channels) {
        _preMuteLevels[ch.ch] = ch.sendLevel;
        _client.setChannelSend(ch.ch, 0.0);
      }
    }
    setState(() => _muted = !_muted);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_client.mixerName ?? 'Mixer', style: const TextStyle(fontSize: 16)),
            Text(
              'Bus ${_client.busIndex}',
              style: const TextStyle(fontSize: 12, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          // Mute toggle — saves levels and restores on second tap
          IconButton(
            icon: Icon(
              _muted ? Icons.volume_off : Icons.volume_up,
              color: _muted ? Colors.redAccent : Colors.white70,
            ),
            tooltip: _muted ? 'Restaurar volume' : 'Mute retorno',
            onPressed: _toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: 'Desconectar',
            onPressed: () async {
              await _client.disconnect();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _AutoMixBar(),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _client.channels.length,
              itemBuilder: (context, i) {
                final ch = _client.channels[i];
                return _ChannelRow(
                  channel: ch,
                  onLevelChanged: _muted
                      ? null // sliders desabilitados enquanto mutado
                      : (v) => _client.setChannelSend(ch.ch, v),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra de Auto-Mix no topo da tela de mixer.
/// Por enquanto desabilitada (disponível no M3).
class _AutoMixBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161616),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, size: 18, color: Colors.white38),
          const SizedBox(width: 8),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Auto-Mix',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white54),
                ),
                Text(
                  'Disponível após capturar referência (M2)',
                  style: TextStyle(fontSize: 11, color: Colors.white24),
                ),
              ],
            ),
          ),
          Switch(
            value: false,
            onChanged: null, // habilitado no M3
            activeThumbColor: Colors.tealAccent,
          ),
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  final ChannelInfo channel;
  final ValueChanged<double>? onLevelChanged;

  const _ChannelRow({required this.channel, required this.onLevelChanged});

  @override
  Widget build(BuildContext context) {
    final db = floatToDb(channel.sendLevel);
    final dbLabel = db <= -89 ? '-∞' : '${db.toStringAsFixed(1)} dB';
    final disabled = onLevelChanged == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              channel.ch.toString().padLeft(2, '0'),
              style: TextStyle(
                fontSize: 11,
                color: disabled ? Colors.white12 : Colors.white38,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              channel.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: disabled ? Colors.white24 : Colors.white,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: disabled ? Colors.white12 : _trackColor(channel.sendLevel),
                inactiveTrackColor: const Color(0xFF2A2A2A),
                thumbColor: disabled ? Colors.white24 : Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                trackHeight: 4,
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              ),
              child: Slider(
                value: channel.sendLevel,
                min: 0,
                max: 1,
                onChanged: onLevelChanged,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Text(
              dbLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: disabled ? Colors.white12 : _dbColor(db),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _trackColor(double level) {
    if (level > 0.85) return Colors.redAccent;
    if (level > 0.7) return Colors.orangeAccent;
    return Colors.tealAccent;
  }

  Color _dbColor(double db) {
    if (db > 0) return Colors.redAccent;
    if (db > -10) return Colors.orangeAccent;
    return Colors.white70;
  }
}
