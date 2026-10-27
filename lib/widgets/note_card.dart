import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../models/user_model.dart';
import '../repositories/note_repository.dart';
import '../repositories/profile_repository.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../utils/app_colors.dart';
import '../utils/markdown_formatter.dart';
import '../viewmodels/settings_viewmodel.dart';
import 'noted_ui.dart';
import 'reference_icon.dart';

class NoteCard extends StatefulWidget {
  const NoteCard(
      {super.key,
      required this.note,
      this.color,
      required this.onTap,
      required this.onFavoritePressed,
      this.compact = false,
      this.tall = false,
      this.list = false});
  final NoteModel note;
  final Color? color;
  final VoidCallback onTap, onFavoritePressed;
  final bool compact, tall, list;
  @override
  State<NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<NoteCard> {
  bool _hover = false, _pressed = false;
  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final theme = Theme.of(context);
    final bg =
        widget.color ?? AppColors.noteColor(theme.brightness, note.color);
    final text = theme.colorScheme.onSurface;
    final settings = context.watch<SettingsViewModel>().settings;
    final compact = widget.compact || settings.density == 'compact';
    return MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0)
              ..scaleByDouble(_pressed ? .985 : 1, _pressed ? .985 : 1, 1, 1),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                  onTap: widget.onTap,
                  onHighlightChanged: (v) => setState(() => _pressed = v),
                  child: Semantics(
                      button: true,
                      label:
                          'Open ${note.title.isEmpty ? 'Untitled' : note.title}',
                      child: Stack(children: [
                        Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: compact ? 14 : 16,
                                vertical: compact ? 12 : 16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                      padding: const EdgeInsets.only(right: 22),
                                      child: Text(note.category.toUpperCase(),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: .88,
                                              color: text.withValues(
                                                  alpha: .65)))),
                                  const SizedBox(height: 6),
                                  Padding(
                                      padding: const EdgeInsets.only(right: 16),
                                      child: Text(
                                          note.title.isEmpty
                                              ? 'Untitled'
                                              : note.title,
                                          maxLines: widget.list ? 1 : 3,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: widget.list ? 15 : 16,
                                              fontWeight: FontWeight.w600,
                                              height: 1.25,
                                              letterSpacing: -.16,
                                              color: text))),
                                  const SizedBox(height: 6),
                                  Text(
                                      MarkdownFormatter.toPlainText(
                                                  note.content)
                                              .trim()
                                              .isEmpty
                                          ? 'No content yet'
                                          : MarkdownFormatter.toPlainText(
                                              note.content),
                                      maxLines: widget.list
                                          ? 1
                                          : compact
                                              ? 2
                                              : widget.tall
                                                  ? 5
                                                  : 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 13,
                                          height: 1.5,
                                          color: text.withValues(alpha: .74))),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    Expanded(
                                        child: Text(
                                            relativeTime(note.updatedAt),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: text.withValues(
                                                    alpha: .65)))),
                                    if (note.isLive)
                                      LiveAvatarStack(
                                          note: note, background: bg)
                                  ]),
                                ])),
                        Positioned(
                            top: 2,
                            right: 2,
                            child: Semantics(
                                toggled: note.isFavorite,
                                child: IconButton(
                                    tooltip: note.isFavorite
                                        ? 'Remove from favorites'
                                        : 'Add to favorites',
                                    onPressed: widget.onFavoritePressed,
                                    icon: ReferenceIcon('star',
                                        size: 18,
                                        filled: note.isFavorite,
                                        color: note.isFavorite
                                            ? AppColors.star
                                            : text.withValues(alpha: .45))))),
                      ]))),
            )));
  }
}

