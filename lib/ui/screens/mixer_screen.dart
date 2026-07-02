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
          // Emergency mute button — always visible
          IconButton(
            icon: const Icon(Icons.volume_off, color: Colors.redAccent),
            tooltip: 'Mute retorno',
            onPressed: _muteAll,
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
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _client.channels.length,
        itemBuilder: (context, i) {
          final ch = _client.channels[i];
          return _ChannelRow(
            channel: ch,
            onLevelChanged: (v) => _client.setChannelSend(ch.ch, v),
          );
        },
      ),
    );
  }

  void _muteAll() {
    for (final ch in _client.channels) {
      _client.setChannelSend(ch.ch, 0.0);
    }
  }
}

class _ChannelRow extends StatelessWidget {
  final ChannelInfo channel;
  final ValueChanged<double> onLevelChanged;

  const _ChannelRow({required this.channel, required this.onLevelChanged});

  @override
  Widget build(BuildContext context) {
    final db = floatToDb(channel.sendLevel);
    final dbLabel = db <= -89 ? '-∞' : '${db.toStringAsFixed(1)} dB';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          // Channel number
          SizedBox(
            width: 28,
            child: Text(
              channel.ch.toString().padLeft(2, '0'),
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white38,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // Channel name
          SizedBox(
            width: 100,
            child: Text(
              channel.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          // Fader slider
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: _trackColor(channel.sendLevel),
                thumbColor: Colors.white,
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
          // dB label
          SizedBox(
            width: 64,
            child: Text(
              dbLabel,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                color: _dbColor(db),
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
