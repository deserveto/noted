import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../utils/app_colors.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import '../widgets/stat_card.dart';
import 'add_edit_note_page.dart';
import 'note_detail_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final notes = context.watch<NoteViewModel>();
    final user = auth.user;
    final theme = Theme.of(context);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(context, user?.uid),
        child: const Icon(Icons.add_rounded, size: 32),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Hello, ${user?.name.split(' ').first ?? 'Student'}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "Let's organize your notes",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.62,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _WeekStrip(),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        StatCard(
                          label: 'Total Notes',
                          value: notes.totalNotes,
                          icon: Icons.sticky_note_2_outlined,
                        ),
                        const SizedBox(width: 12),
                        StatCard(
                          label: 'Favorites',
                          value: notes.totalFavorites,
                          icon: Icons.push_pin_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Recent Notes',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (notes.recentNotes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: notes.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : const EmptyState(
                        title: 'No notes yet',
                        message:
                            'Tap the add button to create your first study note.',
                      ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
                sliver: SliverGrid.builder(
                  itemCount: notes.recentNotes.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, index) {
                    final note = notes.recentNotes[index];
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

class _WeekStrip extends StatelessWidget {
  const _WeekStrip();

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = today.subtract(Duration(days: today.weekday % 7));
    final labels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final theme = Theme.of(context);
    final mutedDateColor = theme.colorScheme.onSurface.withValues(alpha: 0.68);
    final dateColor = theme.colorScheme.onSurface.withValues(alpha: 0.9);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_monthName(today.month)}, ${today.year}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(7, (index) {
            final date = start.add(Duration(days: index));
            final selected = _sameDay(date, today);

            return Container(
              width: 36,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color:
                    selected ? theme.colorScheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Text(
                    labels[index],
                    style: TextStyle(
                      color: selected ? Colors.white : mutedDateColor,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      color: selected ? Colors.white : dateColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return names[month - 1];
  }
}
