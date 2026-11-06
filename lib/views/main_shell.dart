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

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  int _index = 0, _aiGeneration = 0;
  late final AnimationController _transition = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 200), value: 1);
  String? _aiPrompt;
  Map<String, dynamic>? _aiScope;

  void _navigate(int index) {
    if (index == _index) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (MediaQuery.disableAnimationsOf(context) ||
        context.read<SettingsViewModel>().settings.reduceMotion) {
      _transition.value = 1;
    } else {
      _transition.forward(from: 0);
    }
    setState(() => _index = index);
  }

  @override
  void dispose() {
    _transition.dispose();
    super.dispose();
  }

  void _library(String filter) {
    final vm = context.read<NoteViewModel>();
    vm.updateSearch('');
    vm.updateCategory('All');
    vm.updateLibraryFilter(filter == 'Favorites'
        ? LibraryFilter.favorites
        : filter == 'Live'
            ? LibraryFilter.live
            : LibraryFilter.all);
    _navigate(1);
  }

  void _ask(String? prompt, Map<String, dynamic> scope) {
    setState(() {
      _aiPrompt = prompt;
      _aiScope = scope;
      _aiGeneration++;
    });
    _navigate(2);
  }

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
              body: FadeTransition(
                  opacity: _transition.drive(Tween(begin: .94, end: 1.0)),
                  child: IndexedStack(
                      index: visibleIndex < 0 ? 0 : _index,
                      children: [
                        HomePage(
                            onConnections: () => _navigate(3),
                            onNavigate: _library,
                            onProfile: () => _navigate(4)),
                        NotesPage(onAsk: _ask),
                        AiPage(
                            key: ValueKey(_aiGeneration),
                            embedded: true,
                            initialScope: _aiScope,
                            initialPrompt: _aiPrompt),
                        ConnectionsPage(active: _index == 3),
                        ProfilePage(onConnections: () => _navigate(3))
                      ])),
              floatingActionButton: _index == 0 || _index == 1
                  ? FloatingActionButton(
                      tooltip: 'New note',
                      onPressed: () => createNote(context),
                      child: const ReferenceIcon('plus', size: 24))
                  : null,
              bottomNavigationBar: DecoratedBox(
                  decoration: BoxDecoration(
                      border:
                          Border(top: BorderSide(color: theme.dividerColor))),
                  child: NavigationBar(
                      indicatorColor: Colors.transparent,
                      selectedIndex: visibleIndex < 0 ? 0 : visibleIndex,
                      onDestinationSelected: (i) =>
                          _navigate(destinations[i].index),
                      backgroundColor: theme.scaffoldBackgroundColor,
                      height: 72 +
                          (MediaQuery.textScalerOf(context).scale(11) - 11)
                              .clamp(0, 22)
                              .toDouble(),
                      labelBehavior:
                          MediaQuery.textScalerOf(context).scale(11) > 15
                              ? NavigationDestinationLabelBehavior
                                  .onlyShowSelected
                              : NavigationDestinationLabelBehavior.alwaysShow,
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
                                      borderRadius: BorderRadius.circular(100)),
                                  child: ReferenceIcon(d.icon,
                                      color: theme.brightness == Brightness.dark
                                          ? theme.colorScheme.onSurface
                                          : theme.colorScheme.primary)),
                              tooltip: d.label,
                              label: d.label == 'Connections' &&
                                      MediaQuery.textScalerOf(context)
                                              .scale(11) >
                                          15
                                  ? 'People'
                                  : d.label)
                      ])),
            )));
  }
}
