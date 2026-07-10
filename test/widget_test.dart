import 'package:flutter_test/flutter_test.dart';
import 'package:mxwise/main.dart';

void main() {
  testWidgets('app starts on the mixer discovery screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MxWiseApp());
    // Marca no hero + seção de descoberta comprovam que abriu na tela inicial.
    expect(find.text('Mix inteligente. Equilíbrio automático.'), findsOneWidget);
    expect(find.text('Mesas encontradas na rede'), findsOneWidget);
  });
}
