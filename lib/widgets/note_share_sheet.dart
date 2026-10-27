import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/note_links.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../repositories/note_repository.dart';
import '../services/collaboration_service.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'reference_icon.dart';
import 'noted_ui.dart' show NotedAvatar;

class NoteShareSheet extends StatefulWidget {
  const NoteShareSheet({required this.note, super.key});
  final NoteModel note;
  @override
  State<NoteShareSheet> createState() => _NoteShareSheetState();
}

class _NoteShareSheetState extends State<NoteShareSheet> {
  late bool _live;
  late Map<String, String> _roles;
  final _copies = <String>{};
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _live = widget.note.isLive;
    _roles = {...widget.note.liveRoles};
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_live) {
        final service = CollaborationService();
        for (final id in {...widget.note.liveRoles.keys, ..._roles.keys}) {
          if (widget.note.liveRoles[id] != _roles[id]) {
            await service.setLiveRole(
                noteId: widget.note.noteId, targetUserId: id, role: _roles[id]);
          }
        }
      } else {
        final repo = NoteRepository();
        for (final id in _copies) {
          await repo.shareNote(
              note: widget.note,
              targetUserId: id,
              ownerName: widget.note.ownerName,
              ownerEmail: widget.note.ownerEmail);
        }
      }
      if (mounted) {
        Navigator.pop(context, _live ? 'Live members saved' : 'Copy sent');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final connections = context.watch<ConnectionViewModel>();
    final uid = connections.user?.uid ?? '';
    final accepted = connections.acceptedConnections;
    return SafeArea(
        child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                      'Share “${widget.note.title.isEmpty ? 'Untitled' : widget.note.title}”',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 16),
                  SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(
                                value: false,
                                label: Text('Send a copy'),
                                icon: ReferenceIcon('copy', size: 16)),
                            ButtonSegment(
                                value: true,
                                label: Text('Edit together'),
                                icon: ReferenceIcon('live', size: 16))
                          ],
                          selected: {
                            _live
                          },
                          onSelectionChanged: _busy
                              ? null
                              : (v) => setState(() => _live = v.single))),
                  const SizedBox(height: 12),
                  Text(
                      _live
                          ? 'Invite people into this exact note. Edits sync in real time. Conflicting edits are kept for review.'
                          : 'Each person receives their own independent copy. Their edits won’t change yours.',
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                  const SizedBox(height: 12),
                  if (accepted.isEmpty)
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                            'Add and accept a connection before sharing notes.')),
                  for (final c in accepted)
                    Builder(builder: (_) {
                      final id = c.otherUserId(uid);
                      final selected =
                          _live ? _roles.containsKey(id) : _copies.contains(id);
                      final name = c.otherName(uid);
                      return Row(children: [
                        Expanded(
                            child: CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: selected,
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() {
                                          if (_live) {
                                            if (v == true) {
                                              _roles[id] = context
                                                  .read<SettingsViewModel>()
                                                  .settings
                                                  .livePerm;
                                            } else {
                                              _roles.remove(id);
                                            }
                                          } else {
                                            if (v == true) {
                                              _copies.add(id);
                                            } else {
                                              _copies.remove(id);
                                            }
                                          }
                                        }),
                                title: Row(children: [
                                  NotedAvatar(name: name, uid: id, size: 32),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(name))
                                ]),
                                subtitle: Text(c.otherEmail(uid)))),
                        if (_live && selected)
                          TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _roles[id] =
                                      _roles[id] == 'edit' ? 'view' : 'edit'),
                              child: Text(_roles[id] == 'edit'
                                  ? 'Can edit'
                                  : 'Can view')),
                      ]);
                    }),
                  if (_live)
                    for (final id in _roles.keys
                        .where((id) =>
                            !accepted.any((c) => c.otherUserId(uid) == id))
                        .toList())
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Former connection'),
                          subtitle: Text(id),
                          trailing: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _roles.remove(id)),
                              child: const Text('Remove'))),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  if (_live)
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(
                                  text: noteInviteLink(widget.note.noteId)));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Link copied')));
                              }
                            },
                      icon: const ReferenceIcon('link', size: 18),
                      label: const Row(children: [
                        Expanded(child: Text('Copy invite link')),
                        Text('Members only', style: TextStyle(fontSize: 12))
                      ]),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: _busy || (!_live && _copies.isEmpty)
                              ? null
                              : _save,
                          child: Text(_busy
                              ? 'Sharing…'
                              : _live
                                  ? 'Save members'
                                  : _copies.isEmpty
                                      ? 'Choose people'
                                      : 'Send copy to ${_copies.length}'))),
                  if (_live && widget.note.isLive)
                    Center(
                        child: TextButton(
                            onPressed: _busy
                                ? null
                                : () {
                                    setState(_roles.clear);
                                    _save();
                                  },
                            child: Text('Stop live sharing',
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)))),
                ])));
  }
}
