import 'dart:convert';

import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';

import '../models/note_model.dart';
import '../repositories/paginated_query.dart';
import '../utils/document_codec.dart';
import 'supabase_service.dart';

class ExportCollections {
  const ExportCollections({
    this.workspaces = const [],
    this.workspaceAssignments = const [],
    this.studyDecks = const [],
    this.unavailableSections = const [],
  });

  final List<Map<String, dynamic>> workspaces;
  final List<Map<String, dynamic>> workspaceAssignments;
  final List<Map<String, dynamic>> studyDecks;
  final List<String> unavailableSections;
}

typedef ConfirmPartialExport = Future<bool> Function(
  List<String> unavailableSections,
);

/// Export readable notes and the signed-in user's private workspace/deck data.
class ExportService {
  static const _backupSections = [
    'workspaces',
    'workspaceAssignments',
    'studyDecks',
  ];

  static String encode(
    Iterable<NoteModel> notes, {
    DateTime? exportedAt,
    ExportCollections? collections,
  }) {
    final timestamp = (exportedAt ?? DateTime.now()).toUtc().toIso8601String();
    final output = <String, dynamic>{
      'formatVersion': collections == null ? 1 : 2,
      'exportedAt': timestamp,
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
    };

    if (collections != null) {
      final unavailable = _backupSections
          .where(collections.unavailableSections.contains)
          .toList();
      output.addAll({
        'workspaces': collections.workspaces.map(_workspaceJson).toList(),
        'workspaceAssignments':
            collections.workspaceAssignments.map(_assignmentJson).toList(),
        'studyDecks': collections.studyDecks.map(_deckJson).toList(),
        'exportCollectionsComplete': unavailable.isEmpty,
        'unavailableSections': unavailable,
      });
    }

    return const JsonEncoder.withIndent('  ').convert(output);
  }

  static Map<String, dynamic> _workspaceJson(Map<String, dynamic> workspace) =>
      {
        'id': workspace['id']?.toString() ?? '',
        'name': workspace['name']?.toString() ?? '',
      };

  static Map<String, dynamic> _assignmentJson(
          Map<String, dynamic> assignment) =>
      {
        'noteId':
            (assignment['noteId'] ?? assignment['note_id'])?.toString() ?? '',
        'workspaceId': (assignment['workspaceId'] ?? assignment['workspace_id'])
                ?.toString() ??
            '',
      };

  static Map<String, dynamic> _deckJson(Map<String, dynamic> deck) => {
        'id': deck['id']?.toString() ?? '',
        'title': deck['title']?.toString() ?? 'Flashcards',
        'cards': _jsonValue(deck['cards'] ?? const []),
        'sourceNoteId':
            (deck['sourceNoteId'] ?? deck['source_note_id'])?.toString(),
        'createdAt': _jsonTimestamp(deck['createdAt'] ?? deck['created_at']),
        'updatedAt': _jsonTimestamp(deck['updatedAt'] ?? deck['updated_at']),
      };

