import 'package:flutter_test/flutter_test.dart';
import 'package:autodiary/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AutoDiaryApp());
    expect(find.text('АвтоДневник'), findsOneWidget);
  });
}
