import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import 'package:noted/models/note_model.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/models/user_model.dart';
import 'package:noted/repositories/auth_repository.dart';
import 'package:noted/repositories/note_repository.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/services/attachment_service.dart';
import 'package:noted/services/media_url_resolver.dart';
import 'package:noted/utils/app_theme.dart';
import 'package:noted/utils/document_codec.dart';
import 'package:noted/utils/note_image_document.dart';
import 'package:noted/viewmodels/auth_viewmodel.dart';
import 'package:noted/viewmodels/note_viewmodel.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/views/add_edit_note_page.dart';
import 'package:noted/widgets/note_attachments.dart';
import 'package:noted/widgets/rich_note_embed.dart';

const _imageRef = 'noted-media://note-media/users/owner/notes/note/1_photo.png';

String _richContent(List<Map<String, dynamic>> ops) =>
    DocumentCodec.encode(quill.Document.fromJson(ops));

String _twoParagraphs() => _richContent([
      {'insert': 'First paragraph\n'},
      {'insert': 'Second paragraph\n'},
    ]);

class _Repo extends Fake implements NoteRepository {
  _Repo(this.note);
  final NoteModel note;
  final updates = StreamController<NoteModel?>.broadcast();
  final saved = <NoteModel>[];
  Object? saveError;
  int savedCount = 0;

  @override
  Stream<NoteModel?> watchNote(String id) => updates.stream;

  @override
  Future<NoteModel> saveCollaborative(NoteModel local, NoteModel base) async {
    savedCount++;
    if (saveError != null) throw saveError!;
    final result = local.copyWith(
      revision: base.revision + 1,
      updatedAt: DateTime.now(),
    );
    saved.add(result);
    return result;
  }

  @override
  Future<String> createNote(NoteModel note) async {
    savedCount++;
    if (saveError != null) throw saveError!;
    saved.add(note);
    return 'note';
  }
}

class _AuthRepo extends Fake implements AuthRepository {}

class _Auth extends AuthViewModel {
  _Auth() : super(_AuthRepo());
  @override
  UserModel get user => UserModel(
      uid: 'owner',
      name: 'Alex',
      email: 'alex@example.test',
      createdAt: DateTime(2026));
}

class _Settings extends SettingsViewModel {
  _Settings() : super(SettingsRepository());
  @override
  SettingsModel get settings => const SettingsModel(reduceMotion: true);
}

class _FakeAttachments extends AttachmentService {
  final uploads = <String>[];
  final removed = <String>[];
  Completer<Map<String, dynamic>>? pending;
  Object? error;

  @override
  Future<Map<String, dynamic>> upload({
    required String noteId,
    required Uint8List bytes,
    required String type,
    required String name,
    required String contentType,
    int? duration,
  }) async {
    uploads.add(type);
    if (error != null) throw error!;
    if (pending != null) return pending!.future;
    return {
      'type': type,
      'name': name,
      'path': 'users/owner/notes/$noteId/1_photo.png',
      'url': _imageRef,
    };
  }

  @override
  Future<void> remove(String objectPath) async {
    removed.add(objectPath);
  }
}

class _Picker {
  XFile? file;
  Completer<XFile?>? pending;
  int calls = 0;

  Future<XFile?> call() {
    calls++;
    if (pending != null) return pending!.future;
    return Future.value(file);
  }
}

class _Harness {
  _Harness({
    required this.auth,
    required this.notes,
    required this.settings,
    required this.repo,
    required this.attachments,
  });

  final _Auth auth;
  final NoteViewModel notes;
  final _Settings settings;
  final _Repo repo;
  final _FakeAttachments attachments;
  final _Picker picker = _Picker();

  void dispose() {
    auth.dispose();
    notes.dispose();
    settings.dispose();
    repo.updates.close();
  }
}

_Harness _harness(NoteModel note) {
  final repo = _Repo(note);
  final attachments = _FakeAttachments();
  return _Harness(
    auth: _Auth(),
    notes: NoteViewModel(repo),
    settings: _Settings(),
    repo: repo,
    attachments: attachments,
  );
}

Future<void> _pumpEditor(
  WidgetTester tester,
  _Harness harness,
  NoteModel note, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewModel>.value(value: harness.auth),
      ChangeNotifierProvider<NoteViewModel>.value(value: harness.notes),
      ChangeNotifierProvider<SettingsViewModel>.value(value: harness.settings),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      localizationsDelegates: const [quill.FlutterQuillLocalizations.delegate],
      home: AddEditNotePage(
        note: note,
        repository: harness.repo,
        attachmentService: harness.attachments,
        pickImage: harness.picker.call,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

quill.QuillController _controller(WidgetTester tester) =>
    tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor)).controller;

