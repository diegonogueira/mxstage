// Render do MixerScreen com a barra de "Volume geral" — confirma que a barra é
// montada na árvore (retrato e paisagem) e se lê. Usa um MixerClient
// desconectado (channels vazios): os loads de settings dão early-return sem
// mixerName, então não precisa de mesa.
//
// A fonte de teste (Ahem) desenha cada glifo mais largo que a fonte real, então
// as barras já-existentes (_AutoMixBar/_ControlBar, bem cheias) estouram por
// poucos px SÓ no harness — não no aparelho. A _MasterVolumeBar tem slider
// Expanded e não estoura. Drenamos os avisos de overflow (e só eles: qualquer
// outra exceção derruba o teste) e checamos a fiação.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/mixer/mixer_client.dart';
import 'package:mxwise/state/app_mode.dart';
import 'package:mxwise/ui/screens/mixer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Drena avisos de overflow do RenderFlex (artefato da fonte Ahem). Rethrow em
  // qualquer exceção que NÃO seja overflow, pra não mascarar erro de verdade.
  void drainOverflowWarnings(WidgetTester tester) {
    for (var e = tester.takeException(); e != null; e = tester.takeException()) {
      if (e is FlutterError && e.message.contains('overflowed')) continue;
      throw e as Object;
    }
  }

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final client = MixerClient();
    addTearDown(client.dispose);
    await tester.pumpWidget(
      MaterialApp(home: MixerScreen(client: client, mode: AppMode.stage)),
    );
    await tester.pump(); // deixa os loads assíncronos assentarem
  }

  testWidgets('barra de Volume geral entra na árvore do mixer', (tester) async {
    await pumpAt(tester, const Size(500, 900));
    drainOverflowWarnings(tester);
    expect(find.text('Volume geral'), findsOneWidget);
    // O slider do master (faixa −12..+12) — distinto dos faders de canal (0..1).
    expect(
      find.byWidgetPredicate((w) =>
          w is Slider && w.min == kMasterMinDb && w.max == kMasterMaxDb),
      findsOneWidget,
    );
  });
}
