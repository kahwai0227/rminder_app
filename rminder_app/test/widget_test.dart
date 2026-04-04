// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:rminder_app/main.dart';

void main() {
  testWidgets('App shell renders main navigation', (WidgetTester tester) async {
    // Build the app shell.
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.byType(MainScreen), findsOneWidget);
    expect(find.text('Budget'), findsWidgets);
    expect(find.text('Transactions'), findsWidgets);
    expect(find.text('Report'), findsWidgets);
  });
}
