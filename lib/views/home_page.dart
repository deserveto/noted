import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../utils/markdown_formatter.dart';
import '../utils/note_navigation.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../widgets/calendar_sheet.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';
import '../widgets/activity_sheet.dart';

class HomePage extends StatelessWidget {
  const HomePage(
      {super.key, this.onNavigate, this.onProfile, this.onConnections});
  final ValueChanged<String>? onNavigate;
  final VoidCallback? onProfile;
  final VoidCallback? onConnections;
  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NoteViewModel>(),
        user = context.watch<AuthViewModel>().user;
    final settings = context.watch<SettingsViewModel>().settings,
        theme = Theme.of(context);
    final now = DateTime.now();
    final start = DateTime(
        now.year,
        now.month,
        now.day -
            (settings.weekStart == 'mon'
                ? (now.weekday - 1) % 7
                : now.weekday % 7));
    final week = List.generate(
        7, (i) => DateTime(start.year, start.month, start.day + i));
    final weekCount = vm.notes
        .where((n) =>
            !n.createdAt.isBefore(start) &&
            n.createdAt
                .isBefore(DateTime(start.year, start.month, start.day + 7)))
        .length;
    final greet = now.hour < 12
        ? 'Good morning'
        : now.hour < 18
            ? 'Good afternoon'
            : 'Good evening';
    final first = user?.name.trim().split(' ').first ?? '';
    final recent = vm.notes;
    return SafeArea(
        bottom: false,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 100),
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const NotedBrand(),
                Row(children: [
                  ActivityBell(onConnections: onConnections),
                  IconButton(
                      tooltip: 'Profile',
                      onPressed: onProfile,
                      icon: NotedAvatar(
                          name: user?.name ?? '',
                          size: 36,
                          photoUrl: user?.avatarUrl,
                          color: AppColors.secondary))
                ])
              ]),
              const SizedBox(height: 28),
              Text(DateFormat('EEEE, MMMM d').format(now).toUpperCase(),
                  style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: .96)),
              const SizedBox(height: 8),
              Text.rich(
                  TextSpan(text: '$greet, ', children: [
                    TextSpan(
                        text: '$first.',
                        style: TextStyle(
                            fontFamily: 'Newsreader',
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w400,
                            color: theme.colorScheme.primary))
                  ]),
                  style: theme.textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Your thoughts, beautifully organized.',
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              SurfacePanel(
                  padding: const EdgeInsets.all(8),
                  child: Column(children: [
                    Padding(
                        padding: const EdgeInsets.only(left: 8, right: 0),
                        child: Row(children: [
                          Expanded(
                              child: Text.rich(
                                  TextSpan(
                                      text: '$weekCount notes',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: theme.colorScheme.onSurface),
                                      children: [
                                        TextSpan(
                                            text: ' this week',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w400,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant))
                                      ]),
                                  style: const TextStyle(fontSize: 13))),
                          TextButton(
                              onPressed: () => showNotedCalendar(context, now),
                              child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ReferenceIcon('cal', size: 16),
                                    SizedBox(width: 6),
                                    Text('Calendar',
                                        style: TextStyle(fontSize: 13))
                                  ]))
                        ])),
                    Row(children: [
                      for (final d in week)
                        Expanded(child: Builder(builder: (context) {
                          final today = sameDay(d, now),
                              n = vm.notes
                                  .where((n) => sameDay(n.createdAt, d))
                                  .length;
                          return Semantics(
                              label:
                                  '${DateFormat.yMMMMEEEEd().format(d)}, $n notes',
                              child: TextButton(
                                  style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 64),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      backgroundColor: today
                                          ? theme.colorScheme.onSurface
                                          : null,
                                      foregroundColor: today
                                          ? theme.scaffoldBackgroundColor
                                          : theme.colorScheme.onSurface),
                                  onPressed: () =>
                                      showNotedCalendar(context, d),
                                  child: Column(children: [
                                    Text(
                                        DateFormat.E()
                                            .format(d)
                                            .substring(0, 1),
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: today
                                                ? theme.scaffoldBackgroundColor
                                                    .withValues(alpha: .7)
                                                : theme.colorScheme
                                                    .onSurfaceVariant)),
                                    const SizedBox(height: 3),
                                    Text('${d.day}',
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 4),
                                    ActivityDots(n,
                                        selected: today,
                                        visible: settings.calendarDots)
                                  ])));
                        }))
                    ]),
                  ])),
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 16),
                InlineError(vm.errorMessage!, onRetry: vm.retry)
              ],
              if (vm.isLoading && recent.isEmpty) ...[
                const SizedBox(height: 24),
                const NoteSkeleton()
              ] else if (recent.isEmpty) ...[
                const SectionHeader('Your library'),
                EmptyState(
                    title: 'A blank page',
                    message:
                        'Capture your first idea — it only takes a second.',
                    actionLabel: 'New note',
                    onAction: () => createNote(context))
              ] else ...[
                const SectionHeader('Continue where you left off'),
                Material(
                    color: theme.colorScheme.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: theme.dividerColor)),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                        onTap: () => openNote(context, recent.first),
                        child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: IntrinsicHeight(
                                child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                  Container(
                                      width: 6,
                                      decoration: BoxDecoration(
                                          color: AppColors.noteColor(
                                              theme.brightness,
                                              recent.first.color),
                                          borderRadius:
                                              BorderRadius.circular(10))),
                                  const SizedBox(width: 16),
                                  Expanded(
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                        Wrap(
                                            spacing: 5,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                  '${recent.first.category} · edited ${relativeTime(recent.first.updatedAt).toLowerCase()}',
                                                  style: theme
                                                      .textTheme.bodySmall),
                                              if (recent.first.isLive)
                                                const LiveBadge()
                                            ]),
                                        const SizedBox(height: 4),
                                        Text(
                                            recent.first.title.isEmpty
                                                ? 'Untitled'
                                                : recent.first.title,
                                            style: theme.textTheme.titleMedium
                                                ?.copyWith(
                                                    fontSize: 17,
                                                    letterSpacing: -.17)),
                                        const SizedBox(height: 4),
                                        Text(
                                            MarkdownFormatter.toPlainText(
                                                recent.first.content),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    fontSize: 13, height: 1.5))
                                      ])),
                                  const SizedBox(width: 8),
                                  const Center(
                                      child: ReferenceIcon('next', size: 18))
                                ]))))),
                if (recent.length > 1) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                      height: 40,
                      child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: (recent.length - 1).clamp(0, 4),
                          separatorBuilder: (_, i) => const SizedBox(width: 8),
                          itemBuilder: (context, i) {
                            final n = recent[i + 1];
                            return OutlinedButton(
                                onPressed: () => openNote(context, n),
                                style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12)),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                          width: 8,
                                          height: 8,
                                          decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: AppColors.noteColor(
                                                  theme.brightness, n.color))),
                                      const SizedBox(width: 8),
                                      ConstrainedBox(
                                          constraints: const BoxConstraints(
                                              maxWidth: 160),
                                          child: Text(
                                              n.title.isEmpty
                                                  ? 'Untitled'
                                                  : n.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 13)))
                                    ]));
                          }))
                ],
                const SectionHeader('Your library'),
                SurfacePanel(
                    padding: EdgeInsets.zero,
                    color: theme.scaffoldBackgroundColor,
                    child: IntrinsicHeight(
                        child: Row(children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0)
                          VerticalDivider(color: theme.dividerColor, width: 1),
                        Expanded(
                            child: InkWell(
                                onTap: () => onNavigate
                                    ?.call(['All', 'Favorites', 'Live'][i]),
                                borderRadius: BorderRadius.circular(18),
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 14),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                              '${[
                                                vm.totalNotes,
                                                vm.totalFavorites,
                                                vm.totalLive
                                              ][i]}',
                                              style: theme
                                                  .textTheme.headlineMedium
                                                  ?.copyWith(fontSize: 24)),
                                          const SizedBox(height: 2),
                                          Row(children: [
                                            Flexible(
                                                child: Text(
                                                    [
                                                      'All notes',
                                                      'Favorites',
                                                      'Live'
                                                    ][i],
                                                    style: theme
                                                        .textTheme.bodySmall)),
                                            const ReferenceIcon('next',
                                                size: 12)
                                          ])
                                        ])))),
                      ]
                    ]))),
                SectionHeader('Recent notes',
                    action: 'See all', onAction: () => onNavigate?.call('All')),
                NotesMasonry(
                    notes: recent.take(4).toList(),
                    onOpen: (n) => openNote(context, n),
                    onFavorite: vm.toggleFavorite),
              ],
            ]));
  }
}
