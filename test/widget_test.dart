import 'package:flutter_test/flutter_test.dart';
import 'package:omega_call/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OmegaCallApp());
    expect(find.byType(OmegaCallApp), findsOneWidget);
  });
}