Future<void> _focusEditor(WidgetTester tester, quill.QuillController controller,
    {int offset = 0}) async {
  final editor =
      tester.widget<quill.QuillEditor>(find.byType(quill.QuillEditor));
  editor.focusNode.requestFocus();
  controller.updateSelection(
      TextSelection.collapsed(offset: offset), quill.ChangeSource.local);
  await tester.pump();
}

Future<void> _addImage(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Add image'));
  await tester.pump();
  await tester.pumpAndSettle();
}

XFile _file() => XFile.fromData(
      Uint8List.fromList([1, 2, 3]),
      name: 'photo.png',
      mimeType: 'image/png',
    );

void main() {
  setUp(() {
    MediaUrlResolver.clearCache();
    MediaUrlResolver.setSignerForTesting(
        (bucket, path) async => 'https://example.test/$bucket/$path');
  });

  tearDown(() {
    MediaUrlResolver.setSignerForTesting(null);
    MediaUrlResolver.clearCache();
  });

  testWidgets('image inserts before, between and after paragraphs',
      (tester) async {
    for (final (label, offset, expectedIndex) in [
      ('before', 0, 0),
      ('between', 'First paragraph\n'.length, 'First paragraph\n'.length),
      (
        'after',
        'First paragraph\nSecond paragraph'.length,
        'First paragraph\nSecond paragraph'.length
      ),
    ]) {
      final note = NoteModel.empty('owner')
          .copyWith(noteId: 'note', content: _twoParagraphs());
      final harness = _harness(note);
      harness.picker.file = _file();
      addTearDown(harness.dispose);
      await _pumpEditor(tester, harness, note);
      final controller = _controller(tester);
      await _focusEditor(tester, controller, offset: offset);
      await _addImage(tester);

      final images = NoteImageDocument.images(controller.document);
      expect(images, hasLength(1), reason: label);
      expect(images.single.index, expectedIndex, reason: label);
      expect(images.single.reference, _imageRef, reason: label);
      expect(controller.document.toPlainText().replaceAll('\uFFFC', '').trim(),
          'First paragraph\nSecond paragraph',
          reason: label);
      expect(find.byType(NoteImageEmbed), findsOneWidget, reason: label);
      Finder paragraph(String text) => find.byWidgetPredicate((widget) =>
          widget is RichText && widget.text.toPlainText().contains(text));
      final imageOrigin = tester.getTopLeft(find.byType(NoteImageEmbed));
      final firstOrigin = tester.getTopLeft(paragraph('First paragraph'));
      final secondOrigin = tester.getTopLeft(paragraph('Second paragraph'));
      switch (label) {
        case 'before':
          expect(imageOrigin.dy, lessThanOrEqualTo(firstOrigin.dy + 1));
          expect(imageOrigin.dx, lessThanOrEqualTo(firstOrigin.dx));
        case 'between':
          expect(imageOrigin.dy, greaterThan(firstOrigin.dy));
          expect(imageOrigin.dy, lessThanOrEqualTo(secondOrigin.dy + 1));
        case 'after':
          expect(imageOrigin.dy, greaterThanOrEqualTo(secondOrigin.dy - 1));
          expect(imageOrigin.dx, greaterThan(secondOrigin.dx));
      }
      expect(harness.attachments.uploads, ['image'], reason: label);
      expect(harness.repo.saved.last.content, contains('"image"'),
          reason: label);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('new image move is one undoable document change', (tester) async {
    final note = NoteModel.empty('owner')
        .copyWith(noteId: 'note', content: _twoParagraphs());
    final harness = _harness(note);
    harness.picker.file = _file();
    addTearDown(harness.dispose);
    await _pumpEditor(tester, harness, note);
    final controller = _controller(tester);
    await _focusEditor(tester, controller);
    await _addImage(tester);
    // Close Quill's 400 ms history window so the move is its own undo entry.
    controller.document.history.lastRecorded = 0;

    await tester.tap(find.byTooltip('Move image'));
    await tester.pumpAndSettle();
    expect(find.text('Tap in the note where the image should go.'),
        findsOneWidget);

    controller.updateSelection(
        const TextSelection.collapsed(offset: 8), quill.ChangeSource.local);
    await tester.pump();
    expect(find.text('Move here'), findsOneWidget);
    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();

    final images = NoteImageDocument.images(controller.document);
    expect(images, hasLength(1));
    expect(images.single.index, 7);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', '').trim(),
        'First paragraph\nSecond paragraph');

    controller.undo();
    await tester.pump();
    expect(NoteImageDocument.images(controller.document).single.index, 0);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', '').trim(),
        'First paragraph\nSecond paragraph');

    controller.redo();
    await tester.pump();
    expect(NoteImageDocument.images(controller.document).single.index, 7);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', '').trim(),
        'First paragraph\nSecond paragraph');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('legacy trailing image moves inline and undo restores it',
      (tester) async {
    final note = NoteModel.empty('owner').copyWith(
      noteId: 'note',
      content: _twoParagraphs(),
      attachments: [
        {
          'type': 'image',
          'name': 'photo.png',
          'path': 'users/owner/notes/note/1_photo.png',
          'url': _imageRef,
        }
      ],
    );
    final harness = _harness(note);
    addTearDown(harness.dispose);
    await _pumpEditor(tester, harness, note);
    final controller = _controller(tester);
    expect(find.byType(NoteAttachment), findsOneWidget);

    await tester.tap(find.byTooltip('Move image into note'));
    await tester.pumpAndSettle();
    controller.updateSelection(
        const TextSelection.collapsed(offset: 8), quill.ChangeSource.local);
    await tester.pump();
    await tester.tap(find.text('Move here'));
    await tester.pumpAndSettle();

    expect(NoteImageDocument.images(controller.document), hasLength(1));
    expect(find.byType(NoteImageEmbed), findsOneWidget);
    expect(find.byType(NoteAttachment), findsNothing);
    expect(harness.repo.saved.last.attachments, hasLength(1));

    controller.undo();
    await tester.pump();
    expect(NoteImageDocument.images(controller.document), isEmpty);
    expect(find.byType(NoteAttachment), findsOneWidget);
    expect(find.byType(NoteImageEmbed), findsNothing);

    controller.redo();
    await tester.pump();
    expect(NoteImageDocument.images(controller.document), hasLength(1));
    expect(find.byType(NoteImageEmbed), findsOneWidget);
    expect(find.byType(NoteAttachment), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('typing before and at the anchor keeps the insertion position',
      (tester) async {
    final note = NoteModel.empty('owner')
        .copyWith(noteId: 'note', content: _twoParagraphs());
    final harness = _harness(note);
    final attachments = harness.attachments..pending = Completer();
    harness.picker.file = _file();
    addTearDown(harness.dispose);
    await _pumpEditor(tester, harness, note);
    final controller = _controller(tester);
    await _focusEditor(tester, controller, offset: 'First paragraph\n'.length);
    await tester.tap(find.byTooltip('Add image'));
    await tester.pump();
    await tester.pump();
    expect(attachments.uploads, ['image']);
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    // Text typed before the anchor shifts it right. Text typed exactly at the
    // anchor stays after the intended insertion point.
    controller.replaceText(
        0, 0, 'Intro ', const TextSelection.collapsed(offset: 6));
    controller.updateSelection(
        const TextSelection.collapsed(offset: 22), quill.ChangeSource.local);
    await tester.pump();
    attachments.pending!.complete({
      'type': 'image',
      'name': 'photo.png',
      'path': 'users/owner/notes/note/1_photo.png',
      'url': _imageRef,
    });
    await tester.pumpAndSettle();

    final images = NoteImageDocument.images(controller.document);
    expect(images, hasLength(1));
    expect(
        controller.document.toPlainText(), contains('Intro First paragraph'));
    expect(images.single.index, 'Intro First paragraph\n'.length);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', '').trim(),
        'Intro First paragraph\nSecond paragraph');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('remote edit during upload rebases the insertion point',
      (tester) async {
    final note = NoteModel.empty('owner')
        .copyWith(noteId: 'note', content: _twoParagraphs());
    final harness = _harness(note);
    final attachments = harness.attachments..pending = Completer();
    final picker = harness.picker..pending = Completer();
    addTearDown(harness.dispose);
    await _pumpEditor(tester, harness, note);
    final controller = _controller(tester);
    await _focusEditor(tester, controller, offset: 'First paragraph\n'.length);
    await tester.tap(find.byTooltip('Add image'));
    await tester.pump();
    expect(picker.calls, 1);

    harness.repo.updates.add(note.copyWith(
      revision: 1,
      content: _richContent([
        {'insert': 'Remote intro\n'},
        {'insert': 'First paragraph\n'},
        {'insert': 'Second paragraph\n'},
      ]),
    ));
    await tester.pumpAndSettle();
    expect(controller.document.toPlainText(), contains('Remote intro'));
    expect(attachments.uploads, isEmpty);
    picker.pending!.complete(_file());
    await tester.pump();
    await tester.pump();
    attachments.pending!.complete({
      'type': 'image',
      'name': 'photo.png',
      'path': 'users/owner/notes/note/1_photo.png',
      'url': _imageRef,
    });
    await tester.pumpAndSettle();

    final images = NoteImageDocument.images(controller.document);
    expect(images, hasLength(1));
    expect(images.single.index, 'Remote intro\nFirst paragraph\n'.length);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', '').trim(),
        'Remote intro\nFirst paragraph\nSecond paragraph');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('canceled picker, upload error and save error add nothing',
      (tester) async {
    final note = NoteModel.empty('owner')
        .copyWith(noteId: 'note', content: _twoParagraphs());

    // Canceled picker.
    var harness = _harness(note);
    final picker = harness.picker;
    await _pumpEditor(tester, harness, note);
    var controller = _controller(tester);
    await _focusEditor(tester, controller);
    await _addImage(tester);
    expect(picker.calls, 1);
    expect(harness.attachments.uploads, isEmpty);
    expect(NoteImageDocument.images(controller.document), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();

    // Upload error.
    harness = _harness(note);
    harness.attachments.error = StateError('upload failed');
    harness.picker.file = _file();
    await _pumpEditor(tester, harness, note);
    controller = _controller(tester);
    await _focusEditor(tester, controller);
    await _addImage(tester);
    expect(NoteImageDocument.images(controller.document), isEmpty);
    expect(find.textContaining('upload failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();

    // Save error before upload. A new note must be created before its media
    // can be uploaded, so the failed create cancels the upload.
    final draft = NoteModel.empty('owner').copyWith(
      content: _twoParagraphs(),
    );
    harness = _harness(draft);
    harness.repo.saveError = StateError('save failed');
    harness.picker.file = _file();
    await _pumpEditor(tester, harness, draft);
    controller = _controller(tester);
    await _focusEditor(tester, controller);
    await _addImage(tester);
    expect(harness.attachments.uploads, isEmpty);
    expect(NoteImageDocument.images(controller.document), isEmpty);
    expect(find.textContaining('save failed'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    harness.dispose();
  });

  testWidgets('disposing during upload writes no image and removes the blob',
      (tester) async {
    final note = NoteModel.empty('owner')
        .copyWith(noteId: 'note', content: _twoParagraphs());
    final harness = _harness(note);
    final attachments = harness.attachments..pending = Completer();
    harness.picker.file = _file();
    addTearDown(harness.dispose);
    await _pumpEditor(tester, harness, note);
    final controller = _controller(tester);
    await _focusEditor(tester, controller);
    await tester.tap(find.byTooltip('Add image'));
    await tester.pump();
    await tester.pump();
    expect(attachments.uploads, ['image']);
    final savesBefore = harness.repo.saved.length;

    await tester.pumpWidget(const SizedBox.shrink());
    attachments.pending!.complete({
      'type': 'image',
      'name': 'photo.png',
      'path': 'users/owner/notes/note/1_photo.png',
      'url': _imageRef,
    });
    await tester.pump();
    await tester.pump();
    expect(attachments.removed, ['users/owner/notes/note/1_photo.png']);
    expect(harness.repo.saved.length, savesBefore);
    expect(controller.document.toPlainText(), isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied or revoked private media renders an unavailable image',
      (tester) async {
    MediaUrlResolver.setSignerForTesting((bucket, path) async {
      throw StateError('permission denied');
    });
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: NoteImageEmbed(
          reference: _imageRef,
          type: 'image',
          index: 0,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Image unavailable'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved image reopens at its document position', (tester) async {
    final note = NoteModel.empty('owner')
        .copyWith(noteId: 'note', content: _twoParagraphs());
    final harness = _harness(note);
    harness.picker.file = _file();
    addTearDown(harness.dispose);
    await _pumpEditor(tester, harness, note);
    var controller = _controller(tester);
    await _focusEditor(tester, controller, offset: 8);
    await _addImage(tester);
    final saved = harness.repo.saved.last;
    expect(NoteImageDocument.images(controller.document).single.index, 8);
    await tester.pumpWidget(const SizedBox.shrink());

    final reopened = _harness(saved);
    addTearDown(reopened.dispose);
    await _pumpEditor(tester, reopened, saved);
    controller = _controller(tester);
    expect(NoteImageDocument.images(controller.document).single.index, 8);
    expect(find.byType(NoteImageEmbed), findsOneWidget);
    expect(controller.document.toPlainText().replaceAll('\uFFFC', '').trim(),
        'First paragraph\nSecond paragraph');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
