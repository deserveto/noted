import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'repositories/auth_repository.dart';
import 'repositories/connection_repository.dart';
import 'repositories/note_repository.dart';
import 'repositories/settings_repository.dart';
import 'services/supabase_service.dart';
import 'viewmodels/settings_viewmodel.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/connection_viewmodel.dart';
import 'viewmodels/note_viewmodel.dart';
import 'viewmodels/theme_viewmodel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(AuthRepository())..initialize(),
        ),
        ChangeNotifierProxyProvider<AuthViewModel, SettingsViewModel>(
          create: (_) => SettingsViewModel(SettingsRepository()),
          update: (_, auth, settings) {
            final vm = settings ?? SettingsViewModel(SettingsRepository());
            Future.microtask(() => vm.bindUser(auth.user?.uid));
            return vm;
          },
        ),
        ChangeNotifierProxyProvider<SettingsViewModel, ThemeViewModel>(
          create: (_) => ThemeViewModel(),
          update: (_, settings, theme) {
            final vm = theme ?? ThemeViewModel();
            vm.bindSettings(settings);
            return vm;
          },
        ),
        ChangeNotifierProxyProvider<AuthViewModel, ConnectionViewModel>(
          create: (_) => ConnectionViewModel(ConnectionRepository()),
          update: (_, authViewModel, connectionViewModel) {
            final connections = connectionViewModel ??
                ConnectionViewModel(ConnectionRepository());
            connections.bindUser(authViewModel.user, notifyOnBind: false);
            return connections;
          },
        ),
        ChangeNotifierProxyProvider<AuthViewModel, NoteViewModel>(
          create: (_) => NoteViewModel(NoteRepository()),
          update: (_, authViewModel, noteViewModel) {
            final notes = noteViewModel ?? NoteViewModel(NoteRepository());
            final uid = authViewModel.user?.uid;
            Future.microtask(() {
              final changed = notes.boundUserId != uid;
              notes.bindUser(uid);
              if (changed && uid != null) notes.prepareRemoteAccount(uid);
            });
            return notes;
          },
        ),
      ],
      child: const NotedApp(),
    ),
  );
}
