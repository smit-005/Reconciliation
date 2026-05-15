import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reconciliation_app/core/widgets/app_empty_state.dart';

void main() {
  testWidgets('AppEmptyState does not overflow in short constraints', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 110,
            child: AppEmptyState(
              icon: Icons.table_rows_rounded,
              title: 'No rows found',
              message: 'No rows found for selected filters.',
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('No rows found'), findsOneWidget);
  });
}
