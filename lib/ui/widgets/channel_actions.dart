import 'package:flutter/material.dart';

import '../../mixer/mixer_client.dart';
import '../../state/app_settings.dart';
import '../../state/channel_inclusion.dart';
import '../../state/channel_pairs.dart';
import '../../state/instrument_type.dart';
import 'instrument_picker.dart';

/// Ações de canal + persistência, compartilhadas entre o mixer e a tela
/// "Mapear canais" (que também abre antes de escolher o bus). Um par estéreo
/// é um instrumento só: tipo, reforço e no/fora do fone valem pros dois lados.
class ChannelActions {
  final MixerClient client;

  /// `false` quando ainda não há bus escolhido (mapear logo após conectar):
  /// o "no/fora do meu fone" é por bus e fica escondido.
  final bool withInclusion;

  const ChannelActions(this.client, {this.withInclusion = true});

  String? get _mixer {
    final m = client.mixerName;
    return (m != null && m.isNotEmpty) ? m : null;
  }

  List<int> _both(int ch) => [ch, if (client.partnerOf(ch) != null) client.partnerOf(ch)!];

  Future<void> setInstrument(int ch, InstrumentType? type) async {
    for (final c in _both(ch)) {
      client.setInstrumentOverride(c, type);
      final m = _mixer;
      if (m != null) await AppSettings.setInstrumentOverride(m, c, type);
    }
  }

  Future<void> setInclusion(int ch, ChannelInclusion v) async {
    for (final c in _both(ch)) {
      client.setChannelInclusion(c, v);
      final m = _mixer;
      if (m != null) await AppSettings.setChannelInclusion(m, client.busIndex, c, v);
    }
  }

  Future<void> setBoost(int ch, double db) async {
    for (final c in _both(ch)) {
      client.setChannelBoost(c, db);
    }
    await saveBoost(ch);
  }

  /// Grava o reforço atual do canal (e do par) — também depois de arrastar o
  /// fader no modo equalizado, que vira reforço e precisa durar.
  Future<void> saveBoost(int ch) async {
    final m = _mixer;
    if (m == null) return;
    for (final c in _both(ch)) {
      await AppSettings.setChannelBoost(m, c, client.channelBoostDb(c));
    }
  }

  /// Junta [a] e [b] num par: o lado [b] assume o instrumento de [a].
  Future<void> link(int a, int b) async {
    client.linkPair(a, b);
    final type = client.instruments[a - 1];
    client.setInstrumentOverride(b, type);
    final m = _mixer;
    if (m != null) {
      await AppSettings.setInstrumentOverride(m, b, type);
      await AppSettings.setChannelPairs(m, client.channelLinks);
    }
  }

  Future<void> unlink(int ch) async {
    client.unlinkPair(ch);
    final m = _mixer;
    if (m != null) await AppSettings.setChannelPairs(m, client.channelLinks);
  }

  /// Sugestões de par ainda não aplicadas: o link da própria mesa e os nomes
  /// ("Over L"/"Over R", "PC"/"PC").
  List<List<int>> pairSuggestions() {
    final seen = <String>{};
    final out = <List<int>>[];
    void add(int a, int b) {
      final p = a < b ? [a, b] : [b, a];
      if (client.partnerOf(p[0]) == p[1]) return;
      if (seen.add('${p[0]}-${p[1]}')) out.add(p);
    }

    client.mesaLinks.forEach(add);
    for (final p in namePairSuggestions([for (final c in client.channels) c.name])) {
      add(p[0], p[1]);
    }
    return out;
  }

  /// Carrega os pares salvos desta mesa; na primeira vez, aplica as sugestões
  /// (link da mesa + nomes) e grava — o músico desfaz em "Mapear canais".
  Future<void> loadPairs() async {
    final m = _mixer;
    if (m == null) return;
    final saved = await AppSettings.channelPairs(m);
    if (saved != null) {
      client.setChannelLinks(saved);
      return;
    }
    for (final p in pairSuggestions()) {
      if (client.partnerOf(p[0]) == null && client.partnerOf(p[1]) == null) {
        await link(p[0], p[1]);
      }
    }
    await AppSettings.setChannelPairs(m, client.channelLinks);
  }

  /// Editor completo do canal (tipo, reforço e, com bus, no/fora do fone).
  void edit(BuildContext context, ChannelInfo ch) {
    showInstrumentPicker(
      context,
      ch: ch.ch,
      channelName: ch.name,
      current: client.instruments[ch.ch - 1],
      detected: client.detectedInstrument(ch.ch),
      isOverridden: client.isOverridden(ch.ch),
      onSelected: (type) => setInstrument(ch.ch, type),
      inclusion: client.inclusionOf(ch.ch),
      parkedAtMesa: client.isParkedAtMesa(ch.ch),
      onInclusionChanged: withInclusion ? (v) => setInclusion(ch.ch, v) : null,
      boostDb: client.channelBoostDb(ch.ch),
      onBoostChanged: (db) => setBoost(ch.ch, db),
    );
  }
}
