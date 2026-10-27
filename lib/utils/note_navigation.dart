import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../views/add_edit_note_page.dart';
import 'app_colors.dart';

void openNote(BuildContext context, NoteModel note) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
        settings: RouteSettings(name: '/notes/${note.noteId}'),
        builder: (_) => AddEditNotePage(note: note)));
void createNote(BuildContext context, {DateTime? date}) {
  final user = context.read<AuthViewModel>().user;
  if (user == null) return;
  final s = context.read<SettingsViewModel>().settings;
  final now = DateTime.now();
  final created = date == null ||
          (date.year == now.year &&
              date.month == now.month &&
              date.day == now.day)
      ? now
      : DateTime(date.year, date.month, date.day, 12);
  final note =
      NoteModel.empty(user.uid, ownerName: user.name, ownerEmail: user.email)
          .copyWith(
              category: s.defaultCat,
              color: s.defaultColor == 'auto'
                  ? AppColors
                      .colorKeys[context.read<NoteViewModel>().totalNotes % 6]
                  : s.defaultColor,
              createdAt: created);
  Navigator.of(context).push(MaterialPageRoute<void>(
      settings: const RouteSettings(name: '/notes/new'),
      builder: (_) => AddEditNotePage(note: note)));
}
