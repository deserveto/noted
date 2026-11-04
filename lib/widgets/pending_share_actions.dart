import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import 'noted_ui.dart';

/// The same decisions are available on the invitation and its read-only preview.
class PendingShareActions extends StatefulWidget {
  const PendingShareActions({required this.noteId, this.onResolved, super.key});
  final String noteId;
  final VoidCallback? onResolved;

  @override
  State<PendingShareActions> createState() => _PendingShareActionsState();
}

class _PendingShareActionsState extends State<PendingShareActions> {
  bool _busy = false;
  String? _error;

  Future<void> _act(bool accept) async {
    if (_busy) return;
    final vm = context.read<NoteViewModel>();
    final user = context.read<AuthViewModel>().user;
    if (user == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    if (accept) {
      await vm.acceptShare(widget.noteId,
          ownerName: user.name, ownerEmail: user.email);
    } else {
      await vm.declineShare(widget.noteId);
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = vm.errorMessage;
    });
    if (context.read<AuthViewModel>().user?.uid != user.uid) return;
    if (_error == null) {
      notedToast(
          context, accept ? 'Copy added to your notes' : 'Copy declined');
      widget.onResolved?.call();
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Semantics(
                  liveRegion: true,
                  child: Text(
                      'Couldn’t update this invitation. Please try again.',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)))),
        Row(children: [
          Expanded(
              child: OutlinedButton(
                  onPressed: _busy ? null : () => _act(false),
                  child: const Text('Decline'))),
          const SizedBox(width: 8),
          Expanded(
              child: FilledButton(
                  onPressed: _busy ? null : () => _act(true),
                  child: Text(_busy ? 'Please wait…' : 'Accept copy'))),
        ]),
      ]);
}
