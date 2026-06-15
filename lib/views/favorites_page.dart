import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../utils/app_colors.dart';
import '../viewmodels/note_viewmodel.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import 'note_detail_page.dart';

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) {
    // Register dependency on Theme to rebuild when theme changes (fixes IndexedStack cache theme bug)
    Theme.of(context);
    final notes = context.watch<NoteViewModel>();
    final favorites = notes.favoriteNotes;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Favorites',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: favorites.isEmpty
                    ? const EmptyState(
                        title: 'No favorite notes yet',
                        message:
                            'Mark important notes as favorite to find them faster.',
                        icon: Icons.push_pin_outlined,
                      )
                    : GridView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: favorites.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.78,
                        ),
                        itemBuilder: (context, index) {
                          final note = favorites[index];
                          return NoteCard(
                            note: note,
                            color: AppColors.noteColorFor(
                              Theme.of(context).brightness,
                              index,
                            ),
                            onTap: () => _openDetail(context, note),
                            onFavoritePressed: () => notes.toggleFavorite(note),
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

  void _openDetail(BuildContext context, NoteModel note) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NoteDetailPage(note: note)),
    );
  }
}
