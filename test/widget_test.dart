import 'package:flutter_test/flutter_test.dart';
import 'package:mxstage/main.dart';

void main() {
  testWidgets('app starts on connect screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MxStageApp());
    expect(find.text('mxstage'), findsOneWidget);
  });
}
