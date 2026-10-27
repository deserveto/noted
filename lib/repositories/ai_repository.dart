import 'dart:async';
import 'dart:math';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';
import 'paginated_query.dart';

class AiServiceException implements Exception {
  const AiServiceException(this.message, {this.code = 'internal'});
  final String code;
  final String message;

  @override
  String toString() => message;
}

class AiRepository {
  AiRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient? get _maybeClient =>
      _clientOverride ?? SupabaseService.maybeClient;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  String newId() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rng = Random.secure();
    return List.generate(20, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  Future<Map<String, dynamic>> ask({
    required String prompt,
    required Map<String, dynamic> scope,
    required String chatId,
    required String requestId,
    String? selection,
    String? selectionNoteId,
  }) async {
    try {
      return await SupabaseService.invokeFunction(
        'noted-ai',
        {
          'action': 'ask',
          'prompt': prompt,
          'scope': scope,
          'chatId': chatId,
          'requestId': requestId,
          'intent': detectIntent(prompt),
          if (selection != null &&
              selection.isNotEmpty &&
              selectionNoteId != null &&
              selectionNoteId.isNotEmpty) ...{
            'selection': selection,
            'selectionNoteId': selectionNoteId,
          },
        },
        clientOverride: _clientOverride,
      );
    } on BackendFunctionException catch (error) {
      throw AiServiceException(error.message, code: error.code);
    } on BackendNotConfiguredException catch (error) {
      throw AiServiceException(error.message, code: 'failed-precondition');
    }
  }

  Future<void> stop(String requestId) async {
    try {
      await SupabaseService.invokeFunction(
        'noted-ai',
        {
          'action': 'cancel',
          'requestId': requestId,
        },
        clientOverride: _clientOverride,
      );
    } on BackendFunctionException catch (error) {
      throw AiServiceException(error.message, code: error.code);
    }
  }

  Stream<List<Map<String, dynamic>>> history(String uid) {
    final client = _maybeClient;
    if (client == null || uid.isEmpty) {
      return Stream<List<Map<String, dynamic>>>.value(const []);
    }

    late final StreamController<List<Map<String, dynamic>>> controller;
    RealtimeChannel? channel;

    Future<void> refresh() async {
      try {
        final rows = await fetchAllPages((start, end) => client
            .from('ai_chats')
            .select()
            .eq('user_id', uid)
            .order('updated_at', ascending: false)
            .order('chat_id')
            .range(start, end));

        if (!controller.isClosed) {
          controller.add(
            rows.map((raw) {
              final r = Map<String, dynamic>.from(raw);
              return <String, dynamic>{
                'id': r['chat_id']?.toString() ?? '',
                'title': r['title']?.toString() ?? 'New chat',
                'scope': r['scope'] is Map
                    ? Map<String, dynamic>.from(r['scope'] as Map)
                    : const {'kind': 'all'},
                'updatedAt': r['updated_at'],
              };
            }).toList(),
          );
        }
      } catch (err) {
        if (!controller.isClosed) {
          controller.addError(err);
        }
      }
    }

    controller = StreamController<List<Map<String, dynamic>>>(
      onListen: () {
        refresh();
        channel = client
            .channel('ai-chats-$uid-${identityHashCode(controller)}')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'ai_chats',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: uid,
              ),
              callback: (_) => refresh(),
            )
            .subscribe();
      },
      onCancel: () async {
        if (channel != null) {
          await client.removeChannel(channel!);
        }
      },
    );

    return controller.stream;
  }

  Future<List<Map<String, dynamic>>> messages(
    String uid,
    String chatId,
  ) async {
    final rows = await fetchAllPages((start, end) => _client
        .from('ai_messages')
        .select()
        .eq('user_id', uid)
        .eq('chat_id', chatId)
        .order('created_at', ascending: true)
        .order('id')
        .range(start, end));

    var prompt = '';
    return rows.map((raw) {
      final data = Map<String, dynamic>.from(raw);
      if (data['role'] == 'user') {
        prompt = data['text'] as String? ?? '';
      }
      return <String, dynamic>{
        ...data,
        'id': data['id']?.toString() ?? '',
        if (data['role'] == 'ai') 'prompt': prompt,
      };
    }).toList();
  }

  Future<void> rename(String uid, String chatId, String title) async {
    await _client
        .from('ai_chats')
        .update({'title': title})
        .eq('user_id', uid)
        .eq('chat_id', chatId);
  }

  Future<void> feedback(
    String uid,
    String chatId,
    String messageId,
    String? value,
  ) async {
    await _client
        .from('ai_messages')
        .update({'fb': value})
        .eq('user_id', uid)
        .eq('chat_id', chatId)
        .eq('id', messageId);
  }
}

String detectIntent(String prompt) {
  final p = prompt.toLowerCase();
  for (final (pattern, intent) in <(String, String)>[
    (r'flash ?card', 'flashcards'),
    (r'study guide|revision|revise|exam prep', 'guide'),
    (r'summar|tl;?dr|ringkas|key points', 'summary'),
    (r'question|quiz|test me|soal', 'questions'),
    (r'action|to-?do|tasks?\b|open items|deadline', 'actions'),
    (r'related|similar|connect|link|terkait', 'related'),
    (r'organi[sz]e|group|tidy|clean up|structure', 'organize'),
    (
      r'explain|understand|what is|what are|how does|why does|jelaskan|selected',
      'explain'
    )
  ]) {
    if (RegExp(pattern).hasMatch(p)) return intent;
  }
  return 'ask';
}

String blocksMarkdown(List<dynamic> blocks) => blocks.whereType<Map>().map((b) {
      final t = b['t'];
      if (t == 'h') return '### ${b['x']}';
      if (t == 'p') return '${b['x']}';
      if (t == 'quote') return '> ${b['x']}';
      if (t == 'cards') {
        final cardList = (b['items'] ?? b['cards']) as List? ?? const [];
        return cardList
            .whereType<Map>()
            .map((c) => '**${c['q']}**\n${c['a']}')
            .join('\n\n');
      }
      final rawItems = b['items'] as List? ?? const [];
      final items = rawItems
          .map((e) => e is Map ? (e['x']?.toString() ?? '') : e.toString())
          .where((s) => s.isNotEmpty)
          .toList();
      return items
          .asMap()
          .entries
          .map((e) =>
              '${t == 'ol' ? '${e.key + 1}.' : t == 'todo' ? '- [ ]' : '-'} ${e.value}')
          .join('\n');
    }).join('\n\n');
