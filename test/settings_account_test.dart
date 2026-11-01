import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noted/models/settings_model.dart';
import 'package:noted/models/note_model.dart';
import 'package:noted/repositories/settings_repository.dart';
import 'package:noted/viewmodels/settings_viewmodel.dart';
import 'package:noted/services/account_services.dart';

class MemorySettings extends SettingsRepository {
  final controller = StreamController<SettingsModel>.broadcast();
  final users = <String, SettingsModel>{};
  bool fail = false;
  @override
  Stream<SettingsModel> watch(String uid) => controller.stream;
  @override
  Future<void> save(String uid, SettingsModel settings,
      {Map<String, dynamic>? changes}) async {
    await cache(uid, settings);
    if (fail) throw StateError('offline');
    users[uid] = (users[uid] ?? const SettingsModel())
        .merge(changes ?? settings.toMap());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('preferences survive new repository and remain isolated per account',
      () async {
    final repository = SettingsRepository();
    await repository.cache('alice',
        const SettingsModel(theme: 'dark', textSize: 19, requests: 'nobody'));
    final restored = await SettingsRepository().cached('alice');
    expect(restored.theme, 'dark');
    expect(restored.textSize, 19);
    expect(restored.requests, 'nobody');
    expect((await repository.cached('bob')).theme, 'light');
  });
  test('optimistic preferences remain cached if remote persistence fails',
      () async {
    final repository = MemorySettings()..fail = true;
    final vm = SettingsViewModel(repository)..bindUser('alice');
    await Future<void>.delayed(Duration.zero);
    final result = vm.update({'weekStart': 'sun', 'presence': false});
    expect(vm.settings.weekStart, 'sun');
    expect(await result, false);
    expect(vm.errorMessage, isNotNull);
    expect((await repository.cached('alice')).presence, false);
    vm.bindUser('bob');
    expect(vm.settings.weekStart, 'mon');
    vm.dispose();
    await repository.controller.close();
  });
  test(
      'independent device preference updates do not overwrite unrelated settings',
      () async {
    final repository = MemorySettings();
    final first = SettingsViewModel(repository)..bindUser('alice');
    final second = SettingsViewModel(repository)..bindUser('alice');
    await Future<void>.delayed(Duration.zero);
    await first.update({'theme': 'dark'});
    await second.update({'textSize': 19});
    expect(repository.users['alice']!.theme, 'dark');
    expect(repository.users['alice']!.textSize, 19);
    first.dispose();
    second.dispose();
    await repository.controller.close();
  });
  test('reset persists complete defaults without losing other account data',
      () async {
    final repository = MemorySettings();
    final vm = SettingsViewModel(repository)..bindUser('alice');
    await Future<void>.delayed(Duration.zero);
    await vm.update({'theme': 'dark', 'appLock': true});
    expect(await vm.reset(), true);
    expect(repository.users['alice']!.toMap(), const SettingsModel().toMap());
    vm.dispose();
    await repository.controller.close();
  });
  test(
      'export renders rich document operations instead of serializing the envelope',
      () {
    final content = jsonEncode({
      'notedDocument': 1,
      'ops': [
        {'insert': 'Hello '},
        {
          'insert': 'world',
          'attributes': {'bold': true}
        },
        {'insert': '\n'}
      ]
    });
    final note = NoteModel.empty('alice').copyWith(content: content);
    final output =
        jsonDecode(ExportService.encode([note])) as Map<String, dynamic>;
    final html = ((output['notes'] as List).single
        as Map<String, dynamic>)['html'] as String;
    expect(html, contains('Hello'));
    expect(html, contains('world'));
    expect(html, contains('<strong>'));
    expect(html, isNot(contains('notedDocument')));
  });
  test('export emits parseable versioned JSON and UTC dates', () {
    final date = DateTime.utc(2026, 10, 26, 8);
    final note = NoteModel.empty('alice').copyWith(
        noteId: 'one',
        title: 'A note',
        content: '<p>Hello</p>',
        createdAt: date,
        updatedAt: date);
    final encoded = jsonDecode(ExportService.encode([note], exportedAt: date))
        as Map<String, dynamic>;
    expect(encoded['formatVersion'], 1);
    expect(encoded.keys.toSet(), {'formatVersion', 'exportedAt', 'notes'});
    expect(encoded['exportedAt'], '2026-10-26T08:00:00.000Z');
    final row = (encoded['notes'] as List).single as Map<String, dynamic>;
    expect(row['title'], 'A note');
    expect((row['html'] as String).trim(), '<p>Hello</p>');
    expect(row['created'], '2026-10-26T08:00:00.000Z');
  });
  test('v2 backup includes personal workspaces, assignments and saved decks',
      () {
    final date = DateTime.utc(2026, 10, 26, 8);
    final note = NoteModel.empty('alice').copyWith(noteId: 'note-1');
    final encoded = jsonDecode(ExportService.encode(
      [note],
      exportedAt: date,
      collections: ExportCollections(
        workspaces: [
          {'id': 'workspace-1', 'name': 'Work', 'user_id': 'private-user-id'}
        ],
        workspaceAssignments: [
          {
            'note_id': 'note-1',
            'workspace_id': 'workspace-1',
            'user_id': 'private-user-id'
          }
        ],
        studyDecks: [
          {
            'id': 'deck-1',
            'title': 'Biology',
            'cards': [
              {'q': 'What is a cell?', 'a': 'The basic unit of life.'}
            ],
            'source_note_id': 'note-1',
            'created_at': date,
            'updated_at': date,
            'user_id': 'private-user-id'
          }
        ],
      ),
    )) as Map<String, dynamic>;

    expect(encoded['formatVersion'], 2);
    expect(encoded['exportCollectionsComplete'], isTrue);
    expect(encoded['unavailableSections'], isEmpty);
    expect(encoded['workspaces'], [
      {'id': 'workspace-1', 'name': 'Work'}
    ]);
    expect(encoded['workspaceAssignments'], [
      {'noteId': 'note-1', 'workspaceId': 'workspace-1'}
    ]);
    expect(encoded['studyDecks'], [
      {
        'id': 'deck-1',
        'title': 'Biology',
        'cards': [
          {'q': 'What is a cell?', 'a': 'The basic unit of life.'}
        ],
        'sourceNoteId': 'note-1',
        'createdAt': '2026-10-26T08:00:00.000Z',
        'updatedAt': '2026-10-26T08:00:00.000Z',
      }
    ]);
    expect(jsonEncode(encoded), isNot(contains('private-user-id')));
  });
  test('partial backup names unavailable sections and retains note export', () {
    final note = NoteModel.empty('alice').copyWith(noteId: 'note-1');
    final encoded = jsonDecode(ExportService.encode(
      [note],
      collections: const ExportCollections(
        workspaces: [],
        workspaceAssignments: [],
        studyDecks: [],
        unavailableSections: ['studyDecks'],
      ),
    )) as Map<String, dynamic>;

    expect(encoded['exportCollectionsComplete'], isFalse);
    expect(encoded['unavailableSections'], ['studyDecks']);
    expect((encoded['notes'] as List).length, 1);
    expect(encoded['studyDecks'], isEmpty);
  });
}
