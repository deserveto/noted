import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/connection_model.dart';
import '../repositories/connection_repository.dart';
import '../utils/app_colors.dart';
import '../utils/note_navigation.dart';
import '../utils/validators.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../widgets/note_card.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';
import '../widgets/empty_state.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});
  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final _email = TextEditingController();
  bool _sending = false;
  String? _error;
  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final email = _email.text.trim(), error = Validators.email(email);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final vm = context.read<ConnectionViewModel>();
      final ok = await vm.invite(email);
      if (!ok) throw StateError(vm.errorMessage ?? 'Couldn’t send invitation.');
      if (mounted) {
        _email.clear();
        notedToast(context, 'Invitation sent');
      }
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
    if (mounted) setState(() => _sending = false);
  }

  Future<void> _action(Future<bool> Function() action, String success) async {
    final vm = context.read<ConnectionViewModel>();
    final ok = await action();
    if (mounted) {
      notedToast(context,
          ok ? success : vm.errorMessage ?? 'Couldn’t complete that action.');
    }
  }

  Future<void> _remove(ConnectionModel c) async {
    final vm = context.read<ConnectionViewModel>();
    final name = c.otherName(vm.user?.uid ?? '');
    final yes = await notedSheet<bool>(context,
        label: 'Remove connection',
        builder: (context) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Remove $name?',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text(
                      'You can reconnect later by sending a new invitation.'),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'))),
                    const SizedBox(width: 12),
                    Expanded(
                        child: FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: FilledButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.error),
                            child: const Text('Remove')))
                  ])
                ])));
    if (yes == true && mounted) {
      await _action(() => vm.removeConnection(c), '$name has been removed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ConnectionViewModel>(),
        notes = context.watch<NoteViewModel>().liveNotes,
        theme = Theme.of(context),
        uid = vm.user?.uid ?? '';
    return SafeArea(
        bottom: false,
        child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 100),
            children: [
              PageHeading(
                  title: 'Connections',
                  metadata: '${vm.acceptedConnections.length} connections'),
              const SizedBox(height: 20),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                    child: TextField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.send,
                        onChanged: (_) => setState(() => _error = null),
                        onSubmitted: (_) {
                          if (!_sending) _invite();
                        },
                        decoration: const InputDecoration(
                            hintText: 'Invite by email',
                            prefixIcon: Padding(
                                padding: EdgeInsets.all(14),
                                child: ReferenceIcon('mail', size: 18))))),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _sending || _email.text.isEmpty ? null : _invite,
                    style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 18)),
                    child: Text(_sending ? 'Sending…' : 'Invite'))
              ]),
              if (_error != null) ...[
                const SizedBox(height: 8),
                InlineError(_error!)
              ],
              if (vm.errorMessage != null) ...[
                const SizedBox(height: 12),
                InlineError(vm.errorMessage!)
              ],
              if (notes.isNotEmpty) ...[
                const SectionHeader('Live notes'),
                for (final n in notes)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                          color: AppColors.noteColor(theme.brightness, n.color),
                          borderRadius: BorderRadius.circular(16),
                          child: ListTile(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                              title: Text(
                                  n.title.isEmpty ? 'Untitled' : n.title,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${n.liveMemberIds.toSet().union({
                                        n.userId
                                      }).length} people · edited ${relativeTime(n.updatedAt).toLowerCase()}',
                                  style: theme.textTheme.bodySmall),
                              trailing: LiveAvatarStack(
                                  note: n,
                                  size: 26,
                                  background: AppColors.noteColor(
                                      theme.brightness, n.color)),
                              onTap: () => openNote(context, n))))
              ],
              if (vm.incomingRequests.isNotEmpty) ...[
                SectionHeader('Requests · ${vm.incomingRequests.length}'),
                for (final c in vm.incomingRequests)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfacePanel(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            NotedAvatar(
                                name: c.otherName(uid),
                                uid: c.otherUserId(uid),
                                size: 40),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(c.otherName(uid),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500)),
                                  Text(c.otherEmail(uid),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall)
                                ])),
                            IconButton(
                                tooltip: 'Decline ${c.otherName(uid)}',
                                onPressed: vm.isLoading
                                    ? null
                                    : () => _action(() => vm.reject(c),
                                        'Declined ${c.otherName(uid)}'),
                                icon: const ReferenceIcon('x', size: 16)),
                            FilledButton(
                                onPressed: vm.isLoading
                                    ? null
                                    : () => _action(() => vm.accept(c),
                                        'You and ${c.otherName(uid)} are now connected'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor:
                                        theme.colorScheme.onPrimary,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    minimumSize: const Size(0, 44),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12))),
                                child: const Text('Accept',
                                    style: TextStyle(fontSize: 13)))
                          ])))
              ],
              const SectionHeader('Your connections'),
              if (vm.isLoading && vm.connections.isEmpty)
                const NoteSkeleton()
              else if (vm.acceptedConnections.isEmpty)
                const EmptyState(
                    title: 'Better together',
                    message:
                        'Invite someone by email to share ideas and write together.')
              else
                SurfacePanel(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      for (var i = 0;
                          i < vm.acceptedConnections.length;
                          i++) ...[
                        if (i > 0) const Divider(indent: 16, endIndent: 16),
                        Builder(builder: (context) {
                          final c = vm.acceptedConnections[i];
                          return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              leading: NotedAvatar(
                                  name: c.otherName(uid),
                                  uid: c.otherUserId(uid),
                                  size: 40),
                              title: Text(c.otherName(uid),
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500)),
                              subtitle: Text(c.otherEmail(uid),
                                  style: theme.textTheme.bodySmall),
                              trailing: IconButton(
                                  tooltip: 'Remove connection',
                                  onPressed: () => _remove(c),
                                  icon: const ReferenceIcon('more', size: 18)));
                        }),
                      ]
                    ])),
              if (vm.outgoingRequests.isNotEmpty) ...[
                const SectionHeader('Sent requests'),
                for (final c in vm.outgoingRequests)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: SurfacePanel(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            const ReferenceIcon('mail', size: 18),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(c.otherEmail(uid),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 14))),
                            TextButton(
                                onPressed: vm.isLoading
                                    ? null
                                    : () => _action(
                                        () => vm.resend(c), 'Invitation sent'),
                                child: const Text('Resend',
                                    style: TextStyle(fontSize: 12))),
                            IconButton(
                                tooltip: 'Cancel request',
                                onPressed: () => _action(
                                    () => vm.removeConnection(c),
                                    'Invitation cancelled'),
                                icon: const ReferenceIcon('x', size: 15))
                          ])))
              ],
              if (uid.isNotEmpty) _EmailInvitations(uid: uid),
            ]));
  }
}

