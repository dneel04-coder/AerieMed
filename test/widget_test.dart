import 'package:flutter_test/flutter_test.dart';

import 'package:resqruck/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ResQruckApp());
    expect(find.text('ResQruck'), findsOneWidget);
  });
}
