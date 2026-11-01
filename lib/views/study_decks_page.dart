import 'package:flutter/material.dart';
import '../services/supabase_service.dart';
import '../widgets/ai_blocks.dart';

class StudyDecksPage extends StatefulWidget {
  const StudyDecksPage({super.key});
  @override
  State<StudyDecksPage> createState() => _StudyDecksPageState();
}

class _StudyDecksPageState extends State<StudyDecksPage> {
  List<Map<String, dynamic>>? _decks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final client = SupabaseService.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) throw StateError('Please sign in to view your decks.');
      final rows = await client
          .from('ai_flashcard_decks')
          .select()
          .eq('user_id', uid)
          .order('updated_at', ascending: false);
      if (mounted) {
        setState(() {
          _decks = List<Map<String, dynamic>>.from(rows);
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Could not load decks. Check your connection and try again.');
      }
    }
  }

  Future<void> _rename(Map<String, dynamic> deck) async {
    final controller =
        TextEditingController(text: deck['title'] as String? ?? 'Flashcards');
    final title = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Rename deck'),
                content: TextField(
                    controller: controller, maxLength: 200, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(ctx, controller.text.trim()),
                      child: const Text('Save'))
                ]));
    controller.dispose();
    if (title == null || title.isEmpty) return;
    try {
      await SupabaseService.client.from('ai_flashcard_decks').update({
        'title': title,
        'updated_at': DateTime.now().toUtc().toIso8601String()
      }).eq('id', deck['id']);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not rename deck.')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> deck) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete deck?'),
                content: const Text('This permanently deletes the deck.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (ok != true) return;
    try {
      await SupabaseService.client
          .from('ai_flashcard_decks')
          .delete()
          .eq('id', deck['id']);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete deck.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Study decks')),
      body: _error != null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(_error!),
              TextButton(onPressed: _load, child: const Text('Try again'))
            ]))
          : _decks == null
              ? const Center(child: CircularProgressIndicator())
              : _decks!.isEmpty
                  ? const Center(
                      child: Text('Saved flashcards will appear here.'))
                  : ListView(children: [
                      for (final deck in _decks!)
                        ListTile(
                            title:
                                Text(deck['title'] as String? ?? 'Flashcards'),
                            subtitle:
                                Text('${(deck['cards'] as List).length} cards'),
                            onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute<void>(
                                    builder: (_) => Scaffold(
                                        appBar: AppBar(
                                            title: Text(
                                                deck['title'] as String? ??
                                                    'Flashcards')),
                                        body: Padding(
                                            padding: const EdgeInsets.all(24),
                                            child: Flashcards(
                                                cards: (deck['cards'] as List)
                                                    .whereType<Map>()
                                                    .map((e) =>
                                                        Map<String, dynamic>.from(e))
                                                    .toList()))))),
                            trailing: PopupMenuButton<String>(
                                onSelected: (action) => action == 'rename' ? _rename(deck) : _delete(deck),
                                itemBuilder: (_) => const [
                                      PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename')),
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('Delete'))
                                    ]))
                    ]));
}