class _EmailInvitations extends StatefulWidget {
  const _EmailInvitations({required this.uid});
  final String uid;
  @override
  State<_EmailInvitations> createState() => _EmailInvitationsState();
}

class _EmailInvitationsState extends State<_EmailInvitations> {
  late Stream<List<Map<String, dynamic>>> _stream;
  @override
  void initState() {
    super.initState();
    _stream = InvitationService().watchInvitations(widget.uid);
  }

  @override
  void didUpdateWidget(covariant _EmailInvitations oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _stream = InvitationService().watchInvitations(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<
          List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Padding(
              padding: EdgeInsets.only(top: 16),
              child: InlineError('Couldn’t load sent invitations.'));
        }
        final docs = snapshot.data ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SectionHeader('Sent invitations'),
          for (final d in docs)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SurfacePanel(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      const ReferenceIcon('mail', size: 18),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(d['email'] as String? ?? '',
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis)),
                      TextButton(
                          onPressed: () async {
                            try {
                              await ConnectionRepository()
                                  .inviteByEmail(d['email'] as String);
                              if (context.mounted) {
                                notedToast(context, 'Invitation sent');
                              }
                            } catch (error) {
                              if (context.mounted) {
                                notedToast(context, 'Couldn’t resend. $error');
                              }
                            }
                          },
                          child: const Text('Resend',
                              style: TextStyle(fontSize: 12))),
                      IconButton(
                          tooltip: 'Cancel invitation',
                          onPressed: () async {
                            try {
                              await InvitationService().cancelInvitation(
                                  widget.uid, d['email_hash'] as String? ?? '');
                              if (context.mounted) {
                                notedToast(context, 'Invitation cancelled');
                              }
                            } catch (error) {
                              if (context.mounted) {
                                notedToast(context, 'Couldn’t cancel. $error');
                              }
                            }
                          },
                          icon: const ReferenceIcon('x', size: 15))
                    ])))
        ]);
      });
}
