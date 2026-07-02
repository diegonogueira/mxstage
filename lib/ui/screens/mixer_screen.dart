import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../../osc/osc_codec.dart';
import '../../state/reference.dart';

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

  void _captureReference() {
    final ok = _client.captureReference();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nenhum canal ativo detectado. Toque na mesa e tente novamente.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _AutoMixBar(
            reference: _client.reference,
            onCapture: _captureReference,
          ),
          Expanded(
            child: _FaderBoard(
              channels: _client.channels,
              muted: _muted,
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

// ── Auto-Mix bar ─────────────────────────────────────────────────────────────

class _AutoMixBar extends StatelessWidget {
  final Reference? reference;
  final VoidCallback onCapture;

  const _AutoMixBar({required this.reference, required this.onCapture});

  @override
  Widget build(BuildContext context) {
    final hasRef = reference != null;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        border: Border(bottom: BorderSide(color: Color(0xFF222222))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // Auto-Mix toggle (enabled in M3)
          const Icon(Icons.auto_fix_high, size: 16, color: Colors.white24),
          const SizedBox(width: 6),
          const Text(
            'Auto-Mix',
            style: TextStyle(fontSize: 13, color: Colors.white38, fontWeight: FontWeight.w500),
          ),
          Switch(
            value: false,
            onChanged: null, // M3
            activeThumbColor: Colors.tealAccent,
          ),

          const Spacer(),

          // Reference state + capture button
          if (hasRef)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ref capturada às ${reference!.capturedAtLabel}',
                    style: const TextStyle(fontSize: 10, color: Colors.tealAccent),
                  ),
                  Text(
                    '${reference!.activeCount} canais ativos',
                    style: const TextStyle(fontSize: 9, color: Colors.white24),
                  ),
                ],
              ),
            ),

          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: hasRef ? const Color(0xFF1A2A2A) : Colors.tealAccent.withAlpha(30),
              foregroundColor: hasRef ? Colors.tealAccent : Colors.tealAccent,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Colors.tealAccent.withAlpha(hasRef ? 80 : 50),
                ),
              ),
            ),
            onPressed: onCapture,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.radio_button_checked, size: 14),
                const SizedBox(width: 4),
                Text(hasRef ? 'Recapturar' : 'Capturar ref', style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fader board ───────────────────────────────────────────────────────────────

class _FaderBoard extends StatelessWidget {
  final List<ChannelInfo> channels;
  final bool muted;
  final bool isLandscape;
  final double Function(int channelIndex) meterDb;
  final void Function(int ch, double level) onLevelChanged;

  const _FaderBoard({
    required this.channels,
    required this.muted,
    required this.isLandscape,
    required this.meterDb,
    required this.onLevelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final stripW = isLandscape ? 72.0 : 80.0;

    return ScrollConfiguration(
      behavior: const _NoGlowScroll(),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
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
            meterDb: meterDb(i),
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
  final double meterDb;
  final ValueChanged<double> onLevelChanged;

  const _ChannelStrip({
    required this.channel,
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

    return SizedBox(
      width: width,
      child: Column(
        children: [
          // Header: channel number + name
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                Text(
                  channel.ch.toString().padLeft(2, '0'),
                  style: const TextStyle(fontSize: 9, color: Colors.white24, letterSpacing: 1),
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
                  width: 6,
                ),
                const SizedBox(width: 2),
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
                    fontSize: 11,
                    color: muted ? Colors.white12 : _dbColor(db),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 5,
                  height: 5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active ? Colors.tealAccent : const Color(0xFF222222),
                  ),
                ),
              ],
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
          activeTrackColor: muted ? const Color(0xFF222222) : _trackColor(value),
          inactiveTrackColor: const Color(0xFF1A1A1A),
          thumbColor: muted ? const Color(0xFF333333) : Colors.white,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
          trackHeight: 3,
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
          overlayColor: Colors.white10,
        ),
        child: Slider(value: value, min: 0, max: 1, onChanged: onChanged),
      ),
    );
  }

  Color _trackColor(double v) {
    if (v > 0.88) return Colors.redAccent;
    if (v > 0.75) return Colors.orangeAccent;
    return Colors.tealAccent;
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
            Expanded(flex: emptyFlex, child: const ColoredBox(color: Color(0xFF111111))),
            Expanded(flex: filledFlex, child: ColoredBox(color: _barColor(db))),
          ],
        ),
      ),
    );
  }

  Color _barColor(double db) {
    if (db > 0) return Colors.redAccent;
    if (db > -6) return Colors.orangeAccent;
    if (db > -18) return Colors.tealAccent;
    return const Color(0xFF1A4A4A);
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
