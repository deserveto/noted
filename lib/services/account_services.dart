import 'dart:convert';

import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note_model.dart';
import '../utils/document_codec.dart';
import 'supabase_service.dart';

/// Export only notes the signed-in user can read; no private profile data is included.
class ExportService {
  static String encode(Iterable<NoteModel> notes, {DateTime? exportedAt}) =>
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': 1,
        'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'notes': notes
            .map((note) => {
                  'id': note.noteId,
                  'title': note.title,
                  'html': DocumentCodec.toHtml(note.content),
                  'category': note.category,
                  'favorite': note.isFavorite,
                  'color': note.color,
                  'created': note.createdAt.toUtc().toIso8601String(),
                  'edited': note.updatedAt.toUtc().toIso8601String(),
                  'attachments': _jsonValue(note.attachments),
                })
            .toList(),
      });

  static Object? _jsonValue(Object? value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return value
          .map((key, value) => MapEntry(key.toString(), _jsonValue(value)));
    }
    if (value is Iterable) return value.map(_jsonValue).toList();
    return value;
  }

  Future<void> share(Iterable<NoteModel> notes) async {
    final filename =
        'noted-export-${DateTime.now().toIso8601String().substring(0, 10)}.json';
    final String content;
    if (notes.length > 1000) {
      final result = await SupabaseService.invokeFunction(
        'account',
        const {'action': 'exportData'},
      );
      content = const JsonEncoder.withIndent('  ').convert(result);
    } else {
      content = encode(notes);
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            utf8.encode(content),
            mimeType: 'application/json',
            name: filename,
          ),
        ],
        fileNameOverrides: [filename],
        subject: 'Noted notes export',
      ),
    );
  }
}

class AppLockService {
  AppLockService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  Future<bool> authenticate() async {
    if (!await _auth.isDeviceSupported()) {
      throw StateError(
        'Set up a fingerprint, face unlock or device PIN in your device settings first.',
      );
    }
    return _auth.authenticate(
      localizedReason: 'Unlock your Noted notes',
      persistAcrossBackgrounding: true,
    );
  }
}

Future<void> clearNotedAIHistory() async {
  await SupabaseService.invokeFunction(
    'noted-ai',
    const {'action': 'clearHistory'},
  );
}
