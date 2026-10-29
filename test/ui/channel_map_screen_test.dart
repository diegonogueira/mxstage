// "Mapear canais" monta e esconde canais sem nome (o MixerClient desconectado
// só tem os "Ch N" padrão).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/mixer/mixer_client.dart';
import 'package:mxwise/ui/screens/channel_map_screen.dart';
import 'package:mxwise/ui/widgets/channel_actions.dart';

void main() {
  testWidgets('tela de mapear esconde canais sem nome e revela sob pedido',
      (tester) async {
    final client = MixerClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ChannelMapScreen(client: client, actions: ChannelActions(client)),
    ));
    expect(find.text('Mapear canais'), findsOneWidget);
    expect(find.text('Mostrar canais sem nome (32)'), findsOneWidget);
    await tester.tap(find.text('Mostrar canais sem nome (32)'));
    await tester.pump();
    expect(find.text('Sem instrumento (o Equalizar ignora)'), findsOneWidget);
  });

  test('sem nome = vazio ou "Ch N"', () {
    expect(isUnnamedChannel(ChannelInfo(ch: 1, name: '')), isTrue);
    expect(isUnnamedChannel(ChannelInfo(ch: 25, name: 'Ch 25')), isTrue);
    expect(isUnnamedChannel(ChannelInfo(ch: 17, name: 'Igor')), isFalse);
  });
}
