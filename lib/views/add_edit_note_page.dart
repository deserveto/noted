import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../repositories/note_repository.dart';
import '../repositories/workspace_repository.dart';
import '../services/attachment_service.dart';
import '../services/collaboration_service.dart';
import '../services/media_url_resolver.dart';
import '../utils/app_colors.dart';
import '../utils/markdown_formatter.dart';
import '../utils/document_codec.dart';
import '../utils/inline_ai_edit.dart';
import '../utils/collaborative_document.dart';
import '../utils/note_image_document.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../widgets/rich_formatting_toolbar.dart';
import '../widgets/rich_note_embed.dart';
import '../widgets/note_attachments.dart';
import '../widgets/note_share_sheet.dart';
import '../widgets/note_card.dart' show LiveAvatarStack;
import '../widgets/live_metadata.dart';
import '../repositories/profile_repository.dart';
import '../widgets/noted_ui.dart' show notedSheet, notedUndoSnackBar;
import '../widgets/reference_icon.dart';
import '../widgets/inline_ai_popup.dart';
import 'ai_page.dart';
import 'workspaces_page.dart';

typedef NoteImagePicker = Future<XFile?> Function();

class AddEditNotePage extends StatefulWidget {
  const AddEditNotePage(
      {this.note,
      this.initialDate,
      this.repository,
      this.attachmentService,
      this.pickImage,
      super.key});
  final NoteModel? note;
  final DateTime? initialDate;
  final NoteRepository? repository;
  final AttachmentService? attachmentService;
  final NoteImagePicker? pickImage;
  @override
  State<AddEditNotePage> createState() => _AddEditNotePageState();
}

class _PendingImageMove {
  _PendingImageMove.inline(this.inlineTracker) : attachment = null;
  _PendingImageMove.trailing(this.attachment) : inlineTracker = null;

  final DocumentImageAnchor? inlineTracker;
  final Map<String, dynamic>? attachment;

  bool get isValid => inlineTracker?.isValid ?? true;
}

