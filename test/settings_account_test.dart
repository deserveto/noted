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
    expect(encoded['exportedAt'], '2026-10-26T08:00:00.000Z');
    final row = (encoded['notes'] as List).single as Map<String, dynamic>;
    expect(row['title'], 'A note');
    expect((row['html'] as String).trim(), '<p>Hello</p>');
    expect(row['created'], '2026-10-26T08:00:00.000Z');
  });
}
