import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_jaguar/presentation/widgets/status_tile.dart';

void main() {
  testWidgets('StatusTile renderiza etiqueta y valor',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusTile(
            label: 'BLE',
            value: 'ON',
          ),
        ),
      ),
    );

    expect(find.text('BLE'), findsOneWidget);
    expect(find.text('ON'), findsOneWidget);
  });
}
