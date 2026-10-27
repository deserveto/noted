import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'services/analytics_service.dart';
import 'services/app_lock_gate.dart';
import 'repositories/note_repository.dart';
import 'utils/app_routes.dart';
import 'utils/app_theme.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/settings_viewmodel.dart';
import 'viewmodels/theme_viewmodel.dart';
import 'views/main_shell.dart';
import 'views/note_link_page.dart';
import 'utils/note_links.dart';
import 'views/settings_page.dart';
import 'views/sign_in_page.dart';
import 'views/sign_up_page.dart';
import 'views/welcome_page.dart';

class NotedApp extends StatefulWidget {
  const NotedApp({super.key});
  @override
  State<NotedApp> createState() => _NotedAppState();
}

class _NotedAppState extends State<NotedApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) NoteRepository().refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool? _analytics;
  String? _authUid;
  bool _recoveryOpen = false;
  final _navigator = GlobalKey<NavigatorState>();
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final uid = auth.user?.uid;
    if (_authUid != null && _authUid != uid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _authUid == uid) {
          _navigator.currentState?.popUntil((route) => route.isFirst);
        }
      });
    }
    _authUid = uid;
    if (auth.isPasswordRecovery && !_recoveryOpen) {
      _recoveryOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final navContext = _navigator.currentContext;
        if (mounted && navContext != null) {
          await showPasswordRecoverySheet(navContext);
          if (mounted) auth.dismissPasswordRecovery();
        }
        _recoveryOpen = false;
      });
    }
    final theme = context.watch<ThemeViewModel>(),
        settings = context.watch<SettingsViewModel>().settings;
    if (_analytics != settings.analytics) {
      _analytics = settings.analytics;
      AnalyticsService.instance
          .setCollectionEnabled(settings.analytics)
          .catchError((Object _) {});
    }
    return MaterialApp(
      title: 'Noted',
      navigatorKey: _navigator,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: theme.themeMode,
      themeAnimationDuration: settings.reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      localizationsDelegates: const [
        ...GlobalMaterialLocalizations.delegates,
        FlutterQuillLocalizations.delegate
      ],
      supportedLocales: FlutterQuillLocalizations.supportedLocales,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        return MediaQuery(
            data: media.copyWith(
                disableAnimations:
                    media.disableAnimations || settings.reduceMotion),
            child: ScrollConfiguration(
                behavior:
                    const MaterialScrollBehavior().copyWith(scrollbars: false),
                child: AppLockGate(child: child!)));
      },
      onGenerateRoute: (settings) {
        final id = noteIdFromLink(settings.name ?? '');
        if (id == null) return null;
        return MaterialPageRoute<void>(
            settings: settings, builder: (_) => NoteLinkPage(noteId: id));
      },
      routes: {
        AppRoutes.welcome: (_) => const AuthGate(),
        AppRoutes.signIn: (_) => const SignInPage(),
        AppRoutes.signUp: (_) => const SignUpPage(),
        AppRoutes.main: (_) => const AuthGate(),
        '/settings': (_) => const SettingsPage()
      },
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    if (auth.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.isAuthenticated) return const MainShell();
    return const WelcomePage();
  }
}