class _AddEditNotePageState extends State<AddEditNotePage>
    with WidgetsBindingObserver {
  late final NoteRepository _repository;
  late final AttachmentService _attachments;
  late final NoteImagePicker _pickImage;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _rich = quill.QuillController.basic();
  final _editorKey = GlobalKey<quill.EditorState>();
  final _richScroll = ScrollController();
  String _richBaseline = '';
  String? _documentError;
  StreamSubscription<NoteModel?>? _subscription;
  Timer? _debounce;
  Timer? _presenceTimer;
  NoteModel? _note;
  NoteModel? _baseNote;
  NoteModel? _pendingRemote;
  NoteModel? _conflict;
  bool _foreground = true;
  bool _presenceEnabled = true;
  bool _loadingText = false;
  bool _dirty = false;
  bool _saving = false;
  bool _deleting = false;
  bool _uploading = false;
  DocumentInsertionAnchor? _imageInsertionAnchor;
  _PendingImageMove? _imageMove;
  int? _imageMoveTarget;
  bool _imageMoveBusy = false;
  bool _focusMode = false;
  bool _format = false;
  bool _canPop = false;
  String? _error;
  Future<bool>? _saveFuture;
  int _editVersion = 0;
  String _presenceUserId = '';

  String get _uid => context.read<AuthViewModel>().user?.uid ?? '';
  bool _accessUnavailable = false;
  bool get _editable =>
      !_deleting && !_accessUnavailable && (_note?.canEdit(_uid) ?? false);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repository = widget.repository ?? NoteRepository();
    _attachments = widget.attachmentService ?? AttachmentService();
    _pickImage = widget.pickImage ?? _pickImageFromGallery;
    _title.addListener(_changed);
    _body.addListener(_changed);
    _rich.addListener(_richChanged);
    _titleFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _bodyFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final presence = context.watch<SettingsViewModel>().settings.presence;
    if (presence != _presenceEnabled) {
      _presenceEnabled = presence;
      if (!presence) {
        _leavePresence();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sendPresence();
        });
      }
    }
    if (_note != null) return;
    final user = context.read<AuthViewModel>().user;
    final settings = context.read<SettingsViewModel>().settings;
    _note = widget.note ??
        NoteModel.empty(user?.uid ?? '',
                ownerName: user?.name ?? '', ownerEmail: user?.email ?? '')
            .copyWith(
                category: settings.defaultCat,
                color: settings.defaultColor == 'auto'
                    ? const [
                        'blue',
                        'pink',
                        'mint',
                        'yellow',
                        'peach',
                        'lav'
                      ][context.read<NoteViewModel>().notes.length % 6]
                    : settings.defaultColor,
                createdAt: widget.initialDate);
    _baseNote = _note;
    _presenceUserId = user?.uid ?? '';
    _loadText(_note!);
    if (_note!.noteId.isNotEmpty) _listen();
  }

  void _loadText(NoteModel note) {
    _loadingText = true;
    final sameDocument = _richBaseline.isNotEmpty &&
        _documentError == null &&
        _body.text == note.content;
    final wasIgnoringFocus = _rich.ignoreFocusOnTextChange;
    _rich.ignoreFocusOnTextChange = true;
    if (_title.text != note.title) _title.text = note.title;
    _body.text = note.content;
    try {
      if (sameDocument) return;
      final previous = _rich.document.toDelta();
      final selection = _rich.selection;
      final document = DocumentCodec.decode(note.content);
      final change = previous.diff(document.toDelta());
      _rich.document = document;
      _rich.updateSelection(
          TextSelection(
              baseOffset: change
                  .transformPosition(selection.baseOffset)
                  .clamp(0, document.length - 1),
              extentOffset: change
                  .transformPosition(selection.extentOffset)
                  .clamp(0, document.length - 1)),
          quill.ChangeSource.remote);
      _richBaseline = DocumentCodec.encode(_rich.document);
      _documentError = null;
    } catch (error) {
      _documentError = 'This document could not be opened safely.';
    } finally {
      _rich.ignoreFocusOnTextChange = wasIgnoringFocus;
      _loadingText = false;
    }
  }

  void _richChanged() {
    _imageInsertionAnchor?.update(_rich.document);
    final move = _imageMove;
    if (move != null) {
      move.inlineTracker?.update(_rich.document);
      _refreshImageMoveTarget();
    }
    if (_loadingText || _documentError != null) return;
    final encoded = DocumentCodec.encode(_rich.document);
    if (encoded == _richBaseline) return;
    _richBaseline = encoded;
    _body.text = encoded;
  }

  int _insertionOffset() {
    final maximum = (_rich.document.length - 1).clamp(0, _rich.document.length);
    final selection = _rich.selection;
    if (selection.isValid) {
      return selection.extentOffset.clamp(0, maximum);
    }
    return maximum;
  }

  void _refreshImageMoveTarget() {
    final move = _imageMove;
    if (move == null || _imageMoveBusy || !mounted) return;
    final selection = _rich.selection;
    if (!selection.isValid || !selection.isCollapsed) return;
    final maximum = (_rich.document.length - 1).clamp(0, _rich.document.length);
    final target = selection.extentOffset.clamp(0, maximum);
    final source = move.inlineTracker?.index;
    if (source != null && (target == source || target == source + 1)) {
      if (_imageMoveTarget != null) setState(() => _imageMoveTarget = null);
      return;
    }
    if (_imageMoveTarget != target) setState(() => _imageMoveTarget = target);
  }

  void _startInlineImageMove(String reference, int index) {
    if (!_editable || _imageMoveBusy) return;
    final tracker = DocumentImageAnchor(
      document: _rich.document,
      reference: reference,
      index: index,
    );
    if (!tracker.isValid) {
      setState(() => _error = 'That image is no longer in the note.');
      return;
    }
    setState(() {
      _imageMove = _PendingImageMove.inline(tracker);
      _imageMoveTarget = null;
    });
    _bodyFocus.requestFocus();
    _refreshImageMoveTarget();
  }

  void _startTrailingImageMove(Map<String, dynamic> attachment) {
    if (!_editable || _imageMoveBusy) return;
    if (NoteImageDocument.attachmentReference(attachment) == null) {
      setState(() => _error = 'This image cannot be moved into the note.');
      return;
    }
    setState(() {
      _imageMove = _PendingImageMove.trailing(attachment);
      _imageMoveTarget = null;
    });
    _bodyFocus.requestFocus();
    _refreshImageMoveTarget();
  }

  void _cancelImageMove() {
    if (_imageMoveBusy) return;
    setState(() {
      _imageMove = null;
      _imageMoveTarget = null;
    });
  }

  Future<void> _confirmImageMove() async {
    final move = _imageMove;
    final target = _imageMoveTarget;
    if (move == null || target == null || _imageMoveBusy) return;
    setState(() => _imageMoveBusy = true);
    var moved = false;
    try {
      final document = _rich.document;
      final maximum = (document.length - 1).clamp(0, document.length);
      final destination = target.clamp(0, maximum);
      final inline = move.inlineTracker;
      if (inline != null) {
        inline.update(document);
        if (!inline.isValid) {
          throw StateError('That image is no longer in the note.');
        }
        if (destination == inline.index || destination == inline.index + 1) {
          setState(() {
            _imageMove = null;
            _imageMoveTarget = null;
            _imageMoveBusy = false;
          });
          return;
        }
        if (!NoteImageDocument.moveImage(
          _rich,
          from: inline.index,
          to: destination,
        )) {
          throw StateError('That image is no longer in the note.');
        }
      } else {
        final attachmentKey = NoteImageDocument.attachmentKey(move.attachment!);
        if (!_note!.attachments.any(
            (item) => NoteImageDocument.attachmentKey(item) == attachmentKey)) {
          throw StateError('This image is no longer attached to the note.');
        }
        final reference =
            NoteImageDocument.attachmentReference(move.attachment!);
        if (reference == null) {
          throw StateError('This image is not available.');
        }
        final existing = NoteImageDocument.indexOf(document, reference);
        if (existing != null) {
          if (destination != existing && destination != existing + 1) {
            NoteImageDocument.moveImage(
              _rich,
              from: existing,
              to: destination,
            );
          }
        } else {
          NoteImageDocument.insertImage(_rich, destination, reference);
        }
      }
      moved = true;
      if (mounted) {
        setState(() {
          _imageMove = null;
          _imageMoveTarget = null;
          _imageMoveBusy = false;
        });
      }
      final saved = await _save();
      if (saved && mounted) {
        notedUndoSnackBar(context, 'Image moved', onUndo: () {
          _rich.undo();
          _save();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _imageMove = null;
          _imageMoveTarget = null;
          _imageMoveBusy = false;
          _error = 'Could not move image.';
        });
      }
    } finally {
      if (!moved && mounted) {
        setState(() => _imageMoveBusy = false);
      }
    }
  }

  List<Map<String, dynamic>> _visibleAttachments(NoteModel note) {
    final inline = NoteImageDocument.images(_rich.document)
        .map((image) => NoteImageDocument.canonicalReference(image.reference))
        .toSet();
    return note.attachments.where((attachment) {
      final type = attachment['type'];
      if (type != 'image' && type != 'doodle') return true;
      final reference = NoteImageDocument.attachmentReference(attachment);
      return reference == null ||
          !inline.contains(NoteImageDocument.canonicalReference(reference));
    }).toList();
  }

  bool _mergeRemote(NoteModel remote, {NoteModel? original}) {
    final base = original ?? _baseNote!;
    final local = _note!.copyWith(title: _title.text, content: _body.text);
    T choose<T>(T start, T mine, T theirs) {
      if (mine == start) return theirs;
      if (theirs == start || theirs == mine) return mine;
      throw StateError('Both people changed the same note details.');
    }

    try {
      String key(Map<String, dynamic> a) => '${a['path'] ?? a['url']}';
      final baseKeys = base.attachments.map(key).toSet();
      final localKeys = local.attachments.map(key).toSet();
      final remoteKeys = remote.attachments.map(key).toSet();
      final removed = baseKeys
          .where((id) => !localKeys.contains(id) || !remoteKeys.contains(id))
          .toSet();
      final items = <String, Map<String, dynamic>>{
        for (final a in [...remote.attachments, ...local.attachments])
          if (!removed.contains(key(a))) key(a): a
      };
      final merged = remote.copyWith(
        title: choose(base.title, local.title, remote.title),
        category: choose(base.category, local.category, remote.category),
        color: choose(base.color, local.color, remote.color),
        createdAt: choose(base.createdAt, local.createdAt, remote.createdAt),
        content: mergeContent(
            base: base.content, local: local.content, remote: remote.content),
        attachments: items.values.toList(),
      );
      setState(() {
        _baseNote = remote;
        _note = merged;
        _loadText(merged);
        _dirty = true;
        _conflict = null;
        _error = null;
      });
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 200), _save);
      return true;
    } catch (_) {
      setState(() {
        _conflict = remote;
        _error =
            'Both people changed the same note details. Your draft is preserved for review.';
      });
      return false;
    }
  }

  Future<void> _toggleFavorite() async {
    if (_note!.noteId.isEmpty) {
      _changeNote(_note!.copyWith(isFavorite: !_note!.isFavorite));
      return;
    }
    final before = _note!;
    setState(() {
      _note = before.copyWith(isFavorite: !before.isFavorite);
      _baseNote = _baseNote!.copyWith(isFavorite: !before.isFavorite);
    });
    try {
      await _repository.toggleFavorite(before);
    } catch (e) {
      if (mounted) {
        setState(() {
          _note = _note!.copyWith(isFavorite: before.isFavorite);
          _baseNote = _baseNote!.copyWith(isFavorite: before.isFavorite);
          _error = 'Could not update favorite.';
        });
      }
    }
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = _repository.watchNote(_note!.noteId).listen((remote) {
      if (!mounted) return;
      if (remote == null) {
        setState(() {
          _accessUnavailable = true;
          _error =
              'This note is no longer available. Your unsaved text is still here.';
        });
        return;
      }
      _accessUnavailable = false;
      if (remote.deletedAt != null) {
        setState(() => _error =
            'This note was moved to trash. Your unsaved text is still here.');
        return;
      }
      if (_saving) {
        _pendingRemote = remote;
        return;
      }
      if (!_dirty) {
        setState(() {
          _note = remote;
          _baseNote = remote;
          _loadText(remote);
        });
      } else if (remote.revision != _baseNote!.revision) {
        _mergeRemote(remote);
      } else {
        setState(() {
          _note = _note!.copyWith(
              liveMemberIds: remote.liveMemberIds,
              liveRoles: remote.liveRoles,
              isFavorite: remote.isFavorite);
          _baseNote = _baseNote!.copyWith(
              liveMemberIds: remote.liveMemberIds,
              liveRoles: remote.liveRoles,
              isFavorite: remote.isFavorite);
        });
      }
    }, onError: (Object e) {
      if (mounted) setState(() => _error = 'Sync unavailable.');
    });
    _presenceTimer?.cancel();
    _sendPresence();
    _presenceTimer =
        Timer.periodic(const Duration(seconds: 20), (_) => _sendPresence());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _sendPresence();
    } else {
      _leavePresence();
    }
  }

  void _leavePresence() {
    if (_note == null || _note!.noteId.isEmpty || _presenceUserId.isEmpty) {
      return;
    }
    _repository
        .leavePresence(_note!.noteId, _presenceUserId)
        .catchError((Object _) {});
  }

  void _sendPresence() {
    if (!mounted ||
        !_foreground ||
        _note == null ||
        !_note!.isLive ||
        !context.read<SettingsViewModel>().settings.presence) {
      return;
    }
    final user = context.read<AuthViewModel>().user;
    if (user != null) {
      _repository
          .updatePresence(_note!.noteId, user.uid, user.name,
              typing: (_titleFocus.hasFocus || _bodyFocus.hasFocus) && _dirty)
          .catchError((Object _) {});
    }
  }

  void _changed() {
    if (_loadingText || !mounted || !_editable) return;
    _editVersion++;
    setState(() {
      _dirty = true;
      if (_conflict == null) _error = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), _save);
  }

  void _changeNote(NoteModel note) {
    setState(() => _note = note);
    _changed();
  }

  Future<bool> _save({bool forceCreate = false}) {
    if (_saveFuture != null) return _saveFuture!;
    final future = _performSave(forceCreate: forceCreate);
    _saveFuture = future;
    future.whenComplete(() => _saveFuture = null);
    return future;
  }

  Future<bool> _performSave({bool forceCreate = false}) async {
    _debounce?.cancel();
    if (!_dirty && (!forceCreate || _note!.noteId.isNotEmpty)) return true;
    if (_conflict != null || !_editable) return false;
    final snapshot = _note!.copyWith(title: _title.text, content: _body.text);
    final version = _editVersion;
    if (!forceCreate &&
        snapshot.noteId.isEmpty &&
        snapshot.title.trim().isEmpty &&
        snapshot.plainText.trim().isEmpty &&
        snapshot.attachments.isEmpty) {
      return true;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      NoteModel saved;
      if (snapshot.noteId.isEmpty) {
        final id = await _repository.createNote(snapshot);
        saved = snapshot.copyWith(noteId: id, updatedAt: DateTime.now());
      } else {
        saved = await _repository.saveCollaborative(snapshot, _baseNote!);
      }
      if (!mounted) return true;
      setState(() => _saving = false);
      if (_editVersion == version) {
        setState(() {
          _note = saved;
          _baseNote = saved;
          _dirty = false;
          _loadText(saved);
        });
      } else {
        // More typing may arrive while the transaction is awaiting the server.
        // Rebase those later operations on the actual committed result.
        _mergeRemote(saved, original: snapshot);
      }
      if (snapshot.noteId.isEmpty) _listen();
      final pending = _pendingRemote;
      _pendingRemote = null;
      if (pending != null && pending.revision > _baseNote!.revision) {
        _mergeRemote(pending);
      }
      if (_dirty && _conflict == null) {
        _debounce = Timer(const Duration(milliseconds: 100), _save);
      }
      return !_dirty;
    } on NoteConflictException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _conflict = e.currentNote;
          _error =
              'This note changed elsewhere. Review both versions before saving.';
        });
      }
      return false;
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save.';
        });
      }
      return false;
    }
  }

  Future<void> _back() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final saved = await _save();
    if (!mounted || _uploading) return;
    if (!saved) {
      // Never dismiss an error or a newer in-flight edit by navigating away.
      final discard = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Your changes are not saved'),
                content: const Text(
                    'Stay in this note to retry saving or review conflicting changes. Leaving now discards your unsaved changes.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Discard changes')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Keep writing'))
                ],
              ));
      if (discard != true || !mounted) return;
    }
    setState(() => _canPop = true);
    Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _presenceTimer?.cancel();
    _subscription?.cancel();
    if (_note?.isLive == true) {
      _repository
          .leavePresence(_note!.noteId, _presenceUserId)
          .catchError((Object _) {});
    }
    _rich.dispose();
    _richScroll.dispose();
    _title.dispose();
    _body.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = _note!;
    final settings = context.watch<SettingsViewModel>().settings;
    final scheme = Theme.of(context).colorScheme;
    final words = MarkdownFormatter.toPlainText(_body.text)
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .length;
    final writing = _titleFocus.hasFocus || _bodyFocus.hasFocus;
    _rich.readOnly = !_editable;
    return PopScope(
        canPop: _canPop,
        onPopInvokedWithResult: (popped, _) {
          if (!popped) _back();
        },
        child: Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
                tooltip: 'Back to notes',
                onPressed: _back,
                icon: const ReferenceIcon('back')),
            titleSpacing: 0,
            title: Semantics(
                liveRegion: true,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  ReferenceIcon(_saving || _dirty ? 'clock' : 'check',
                      size: 14, color: scheme.primary),
                  const SizedBox(width: 5),
                  Text(
                      _saving
                          ? 'Saving…'
                          : _dirty
                              ? 'Unsaved'
                              : note.isLive
                                  ? 'Synced'
                                  : 'Saved',
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant))
                ])),
            actions: [
              if (note.isLive)
                IconButton(
                    tooltip: 'Collaborators',
                    onPressed: note.isOwner(_uid) ? _share : _members,
                    icon: LiveAvatarStack(note: note, size: 26)),
              ...writing
                  ? [
                      TextButton(
                          onPressed: () {
                            _titleFocus.unfocus();
                            _bodyFocus.unfocus();
                            FocusScope.of(context).unfocus();
                            _save();
                          },
                          child: const Text('Done'))
                    ]
                  : [
                      IconButton(
                          tooltip: note.isFavorite
                              ? 'Remove from favorites'
                              : 'Add to favorites',
                          onPressed: _toggleFavorite,
                          icon: ReferenceIcon('star',
                              filled: note.isFavorite,
                              color: note.isFavorite
                                  ? const Color(0xffe8a93a)
                                  : null)),
                      IconButton(
                          tooltip: 'Share',
                          onPressed: note.isOwner(_uid) ? _share : null,
                          icon: const ReferenceIcon('share')),
                      PopupMenuButton<String>(
                          tooltip: 'More actions',
                          icon: const ReferenceIcon('more'),
                          onSelected: _menu,
                          itemBuilder: (_) => [
                                PopupMenuItem(
                                    value: 'focus',
                                    child: Text(_focusMode
                                        ? 'Exit focus mode'
                                        : 'Focus mode')),
                                const PopupMenuItem(
                                    value: 'duplicate',
                                    child: Text('Duplicate')),
                                const PopupMenuItem(
                                    value: 'copy', child: Text('Copy text')),
                                if (note.isOwner(_uid))
                                  const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('Delete note'))
                              ]),
                    ],
            ],
          ),
          body: SafeArea(
              child: Center(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 700),
                      child: Column(children: [
                        if (_error != null)
                          Material(
                              color: scheme.errorContainer,
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  child: Row(children: [
                                    Expanded(
                                        child: Text(_error!,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color:
                                                    scheme.onErrorContainer))),
                                    TextButton(
                                        onPressed: _conflict != null
                                            ? _reviewConflict
                                            : _save,
                                        child: Text(_conflict != null
                                            ? 'Review'
                                            : 'Retry'))
                                  ]))),
                        if (_uploading) const LinearProgressIndicator(),
                        if (_imageMove != null) _imageMoveBanner(scheme),
                        Expanded(
                            child: SingleChildScrollView(
                                padding:
                                    const EdgeInsets.fromLTRB(24, 4, 24, 28),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (!_focusMode)
                                        Wrap(
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            spacing: 8,
                                            children: [
                                              ActionChip(
                                                  backgroundColor: scheme
                                                      .surfaceContainerHighest,
                                                  side: BorderSide.none,
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8)),
                                                  avatar: CircleAvatar(
                                                      radius: 5,
                                                      backgroundColor:
                                                          _noteColor(
                                                              note.color)),
                                                  label: Text(note.category,
                                                      style: TextStyle(
                                                          fontSize: 13,
                                                          color: scheme
                                                              .onSurface)),
                                                  onPressed: _editable
                                                      ? _category
                                                      : null),
                                              if (note.noteId.isNotEmpty)
                                                ActionChip(
                                                    label:
                                                        const Text('Workspace'),
                                                    onPressed: () async {
                                                      final workspace =
                                                          await pickWorkspace(
                                                              context,
                                                              noteId:
                                                                  note.noteId);
                                                      if (workspace == null) {
                                                        return;
                                                      }
                                                      try {
                                                        await WorkspaceRepository()
                                                            .assign(note.noteId,
                                                                workspace);
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                                  const SnackBar(
                                                                      content: Text(
                                                                          'Workspace updated')));
                                                        }
                                                      } catch (_) {
                                                        if (context.mounted) {
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                                  const SnackBar(
                                                                      content: Text(
                                                                          'Could not update workspace.')));
                                                        }
                                                      }
                                                    }),
                                              TextButton(
                                                  onPressed:
                                                      _editable ? _date : null,
                                                  child: Text(
                                                      DateFormat('MMM d, yyyy')
                                                          .format(
                                                              note.createdAt),
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: scheme
                                                              .onSurfaceVariant))),
                                              if (settings.wordCount)
                                                Text('$words words',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: scheme
                                                            .onSurfaceVariant)),
                                              if (note.isLive)
                                                LiveMetadata(note: note),
                                            ]),
                                      const SizedBox(height: 10),
                                      Semantics(
                                          label: 'Note title',
                                          textField: true,
                                          child: TextField(
                                              controller: _title,
                                              focusNode: _titleFocus,
                                              readOnly: !_editable,
                                              autocorrect: settings.spellcheck,
                                              enableSuggestions:
                                                  settings.spellcheck,
                                              maxLines: null,
                                              textInputAction:
                                                  TextInputAction.next,
                                              onSubmitted: (_) =>
                                                  _bodyFocus.requestFocus(),
                                              style: const TextStyle(
                                                  fontSize: 30,
                                                  fontWeight: FontWeight.w600,
                                                  letterSpacing: -.75,
                                                  height: 1.2),
                                              decoration: const InputDecoration(
                                                  hintText: 'Untitled',
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  filled: false,
                                                  contentPadding:
                                                      EdgeInsets.zero))),
                                      const SizedBox(height: 20),
                                      if (_documentError != null)
                                        Text(_documentError!,
                                            style:
                                                TextStyle(color: scheme.error))
                                      else
                                        Semantics(
                                          label: 'Note content',
                                          multiline: true,
                                          textField: true,
                                          child: quill.QuillEditor.basic(
                                            controller: _rich,
                                            focusNode: _bodyFocus,
                                            scrollController: _richScroll,
                                            config: quill.QuillEditorConfig(
                                              editorKey: _editorKey,
                                              embedBuilders: [
                                                RichNoteEmbed(
                                                  onMove: _editable
                                                      ? _startInlineImageMove
                                                      : null,
                                                )
                                              ],
                                              unknownEmbedBuilder:
                                                  RichNoteEmbed(
                                                onMove: _editable
                                                    ? _startInlineImageMove
                                                    : null,
                                              ),
                                              scrollable: false,
                                              autoFocus: false,
                                              placeholder: 'Start writing…',
                                              padding: EdgeInsets.zero,
                                              expands: false,
                                              minHeight: 220,
                                              enableInteractiveSelection: true,
                                              enableSelectionToolbar: true,
                                              // Keep Quill’s line-aware toggle and read-only state.
                                              // ignore: experimental_member_use
                                              customLeadingBlockBuilder:
                                                  (line, leading) {
                                                if (leading.attribute !=
                                                        quill.Attribute
                                                            .checked &&
                                                    leading.attribute !=
                                                        quill.Attribute
                                                            .unchecked) {
                                                  return null;
                                                }
                                                return Checkbox(
                                                  value: leading.value,
                                                  onChanged: leading.enabled ==
                                                          true
                                                      ? (checked) =>
                                                          leading.onCheckboxTap(
                                                              checked!)
                                                      : null,
                                                );
                                              },
                                              customStyles: quill.DefaultStyles(
                                                h3: quill.DefaultTextBlockStyle(
                                                    TextStyle(
                                                        fontFamily: 'DM Sans',
                                                        fontSize: 19,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: -.19,
                                                        color:
                                                            scheme.onSurface),
                                                    const quill
                                                        .HorizontalSpacing(
                                                        0, 0),
                                                    const quill.VerticalSpacing(
                                                        0, 9),
                                                    const quill.VerticalSpacing(
                                                        0, 0),
                                                    null),
                                                quote: quill.DefaultTextBlockStyle(
                                                    TextStyle(
                                                        fontFamily:
                                                            'Newsreader',
                                                        fontStyle:
                                                            FontStyle.italic,
                                                        fontSize: 19,
                                                        height: 1.7,
                                                        color: scheme
                                                            .onSurfaceVariant),
                                                    const quill
                                                        .HorizontalSpacing(
                                                        14, 0),
                                                    const quill
                                                        .VerticalSpacing(0, 9),
                                                    const quill.VerticalSpacing(
                                                        0,
                                                        0),
                                                    BoxDecoration(
                                                        border: Border(
                                                            left: BorderSide(
                                                                color: scheme
                                                                    .primary,
                                                                width: 3)))),
                                                paragraph:
                                                    quill.DefaultTextBlockStyle(
                                                        TextStyle(
                                                            fontFamily:
                                                                'DM Sans',
                                                            fontSize: settings
                                                                .textSize,
                                                            height: 1.7,
                                                            color: scheme
                                                                .onSurface),
                                                        const quill
                                                            .HorizontalSpacing(
                                                            0, 0),
                                                        const quill
                                                            .VerticalSpacing(
                                                            0, 9),
                                                        const quill
                                                            .VerticalSpacing(
                                                            0, 0),
                                                        null),
                                              ),
                                            ),
                                          ),
                                        ),
                                      for (final attachment
                                          in _visibleAttachments(note))
                                        NoteAttachment(
                                            key: ValueKey(
                                                NoteImageDocument.attachmentKey(
                                                    attachment)),
                                            attachment: attachment,
                                            onRemove: _editable
                                                ? () {
                                                    final key =
                                                        NoteImageDocument
                                                            .attachmentKey(
                                                                attachment);
                                                    final items = note
                                                        .attachments
                                                        .where((item) =>
                                                            NoteImageDocument
                                                                .attachmentKey(
                                                                    item) !=
                                                            key)
                                                        .toList();
                                                    _changeNote(note.copyWith(
                                                        attachments: items));
                                                  }
                                                : null,
                                            onMove: _editable &&
                                                    (attachment['type'] ==
                                                            'image' ||
                                                        attachment['type'] ==
                                                            'doodle')
                                                ? () => _startTrailingImageMove(
                                                    attachment)
                                                : null),
                                      if (note.isLive)
                                        StreamBuilder<
                                                List<Map<String, dynamic>>>(
                                            stream: _repository
                                                .watchPresence(note.noteId),
                                            builder: (context, snapshot) {
                                              final people =
                                                  (snapshot.data ?? [])
                                                      .where((p) =>
                                                          p['userId'] != _uid)
                                                      .toList();
                                              if (people.isEmpty) {
                                                return const SizedBox.shrink();
                                              }
                                              return Text(
                                                  people
                                                      .map((p) =>
                                                          '${p['name']}${p['typing'] == true ? ' is typing…' : ' is here'}')
                                                      .join(' · '),
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: scheme.primary));
                                            }),
                                    ]))),
                        if (!_focusMode)
                          Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (_editable && writing)
                                      Expanded(
                                          child: _format
                                              ? RichFormattingToolbar(
                                                  controller: _rich,
                                                  focusNode: _bodyFocus,
                                                  onClose: () => setState(
                                                      () => _format = false))
                                              : Container(
                                                  decoration: BoxDecoration(
                                                      color: scheme.surface,
                                                      border: Border.all(
                                                          color: Theme.of(
                                                                  context)
                                                              .dividerColor),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              28)),
                                                  child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceEvenly,
                                                      children: [
                                                        _tool(
                                                            'Record audio',
                                                            'mic',
                                                            () => _attach(
                                                                'audio')),
                                                        _tool(
                                                            'Add image',
                                                            'image',
                                                            () => _attach(
                                                                'image')),
                                                        _tool(
                                                            'Doodle',
                                                            'pen',
                                                            () => _attach(
                                                                'doodle')),
                                                        _tool('Checklist',
                                                            'todo', _checklist),
                                                        _tool('Formatting',
                                                            'type', () {
                                                          _bodyFocus
                                                              .requestFocus();
                                                          setState(() =>
                                                              _format = true);
                                                        }),
                                                      ]))),
                                    if (!writing || !_editable) const Spacer(),
                                    if (settings.aiEnabled) ...[
                                      const SizedBox(width: 8),
                                      IconButton.filled(
                                          tooltip: 'Ask Noted AI',
                                          onPressed: _ai,
                                          style: IconButton.styleFrom(
                                              backgroundColor: scheme.onSurface,
                                              foregroundColor: Theme.of(context)
                                                  .scaffoldBackgroundColor,
                                              minimumSize: const Size(48, 48),
                                              shape: const CircleBorder()),
                                          icon: const ReferenceIcon('spark'))
                                    ],
                                  ])),
                      ])))),
        ));
  }

  Widget _imageMoveBanner(ColorScheme scheme) {
    final move = _imageMove!;
    final valid = move.isValid;
    final target = _imageMoveTarget;
    final message = !valid
        ? 'That image is no longer in the note.'
        : target == null
            ? 'Tap in the note where the image should go.'
            : 'The image will move to the selected position.';
    return Material(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              ReferenceIcon('target',
                  size: 18, color: scheme.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    message,
                    style: TextStyle(color: scheme.onPrimaryContainer),
                  ),
                ),
              ),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: _imageMoveBusy ? null : _cancelImageMove,
                child: const Text('Cancel'),
              ),
              if (valid && target != null)
                FilledButton(
                  onPressed: _imageMoveBusy ? null : _confirmImageMove,
                  child: Text(_imageMoveBusy ? 'Moving…' : 'Move here'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _tool(String label, String icon, VoidCallback action) => IconButton(
      tooltip: label,
      onPressed: _uploading ? null : action,
      icon: ReferenceIcon(icon, size: 20));
  Color _noteColor(String key) => AppColors.noteColorFor(
      Theme.of(context).brightness,
      const ['blue', 'pink', 'mint', 'yellow', 'peach', 'lav']
          .indexOf(key)
          .clamp(0, 5));
  void _checklist() {
    _rich.formatSelection(quill.Attribute.unchecked);
    _bodyFocus.requestFocus();
  }

  Future<void> _category() async {
    final categories = {
      _note!.category,
      ...context.read<NoteViewModel>().categories,
    }.toList()
      ..sort();
    final controller = TextEditingController();
    final value = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
            child: Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Category & color',
                          style: TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, children: [
                        for (final (key, label) in const [
                          ('blue', 'Blue note'),
                          ('pink', 'Pink note'),
                          ('mint', 'Mint note'),
                          ('yellow', 'Yellow note'),
                          ('peach', 'Peach note'),
                          ('lav', 'Lavender note'),
                        ])
                          IconButton(
                              tooltip: label,
                              onPressed: () {
                                _changeNote(_note!.copyWith(color: key));
                                Navigator.pop(ctx);
                              },
                              icon: CircleAvatar(
                                  radius: 16,
                                  backgroundColor: _noteColor(key),
                                  child: _note!.color == key
                                      ? const ReferenceIcon('check', size: 16)
                                      : null))
                      ]),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, children: [
                        for (final c in categories)
                          ChoiceChip(
                              label: Text(c),
                              selected: c == _note!.category,
                              labelStyle: TextStyle(
                                  color: c == _note!.category
                                      ? Theme.of(ctx).colorScheme.onPrimary
                                      : Theme.of(ctx).colorScheme.onSurface,
                                  fontWeight: FontWeight.w500),
                              selectedColor: Theme.of(ctx).colorScheme.primary,
                              backgroundColor:
                                  Theme.of(ctx).colorScheme.surface,
                              checkmarkColor:
                                  Theme.of(ctx).colorScheme.onPrimary,
                              side: BorderSide(
                                  color: c == _note!.category
                                      ? Theme.of(ctx).colorScheme.primary
                                      : Theme.of(ctx).colorScheme.outline),
                              onSelected: (_) => Navigator.pop(ctx, c))
                      ]),
                      const SizedBox(height: 12),
                      Semantics(
                          label: 'Add a category',
                          textField: true,
                          child: TextField(
                              controller: controller,
                              autofocus: false,
                              decoration: InputDecoration(
                                  hintText: 'Add a category',
                                  suffixIcon: IconButton(
                                      tooltip: 'Add category',
                                      onPressed: () {
                                        if (controller.text.trim().isNotEmpty) {
                                          Navigator.pop(
                                              ctx, controller.text.trim());
                                        }
                                      },
                                      icon: const ReferenceIcon('plus'))),
                              onSubmitted: (v) {
                                if (v.trim().isNotEmpty) {
                                  Navigator.pop(ctx, v.trim());
                                }
                              })),
                    ]))));
    controller.dispose();
    if (value != null && mounted) _changeNote(_note!.copyWith(category: value));
  }

  Future<void> _date() async {
    final value = await showDatePicker(
        context: context,
        initialDate: _note!.createdAt,
        firstDate: DateTime(1970),
        lastDate: DateTime(2100));
    if (value != null && mounted) {
      _changeNote(_note!.copyWith(createdAt: value));
    }
  }

  Future<void> _members() => notedSheet<void>(context,
      label: 'Collaborators',
      builder: (context) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Collaborators',
                    style: Theme.of(context).textTheme.titleLarge),
                for (final id in {_note!.userId, ..._note!.liveMemberIds})
                  FutureBuilder(
                      future: ProfileRepository().load(id),
                      builder: (context, snapshot) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(snapshot.data?.name ?? 'Collaborator'),
                          subtitle: Text(id == _note!.userId
                              ? 'Owner'
                              : _note!.liveRoles[id] == 'edit'
                                  ? 'Can edit'
                                  : 'Can view'))),
              ])));

  Future<void> _share() async {
    if (!await _save() || !mounted || _note!.noteId.isEmpty) return;
    final result = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => NoteShareSheet(note: _note!));
    if (mounted && result != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result)));
    }
  }

  Future<void> _ai() async {
    final selection = _rich.selection;
    Offset? anchor;
    final renderEditor = _editorKey.currentState?.renderEditor;
    if (selection.isValid && !selection.isCollapsed && renderEditor != null) {
      final endpoints = renderEditor.getEndpointsForSelection(selection);
      if (endpoints.isNotEmpty) {
        anchor = renderEditor.localToGlobal(endpoints.last.point);
      }
    }
    final initialDocument = DocumentCodec.encode(_rich.document);
    FocusScope.of(context).unfocus();
    if (!await _save() || !mounted) return;
    if (_note!.noteId.isEmpty) {
      setState(() => _error = 'Write something in this note before asking AI.');
      return;
    }
    if (selection.isValid &&
        !selection.isCollapsed &&
        (DocumentCodec.encode(_rich.document) != initialDocument ||
            _rich.selection != selection)) {
      setState(() => _error = 'The note changed. Select the text again.');
      return;
    }
    final plain = _rich.document.toPlainText();
    final selected = selection.isValid && !selection.isCollapsed
        ? plain.substring(selection.start.clamp(0, plain.length),
            selection.end.clamp(0, plain.length))
        : null;
    final selectionDocument = DocumentCodec.encode(_rich.document);
    _titleFocus.canRequestFocus = false;
    _bodyFocus.canRequestFocus = false;
    try {
      if (selected != null && selected.isNotEmpty) {
        await showGeneralDialog<void>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'Close inline AI',
          barrierColor: Colors.black26,
          pageBuilder: (dialogContext, _, __) {
            final media = MediaQuery.of(dialogContext);
            final width = (media.size.width - 32).clamp(0.0, 400.0);
            final height = (media.size.height * .55).clamp(0.0, 440.0);
            final minTop = media.padding.top + 12;
            final maxTop =
                (media.size.height - media.padding.bottom - height - 12)
                    .clamp(minTop, double.infinity);
            final anchorY = anchor?.dy ?? media.size.height / 2;
            final below = anchorY + 16;
            final top = (below <= maxTop ? below : anchorY - height - 16)
                .clamp(minTop, maxTop);
            final left = ((anchor?.dx ?? media.size.width / 2) - width / 2)
                .clamp(
                    16.0,
                    (media.size.width - width - 16)
                        .clamp(16.0, double.infinity));
            return Stack(children: [
              Positioned(
                left: left,
                top: top,
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: height),
                  child: InlineAiPopup(
                    selection: selected,
                    noteId: _note!.noteId,
                    onApply: !_editable
                        ? null
                        : (markdown, replace) =>
                            _editable &&
                            applyInlineAiEdit(
                                _rich, selection, selectionDocument, markdown,
                                replace: replace),
                  ),
                ),
              ),
            ]);
          },
        );
        return;
      }
      await notedSheet<void>(context,
          label: 'Noted AI',
          tall: true,
          builder: (_) => AiPage(
                compact: true,
                initialNoteIds: [_note!.noteId],
                selection: selected,
                selectionNoteId: _note!.noteId,
                onInlineEdit: !_editable || selected == null
                    ? null
                    : (markdown, replace) =>
                        _editable &&
                        applyInlineAiEdit(
                            _rich, selection, selectionDocument, markdown,
                            replace: replace),
                onInsert: !_editable
                    ? null
                    : (markdown) {
                        final appended = DocumentCodec.fromMarkdown(markdown);
                        final wasIgnoringFocus = _rich.ignoreFocusOnTextChange;
                        _rich.ignoreFocusOnTextChange = true;
                        try {
                          _rich.document = quill.Document.fromJson([
                            ..._rich.document.toDelta().toJson(),
                            ...appended.toDelta().toJson(),
                          ]);
                        } finally {
                          _rich.ignoreFocusOnTextChange = wasIgnoringFocus;
                        }
                        _richChanged();
                      },
              ));
    } finally {
      if (mounted) {
        _titleFocus.canRequestFocus = true;
        _bodyFocus.canRequestFocus = true;
      }
    }
  }

  Future<void> _attach(String type) async {
    DocumentInsertionAnchor? anchor;
    try {
      Uint8List? bytes;
      String name;
      String mime;
      int? duration;
      if (type == 'image') {
        anchor = DocumentInsertionAnchor(
          document: _rich.document,
          offset: _insertionOffset(),
        );
        _imageInsertionAnchor = anchor;
        final image = await _pickImage();
        if (image == null) return;
        if (!mounted) return;
        bytes = await image.readAsBytes();
        name = image.name;
        mime = image.mimeType ?? 'image/jpeg';
      } else if (type == 'doodle') {
        bytes = await showModalBottomSheet<Uint8List>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (_) => const DoodleSheet());
        if (bytes == null) return;
        name = 'doodle.png';
        mime = 'image/png';
      } else {
        final audio = await showModalBottomSheet<RecordedAudio>(
            context: context,
            showDragHandle: true,
            isDismissible: false,
            builder: (_) => const AudioRecordingSheet());
        if (audio == null) return;
        bytes = audio.bytes;
        duration = audio.seconds;
        name = 'voice-memo.m4a';
        mime = 'audio/mp4';
      }
      if (!mounted) return;
      final saved = await _save(forceCreate: true);
      if (!mounted || !saved) return;
      // An existing no-op save may have been in flight before the force request.
      if (_note!.noteId.isEmpty) await _save(forceCreate: true);
      if (!mounted) return;
      if (_note!.noteId.isEmpty) {
        throw StateError('Save this note before uploading an attachment.');
      }
      setState(() => _uploading = true);
      final item = await _attachments.upload(
          noteId: _note!.noteId,
          bytes: bytes,
          type: type,
          name: name,
          contentType: mime,
          duration: duration);
      if (type == 'image') {
        final path = item['path'] as String? ?? '';
        if (!mounted) {
          await _discardUpload(path);
          return;
        }
        anchor?.update(_rich.document);
        final reference = path.isNotEmpty
            ? MediaUrlResolver.canonicalUri(
                MediaUrlResolver.noteMediaBucket, path)
            : (item['url'] as String?)?.trim() ?? '';
        if (anchor == null || reference.isEmpty) {
          await _discardUpload(path);
          throw StateError(
              'The note changed while the image was uploading. Try again.');
        }
        NoteImageDocument.insertImage(_rich, anchor.offset, reference);
        await _save();
      } else if (mounted) {
        _changeNote(
            _note!.copyWith(attachments: [..._note!.attachments, item]));
        await _save();
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not add attachment.');
    } finally {
      if (identical(_imageInsertionAnchor, anchor)) {
        _imageInsertionAnchor = null;
      }
      if (mounted) setState(() => _uploading = false);
    }
  }

  static Future<XFile?> _pickImageFromGallery() => ImagePicker()
      .pickImage(source: ImageSource.gallery, maxWidth: 2400, imageQuality: 90);

  Future<void> _discardUpload(String path) async {
    if (path.trim().isEmpty) return;
    try {
      await _attachments.remove(path);
    } catch (_) {
      // The note-deletion/media-copy cleanup also removes unreferenced prefixes.
    }
  }

  Future<void> _duplicateDraft(String suffix) async {
    if (_note!.noteId.isEmpty) await _save(forceCreate: true);
    if (!mounted) return;
    if (_note!.noteId.isEmpty) {
      throw StateError('Save this note before creating a copy.');
    }
    await CollaborationService().duplicate(noteId: _note!.noteId, draft: {
      'title': '${_title.text} ($suffix)',
      'content': _body.text,
      'category': _note!.category,
      'color': _note!.color,
      'createdAt': DateTime.now().toIso8601String(),
      'attachments': _note!.attachments,
    });
  }

  Future<void> _menu(String action) async {
    if (action == 'focus') {
      setState(() => _focusMode = !_focusMode);
      return;
    }
    if (action == 'copy') {
      await Clipboard.setData(ClipboardData(
          text:
              '${_title.text}\n\n${MarkdownFormatter.toPlainText(_body.text)}'));
      return;
    }
    if (action == 'duplicate') {
      try {
        await _duplicateDraft('copy');
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Note duplicated')));
        }
      } catch (e) {
        if (mounted) setState(() => _error = 'Could not duplicate.');
      }
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Delete note?'),
                  content: const Text(
                      'This note will move to trash. You can restore it from Settings.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'))
                  ]));
      if (confirmed != true || !mounted) return;
      if (_deleting) return;
      setState(() => _deleting = true);
      _debounce?.cancel();
      try {
        // A new note can acquire its ID while deletion is being confirmed.
        // Wait for any outstanding write before deciding what to delete.
        final pendingSave = _saveFuture;
        if (pendingSave != null) await pendingSave;
        if (!mounted) return;
        _debounce?.cancel();
        final id = _note!.noteId;
        final title = _title.text.trim().isEmpty ? 'Untitled' : _title.text;
        final messenger = ScaffoldMessenger.of(context);
        final repository = _repository;
        if (id.isNotEmpty) await repository.deleteNote(id);
        if (mounted) {
          _debounce?.cancel();
          _dirty = false;
          _canPop = true;
          Navigator.pop(context);
          if (id.isNotEmpty) {
            notedUndoSnackBar(context, 'Deleted “$title”', onUndo: () async {
              try {
                await repository.restoreNote(id);
              } catch (error) {
                if (messenger.mounted) {
                  messenger.showSnackBar(
                      const SnackBar(content: Text('Could not restore.')));
                }
              }
            });
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _deleting = false;
            _error = 'Could not delete.';
          });
        }
      }
    }
  }

  Future<void> _reviewConflict() async {
    final remote = _conflict!;
    final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Review changes'),
                content: SizedBox(
                    width: double.maxFinite,
                    child: SingleChildScrollView(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          const Text('Latest shared version',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                              '${remote.title}\n${MarkdownFormatter.toPlainText(remote.content)}'),
                          const SizedBox(height: 16),
                          const Text('Your version',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                              '${_title.text}\n${MarkdownFormatter.toPlainText(_body.text)}')
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Keep reviewing')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, 'copy'),
                      child: const Text('Save mine as copy')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'latest'),
                      child: const Text('Use latest'))
                ]));
    if (choice == null || !mounted) return;
    try {
      if (choice == 'copy') {
        await _duplicateDraft('recovered');
      }
      if (mounted) {
        setState(() {
          _note = remote;
          _baseNote = remote;
          _loadText(remote);
          _dirty = false;
          _conflict = null;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not recover changes.');
    }
  }
}
