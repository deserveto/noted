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
import 'notes_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key, this.onNavigate, this.onConnections});
  final ValueChanged<String>? onNavigate;
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
    void openSettings() => Navigator.push(
        context, MaterialPageRoute<void>(builder: (_) => const SettingsPage()));
    void openNotes(String filter) {
      if (onNavigate != null) {
        onNavigate!(filter);
      } else {
        Navigator.push(context,
            MaterialPageRoute<void>(builder: (_) => const NotesPage()));
      }
    }

    Widget section(String text) => Padding(
        padding: const EdgeInsets.only(top: 32, bottom: 12),
        child: Text(text,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: -.2)));
    return Scaffold(
        body: SafeArea(
            child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 128),
                children: [
          Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                  tooltip: 'Settings',
                  icon: const ReferenceIcon('gear', size: 21),
                  onPressed: openSettings)),
          Center(
              child: Column(children: [
            _buildProfileAvatar(user?.name ?? '', user?.avatarUrl ?? ''),
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
                style: TextStyle(fontSize: 14, color: theme.hintColor))
          ])),
          const SizedBox(height: 28),
          Container(
              decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(18)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: IntrinsicHeight(
                  child: Row(children: [
                for (final item in [
                  ('Notes', notes.length, 'All'),
                  (
                    'Favorites',
                    notes.where((n) => n.isFavorite).length,
                    'Favorites'
                  ),
                  ('Live', notes.where((n) => n.isLive).length, 'Live')
                ]) ...[
                  if (item.$1 != 'Notes')
                    VerticalDivider(width: 1, color: theme.dividerColor),
                  Expanded(
                      child: InkWell(
                          onTap: () => openNotes(item.$3),
                          child: Column(children: [
                            Text('${item.$2}',
                                style: const TextStyle(
                                    fontSize: 22, fontWeight: FontWeight.w600)),
                            Text(item.$1,
                                style: TextStyle(
                                    fontSize: 12, color: theme.hintColor))
                          ])))
                ]
              ]))),
          const SizedBox(height: 12),
          Row(children: [
            for (final stat in [
              (month, 'notes this month', 2),
              (words, 'words written', 3)
            ]) ...[
              if (stat.$3 == 3) const SizedBox(width: 12),
              Expanded(
                  child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color:
                              AppColors.noteColorFor(theme.brightness, stat.$3),
                          borderRadius: BorderRadius.circular(18)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${stat.$1}',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w600)),
                            Text(stat.$2,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: .7)))
                          ])))
            ]
          ]),
          section('What you write about'),
          if (sorted.isEmpty)
            Text('Your categories will appear as you add notes.',
                style: TextStyle(fontSize: 13, color: theme.hintColor)),
          ...sorted.map((cat) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                SizedBox(
                    width: 80,
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
                            backgroundColor:
                                theme.colorScheme.surfaceContainerHighest,
                            color: theme.colorScheme.primary))),
                const SizedBox(width: 12),
                SizedBox(
                    width: 20,
                    child: Text('${cat.value}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, color: theme.hintColor)))
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
                                  fontSize: 13, color: theme.hintColor)))
                    ]))),
          ],
          const SizedBox(height: 32),
          Container(
              decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border.all(color: theme.dividerColor),
                  borderRadius: BorderRadius.circular(16)),
              child: ListTile(
                  leading: const ReferenceIcon('gear', size: 18),
                  title: const Text('Settings', style: TextStyle(fontSize: 15)),
                  trailing: const ReferenceIcon('next', size: 16),
                  onTap: openSettings)),
        ])));
  }
}
