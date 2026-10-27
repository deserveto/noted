import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/note_navigation.dart';
import '../utils/app_colors.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../widgets/reference_icon.dart';
import 'ai_page.dart';
import 'connections_page.dart';
import 'home_page.dart';
import 'notes_page.dart';
import 'profile_page.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0, _aiGeneration = 0;
  String? _aiPrompt;
  Map<String, dynamic>? _aiScope;
  void _library(String filter) {
    final vm = context.read<NoteViewModel>();
    vm.updateSearch('');
    vm.updateCategory('All');
    vm.updateLibraryFilter(filter == 'Favorites'
        ? LibraryFilter.favorites
        : filter == 'Live'
            ? LibraryFilter.live
            : LibraryFilter.all);
    setState(() => _index = 1);
  }

  void _ask(String? prompt, Map<String, dynamic> scope) => setState(() {
        _aiPrompt = prompt;
        _aiScope = scope;
        _aiGeneration++;
        _index = 2;
      });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        ai = context.watch<SettingsViewModel>().settings.aiEnabled;
    final destinations = <({int index, String label, String icon})>[
      (index: 0, label: 'Home', icon: 'home'),
      (index: 1, label: 'Notes', icon: 'notes'),
      if (ai) (index: 2, label: 'AI', icon: 'spark'),
      (index: 3, label: 'Connections', icon: 'people'),
      (index: 4, label: 'Profile', icon: 'user')
    ];
    final visibleIndex = destinations.indexWhere((d) => d.index == _index);
    if (visibleIndex < 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = 0);
      });
    }
    return Center(
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Scaffold(
              body:
                  IndexedStack(index: visibleIndex < 0 ? 0 : _index, children: [
                HomePage(
                    onConnections: () => setState(() => _index = 3),
                    onNavigate: _library,
                    onProfile: () => setState(() => _index = 4)),
                NotesPage(onAsk: _ask),
                AiPage(
                    key: ValueKey(_aiGeneration),
                    initialScope: _aiScope,
                    initialPrompt: _aiPrompt),
                const ConnectionsPage(),
                ProfilePage(
                    onNavigate: _library,
                    onConnections: () => setState(() => _index = 3))
              ]),
              floatingActionButton: _index == 0 || _index == 1
                  ? FloatingActionButton(
                      tooltip: 'New note',
                      onPressed: () => createNote(context),
                      child: const ReferenceIcon('plus', size: 24))
                  : null,
              bottomNavigationBar: ClipRect(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              border: Border(
                                  top: BorderSide(color: theme.dividerColor))),
                          child: NavigationBar(
                              indicatorColor: Colors.transparent,
                              selectedIndex:
                                  visibleIndex < 0 ? 0 : visibleIndex,
                              onDestinationSelected: (i) => setState(
                                  () => _index = destinations[i].index),
                              backgroundColor: theme.scaffoldBackgroundColor
                                  .withValues(alpha: .95),
                              destinations: [
                                for (final d in destinations)
                                  NavigationDestination(
                                      icon: ReferenceIcon(d.icon),
                                      selectedIcon: Container(
                                          width: 48,
                                          height: 28,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                              color: AppColors.noteColorFor(
                                                  theme.brightness, 2),
                                              borderRadius:
                                                  BorderRadius.circular(100)),
                                          child: ReferenceIcon(d.icon,
                                              color: theme.brightness ==
                                                      Brightness.dark
                                                  ? theme.colorScheme.onSurface
                                                  : theme.colorScheme.primary)),
                                      label: d.label)
                              ])))),
            )));
  }
}
