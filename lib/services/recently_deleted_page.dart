import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../repositories/note_repository.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';

class RecentlyDeletedPage extends StatelessWidget {
  const RecentlyDeletedPage({super.key, this.repository});

  final NoteRepository? repository;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthViewModel>().user?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to view recently deleted notes.')),
      );
    }

    final repo = repository ?? NoteRepository();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Recently deleted',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      body: StreamBuilder<List<NoteModel>>(
        stream: repo.watchDeletedNotes(uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: InlineError(
                'Couldn’t load recently deleted notes. ${snapshot.error}',
                onRetry: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => RecentlyDeletedPage(repository: repo),
                  ),
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final notes = snapshot.data!;
          if (notes.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ReferenceIcon(
                      'trash',
                      size: 40,
                      color: Theme.of(context).hintColor,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No recently deleted notes',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Deleted notes appear here so you can restore them.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(context).hintColor,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: notes.length,
            separatorBuilder: (_, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final note = notes[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(note.title.isEmpty ? 'Untitled note' : note.title),
                subtitle: Text(
                  '${note.category} · Deleted ${relativeTime(note.deletedAt!)}',
                ),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Deleted note actions',
                  icon: const ReferenceIcon('more'),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'restore', child: Text('Restore')),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete permanently'),
                    ),
                  ],
                  onSelected: (action) async {
                    if (action == 'restore') {
                      try {
                        await repo.restoreNote(note.noteId);
                        if (context.mounted) {
                          notedToast(context, 'Note restored');
                        }
                      } catch (error) {
                        if (context.mounted) {
                          notedToast(context, 'Couldn’t restore note. $error');
                        }
                      }
                      return;
                    }
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('Delete this note permanently?'),
                        content: const Text(
                          'This can’t be undone. The note and its live collaboration data will be removed.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('Delete permanently'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    try {
                      await repo.permanentlyDeleteNote(note.noteId);
                      if (context.mounted) {
                        notedToast(context, 'Note permanently deleted');
                      }
                    } catch (error) {
                      if (context.mounted) {
                        notedToast(context, 'Couldn’t delete note. $error');
                      }
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
