import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/services/app_lock_gate.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';

class LockAuth extends ChangeNotifier implements AuthViewModel {
  @override
  bool get isAuthenticated => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class LockSettings extends ChangeNotifier implements SettingsViewModel {
  @override
  bool get isLoading => false;
  @override
  SettingsModel get settings => const SettingsModel(appLock: true);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('lock covers pushed routes and preserves unsaved editor state',
      (tester) async {
    var authentication = Completer<bool>();
    final draft = TextEditingController();
    addTearDown(draft.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>(create: (_) => LockAuth()),
          ChangeNotifierProvider<SettingsViewModel>(
              create: (_) => LockSettings())
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) => AppLockGate(
                authenticate: () => authentication.future, child: child!),
            home: const Scaffold(body: Text('Home')))));
    await tester.pump();
    expect(find.text('Your notes are locked'), findsOneWidget);
    authentication.complete(true);
    await tester.pumpAndSettle();
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => Scaffold(body: TextField(controller: draft))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved private draft');
    authentication = Completer<bool>();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(find.text('Your notes are locked'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextField, skipOffstage: false), findsOneWidget);
    expect(draft.text, 'Unsaved private draft');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    authentication.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(draft.text, 'Unsaved private draft');
  });
}
