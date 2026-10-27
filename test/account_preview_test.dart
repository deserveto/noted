import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:noted/models/connection_model.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:noted/viewmodels/connection_viewmodel.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/profile_page.dart';
import 'package:noted/views/settings_page.dart';
import 'package:noted/views/welcome_page.dart';
import 'package:noted/utils/app_theme.dart';

// Preview fixtures are confined to tests. Production reads Supabase providers.
class _PreviewAuth extends ChangeNotifier implements AuthViewModel {
  @override
  UserModel get user => UserModel(
      uid: 'preview',
      name: 'Taylor Morgan',
      email: 'taylor@example.com',
      fieldOfStudy: 'Computer Science',
      createdAt: DateTime(2026));
  @override
  bool get isLoading => false;
  @override
  String? get errorMessage => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewNotes extends ChangeNotifier implements NoteViewModel {
  @override
  List<NoteModel> get notes => [
        for (var i = 0; i < 6; i++)
          NoteModel.empty('preview').copyWith(
              noteId: 'preview-$i',
              title: [
                'Understanding Neural Networks',
                'Weekly Project Notes',
                'Machine Learning Research',
                'Lecture notes',
                'Scheduling',
                'Ideas for later'
              ][i],
              content:
                  'Capture ideas and think clearly. Write together and keep moving forward.',
              category: [
                'AI',
                'Projects',
                'Research',
                'AI',
                'Systems',
                'Personal'
              ][i],
              isFavorite: i == 0 || i == 3,
              createdAt: DateTime.now(),
              liveMemberIds: i == 1 ? ['colleague'] : [])
      ];
  @override
  List<String> get categories => [
        'AI',
        'Networks',
        'Systems',
        'Security',
        'Research',
        'Personal',
        'Projects'
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewConnections extends ChangeNotifier
    implements ConnectionViewModel {
  @override
  List<ConnectionModel> get acceptedConnections => [
        ConnectionModel(
            connectionId: 'preview-connection',
            fromUserId: 'preview',
            fromName: 'Taylor Morgan',
            fromEmail: 'taylor@example.com',
            toUserId: 'colleague',
            toName: 'Jordan Lee',
            toEmail: 'jordan@example.com',
            status: ConnectionStatus.accepted,
            createdAt: DateTime(2026),
            updatedAt: DateTime(2026))
      ];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewSettings extends SettingsViewModel {
  _PreviewSettings(bool dark)
      : value =
            SettingsModel(theme: dark ? 'dark' : 'light', reduceMotion: true),
        super(SettingsRepository());
  final SettingsModel value;
  @override
  SettingsModel get settings => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final font in [
      ('DM Sans', 'assets/fonts/DMSans.ttf'),
      ('Newsreader', 'assets/fonts/Newsreader-Italic.ttf')
    ]) {
      final loader = FontLoader(font.$1)..addFont(rootBundle.load(font.$2));
      await loader.load();
    }
    PackageInfo.setMockInitialValues(
        appName: 'Noted',
        packageName: 'com.deserveto.noted',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
  });
  for (final width in [360.0, 390.0, 430.0]) {
    for (final dark in [false, true]) {
      for (final screen in ['welcome', 'profile', 'settings']) {
        testWidgets(
            '$screen preview ${width.toInt()} ${dark ? 'dark' : 'light'}',
            (tester) async {
          tester.view.physicalSize = Size(width, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final page = switch (screen) {
            'profile' => const ProfilePage(),
            'settings' => const SettingsPage(),
            _ => const WelcomePage()
          };
          await tester.pumpWidget(MultiProvider(
              providers: [
                ChangeNotifierProvider<AuthViewModel>(
                    create: (_) => _PreviewAuth()),
                ChangeNotifierProvider<NoteViewModel>(
                    create: (_) => _PreviewNotes()),
                ChangeNotifierProvider<ConnectionViewModel>(
                    create: (_) => _PreviewConnections()),
                ChangeNotifierProvider<SettingsViewModel>(
                    create: (_) => _PreviewSettings(dark))
              ],
              child: MaterialApp(
                  theme: dark ? AppTheme.dark : AppTheme.light,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(disableAnimations: true),
                      child: child!),
                  home: RepaintBoundary(
                      key: const ValueKey('preview'), child: page))));
          await tester.pumpAndSettle();
          final initialError = tester.takeException();
          await expectLater(
              find.byKey(const ValueKey('preview')),
              matchesGoldenFile(
                  'goldens/${screen}_${width.toInt()}_${dark ? 'dark' : 'light'}.png'));
          expect(initialError, isNull);
          if (screen == 'settings') {
            await tester.drag(
                find.byType(ListView).first, const Offset(0, -700));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
                find.byKey(const ValueKey('preview')),
                matchesGoldenFile(
                    'goldens/${screen}_${width.toInt()}_${dark ? 'dark' : 'light'}_writing.png'));
            await tester.drag(
                find.byType(ListView).first, const Offset(0, -5000));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await expectLater(
                find.byKey(const ValueKey('preview')),
                matchesGoldenFile(
                    'goldens/${screen}_${width.toInt()}_${dark ? 'dark' : 'light'}_privacy.png'));
          }
        });
      }
    }
  }
}
