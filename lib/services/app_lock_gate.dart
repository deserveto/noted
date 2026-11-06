import 'package:flutter/material.dart';
import '../widgets/reference_icon.dart';
import 'package:provider/provider.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'account_services.dart';

/// Lives above Navigator, preserving all routes and drafts behind an opaque gate.
class AppLockGate extends StatefulWidget {
  const AppLockGate(
      {super.key,
      required this.child,
      this.authenticate,
      this.onObscuredChanged});
  final Widget child;
  final Future<bool> Function()? authenticate;
  final ValueChanged<bool>? onObscuredChanged;
  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _locked = true, _authenticating = false, _wasEnabled = false;
  String? _error;
  bool? _reportedObscured;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_wasEnabled || _authenticating) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      setState(() => _locked = true);
    }
    if (state == AppLifecycleState.resumed && _locked) {
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });
    try {
      final unlocked = await (widget.authenticate?.call() ??
          AppLockService().authenticate());
      if (mounted) setState(() => _locked = !unlocked);
    } catch (error) {
      if (mounted) setState(() => _error = 'Couldn’t unlock Noted. Try again.');
    }
    if (mounted) setState(() => _authenticating = false);
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<SettingsViewModel>();
    final signedIn = context.watch<AuthViewModel>().isAuthenticated;
    final loading = signedIn && preferences.isLoading;
    final enabled = signedIn && preferences.settings.appLock;
    if (enabled && !_wasEnabled) {
      _locked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _unlock();
      });
    }
    _wasEnabled = enabled;
    final obscured = loading || (enabled && _locked);
    if (_reportedObscured != obscured) {
      _reportedObscured = obscured;
      widget.onObscuredChanged?.call(obscured);
    }
    return Stack(fit: StackFit.expand, children: [
      Offstage(
          offstage: obscured,
          child: TickerMode(enabled: !obscured, child: widget.child)),
      if (obscured)
        Scaffold(
            body: loading
                ? const Center(
                    child: CircularProgressIndicator(
                        semanticsLabel: 'Checking app lock'))
                : SafeArea(
                    child: Center(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Image.asset('docs/Logo.png', height: 64),
                                  const SizedBox(height: 24),
                                  const ReferenceIcon('lock', size: 36),
                                  const SizedBox(height: 16),
                                  const Text('Your notes are locked',
                                      style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Use your fingerprint, face or device PIN to continue.',
                                      textAlign: TextAlign.center),
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(_error!,
                                            textAlign: TextAlign.center)),
                                  const SizedBox(height: 24),
                                  FilledButton(
                                      onPressed:
                                          _authenticating ? null : _unlock,
                                      child: Text(_authenticating
                                          ? 'Unlocking…'
                                          : 'Unlock Noted')),
                                ]))))),
    ]);
  }
}
