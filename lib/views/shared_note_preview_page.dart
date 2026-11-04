import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:provider/provider.dart';

import '../models/note_model.dart';
import '../utils/document_codec.dart';
import '../utils/note_image_document.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../widgets/note_attachments.dart';
import '../widgets/noted_ui.dart';
import '../widgets/pending_share_actions.dart';
import '../widgets/rich_note_embed.dart';

/// A pending invitation is never mounted in the editor or given owner actions.
class SharedNotePreviewPage extends StatefulWidget {
  const SharedNotePreviewPage({required this.noteId, super.key});
  final String noteId;

  @override
  State<SharedNotePreviewPage> createState() => _SharedNotePreviewPageState();
}

class _SharedNotePreviewPageState extends State<SharedNotePreviewPage>
    with WidgetsBindingObserver {
  Stream<NoteModel?>? _stream;
  String? _uid;
  bool _foreground = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _stream = null;
      _generation++;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<AuthViewModel>().user?.uid;
    if (_uid != uid) {
      _uid = uid;
      _stream = null;
      _generation++;
    }
    if (_foreground && uid != null) {
      _stream ??=
          context.read<NoteViewModel>().watchSharedPreview(widget.noteId);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Shared note preview')),
      body: !_foreground || uid == null
          ? const Center(
              child: Text('Preview unavailable. Sign in to continue.'))
          : StreamBuilder<NoteModel?>(
              key: ValueKey(_generation),
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                      child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: InlineError('Couldn’t load this shared note.',
                        onRetry: () => setState(() {
                              _stream = null;
                              _generation++;
                            })),
                  ));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(
                          semanticsLabel: 'Loading shared note'));
                }
                final note = snapshot.data;
                if (note == null ||
                    note.deletedAt != null ||
                    !note.pendingSharedWithUserIds.contains(uid)) {
                  return const Center(
                      child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('This shared note is no longer available.'),
                  ));
                }
                return Column(children: [
                  Expanded(
                      child: _SharedDocument(
                          key: ValueKey(note.content), note: note)),
                  SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: PendingShareActions(
                          noteId: note.noteId,
                          onResolved: () {
                            if (mounted &&
                                ModalRoute.of(context)?.isCurrent == true) {
                              Navigator.pop(context);
                            }
                          },
                        ),
                      )),
                ]);
              },
            ),
    );
  }
}

class _SharedDocument extends StatefulWidget {
  const _SharedDocument({required this.note, super.key});
  final NoteModel note;

  @override
  State<_SharedDocument> createState() => _SharedDocumentState();
}

class _SharedDocumentState extends State<_SharedDocument> {
  quill.QuillController? _controller;

  @override
  void initState() {
    super.initState();
    try {
      _controller = quill.QuillController(
        document: DocumentCodec.decode(widget.note.content),
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
    } catch (_) {
      // Keep decisions and navigation available for malformed legacy content.
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final controller = _controller;
    final inline = controller == null
        ? <String>{}
        : NoteImageDocument.images(controller.document)
            .map((image) =>
                NoteImageDocument.canonicalReference(image.reference))
            .toSet();
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(note.title.isEmpty ? 'Untitled' : note.title,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
            'From ${note.ownerName.isEmpty ? note.ownerEmail : note.ownerName}'),
        const SizedBox(height: 8),
        const Text('Read-only · Accept to save an independent copy'),
        const SizedBox(height: 20),
        if (controller == null)
          const Text('This document could not be displayed.')
        else
          quill.QuillEditor.basic(
              controller: controller,
              config: const quill.QuillEditorConfig(
                scrollable: false,
                showCursor: false,
                enableInteractiveSelection: false,
                embedBuilders: [RichNoteEmbed()],
                unknownEmbedBuilder: RichNoteEmbed(),
              )),
        for (final attachment in note.attachments)
          if (!inline
              .contains(NoteImageDocument.attachmentReference(attachment)))
            NoteAttachment(attachment: attachment),
      ]),
    );
  }
}
