import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../utils/app_colors.dart';
import '../utils/note_navigation.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../widgets/category_chips.dart';
import '../widgets/empty_state.dart';
import '../widgets/note_card.dart';
import '../widgets/noted_ui.dart';
import '../widgets/pending_share_actions.dart';
import '../widgets/reference_icon.dart';
import '../widgets/workspace_filter_bar.dart';
import 'ai_page.dart';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key, this.onAsk});
  final void Function(String? prompt, Map<String, dynamic> scope)? onAsk;
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  final _search = TextEditingController();
  Timer? _debounce;
  bool _list = false, _initialized = false;
  String _defaultView = '', _defaultSort = '';
  int? _lastObservedSearchRevision;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = context.watch<SettingsViewModel>().settings;
    if (!_initialized || _defaultView != s.defaultView) {
      _list = s.defaultView == 'list';
      _defaultView = s.defaultView;
    }
    if (!_initialized || _defaultSort != s.defaultSort) {
      _defaultSort = s.defaultSort;
      final vm = context.read<NoteViewModel>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          vm.updateSort(_defaultSort == 'Title A–Z'
              ? NoteSort.title
              : _defaultSort == 'Date created'
                  ? NoteSort.dateCreated
                  : NoteSort.lastEdited);
        }
      });
    }
    _initialized = true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _clear() {
    _search.clear();
    _debounce?.cancel();
    final vm = context.read<NoteViewModel>();
    vm.updateSearch('');
    vm.updateCategory('All');
    vm.updateLibraryFilter(LibraryFilter.all);
    vm.resetWorkspaceSelection();
    setState(() {});
  }

  void _ask() {
    final vm = context.read<NoteViewModel>(), q = _search.text.trim();
    _debounce?.cancel();
    vm.updateSearch(q);
    final Map<String, dynamic> scope;
    if (!vm.workspaceSelection.isAll) {
      scope = {
        'kind': 'notes',
        'ids': vm.filteredNotes.map((n) => n.noteId).toList()
      };
    } else if (vm.selectedCategory == 'All' &&
        vm.libraryFilter == LibraryFilter.all) {
      scope = {'kind': 'all'};
    } else if (q.isEmpty &&
        vm.selectedCategory == 'All' &&
        vm.libraryFilter == LibraryFilter.favorites) {
      scope = {'kind': 'fav'};
    } else if (q.isEmpty && vm.libraryFilter == LibraryFilter.all) {
      scope = {'kind': 'cat', 'cat': vm.selectedCategory};
    } else {
      scope = {
        'kind': 'notes',
        'ids': vm.filteredNotes.map((n) => n.noteId).toList()
      };
    }
    final prompt = q.isEmpty ? null : 'What do my notes say about $q?';
    if (widget.onAsk != null) {
      widget.onAsk!(prompt, scope);
    } else {
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AiPage(initialPrompt: prompt, initialScope: scope)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NoteViewModel>(),
        theme = Theme.of(context),
        ai = context.watch<SettingsViewModel>().settings.aiEnabled;
    if (_lastObservedSearchRevision != vm.searchRevision) {
      _lastObservedSearchRevision = vm.searchRevision;
      if (_search.text != vm.searchQuery) {
        _debounce?.cancel();
        _search.value = TextEditingValue(
          text: vm.searchQuery,
          selection: TextSelection.collapsed(offset: vm.searchQuery.length),
        );
      }
    }
    final results = vm.filteredNotes;
    return SafeArea(
        bottom: false,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
            children: [
              PageHeading(
                  title: 'Your ',
                  accent: 'notes',
                  metadata:
                      '${pluralize(vm.totalNotes, 'note')} total · ${pluralize(vm.totalFavorites, 'favorite')} total'),
              const SizedBox(height: 20),
              TextField(
                  controller: _search,
                  onChanged: (q) {
                    setState(() {});
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 220),
                        () => vm.updateSearch(q));
                  },
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                      hintText: 'Search titles and content',
                      prefixIcon: const Padding(
                          padding: EdgeInsets.all(14),
                          child: ReferenceIcon('search', size: 18)),
                      suffixIcon: _search.text.isNotEmpty
                          ? IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                _search.clear();
                                _debounce?.cancel();
                                vm.updateSearch('');
                                setState(() {});
                              },
                              icon: const ReferenceIcon('x', size: 16))
                          : ai
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: TextButton(
                                      onPressed: _ask,
                                      style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8),
                                          minimumSize: const Size(0, 44)),
                                      child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            ReferenceIcon('spark', size: 13),
                                            SizedBox(width: 4),
                                            Text('Ask AI',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w600))
                                          ])))
                              : null)),
              if (ai && _search.text.trim().isNotEmpty)
                TextButton(
                    onPressed: _ask,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft),
                    child: Row(children: [
                      const ReferenceIcon('spark', size: 16),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text('Ask AI about “${_search.text.trim()}”',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 14,
                                  color: theme.colorScheme.onSurface))),
                      Text(
                          results.isEmpty
                              ? 'Search all'
                              : pluralize(results.length, 'match', 'matches'),
                          style: theme.textTheme.bodySmall)
                    ])),
              const SizedBox(height: 12),
              WorkspaceFilterBar(
                key: const ValueKey('workspace-filter'),
                workspaces: vm.workspaces,
                selection: vm.workspaceSelection,
                selectionLabel: vm.workspaceSelectionLabel,
                status: vm.workspaceStatus,
                assignmentsKnown: vm.workspaceAssignmentsKnown,
                errorMessage: vm.workspaceErrorMessage,
                onSelected: vm.updateWorkspaceSelection,
                onReset: vm.resetWorkspaceSelection,
                onRetry: vm.retryWorkspaces,
              ),
              const SizedBox(height: 16),
              Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12)),
                  child: LayoutBuilder(builder: (context, constraints) {
                    final reducedMotion =
                        MediaQuery.disableAnimationsOf(context) ||
                            context
                                .watch<SettingsViewModel>()
                                .settings
                                .reduceMotion;
                    return Stack(children: [
                      AnimatedAlign(
                        duration: reducedMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment(
                            -1 + vm.libraryFilter.index.toDouble(), 0),
                        child: Container(
                          width: constraints.maxWidth / 3,
                          height: 44,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surface,
                            borderRadius: BorderRadius.circular(9),
                          ),
                        ),
                      ),
                      Row(children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(
                              child: Semantics(
                                  selected: vm.libraryFilter ==
                                      LibraryFilter.values[i],
                                  button: true,
                                  child: TextButton(
                                      onPressed: () => vm.updateLibraryFilter(
                                          LibraryFilter.values[i]),
                                      style: TextButton.styleFrom(
                                          foregroundColor: vm.libraryFilter ==
                                                  LibraryFilter.values[i]
                                              ? theme.colorScheme.onSurface
                                              : theme
                                                  .colorScheme.onSurfaceVariant,
                                          minimumSize: const Size(0, 44),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 4),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(9))),
                                      child:
                                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                        if (i > 0) ...[
                                          ReferenceIcon(
                                              i == 1 ? 'star' : 'live',
                                              size: 13,
                                              filled: i == 1 &&
                                                  vm.libraryFilter ==
                                                      LibraryFilter.favorites,
                                              color: i == 1 &&
                                                      vm.libraryFilter ==
                                                          LibraryFilter
                                                              .favorites
                                                  ? AppColors.star
                                                  : null),
                                          const SizedBox(width: 4)
                                        ],
                                        Flexible(
                                            child: Text(
                                                ['All', 'Favorites', 'Live'][i],
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight:
                                                        FontWeight.w500),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        const SizedBox(width: 4),
                                        Text(
                                            '${[
                                              vm.visibleAllCount,
                                              vm.visibleFavoriteCount,
                                              vm.visibleLiveCount
                                            ][i]}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant))
                                      ]))))
                      ])
                    ]);
                  })),
              const SizedBox(height: 16),
              CategoryChips(
                  categories: vm.categories,
                  selectedCategory: vm.selectedCategory,
                  onSelected: vm.updateCategory),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: Semantics(
                        liveRegion: true,
                        child: Text(pluralize(results.length, 'note'),
                            style: theme.textTheme.bodySmall))),
                TextButton(
                    onPressed: () => _sort(context),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                          switch (vm.sort) {
                            NoteSort.lastEdited => 'Last edited',
                            NoteSort.dateCreated => 'Date created',
                            NoteSort.title => 'Title A–Z'
                          },
                          style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(width: 5),
                      const ReferenceIcon('sort', size: 15)
                    ])),
                IconButton(
                    tooltip: _list ? 'Grid view' : 'List view',
                    isSelected: _list,
                    onPressed: () => setState(() => _list = !_list),
                    icon: ReferenceIcon(_list ? 'grid' : 'list', size: 18))
              ]),
              if (vm.errorMessage != null) ...[
                InlineError(vm.errorMessage!, onRetry: vm.retry),
                const SizedBox(height: 16)
              ],
              if (vm.pendingSharedNotes.isNotEmpty) ...[
                SectionHeader(
                    'Shared with you · ${vm.pendingSharedNotes.length}'),
                for (final note in vm.pendingSharedNotes)
                  _PendingCopy(note: note),
                const SizedBox(height: 16),
              ],
              if (vm.isLoading && vm.notes.isEmpty)
                const NoteSkeleton()
              else if (results.isEmpty)
                _empty(context, vm)
              else
                NotesMasonry(
                    notes: results,
                    onOpen: (n) => openNote(context, n),
                    onFavorite: vm.toggleFavorite,
                    list: _list),
            ]));
  }

  Widget _empty(BuildContext context, NoteViewModel vm) {
    if (vm.notes.isEmpty) {
      return EmptyState(
          title: 'A blank page',
          message: 'Capture your first idea — it only takes a second.',
          actionLabel: 'New note',
          onAction: () => createNote(context));
    }
    if (!vm.workspaceSelection.isAll && vm.workspaceScopedCount == 0) {
      return EmptyState(
        title: 'No notes in ${vm.workspaceSelectionLabel}',
        message: vm.workspaceSelection.isNamed
            ? 'Assign a note to this workspace, or show every workspace.'
            : 'Notes assigned to another workspace stay out of Default.',
        actionLabel: 'Show all workspaces',
        onAction: vm.resetWorkspaceSelection,
      );
    }
    if (_search.text.isNotEmpty || vm.selectedCategory != 'All') {
      return EmptyState(
          title: _search.text.isNotEmpty
              ? 'Nothing matches “${_search.text}”'
              : 'No notes here',
          message: 'Try another word, or clear the filters.',
          actionLabel: 'Clear filters',
          onAction: _clear);
    }
    if (vm.libraryFilter == LibraryFilter.favorites) {
      return EmptyState(
          title: vm.workspaceSelection.isAll
              ? 'No favorites yet'
              : 'No favorites in ${vm.workspaceSelectionLabel}',
          message: vm.workspaceSelection.isAll
              ? 'Tap the star on any note to keep it here, one tap away.'
              : 'Try another workspace, or reset the workspace filter.',
          actionLabel:
              vm.workspaceSelection.isAll ? null : 'Show all workspaces',
          onAction:
              vm.workspaceSelection.isAll ? null : vm.resetWorkspaceSelection);
    }
    return EmptyState(
        title: vm.workspaceSelection.isAll
            ? 'No live notes'
            : 'No live notes in ${vm.workspaceSelectionLabel}',
        message: vm.workspaceSelection.isAll
            ? 'Open a note, tap Share, then choose Edit together to work on it with others.'
            : 'Try another workspace, or reset the workspace filter.',
        actionLabel: vm.workspaceSelection.isAll ? null : 'Show all workspaces',
        onAction:
            vm.workspaceSelection.isAll ? null : vm.resetWorkspaceSelection);
  }

  void _sort(BuildContext context) => notedSheet<void>(context,
      label: 'Sort notes',
      builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sort notes',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 12),
                RadioGroup<NoteSort>(
                  groupValue: context.read<NoteViewModel>().sort,
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    context.read<NoteViewModel>().updateSort(value);
                    Navigator.pop(context);
                  },
                  child: Column(children: [
                    for (final sort in NoteSort.values)
                      RadioListTile<NoteSort>(
                          value: sort,
                          title: Text(switch (sort) {
                            NoteSort.lastEdited => 'Last edited',
                            NoteSort.dateCreated => 'Date created',
                            NoteSort.title => 'Title A–Z'
                          })),
                  ]),
                ),
              ])));
}

class _PendingCopy extends StatelessWidget {
  const _PendingCopy({required this.note});
  final NoteModel note;

  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfacePanel(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(note.title.isEmpty ? 'Untitled' : note.title,
                style: Theme.of(context).textTheme.titleMedium),
            Text(
                'From ${note.ownerName.isEmpty ? note.ownerEmail : note.ownerName}',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                    onPressed: () => openNote(context, note),
                    child: const Text('Preview'))),
            const SizedBox(height: 8),
            PendingShareActions(noteId: note.noteId),
          ])));
}