  static Object? _jsonTimestamp(Object? value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      return parsed?.toUtc().toIso8601String() ?? value;
    }
    return _jsonValue(value);
  }

  static Object? _jsonValue(Object? value) {
    if (value is DateTime) return value.toUtc().toIso8601String();
    if (value is Map) {
      return value
          .map((key, value) => MapEntry(key.toString(), _jsonValue(value)));
    }
    if (value is Iterable) return value.map(_jsonValue).toList();
    return value;
  }

  Future<void> share(
    Iterable<NoteModel> notes, {
    required ConfirmPartialExport confirmPartial,
  }) async {
    final noteList = notes.toList();
    late final String content;
    late final bool collectionsComplete;
    if (noteList.length > 1000) {
      final result = await SupabaseService.invokeFunction(
        'account',
        const {'action': 'exportData'},
      );
      final normalized = _normalizeRemoteBackup(result);
      collectionsComplete = normalized['exportCollectionsComplete'] as bool;
      if (collectionsComplete) {
        content = const JsonEncoder.withIndent('  ').convert(normalized);
      } else {
        final shouldContinue = await confirmPartial(
          List<String>.from(normalized['unavailableSections'] as List),
        );
        if (!shouldContinue) return;
        final noteOnly = result['formatVersion'] == 2
            ? {
                'formatVersion': 1,
                'exportedAt': result['exportedAt'],
                'notes': result['notes'],
              }
            : result;
        content = const JsonEncoder.withIndent('  ').convert(noteOnly);
      }
    } else {
      final collections = await _loadCollections(noteList);
      collectionsComplete = collections.unavailableSections.isEmpty;
      if (collectionsComplete) {
        content = encode(noteList, collections: collections);
      } else {
        final unavailable = _backupSections
            .where(collections.unavailableSections.contains)
            .toList();
        final shouldContinue = await confirmPartial(unavailable);
        if (!shouldContinue) return;
        content = encode(noteList);
      }
    }
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final filename =
        'noted-export-$date${collectionsComplete ? '' : '-partial'}.json';
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
        subject: collectionsComplete
            ? 'Noted notes export'
            : 'Noted notes export (partial)',
      ),
    );
  }

  static Future<ExportCollections> _loadCollections(
      List<NoteModel> notes) async {
    final client = SupabaseService.maybeClient;
    final uid = client?.auth.currentUser?.id;
    if (client == null || uid == null) {
      return const ExportCollections(unavailableSections: _backupSections);
    }

    final unavailable = <String>[];
    Future<List<Map<String, dynamic>>> readRows(
      String section,
      Future<List<dynamic>> Function() query,
    ) async {
      try {
        return (await query())
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      } catch (_) {
        unavailable.add(section);
        return const [];
      }
    }

    final results = await Future.wait([
      readRows(
        'workspaces',
        () => fetchAllPages((start, end) => client
            .from('personal_workspaces')
            .select('id, name')
            .eq('user_id', uid)
            .order('id')
            .range(start, end)),
      ),
      readRows(
        'workspaceAssignments',
        () => fetchAllPages((start, end) => client
            .from('personal_workspace_notes')
            .select('note_id, workspace_id')
            .eq('user_id', uid)
            .order('note_id')
            .range(start, end)),
      ),
      readRows(
        'studyDecks',
        () => fetchAllPages((start, end) => client
            .from('ai_flashcard_decks')
            .select('id, title, cards, source_note_id, created_at, updated_at')
            .eq('user_id', uid)
            .order('id')
            .range(start, end)),
      ),
    ]);

    final noteIds = notes.map((note) => note.noteId).toSet();
    final assignments = results[1]
        .where((row) => noteIds.contains(row['note_id']?.toString()))
        .toList();
    return ExportCollections(
      workspaces: results[0],
      workspaceAssignments: assignments,
      studyDecks: results[2],
      unavailableSections: unavailable,
    );
  }

  static Map<String, dynamic> _normalizeRemoteBackup(
      Map<String, dynamic> result) {
    final output = Map<String, dynamic>.from(result);
    if (output['notes'] is! List) {
      throw StateError('The server returned an incomplete notes export.');
    }
    final unavailable = <String>{};
    if (output['formatVersion'] != 2 ||
        output['unavailableSections'] is! List ||
        output['exportCollectionsComplete'] is! bool) {
      unavailable.addAll(_backupSections);
    }
    final remoteUnavailable = output['unavailableSections'];
    if (remoteUnavailable is List) {
      for (final value in remoteUnavailable) {
        final section = value.toString();
        if (_backupSections.contains(section)) {
          unavailable.add(section);
        } else {
          unavailable.addAll(_backupSections);
        }
      }
    }
    for (final section in _backupSections) {
      if (output[section] is! List) {
        output[section] = const [];
        unavailable.add(section);
      }
    }
    if (output['exportCollectionsComplete'] == false && unavailable.isEmpty) {
      unavailable.addAll(_backupSections);
    }

    final orderedUnavailable =
        _backupSections.where(unavailable.contains).toList();
    output['formatVersion'] = 2;
    output['exportCollectionsComplete'] = orderedUnavailable.isEmpty &&
        output['exportCollectionsComplete'] != false;
    output['unavailableSections'] = orderedUnavailable;
    return output;
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
