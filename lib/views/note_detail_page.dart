import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../utils/app_colors.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../widgets/markdown_content.dart';
import 'add_edit_note_page.dart';

class NoteDetailPage extends StatelessWidget {
  const NoteDetailPage({required this.note, super.key});

  final NoteModel note;

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<NoteViewModel>();
    final auth = context.watch<AuthViewModel>();
    final connections = context.watch<ConnectionViewModel>();
    final currentUserId = auth.user?.uid ?? '';
    var current = note;
    for (final item in notes.notes) {
      if (item.noteId == note.noteId) {
        current = item;
        break;
      }
    }

    final isOwner = current.isOwner(currentUserId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Note Detail'),
        actions: [
          IconButton(
            tooltip: 'Favorite',
            onPressed: isOwner ? () => notes.toggleFavorite(current) : null,
            icon: Icon(
                current.isFavorite ? Icons.push_pin : Icons.push_pin_outlined),
          ),
          IconButton(
            tooltip: 'Share',
            onPressed: isOwner
                ? () => _showShareSheet(context, notes, connections, current)
                : null,
            icon: const Icon(Icons.ios_share_rounded),
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: isOwner ? () => _openEditor(context, current) : null,
            icon: const Icon(Icons.edit_note_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                current.title,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _DetailChip(
                      label: current.category, icon: Icons.category_outlined),
                  if (!isOwner)
                    _DetailChip(
                      label: 'Shared by ${current.ownerName}',
                      icon: Icons.group_outlined,
                    ),
                  _DetailChip(
                    label:
                        'Created ${DateFormat('dd MMM yyyy').format(current.createdAt)}',
                    icon: Icons.calendar_today_outlined,
                  ),
                  _DetailChip(
                    label:
                        'Updated ${DateFormat('dd MMM yyyy').format(current.updatedAt)}',
                    icon: Icons.update_rounded,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              MarkdownContent(
                content: current.content,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontSize: 16,
                      height: 1.65,
                    ),
              ),
              const SizedBox(height: 32),
              if (isOwner)
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => _openEditor(context, current),
                        icon: const Icon(Icons.edit_rounded),
                        label: const Text('Edit'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _confirmDelete(context, notes, current),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Delete'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size.fromHeight(52),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, NoteModel note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AddEditNotePage(note: note)),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    NoteViewModel notes,
    NoteModel note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete note?'),
          content: const Text('This note will be permanently removed.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    await notes.deleteNote(note.noteId);
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _showShareSheet(
    BuildContext context,
    NoteViewModel notes,
    ConnectionViewModel connections,
    NoteModel note,
  ) async {
    final user = connections.user;
    if (user == null) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final accepted = connections.acceptedConnections;
        if (accepted.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('Add and accept a connection before sharing notes.'),
          );
        }

        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            itemCount: accepted.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final connection = accepted[index];
              final targetUserId = connection.otherUserId(user.uid);
              final alreadyPending =
                  note.pendingSharedWithUserIds.contains(targetUserId);
              return ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: Text(connection.otherName(user.uid)),
                subtitle: Text(connection.otherEmail(user.uid)),
                trailing: alreadyPending
                    ? const Icon(Icons.hourglass_top_rounded)
                    : const Icon(Icons.send_rounded),
                onTap: alreadyPending
                    ? null
                    : () async {
                        await notes.shareNote(
                          note,
                          targetUserId,
                          ownerName: user.name,
                          ownerEmail: user.email,
                        );
                        if (context.mounted) {
                          Navigator.pop(context);
                        }
                      },
              );
            },
          ),
        );
      },
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
