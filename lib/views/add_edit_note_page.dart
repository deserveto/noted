import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../utils/app_colors.dart';
import '../utils/validators.dart';
import '../viewmodels/note_viewmodel.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/formatting_toolbar.dart';

class AddEditNotePage extends StatefulWidget {
  const AddEditNotePage({required this.note, super.key});

  final NoteModel note;

  @override
  State<AddEditNotePage> createState() => _AddEditNotePageState();
}

class _AddEditNotePageState extends State<AddEditNotePage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late String _category;
  late bool _isFavorite;

  bool get _isEditing => widget.note.noteId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note.title);
    _contentController = TextEditingController(text: widget.note.content);
    _category = widget.note.category;
    _isFavorite = widget.note.isFavorite;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notes = context.watch<NoteViewModel>();

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Note' : 'Add Note')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomTextField(
                  controller: _titleController,
                  label: 'Title',
                  icon: Icons.title_rounded,
                  validator: (value) => Validators.requiredText(value, 'Title'),
                ),
                const SizedBox(height: 16),
                _CategorySelector(
                  category: _category,
                  onTap: () => _showCategorySheet(notes.categories),
                ),
                const SizedBox(height: 16),
                FormattingToolbar(controller: _contentController),
                const SizedBox(height: 12),
                CustomTextField(
                  controller: _contentController,
                  label: 'Content',
                  hint: 'Write your note here...',
                  icon: Icons.notes_rounded,
                  maxLines: 12,
                  validator: (value) =>
                      Validators.requiredText(value, 'Content'),
                ),
                const SizedBox(height: 18),
                Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: SwitchListTile(
                    value: _isFavorite,
                    onChanged: (value) => setState(() => _isFavorite = value),
                    title: const Text(
                      'Favorite',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle:
                        const Text('Pin important notes for quick access'),
                    activeThumbColor: AppColors.ink,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
                const SizedBox(height: 18),
                CustomButton(
                  label: _isEditing ? 'Save Changes' : 'Save Note',
                  icon: Icons.check_rounded,
                  isLoading: notes.isLoading,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showCategorySheet(List<String> categories) async {
    final customController = TextEditingController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 18,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Category',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: customController,
                  decoration: const InputDecoration(
                    hintText: 'Add a new category',
                    prefixIcon: Icon(Icons.add_rounded),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.pop(context, value.trim());
                    }
                  },
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.separated(
                    itemCount: categories.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final value = categories[index];
                      return ListTile(
                        dense: true,
                        title: Text(value),
                        trailing: Icon(
                          value == _category
                              ? Icons.check_circle
                              : Icons.circle_outlined,
                          color: value == _category
                              ? AppColors.ink
                              : Theme.of(context).dividerColor,
                        ),
                        onTap: () => Navigator.pop(context, value),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                CustomButton(
                  label: 'Save',
                  icon: Icons.check_rounded,
                  onPressed: () {
                    final value = customController.text.trim();
                    Navigator.pop(context, value.isEmpty ? _category : value);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
    customController.dispose();

    if (selected != null && mounted) {
      setState(() => _category = selected);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final note = widget.note.copyWith(
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      category: _category,
      isFavorite: _isFavorite,
    );

    await context.read<NoteViewModel>().saveNote(note);

    if (!mounted) {
      return;
    }
    Navigator.pop(context);
  }
}

class _CategorySelector extends StatelessWidget {
  const _CategorySelector({
    required this.category,
    required this.onTap,
  });

  final String category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Category',
          prefixIcon: Icon(Icons.category_outlined),
          suffixIcon: Icon(Icons.keyboard_arrow_down_rounded),
        ),
        child: Text(category),
      ),
    );
  }
}
