import 'package:flutter/material.dart';

import '../models/note_model.dart';
import 'add_edit_note_page.dart';

/// Reading and writing share one document surface, including live updates.
class NoteDetailPage extends StatelessWidget {
  const NoteDetailPage({required this.note, super.key});
  final NoteModel note;

  @override
  Widget build(BuildContext context) => AddEditNotePage(note: note);
}
