import 'package:flutter/material.dart';
import '../models/app_release.dart';
import '../viewmodels/update_viewmodel.dart';
import '../widgets/update_dialog.dart';

class UpdatesPage extends StatefulWidget {
  const UpdatesPage({super.key, required this.vm, this.history = false});
  final UpdateViewModel vm;
  final bool history;
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends State<UpdatesPage> {
  bool _loading = true;
  String? _error;
  List<AppRelease> _releases = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (widget.history) {
        if (!widget.vm.enabled) throw StateError('Unavailable');
        _releases = await widget.vm.history();
      } else {
        await widget.vm.check(manual: true);
      }
    } catch (_) {
      _error =
          'Release history is unavailable. Check your connection and sign-in status, then try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
            title: Text(widget.history ? 'Release history' : 'Beta updates')),
        body: AnimatedBuilder(
            animation: widget.vm,
            builder: (context, _) {
              final vm = widget.vm, app = vm.installed;
              return Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            Text(
                                app == null
                                    ? 'Current version unavailable'
                                    : 'Installed ${app.version} · build ${app.build}',
                                style: Theme.of(context).textTheme.titleMedium),
                            Text(
                                'Channel: ${vm.channel.isEmpty ? 'not configured' : vm.channel}'),
                            const SizedBox(height: 24),
                            if (_loading)
                              const Center(child: CircularProgressIndicator())
                            else ...[
                              Text(_error ??
                                  (widget.history
                                      ? (_releases.isEmpty
                                          ? 'No published releases are available.'
                                          : 'Published beta releases')
                                      : vm.message ??
                                          'Updates unavailable. Try again.')),
                              const SizedBox(height: 16),
                              if (!widget.history && vm.available != null) ...[
                                ReleaseNotes(release: vm.available!),
                                FilledButton(
                                    onPressed: () => showUpdateDialog(
                                        context, vm, vm.available!),
                                    child: const Text('Update now')),
                              ],
                              for (final release in _releases) ...[
                                const Divider(height: 32),
                                ReleaseNotes(release: release),
                              ],
                              const SizedBox(height: 16),
                              OutlinedButton(
                                  onPressed: _load,
                                  child: Text(widget.history
                                      ? 'Refresh'
                                      : 'Check again')),
                            ],
                          ])));
            }),
      );
}
