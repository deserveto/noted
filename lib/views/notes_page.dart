import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../utils/app_colors.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../widgets/category_chips.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import 'add_edit_note_page.dart';
import 'note_detail_page.dart';

class NotesPage extends StatelessWidget {
  const NotesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Register dependency on Theme to rebuild when theme changes (fixes IndexedStack cache theme bug)
    Theme.of(context);
    final auth = context.watch<AuthViewModel>();
    final notes = context.watch<NoteViewModel>();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, auth.user?.uid),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Notes',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              _CompactSearchField(
                initialValue: notes.searchQuery,
                onChanged: notes.updateSearch,
              ),
              const SizedBox(height: 14),
              CategoryChips(
                categories: notes.categories,
                selectedCategory: notes.selectedCategory,
                onSelected: notes.updateCategory,
              ),
              if (notes.errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: notes.errorMessage!),
              ],
              const SizedBox(height: 14),
              if (notes.pendingSharedNotes.isNotEmpty) ...[
                const Text(
                  'Pending Shares',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 105,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: notes.pendingSharedNotes.length,
                    itemBuilder: (context, index) {
                      final pendingNote = notes.pendingSharedNotes[index];
                      return Container(
                        width: 250,
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.1),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    pendingNote.title.isEmpty
                                        ? 'Untitled'
                                        : pendingNote.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Shared by: ${pendingNote.ownerName.isEmpty ? pendingNote.ownerEmail : pendingNote.ownerName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor:
                                        Theme.of(context).colorScheme.error,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () =>
                                      notes.declineShare(pendingNote.noteId),
                                  child: const Text('Decline',
                                      style: TextStyle(fontSize: 12)),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Theme.of(context).colorScheme.primary,
                                    foregroundColor:
                                        Theme.of(context).colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  onPressed: () => notes.acceptShare(
                                    pendingNote.noteId,
                                    ownerName: auth.user?.name ?? '',
                                    ownerEmail: auth.user?.email ?? '',
                                  ),
                                  child: const Text('Accept',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
              ],
              Expanded(
                child: notes.isLoading && notes.notes.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : notes.filteredNotes.isEmpty
                        ? const EmptyState(
                            title: 'No matching notes',
                            message: 'Try another search term or category.',
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.only(bottom: 96),
                            itemCount: notes.filteredNotes.length,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                              childAspectRatio: 0.78,
                            ),
                            itemBuilder: (context, index) {
                              final note = notes.filteredNotes[index];
                              return NoteCard(
                                note: note,
                                color: AppColors.noteColorFor(
                                  Theme.of(context).brightness,
                                  index,
                                ),
                                onTap: () => _openDetail(context, note),
                                onFavoritePressed: () =>
                                    notes.toggleFavorite(note),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openEditor(BuildContext context, String? userId) {
    if (userId == null) {
      return;
    }
    final user = context.read<AuthViewModel>().user;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditNotePage(
          note: NoteModel.empty(
            userId,
            ownerName: user?.name ?? '',
            ownerEmail: user?.email ?? '',
          ),
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, NoteModel note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteDetailPage(note: note)),
    );
  }
}

class _CompactSearchField extends StatefulWidget {
  const _CompactSearchField({
    required this.initialValue,
    required this.onChanged,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  State<_CompactSearchField> createState() => _CompactSearchFieldState();
}

class _CompactSearchFieldState extends State<_CompactSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void didUpdateWidget(covariant _CompactSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != _controller.text) {
      _controller.text = widget.initialValue;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 42,
      child: TextField(
        controller: _controller,
        onChanged: (value) {
          widget.onChanged(value);
          setState(() {});
        },
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search Note...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
          fillColor: theme.inputDecorationTheme.fillColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(21),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 1),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.error, fontSize: 12),
      ),
    );
  }
}