class NotesMasonry extends StatelessWidget {
  const NotesMasonry(
      {super.key,
      required this.notes,
      required this.onOpen,
      required this.onFavorite,
      this.list = false});
  final List<NoteModel> notes;
  final ValueChanged<NoteModel> onOpen, onFavorite;
  final bool list;
  @override
  Widget build(BuildContext context) {
    Widget card(int i) => NoteCard(
        note: notes[i],
        tall: (i ~/ 2 + i % 2).isEven,
        list: list,
        onTap: () => onOpen(notes[i]),
        onFavoritePressed: () => onFavorite(notes[i]));
    if (list) {
      return Column(children: [
        for (var i = 0; i < notes.length; i++)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: card(i))
      ]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var col = 0; col < 2; col++) ...[
        if (col == 1) const SizedBox(width: 12),
        Expanded(
            child: Column(children: [
          for (var i = col; i < notes.length; i += 2)
            Padding(padding: const EdgeInsets.only(bottom: 12), child: card(i))
        ])),
      ]
    ]);
  }
}

class LiveAvatarStack extends StatefulWidget {
  const LiveAvatarStack(
      {super.key, required this.note, this.size = 20, this.background});
  final NoteModel note;
  final double size;
  final Color? background;
  @override
  State<LiveAvatarStack> createState() => _LiveAvatarStackState();
}

class _LiveAvatarStackState extends State<LiveAvatarStack> {
  late Stream<List<Map<String, dynamic>>> _stream;
  Timer? _expiry;
  @override
  void initState() {
    super.initState();
    _listen();
    _expiry = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  void _listen() =>
      _stream = NoteRepository().watchPresence(widget.note.noteId);
  @override
  void didUpdateWidget(covariant LiveAvatarStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.noteId != widget.note.noteId) _listen();
  }

  @override
  void dispose() {
    _expiry?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.read<AuthViewModel>().user?.uid;
    final ids = {widget.note.userId, ...widget.note.liveMemberIds}
        .where((id) => id != uid)
        .take(3)
        .toList();
    if (ids.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<Map<String, dynamic>>>(
        stream: _stream,
        builder: (context, snapshot) {
          final now = DateTime.now();
          final online = <String>{
            for (final d in snapshot.data ?? const <Map<String, dynamic>>[])
              if (d['userId'] is String &&
                  ((d['expiresAt'] is DateTime &&
                          (d['expiresAt'] as DateTime).isAfter(now)) ||
                      d['expiresAt'] == null))
                d['userId'] as String
          };
          return SizedBox(
              width: widget.size + (ids.length - 1) * (widget.size - 6),
              height: widget.size + 4,
              child: Stack(children: [
                for (var i = 0; i < ids.length; i++)
                  Positioned(
                      left: i * (widget.size - 6),
                      top: 0,
                      child: _MemberAvatar(
                          uid: ids[i],
                          size: widget.size,
                          online: online.contains(ids[i]),
                          background: widget.background ??
                              Theme.of(context).scaffoldBackgroundColor))
              ]));
        });
  }
}

class _MemberAvatar extends StatefulWidget {
  const _MemberAvatar(
      {required this.uid,
      required this.size,
      required this.online,
      required this.background});
  final String uid;
  final double size;
  final bool online;
  final Color background;
  @override
  State<_MemberAvatar> createState() => _MemberAvatarState();
}

class _MemberAvatarState extends State<_MemberAvatar> {
  late Future<UserModel?> _profile;
  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => _profile = ProfileRepository().load(widget.uid);
  @override
  void didUpdateWidget(covariant _MemberAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<UserModel?>(
      future: _profile,
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name =
            (user?.name.isNotEmpty ?? false) ? user!.name : 'Collaborator';
        return Tooltip(
            message: '$name${widget.online ? ' · online' : ''}',
            child: Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.background, width: 2)),
                child: Stack(clipBehavior: Clip.none, children: [
                  NotedAvatar(
                      name: name,
                      uid: widget.uid,
                      size: widget.size,
                      photoUrl: user?.avatarUrl),
                  if (widget.online)
                    Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Theme.of(context).colorScheme.primary,
                                border: Border.all(
                                    color: widget.background, width: 2))))
                ])));
      });
}
