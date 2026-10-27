import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/welcome_page.dart';
import 'package:noted/utils/app_routes.dart';
import 'package:noted/utils/app_theme.dart';

void main() {
  for (final width in [360.0, 390.0, 430.0]) {
    for (final dark in [false, true]) {
      testWidgets(
          'welcome fits $width in ${dark ? 'dark' : 'light'} theme and opens signup',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(ChangeNotifierProvider(
            create: (_) => SettingsViewModel(SettingsRepository()),
            child: MaterialApp(
                theme: dark ? AppTheme.dark : AppTheme.light,
                home: const WelcomePage(),
                routes: {
                  AppRoutes.signUp: (_) =>
                      const Scaffold(body: Text('Signup destination'))
                })));
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull);
        expect(find.text('Create an account'), findsOneWidget);
        await tester.ensureVisible(find.text('Create an account'));
        await tester.tap(find.text('Create an account'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Signup destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
