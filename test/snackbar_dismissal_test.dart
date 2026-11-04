import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noted/widgets/noted_ui.dart';

void main() {
  testWidgets('Undo snackbar still dismisses with accessible navigation',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(accessibleNavigation: true),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => notedToast(context, 'Deleted note', undo: () {}),
            child: const Text('show'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('show'));
    await tester.pump();
    expect(find.text('Deleted note'), findsOneWidget);

    // Flutter keeps action snackbars open indefinitely for screen readers
    // unless persistence is explicitly disabled.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 4600));
    await tester.pumpAndSettle();
    expect(find.text('Deleted note'), findsNothing);
  });
}
