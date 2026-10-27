import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../repositories/note_repository.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../widgets/noted_ui.dart';
import 'add_edit_note_page.dart';
import 'welcome_page.dart';

class NoteLinkPage extends StatefulWidget {
  const NoteLinkPage({super.key, required this.noteId});
  final String noteId;
  @override
  State<NoteLinkPage> createState() => _NoteLinkPageState();
}

class _NoteLinkPageState extends State<NoteLinkPage> {
  Stream<NoteModel?>? _stream;
  String? _uid;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    if (auth.isInitializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!auth.isAuthenticated) return const WelcomePage();
    if (_uid != auth.user!.uid) {
      _uid = auth.user!.uid;
      _stream = NoteRepository().watchNote(widget.noteId);
    }
    return StreamBuilder<NoteModel?>(
        stream: _stream,
        builder: (context, snapshot) {
          if (snapshot.hasError ||
              (snapshot.connectionState == ConnectionState.active &&
                  snapshot.data == null)) {
            return Scaffold(
                appBar: AppBar(title: const Text('Shared note')),
                body: Padding(
                    padding: const EdgeInsets.all(24),
                    child: InlineError(
                        'This note is unavailable. Ask its owner to add you as a member.',
                        onRetry: () => setState(() => _stream =
                            NoteRepository().watchNote(widget.noteId)))));
          }
          final note = snapshot.data;
          if (note == null) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (note.deletedAt != null) {
            return Scaffold(
                appBar: AppBar(title: const Text('Shared note')),
                body: const Padding(
                    padding: EdgeInsets.all(24),
                    child:
                        Text('This note has been moved to Recently deleted.')));
          }
          return AddEditNotePage(key: ValueKey(note.noteId), note: note);
        });
  }
}
