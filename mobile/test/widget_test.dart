import 'package:flutter_test/flutter_test.dart';
import 'package:doctransit/main.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const DocTransitApp());
    expect(find.byType(DocTransitApp), findsOneWidget);
  });
}
