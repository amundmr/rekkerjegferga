import 'package:flutter_test/flutter_test.dart';
import 'package:rekker_jeg_ferga/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const RekkerJegFerjaApp());
    expect(find.text('Rekker jeg ferja?'), findsOneWidget);
  });
}
