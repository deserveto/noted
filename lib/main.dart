import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'repositories/auth_repository.dart';
import 'repositories/connection_repository.dart';
import 'repositories/note_repository.dart';
import 'viewmodels/auth_viewmodel.dart';
import 'viewmodels/connection_viewmodel.dart';
import 'viewmodels/note_viewmodel.dart';
import 'viewmodels/theme_viewmodel.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
        ChangeNotifierProvider(
          create: (_) => AuthViewModel(AuthRepository())..initialize(),
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
            Future.microtask(() => notes.bindUser(authViewModel.user?.uid));
            return notes;
          },
        ),
      ],
      child: const NotedApp(),
    ),
  );
}
