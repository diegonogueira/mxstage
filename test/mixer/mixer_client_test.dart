// Integration test: MixerClient writes correct /ch/NN/mix/MM/level OSC messages.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxstage/mixer/mixer_client.dart';
import 'package:mxstage/osc/osc_codec.dart';
import 'package:mxstage/osc/x32_protocol.dart';

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
}
