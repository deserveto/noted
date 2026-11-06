import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/media_url_resolver.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';
import 'connections_page.dart';
import '../utils/app_colors.dart';
import '../utils/document_codec.dart';
import 'settings_page.dart';
import 'study_decks_page.dart';
import 'workspaces_page.dart';
import '../viewmodels/settings_viewmodel.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.onConnections});
  final VoidCallback? onConnections;

  Widget _buildProfileAvatar(String name, String avatarUrl) {
    CircleAvatar circle(String? resolvedUrl) => CircleAvatar(
        radius: 40,
        backgroundColor: AppColors.secondary,
        backgroundImage: resolvedUrl != null ? NetworkImage(resolvedUrl) : null,
        child: resolvedUrl != null
            ? null
            : Text(profileInitials(name),
                style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text)));

    if (avatarUrl.trim().isEmpty) return circle(null);
    final immediate = MediaUrlResolver.peekResolved(
      avatarUrl,
      defaultBucket: MediaUrlResolver.avatarsBucket,
    );
    if (immediate != null) return circle(immediate);
    return FutureBuilder<String?>(
      future: MediaUrlResolver.resolve(
        avatarUrl,
        defaultBucket: MediaUrlResolver.avatarsBucket,
      ),
      builder: (context, snapshot) => circle(snapshot.data),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthViewModel>().user;
    final vm = context.watch<NoteViewModel>();
    final notes = vm.notes;
    final memberIds = notes
        .expand((n) => n.liveMemberIds)
        .where((id) => id != user?.uid)
        .toSet();
    final collaborators = context
        .watch<ConnectionViewModel>()
        .acceptedConnections
        .where((c) => memberIds.contains(c.otherUserId(user?.uid ?? '')))
        .toList();
    final now = DateTime.now();
    final month = notes
        .where((n) =>
            n.createdAt.year == now.year && n.createdAt.month == now.month)
        .length;
    final words = notes.fold<int>(
        0,
        (sum, n) =>
            sum +
            DocumentCodec.toPlainText(n.content)
                .trim()
                .split(RegExp(r'\s+'))
                .where((w) => w.isNotEmpty)
                .length);
    final categories = <String, int>{};
    for (final n in notes) {
      categories.update(n.category, (v) => v + 1, ifAbsent: () => 1);
    }
    final sorted = categories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = sorted.isEmpty ? 1 : sorted.first.value;
    final theme = Theme.of(context);
    final aiEnabled = context.watch<SettingsViewModel>().settings.aiEnabled;
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute<void>(builder: (_) => page));

    Widget shortcut(String label, String icon, VoidCallback onTap) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: ReferenceIcon(icon),
          title: Text(label),
          trailing: const ReferenceIcon('next', size: 16),
          onTap: onTap,
        );

    Widget section(String text) => Padding(
        padding: const EdgeInsets.only(top: 32, bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -.2)));
    return Material(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
            bottom: false,
            child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
                children: [
                  Center(
                      child: Column(children: [
                    _buildProfileAvatar(
                        user?.name ?? '', user?.avatarUrl ?? ''),
                    const SizedBox(height: 16),
                    Text(user?.name ?? '',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.5)),
                    Text(
                        '${user?.email ?? ''}${user?.fieldOfStudy.isNotEmpty == true ? ' · ${user!.fieldOfStudy}' : ''}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14,
                            color: theme.colorScheme.onSurfaceVariant))
                  ])),
                  const SizedBox(height: 20),
                  shortcut(
                      'Edit profile', 'edit', () => showEditProfile(context)),
                  shortcut('Workspaces', 'layers',
                      () => open(const WorkspacesPage())),
                  if (aiEnabled)
                    shortcut('Saved decks', 'cards',
                        () => open(const StudyDecksPage())),
                  shortcut(
                      'Settings', 'gear', () => open(const SettingsPage())),
                  section('Writing summary'),
                  Text(
                      '${pluralize(month, 'note')} this month · ${pluralize(words, 'word')} written',
                      style: theme.textTheme.bodyMedium),
                  section('What you write about'),
                  if (sorted.isEmpty)
                    Text('Your categories will appear as you add notes.',
                        style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ...sorted.map((cat) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Flexible(
                            flex: 2,
                            child: Text(cat.key,
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: LinearProgressIndicator(
                                    value: cat.value / max,
                                    minHeight: 8,
                                    backgroundColor: theme
                                        .colorScheme.surfaceContainerHighest,
                                    color: theme.colorScheme.primary))),
                        const SizedBox(width: 12),
                        ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 28),
                            child: Text('${cat.value}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurfaceVariant)))
                      ]))),
                  if (collaborators.isNotEmpty) ...[
                    section('Writing with'),
                    InkWell(
                        onTap: onConnections ??
                            () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => const ConnectionsPage())),
                        child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                border: Border.all(color: theme.dividerColor),
                                borderRadius: BorderRadius.circular(16)),
                            child: Row(children: [
                              for (final c in collaborators.take(4))
                                NotedAvatar(
                                    name: c.otherName(user?.uid ?? ''),
                                    uid: c.otherUserId(user?.uid ?? ''),
                                    size: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Text(
                                      '${collaborators.map((c) => c.otherName(user?.uid ?? '').split(' ').first).join(', ')} in live notes',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: theme
                                              .colorScheme.onSurfaceVariant)))
                            ]))),
                  ],
                ])));
  }
}
