import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/services/update_coordinator.dart';
import 'package:noted/utils/app_theme.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/viewmodels/update_viewmodel.dart';
import 'package:noted/views/updates_page.dart';
import 'package:noted/widgets/update_dialog.dart';
import 'update_viewmodel_test.dart' show FakeUpdates, FakeUpdateService;

class UpdateAuth extends ChangeNotifier implements AuthViewModel {
  @override
  bool get isAuthenticated => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class UpdateSettings extends ChangeNotifier implements SettingsViewModel {
  bool locked = true;
  @override
  bool get isLoading => false;
  @override
  SettingsModel get settings => SettingsModel(appLock: locked);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    for (final font in [
      ('DM Sans', 'assets/fonts/DMSans.ttf'),
      ('Newsreader', 'assets/fonts/Newsreader-Italic.ttf')
    ]) {
      await (FontLoader(font.$1)..addFont(rootBundle.load(font.$2))).load();
    }
  });
  testWidgets(
      'automatic prompts defer behind lock, editor and modal then appear once',
      (tester) async {
    final repo = FakeUpdates()..wait = Completer<void>();
    final vm = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta');
    addTearDown(vm.dispose);
    final unlock = Completer<bool>();
    final navigation = UpdateNavigationObserver();
    final navigator = GlobalKey<NavigatorState>();
    final preferences = UpdateSettings();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>(create: (_) => UpdateAuth()),
          ChangeNotifierProvider<SettingsViewModel>.value(value: preferences),
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [navigation],
            theme: AppTheme.light,
            builder: (context, child) => UpdateCoordinator(
                vm: vm,
                uid: 'alice',
                recovering: false,
                navigation: navigation,
                navigatorKey: navigator,
                authenticate: () => unlock.future,
                child: child!),
            home: const Scaffold(body: Text('Shell')))));
    await tester.pumpAndSettle();
    expect(repo.checks, 0);
    expect(find.text('Your notes are locked'), findsOneWidget);
    unlock.complete(true);
    await tester.pumpAndSettle();
    expect(repo.checks, 1);
    navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: TextField())));
    await tester.pumpAndSettle();
    repo.wait!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    navigator.currentState!.pop();
    final modal = showDialog<void>(
        context: navigator.currentContext!,
        builder: (_) => const AlertDialog(title: Text('Sensitive modal')));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    navigator.currentState!.pop();
    await modal;
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(repo.checks, 1);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(repo.checks, 1);
    await tester.pumpWidget(const SizedBox());
    preferences.dispose();
  });
  testWidgets('release history exposes retry and preserves current build',
      (tester) async {
    final repo = FakeUpdates()..failure = StateError('offline');
    final vm = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
      ..bindUser('alice');
    addTearDown(vm.dispose);
    await tester
        .pumpWidget(MaterialApp(home: UpdatesPage(vm: vm, history: true)));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Release history is unavailable'), findsOneWidget);
    repo.failure = null;
    repo.releases = [repo.release!];
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('build 10'), findsOneWidget);
    expect(find.textContaining('Installed 2.0.0'), findsOneWidget);
  });
  testWidgets(
      'recovery and background completion defer until a safe foreground',
      (tester) async {
    final repo = FakeUpdates()..wait = Completer<void>();
    final vm = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta');
    addTearDown(vm.dispose);
    final recovering = ValueNotifier(true);
    final settings = UpdateSettings()..locked = false;
    addTearDown(recovering.dispose);
    addTearDown(settings.dispose);
    final navigation = UpdateNavigationObserver();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewModel>(create: (_) => UpdateAuth()),
          ChangeNotifierProvider<SettingsViewModel>.value(value: settings),
        ],
        child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [navigation],
            builder: (context, child) => ValueListenableBuilder<bool>(
                valueListenable: recovering,
                builder: (context, value, _) => UpdateCoordinator(
                    vm: vm,
                    uid: 'alice',
                    recovering: value,
                    navigation: navigation,
                    navigatorKey: navigator,
                    child: child!)),
            home: const Scaffold(body: Text('Shell')))));
    await tester.pumpAndSettle();
    expect(repo.checks, 0);
    recovering.value = false;
    await tester.pumpAndSettle();
    expect(repo.checks, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repo.wait!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(UpdateDialog), findsOneWidget);
    expect(repo.checks, 1);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });
  for (final dark in [false, true]) {
    for (final width in [360.0, 390.0, 430.0]) {
      testWidgets('update dialog ${width.toInt()} ${dark ? 'dark' : 'light'}',
          (tester) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = FakeUpdates();
        final service = FakeUpdateService()..launchResult = false;
        final vm = UpdateViewModel(repo, service, channel: 'beta')
          ..bindUser('alice');
        addTearDown(vm.dispose);
        await vm.check(manual: true);
        await tester.pumpWidget(MaterialApp(
            theme: dark ? AppTheme.dark : AppTheme.light,
            home: RepaintBoundary(
                key: const ValueKey('update-preview'),
                child: Scaffold(
                    body: UpdateDialog(vm: vm, release: repo.release!)))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await expectLater(
            find.byKey(const ValueKey('update-preview')),
            matchesGoldenFile(
                'goldens/update_${width.toInt()}_${dark ? 'dark' : 'light'}.png'));
        await tester.tap(find.text('Update now'));
        await tester.pumpAndSettle();
        expect(
            find.textContaining('Couldn’t open your browser'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets('long notes and large text remain scrollable on a narrow phone',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeUpdates();
    final vm = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
      ..bindUser('alice');
    addTearDown(vm.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: Scaffold(body: UpdateDialog(vm: vm, release: repo.release!))));
    await tester.pumpAndSettle();
    expect(find.text('Update now'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
