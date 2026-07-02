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
      for (final ch in _client.channels) {
        final saved = _preMuteLevels[ch.ch];
        if (saved != null) _client.setChannelSend(ch.ch, saved);
      }
      _preMuteLevels.clear();
    } else {
      for (final ch in _client.channels) {
        _preMuteLevels[ch.ch] = ch.sendLevel;
        _client.setChannelSend(ch.ch, 0.0);
      }
    }
    setState(() => _muted = !_muted);
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _AutoMixBar(),
          Expanded(
            child: _FaderBoard(
              channels: _client.channels,
              muted: _muted,
              isLandscape: isLandscape,
              onLevelChanged: (ch, v) => _client.setChannelSend(ch, v),
            ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0D0D0D),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _client.mixerName ?? 'Mixer',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          Text(
            'Bus ${_client.busIndex}',
            style: const TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            _muted ? Icons.volume_off : Icons.volume_up,
            color: _muted ? Colors.redAccent : Colors.white54,
          ),
          tooltip: _muted ? 'Restaurar volume' : 'Mute retorno',
          onPressed: _toggleMute,
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

class _AutoMixBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF222222))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, size: 16, color: Colors.white24),
          const SizedBox(width: 8),
          const Text(
            'Auto-Mix',
            style: TextStyle(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.w500),
          ),
          const SizedBox(width: 4),
          const Text(
            '— disponível após M2',
            style: TextStyle(fontSize: 11, color: Colors.white12),
          ),
          const Spacer(),
          Switch(
            value: false,
            onChanged: null,
            activeThumbColor: Colors.tealAccent,
          ),
        ],
      ),
    );
  }
}

// ── Fader board ──────────────────────────────────────────────────────────────

class _FaderBoard extends StatelessWidget {
  final List<ChannelInfo> channels;
  final bool muted;
  final bool isLandscape;
  final void Function(int ch, double level) onLevelChanged;

  const _FaderBoard({
    required this.channels,
    required this.muted,
    required this.isLandscape,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Channel strip width adapts to orientation
    final stripW = isLandscape ? 72.0 : 80.0;

    return ScrollConfiguration(
      behavior: const _NoGlowScroll(),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
        itemCount: channels.length,
        separatorBuilder: (context, index) => const SizedBox(
          width: 1,
          child: VerticalDivider(color: Color(0xFF1E1E1E), width: 1),
        ),
        itemBuilder: (context, i) {
          final ch = channels[i];
          return _ChannelStrip(
            channel: ch,
            width: stripW,
            muted: muted,
            onLevelChanged: (v) => onLevelChanged(ch.ch, v),
          );
        },
      ),
    );
  }
}

class _ChannelStrip extends StatelessWidget {
  final ChannelInfo channel;
  final double width;
  final bool muted;
  final ValueChanged<double> onLevelChanged;

  const _ChannelStrip({
    required this.channel,
    required this.width,
    required this.muted,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final db = floatToDb(channel.sendLevel);
    final dbLabel = db <= -89 ? '-∞' : db.toStringAsFixed(1);
    final active = !muted && channel.sendLevel > 0.001;

    return SizedBox(
      width: width,
      child: Column(
        children: [
          // Channel number + name header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  channel.ch.toString().padLeft(2, '0'),
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white24,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  channel.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: muted ? Colors.white12 : Colors.white70,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // Vertical fader — fills remaining space
          Expanded(
            child: _VerticalFader(
              value: channel.sendLevel,
              muted: muted,
              onChanged: muted ? null : onLevelChanged,
            ),
          ),

          // dB label footer
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              dbLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: muted ? Colors.white12 : _dbColor(db),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),

          // Active indicator dot
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.tealAccent : const Color(0xFF222222),
            ),
          ),
        ],
      ),
    );
  }

  Color _dbColor(double db) {
    if (db > 0) return Colors.redAccent;
    if (db > -6) return Colors.orangeAccent;
    return Colors.white54;
  }
}

class _VerticalFader extends StatelessWidget {
  final double value;
  final bool muted;
  final ValueChanged<double>? onChanged;

  const _VerticalFader({required this.value, required this.muted, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return RotatedBox(
      quarterTurns: 3, // min=bottom, max=top
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          activeTrackColor: muted ? const Color(0xFF222222) : _trackColor(value),
          inactiveTrackColor: const Color(0xFF1A1A1A),
          thumbColor: muted ? const Color(0xFF333333) : Colors.white,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          trackHeight: 3,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          overlayColor: Colors.white10,
        ),
        child: Slider(
          value: value,
          min: 0,
          max: 1,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Color _trackColor(double v) {
    if (v > 0.88) return Colors.redAccent;
    if (v > 0.75) return Colors.orangeAccent;
    return Colors.tealAccent;
  }
}

class _NoGlowScroll extends ScrollBehavior {
  const _NoGlowScroll();

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}
