// Integration test: MixerClient writes correct /ch/NN/mix/MM/level OSC messages.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/mixer/mixer_client.dart';
import 'package:mxwise/osc/osc_codec.dart';
import 'package:mxwise/osc/x32_protocol.dart';
import 'package:mxwise/state/instrument_type.dart';

void main() {
  late RawDatagramSocket fakeX32;
  late MixerClient client;
  // All messages received by the fake X32 (single listener)
  final received = <OscMessage>[];

  setUp(() async {
    received.clear();
    fakeX32 = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, kX32Port);

    fakeX32.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = fakeX32.receive();
      if (dg == null) return;
      final msg = decodeOsc(dg.data);
      received.add(msg);

      if (msg.address == '/xinfo') {
        fakeX32.send(
          encodeOsc('/xinfo', ',ssss', ['127.0.0.1', 'X32-TEST', 'X32', '1.0']),
          dg.address,
          dg.port,
        );
      }
      if (msg.address.contains('/config/name')) {
        fakeX32.send(
          encodeOsc(msg.address, ',s', ['Ch ${msg.address.split('/')[2]}']),
          dg.address,
          dg.port,
        );
      }
    });

    client = MixerClient();
    await client.connect('127.0.0.1', busIndex: 3);
    received.clear(); // discard handshake messages; only care about sends
  });

  tearDown(() async {
    await client.disconnect();
    fakeX32.close();
  });

  test('setChannelSend writes /ch/08/mix/03/level ,f 0.75', () async {
    client.setChannelSend(8, 0.75);
    await Future.delayed(const Duration(milliseconds: 100));

    final send = received.firstWhere(
      (m) => m.address == '/ch/08/mix/03/level',
      orElse: () => throw StateError('No level message received'),
    );
    expect((send.args.first as double), closeTo(0.75, 0.001));
  });

  test('setChannelSend updates local channel state immediately', () {
    client.setChannelSend(1, 0.5);
    expect(client.channels[0].sendLevel, closeTo(0.5, 0.001));
  });

  test('setChannelSend clamps level to 0..1', () {
    client.setChannelSend(1, 1.5);
    expect(client.channels[0].sendLevel, 1.0);
    client.setChannelSend(1, -0.5);
    expect(client.channels[0].sendLevel, 0.0);
  });

  test('connect populates bus names; busName reflects selected bus', () {
    // The fake X32 answers /bus/NN/config/name with 'Ch NN'.
    expect(client.busNames[0], 'Ch 01');
    expect(client.busName, 'Ch 03'); // connected on busIndex 3
  });

  test('setBus switches bus and re-reads send levels for the new bus', () async {
    received.clear();
    await client.setBus(5);

    expect(client.busIndex, 5);
    await Future.delayed(const Duration(milliseconds: 100));
    // Re-fetch issues a GET (empty args) on the new bus.
    expect(
      received.any((m) => m.address == '/ch/01/mix/05/level' && m.args.isEmpty),
      isTrue,
    );
  });

  test('setChannelSend targets the newly selected bus after setBus', () async {
    await client.setBus(6);
    received.clear();

    client.setChannelSend(8, 0.5);
    await Future.delayed(const Duration(milliseconds: 100));

    // Only the selected bus is ever written (safety invariant).
    final writes = received.where((m) => m.address.endsWith('/level') && m.args.isNotEmpty);
    expect(writes, isNotEmpty);
    expect(writes.every((m) => m.address == '/ch/08/mix/06/level'), isTrue);
  });

  // ── Override manual de instrumento ─────────────────────────────────────────
  // A mesa fake nomeia os canais "Ch NN", que a auto-detecção não reconhece
  // (unknown) — base ideal para checar que o override vence o detectado.

  test('setInstrumentOverride wins over detection and flags the channel', () {
    expect(client.detectedInstrument(1), InstrumentType.unknown);
    expect(client.isOverridden(1), isFalse);

    client.setInstrumentOverride(1, InstrumentType.backingVocal);

    expect(client.instruments[0], InstrumentType.backingVocal);
    expect(client.isOverridden(1), isTrue);
    // Detecção original preservada por baixo do override.
    expect(client.detectedInstrument(1), InstrumentType.unknown);
  });

  test('setInstrumentOverride(null) reverts to the detected type', () {
    client.setInstrumentOverride(1, InstrumentType.leadVocal);
    expect(client.instruments[0], InstrumentType.leadVocal);

    client.setInstrumentOverride(1, null);

    expect(client.isOverridden(1), isFalse);
    expect(client.instruments[0], client.detectedInstrument(1));
  });

  test('setInstrumentOverrides bulk-loads and clearInstrumentOverrides resets', () {
    client.setInstrumentOverrides({
      2: InstrumentType.guitar,
      3: InstrumentType.bass,
    });

    expect(client.instruments[1], InstrumentType.guitar);
    expect(client.instruments[2], InstrumentType.bass);
    expect(client.isOverridden(2), isTrue);
    expect(client.isOverridden(1), isFalse);

    client.clearInstrumentOverrides();

    expect(client.isOverridden(2), isFalse);
    expect(client.instruments[1], client.detectedInstrument(2));
    expect(client.instruments[2], client.detectedInstrument(3));
  });
}
