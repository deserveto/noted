import 'package:flutter/material.dart';
import '../viewmodels/update_viewmodel.dart';
import '../widgets/update_dialog.dart';
import 'app_lock_gate.dart';

/// Only the shell is safe for unsolicited prompts. Editors, sheets, recovery,
/// settings and external note-link routes all defer them automatically.
class UpdateNavigationObserver extends NavigatorObserver {
  final List<Route<dynamic>> _routes = [];
  VoidCallback? onChanged;
  bool get safe {
    if (_routes.isEmpty) return false;
    final route = _routes.last;
    return route is PageRoute &&
        const ['/', '/main'].contains(route.settings.name) &&
        (route.animation == null || route.animation!.isCompleted);
  }

  void _changed() => onChanged?.call();
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    if (route is TransitionRoute) {
      route.animation?.addStatusListener((_) => _changed());
    }
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (index >= 0) {
      if (newRoute == null) {
        _routes.removeAt(index);
      } else {
        _routes[index] = newRoute;
      }
    }
    if (newRoute is TransitionRoute) {
      newRoute.animation?.addStatusListener((_) => _changed());
    }
    _changed();
  }
}

class UpdateCoordinator extends StatefulWidget {
  const UpdateCoordinator(
      {super.key,
      required this.child,
      required this.vm,
      required this.uid,
      required this.recovering,
      required this.navigation,
      required this.navigatorKey,
      this.authenticate});
  final Widget child;
  final UpdateViewModel? vm;
  final String? uid;
  final bool recovering;
  final UpdateNavigationObserver navigation;
  final GlobalKey<NavigatorState> navigatorKey;
  final Future<bool> Function()? authenticate;
  @override
  State<UpdateCoordinator> createState() => _UpdateCoordinatorState();
}

class _UpdateCoordinatorState extends State<UpdateCoordinator>
    with WidgetsBindingObserver {
  bool _obscured = true, _promptOpen = false, _scheduled = false;
  bool _foreground = true;
  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.navigation.onChanged = _schedule;
    widget.vm?.addListener(_schedule);
    _schedule();
  }

  @override
  void didUpdateWidget(UpdateCoordinator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.vm != oldWidget.vm) {
      oldWidget.vm?.removeListener(_schedule);
      widget.vm?.addListener(_schedule);
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _schedule();
  }

  bool get _safe =>
      _foreground &&
      !_obscured &&
      !widget.recovering &&
      widget.uid != null &&
      widget.navigation.safe;

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) _tick();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _tick() async {
    final vm = widget.vm;
    if (vm == null) return;
    vm.bindUser(widget.uid);
    if (!_safe || _promptOpen || vm.checking || !vm.enabled) return;
    // Cooldown and in-flight coalescing live in the viewmodel.
    await vm.check();
    if (!mounted || !_safe || _promptOpen || vm.checking) return;
    final release = vm.whatsNew ?? (vm.shouldPrompt ? vm.available : null);
    final navigatorContext = widget.navigatorKey.currentContext;
    if (release == null ||
        navigatorContext == null ||
        !navigatorContext.mounted) {
      return;
    }
    _promptOpen = true;
    final whatsNew = vm.whatsNew != null;
    try {
      await showUpdateDialog(navigatorContext, vm, release, whatsNew: whatsNew);
    } finally {
      _promptOpen = false;
      _schedule();
    }
  }

  @override
  void dispose() {
    widget.navigation.onChanged = null;
    widget.vm?.removeListener(_schedule);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLockGate(
      authenticate: widget.authenticate,
      onObscuredChanged: (value) {
        _obscured = value;
        _schedule();
      },
      child: widget.child);
}
