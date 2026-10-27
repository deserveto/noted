import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../repositories/activity_repository.dart';
import '../repositories/note_repository.dart';
import '../utils/app_colors.dart';
import '../utils/note_navigation.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../views/connections_page.dart';
import 'empty_state.dart';
import 'noted_ui.dart';
import 'reference_icon.dart';

class ActivityBell extends StatefulWidget {
  const ActivityBell({super.key, this.onConnections});
  final VoidCallback? onConnections;
  @override
  State<ActivityBell> createState() => _ActivityBellState();
}

class _ActivityBellState extends State<ActivityBell> {
  String? _uid;
  Stream<bool>? _stream;

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthViewModel>().user?.uid;
    if (uid == null) return const SizedBox.shrink();
    if (_uid != uid || _stream == null) {
      _uid = uid;
      _stream = ActivityRepository().watchHasUnread(uid);
    }
    return StreamBuilder<bool>(
        stream: _stream,
        builder: (context, snapshot) {
          final unread = snapshot.data ?? false;
          return IconButton(
              tooltip: unread ? 'Notifications, new activity' : 'Notifications',
              onPressed: () => notedSheet<void>(context,
                  label: 'Activity',
                  tall: true,
                  builder: (_) => ActivitySheet(
                      uid: uid, onConnections: widget.onConnections)),
              icon: Stack(clipBehavior: Clip.none, children: [
                const ReferenceIcon('bell'),
                if (unread)
                  Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.error,
                              border: Border.all(
                                  color:
                                      Theme.of(context).scaffoldBackgroundColor,
                                  width: 2))))
              ]));
        });
  }
}

class ActivitySheet extends StatefulWidget {
  const ActivitySheet({super.key, required this.uid, this.onConnections});
  final VoidCallback? onConnections;
  final String uid;
  @override
  State<ActivitySheet> createState() => _ActivitySheetState();
}

class _ActivitySheetState extends State<ActivitySheet> {
  late Stream<List<Map<String, dynamic>>> _stream;
  final _marked = <String>{};
  @override
  void initState() {
    super.initState();
    _stream = ActivityRepository().watchNotifications(widget.uid);
  }

  Future<void> _open(Map<String, dynamic> data) async {
    final id = data['noteId'] as String?;
    if (id != null && id.isNotEmpty) {
      try {
        final note = await NoteRepository().getNoteById(id);
        if (!mounted) return;
        if (note != null) {
          Navigator.pop(context);
          openNote(context, note);
        } else {
          notedToast(context, 'This note is no longer available.');
        }
      } catch (error) {
        if (mounted) notedToast(context, 'Couldn’t open this note. $error');
      }
    } else {
      Navigator.pop(context);
      if (widget.onConnections != null) {
        widget.onConnections!();
      } else {
        Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Connections')),
                body: const ConnectionsPage())));
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 16, 16),
            child: Row(children: [
              Expanded(
                  child: Text('Activity',
                      style: Theme.of(context).textTheme.titleLarge)),
              IconButton(
                  tooltip: 'Close Activity',
                  onPressed: () => Navigator.pop(context),
                  icon: const ReferenceIcon('x'))
            ])),
        Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
                stream: _stream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                        padding: const EdgeInsets.all(24),
                        child: InlineError('Couldn’t load activity.',
                            onRetry: () => setState(() {
                                  _stream = ActivityRepository()
                                      .watchNotifications(widget.uid);
                                })));
                  }
                  if (!snapshot.hasData) {
                    return const Padding(
                        padding: EdgeInsets.all(24), child: NoteSkeleton());
                  }
                  final docs = snapshot.data!;
                  final unreadIds = docs
                      .where((d) =>
                          d['read'] != true &&
                          (d['id'] as String? ?? '').isNotEmpty &&
                          !_marked.contains(d['id']))
                      .map((d) => d['id'] as String)
                      .toList();
                  if (unreadIds.isNotEmpty) {
                    _marked.addAll(unreadIds);
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      try {
                        await ActivityRepository()
                            .markAsRead(widget.uid, unreadIds);
                      } catch (_) {
                        _marked.removeAll(unreadIds);
                      }
                    });
                  }
                  if (docs.isEmpty) {
                    return const Padding(
                        padding: EdgeInsets.all(24),
                        child: EmptyState(
                            title: 'All caught up',
                            message:
                                'Connection requests and shared-note activity will appear here.'));
                  }
                  return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final data = docs[i],
                            title =
                                data['title'] as String? ?? 'Noted activity',
                            body = data['body'] as String? ?? '',
                            rawDate = data['createdAt'],
                            date = rawDate is DateTime
                                ? rawDate
                                : DateTime.tryParse('${rawDate ?? ''}');
                        return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 4),
                            leading: NotedAvatar(
                                name: data['actorName'] as String? ?? title,
                                uid: data['actorId'] as String? ??
                                    (data['id'] as String? ?? '$i')),
                            title: Text(title,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600)),
                            subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (body.isNotEmpty)
                                    Text(body,
                                        style: const TextStyle(fontSize: 13)),
                                  if (date != null)
                                    Text(relativeTime(date),
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)
                                ]),
                            trailing: const ReferenceIcon('next', size: 16),
                            onTap: () => _open(data));
                      });
                }))
      ]);
}
