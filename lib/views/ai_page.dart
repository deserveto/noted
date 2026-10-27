import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/note_model.dart';
import '../repositories/ai_repository.dart';
import '../utils/app_colors.dart';
import '../utils/note_navigation.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../widgets/empty_state.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';
import '../widgets/ai_blocks.dart';

class AiPage extends StatefulWidget {
  const AiPage(
      {super.key,
      this.initialNoteIds,
      this.initialPrompt,
      this.initialScope,
      this.selection,
      this.selectionNoteId,
      this.onInsert,
      this.compact = false,
      this.repository});
  final AiRepository? repository;
  final List<String>? initialNoteIds;
  final String? initialPrompt, selection, selectionNoteId;
  final Map<String, dynamic>? initialScope;
  final ValueChanged<String>? onInsert;
  final bool compact;
  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  late final AiRepository _repo;
  final _text = TextEditingController(), _scroll = ScrollController();
  late String _chatId;
  late Map<String, dynamic> _scope;
  final List<Map<String, dynamic>> _messages = [];
  bool _busy = false, _historyEnabled = true;
  String? _requestId, _error, _lastPrompt;
  int _generation = 0;
  int? _historyEpoch;
  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? AiRepository();
    _chatId = _repo.newId();
    _scope = widget.initialScope ??
        (widget.initialNoteIds == null
            ? {'kind': 'all'}
            : {'kind': 'notes', 'ids': widget.initialNoteIds});
    if (widget.initialPrompt?.trim().isNotEmpty == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _send(widget.initialPrompt!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final preferences = context.watch<SettingsViewModel>();
    final history = preferences.settings.aiHistory;
    final cleared =
        _historyEpoch != null && _historyEpoch != preferences.aiHistoryEpoch;
    _historyEpoch = preferences.aiHistoryEpoch;
    if (cleared || (_historyEnabled && !history)) {
      _generation++;
      _busy = false;
      _requestId = null;
      _error = null;
      _lastPrompt = null;
      _messages.clear();
      _chatId = _repo.newId();
    }
    _historyEnabled = history;
  }

  @override
  void dispose() {
    if (_requestId != null) {
      _repo.stop(_requestId!).catchError((Object _) {});
    }
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  List<NoteModel> _pool(List<NoteModel> notes) => switch (_scope['kind']) {
        'fav' => notes.where((n) => n.isFavorite).toList(),
        'cat' => notes.where((n) => n.category == _scope['cat']).toList(),
        'notes' => notes
            .where((n) => (_scope['ids'] as List? ?? []).contains(n.noteId))
            .toList(),
        _ => notes
      };
  String _scopeLabel(List<NoteModel> notes) {
    if (_scope['kind'] == 'fav') return 'Favorites';
    if (_scope['kind'] == 'cat') return '${_scope['cat']} notes';
    if (_scope['kind'] == 'notes') {
      final ids = _scope['ids'] as List? ?? [];
      if (ids.length == 1) {
        final n = notes.where((n) => n.noteId == ids.first);
        return widget.compact
            ? 'This note'
            : n.isEmpty
                ? 'Selected note'
                : n.first.title.isEmpty
                    ? 'Untitled'
                    : n.first.title;
      }
      return '${ids.length} notes';
    }
    return 'All notes';
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 220),
            curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send(String raw, {bool retry = false}) async {
    final prompt = raw.trim();
    if (prompt.isEmpty || _busy) return;
    final generation = ++_generation, request = _repo.newId();
    setState(() {
      _busy = true;
      _requestId = request;
      _error = null;
      _lastPrompt = prompt;
      if (!retry) _messages.add({'role': 'user', 'text': prompt});
      _text.clear();
    });
    _toBottom();
    try {
      final answer = await _repo.ask(
          prompt: prompt,
          scope: _scope,
          chatId: _chatId,
          requestId: request,
          selection: widget.selection,
          selectionNoteId: widget.selectionNoteId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _messages.add({
          ...answer,
          'role': 'ai',
          'id': answer['messageId'],
          'prompt': prompt
        });
        _busy = false;
        _requestId = null;
      });
    } on AiServiceException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _requestId = null;
          _error = error.message.isNotEmpty
              ? error.message
              : 'Couldn’t reach Noted AI. Please retry.';
        });
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _busy = false;
          _requestId = null;
          _error = 'Couldn’t reach Noted AI. Please retry. $error';
        });
      }
    }
    _toBottom();
  }

  Future<void> _stop() async {
    final request = _requestId;
    if (request == null) return;
    final generation = ++_generation;
    setState(() {
      _busy = false;
      _requestId = null;
      _messages.add({'role': 'ai', 'stopped': true});
    });
    try {
      await _repo.stop(request);
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(
            () => _error = 'Couldn’t stop the request. Please retry. $error');
      }
    }
  }

  void _newChat() {
    if (_busy) return;
    setState(() {
      _chatId = _repo.newId();
      _messages.clear();
      _error = null;
      _lastPrompt = null;
    });
  }

  Future<void> _save(List<dynamic> blocks, String? intent) async {
    final user = context.read<AuthViewModel>().user;
    if (user == null) return;
    final vm = context.read<NoteViewModel>(),
        s = context.read<SettingsViewModel>().settings;
    final note =
        NoteModel.empty(user.uid, ownerName: user.name, ownerEmail: user.email)
            .copyWith(
                title: switch (intent) {
                  'flashcards' => 'Flashcards',
                  'guide' => 'Study guide',
                  'actions' => 'Action items',
                  _ => 'AI notes'
                },
                content: blocksMarkdown(blocks),
                category: s.defaultCat,
                color: 'lav');
    final id = await vm.saveNoteAndReturnId(note);
    if (mounted) {
      notedToast(
          context,
          id == null
              ? vm.errorMessage ?? 'Couldn’t save note.'
              : 'Saved as a new note');
    }
  }

  Future<void> _feedback(Map<String, dynamic> m, String value) async {
    final uid = context.read<AuthViewModel>().user?.uid;
    if (uid == null) return;
    final selected = m['fb'] == value ? null : value;
    try {
      if (_historyEnabled && m['id'] != null) {
        await _repo.feedback(uid, _chatId, m['id'] as String, selected);
      }
      if (mounted) setState(() => m['fb'] = selected);
    } catch (error) {
      if (mounted) notedToast(context, 'Couldn’t save feedback. $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        settings = context.watch<SettingsViewModel>().settings,
        notes = context.watch<NoteViewModel>().notes;
    if (!settings.aiEnabled) {
      return SafeArea(
          child: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(
                      title: 'A little help, when you need it',
                      message:
                          'Turn on Noted AI to explore ideas across the notes you choose.',
                      actionLabel: 'Enable Noted AI',
                      onAction: () => context
                          .read<SettingsViewModel>()
                          .update({'aiEnabled': true})))));
    }
    return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
            bottom: widget.compact,
            child: Column(children: [
              Padding(
                  padding: EdgeInsets.fromLTRB(widget.compact ? 20 : 24,
                      widget.compact ? 0 : 16, 12, 12),
                  child: Row(children: [
                    if (!widget.compact && Navigator.of(context).canPop())
                      IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.pop(context),
                          icon: const ReferenceIcon('back')),
                    Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary),
                        child: ReferenceIcon('spark',
                            size: 16, color: theme.colorScheme.onPrimary)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Noted AI',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: widget.compact ? 15 : 19)),
                          if (widget.compact)
                            Text(_scopeLabel(notes),
                                style: theme.textTheme.bodySmall)
                        ])),
                    if (_historyEnabled && !widget.compact)
                      IconButton(
                          tooltip: 'Chat history',
                          onPressed: _busy ? null : _history,
                          icon: const ReferenceIcon('history')),
                    IconButton(
                        tooltip: 'New chat',
                        onPressed: _busy ? null : _newChat,
                        icon: const ReferenceIcon('plus')),
                    if (widget.compact)
                      IconButton(
                          tooltip: 'Close',
                          onPressed: () => Navigator.pop(context),
                          icon: const ReferenceIcon('x'))
                  ])),
              Expanded(
                  child: ListView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                      children: [
                    if (_messages.isEmpty && !_busy) _welcome(context, notes),
                    for (final m in _messages)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: m['role'] == 'user'
                              ? Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                      constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.sizeOf(context).width *
                                                  .75),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                          color: theme.colorScheme.onSurface,
                                          borderRadius: const BorderRadius.only(
                                              topLeft: Radius.circular(16),
                                              topRight: Radius.circular(16),
                                              bottomLeft: Radius.circular(16),
                                              bottomRight: Radius.circular(5))),
                                      child: Text(m['text'] as String? ?? '',
                                          style: TextStyle(
                                              color:
                                                  theme.scaffoldBackgroundColor,
                                              fontSize: 14,
                                              height: 1.5))))
                              : m['stopped'] == true
                                  ? Text('Stopped. Nothing was written.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              fontStyle: FontStyle.italic))
                                  : _answer(context, m, notes)),
                    if (_busy)
                      const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: SurfacePanel(
                              child: Row(children: [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 12),
                            Expanded(
                                child: Text(
                                    'Reading your notes and writing a suggestion…',
                                    style: TextStyle(fontSize: 13)))
                          ]))),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: InlineError(_error!,
                              onRetry: _busy || _lastPrompt == null
                                  ? null
                                  : () => _send(_lastPrompt!, retry: true))),
                    if (!_busy &&
                        _messages.any(
                            (m) => m['role'] == 'ai' && m['stopped'] != true))
                      Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final p in [
                              'Summarize this',
                              'Find related notes'
                            ])
                              OutlinedButton(
                                  onPressed: () => _send(p),
                                  style: OutlinedButton.styleFrom(
                                      shape: const StadiumBorder()),
                                  child: Text(p,
                                      style: const TextStyle(fontSize: 13)))
                          ])),
                  ])),
              Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Column(children: [
                    SurfacePanel(
                        padding: const EdgeInsets.all(6),
                        child: Column(children: [
                          TextField(
                              controller: _text,
                              keyboardType: TextInputType.multiline,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.newline,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                  hintText: widget.compact
                                      ? 'Ask about this note…'
                                      : 'Ask about your notes…',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      const EdgeInsets.fromLTRB(10, 8, 10, 8))),
                          Row(children: [
                            Flexible(
                                child: TextButton(
                                    onPressed: _busy ? null : _pickScope,
                                    style: TextButton.styleFrom(
                                        backgroundColor: theme.colorScheme
                                            .surfaceContainerHighest,
                                        foregroundColor:
                                            theme.colorScheme.onSurface,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        minimumSize: const Size(0, 44),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12))),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const ReferenceIcon('doc', size: 14),
                                          const SizedBox(width: 6),
                                          Flexible(
                                              child: Text(_scopeLabel(notes),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                      fontSize: 12))),
                                          Text(' · ${_pool(notes).length}',
                                              style: theme.textTheme.bodySmall)
                                        ]))),
                            const Spacer(),
                            IconButton.filled(
                                tooltip: _busy ? 'Stop generating' : 'Send',
                                onPressed: _busy
                                    ? _stop
                                    : _text.text.trim().isEmpty
                                        ? null
                                        : () => _send(_text.text),
                                style: IconButton.styleFrom(
                                    backgroundColor: theme.colorScheme.primary,
                                    foregroundColor:
                                        theme.colorScheme.onPrimary),
                                icon: ReferenceIcon(_busy ? 'stop' : 'arrow',
                                    size: 16))
                          ])
                        ])),
                    const SizedBox(height: 6),
                    Text('AI can be wrong — check the sources.',
                        textAlign: TextAlign.center,
                        style:
                            theme.textTheme.bodySmall?.copyWith(fontSize: 11))
                  ])),
            ])));
  }

  Widget _welcome(BuildContext context, List<NoteModel> notes) {
    final theme = Theme.of(context);
    final caps = <(String, String, String, String, String)>[
      (
        'Summarize',
        'The key points, fast',
        'Summarize these notes',
        'list',
        'blue'
      ),
      (
        'Study guide',
        'Concepts, recap, quiz',
        'Build a study guide',
        'target',
        'mint'
      ),
      ('Flashcards', 'Flip-to-reveal cards', 'Make flashcards', 'cards', 'lav'),
      (
        'Action items',
        'Open tasks & to-dos',
        'What action items are still open?',
        'todo',
        'yellow'
      ),
      (
        'Find related',
        'Connect your ideas',
        'Find related notes',
        'link',
        'peach'
      ),
      (
        'Organize',
        'Suggest collections',
        'Help me organize my notes',
        'layers',
        'pink'
      ),
    ];
    if (widget.compact) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.selection?.isNotEmpty == true) ...[
          OutlinedButton(
              onPressed: () => _send('Explain the selected text'),
              child: Text('Explain your selection: “${widget.selection}”',
                  maxLines: 3, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 12),
        ],
        Text('For this note', style: theme.textTheme.bodySmall),
        for (final p in [
          'Summarize this note',
          'Help me understand this topic',
          'Make flashcards',
          'Generate study questions',
          'Extract action items',
          'Find related notes'
        ])
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(p, style: const TextStyle(fontSize: 14)),
              trailing: const ReferenceIcon('arrow', size: 16),
              onTap: () => _send(p)),
      ]);
    }
    Widget capability((String, String, String, String, String) c) {
      return Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: theme.dividerColor)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: () => _send(c.$3),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                            color: AppColors.noteColor(theme.brightness, c.$5),
                            borderRadius: BorderRadius.circular(12)),
                        child: ReferenceIcon(c.$4, size: 18)),
                    const SizedBox(height: 12),
                    Text(c.$1,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontSize: 14)),
                    Text(c.$2, style: theme.textTheme.bodySmall),
                  ]),
            )),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(
          TextSpan(text: 'What would you like to ', children: [
            TextSpan(
                text: 'understand',
                style: TextStyle(
                    fontFamily: 'Newsreader',
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w400,
                    color: theme.colorScheme.primary)),
            const TextSpan(text: ' today?'),
          ]),
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontSize: 26, height: 1.15, letterSpacing: -.52)),
      const SizedBox(height: 8),
      Text(
          'Noted AI reads only the notes you choose and always shows where an answer came from.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const SizedBox(height: 20),
      for (var row = 0; row < 3; row++)
        Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: capability(caps[row * 2])),
              const SizedBox(width: 10),
              Expanded(child: capability(caps[row * 2 + 1])),
            ])),
      if (notes.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Suggested from your notes',
            style: theme.textTheme.bodySmall
                ?.copyWith(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        SurfacePanel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final n in notes.take(3))
                ListTile(
                  leading: ReferenceIcon('spark',
                      size: 15, color: theme.colorScheme.primary),
                  title: Text(
                      'Summarize “${n.title.isEmpty ? 'Untitled' : n.title}”',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14)),
                  onTap: () {
                    setState(() => _scope = {
                          'kind': 'notes',
                          'ids': [n.noteId]
                        });
                    _send(
                        'Summarize “${n.title.isEmpty ? 'Untitled' : n.title}”');
                  },
                ),
            ])),
      ],
    ]);
  }

  Widget _answer(
      BuildContext context, Map<String, dynamic> m, List<NoteModel> notes) {
    final blocks = m['blocks'] as List? ?? [],
        sources = (m['sources'] as List? ?? []).whereType<String>().toSet(),
        theme = Theme.of(context);
    final showSources = context.watch<SettingsViewModel>().settings.aiSources;
    return SurfacePanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        ReferenceIcon('spark', size: 13, color: theme.colorScheme.primary),
        const SizedBox(width: 6),
        Expanded(
            child: Text('SUGGESTION · NOT SAVED ANYWHERE YET',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .5,
                    color: theme.colorScheme.primary)))
      ]),
      const SizedBox(height: 12),
      AiBlocks(blocks: blocks),
      if (showSources && sources.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 12),
        Text('Based on ${sources.length} note${sources.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in notes.where((n) => sources.contains(n.noteId)))
            OutlinedButton(
                onPressed: () => openNote(context, n),
                style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10)),
                child: Text(n.title.isEmpty ? 'Untitled' : n.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12)))
        ])
      ],
      if (widget.onInsert != null) ...[
        const SizedBox(height: 12),
        SizedBox(
            width: double.infinity,
            child: FilledButton(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                              title: const Text('Insert into note?'),
                              content: const Text(
                                  'Add this suggestion to the end of your note?'),
                              actions: [
                                TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Insert'))
                              ]));
                  if (ok == true) {
                    widget.onInsert!(blocksMarkdown(blocks));
                    if (context.mounted) {
                      notedToast(context, 'Added to your note');
                    }
                  }
                },
                child: const Text('Insert into note')))
      ],
      const SizedBox(height: 8),
      Wrap(
          spacing: 0,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: blocksMarkdown(blocks)));
                  if (context.mounted) notedToast(context, 'Copied');
                },
                icon: const ReferenceIcon('copy', size: 15),
                label: const Text('Copy', style: TextStyle(fontSize: 12))),
            TextButton.icon(
                onPressed: () => _save(blocks, m['intent'] as String?),
                icon: const ReferenceIcon('doc', size: 15),
                label:
                    const Text('Save as note', style: TextStyle(fontSize: 12))),
            IconButton(
                tooltip: 'Retry',
                onPressed: _busy
                    ? null
                    : () => _send(
                        m['prompt'] as String? ??
                            _lastPrompt ??
                            'Summarize this',
                        retry: true),
                icon: const ReferenceIcon('refresh', size: 16)),
            IconButton(
                tooltip: 'Helpful',
                isSelected: m['fb'] == 'up',
                onPressed: () => _feedback(m, 'up'),
                icon: ReferenceIcon('up',
                    size: 16,
                    color: m['fb'] == 'up' ? theme.colorScheme.primary : null)),
            IconButton(
                tooltip: 'Not helpful',
                isSelected: m['fb'] == 'down',
                onPressed: () => _feedback(m, 'down'),
                icon: ReferenceIcon('down',
                    size: 16,
                    color: m['fb'] == 'down' ? theme.colorScheme.error : null))
          ]),
    ]));
  }

  Future<void> _pickScope() async {
    final notes = context.read<NoteViewModel>().notes;
    final selected =
        Set<String>.from((_scope['ids'] as List? ?? []).whereType<String>());
    bool specific = false;
    final result = await notedSheet<Map<String, dynamic>>(context,
        label: 'Choose context',
        tall: true,
        builder: (context) => StatefulBuilder(
            builder: (context, setSheet) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                specific
                                    ? 'Choose notes'
                                    : 'What should AI read?',
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(context),
                            icon: const ReferenceIcon('x'))
                      ]),
                      const Text('Noted AI only uses the notes you pick here.',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 12),
                      Expanded(
                          child: ListView(
                              children: specific
                                  ? [
                                      for (final n in notes)
                                        CheckboxListTile(
                                            value: selected.contains(n.noteId),
                                            title: Text(
                                                n.title.isEmpty
                                                    ? 'Untitled'
                                                    : n.title,
                                                style: const TextStyle(
                                                    fontSize: 14)),
                                            subtitle: Text(n.category),
                                            onChanged: !selected
                                                        .contains(n.noteId) &&
                                                    selected.length >= 5
                                                ? null
                                                : (on) => setSheet(() {
                                                      if (on == true) {
                                                        selected.add(n.noteId);
                                                      } else {
                                                        selected
                                                            .remove(n.noteId);
                                                      }
                                                    }))
                                    ]
                                  : [
                                      ListTile(
                                          leading: const ReferenceIcon('notes'),
                                          title: const Text('All notes'),
                                          subtitle:
                                              Text('${notes.length} notes'),
                                          onTap: () => Navigator.pop(
                                              context, {'kind': 'all'})),
                                      ListTile(
                                          leading: const ReferenceIcon('star'),
                                          title: const Text('Favorites'),
                                          subtitle: Text(
                                              '${notes.where((n) => n.isFavorite).length} notes'),
                                          onTap: () => Navigator.pop(
                                              context, {'kind': 'fav'})),
                                      ListTile(
                                          leading: const ReferenceIcon('check'),
                                          title: const Text('Specific notes…'),
                                          subtitle: const Text('Pick up to 5'),
                                          onTap: () =>
                                              setSheet(() => specific = true)),
                                      const Padding(
                                          padding: EdgeInsets.only(
                                              top: 16, bottom: 8),
                                          child: Text('By category')),
                                      for (final cat in notes
                                          .map((n) => n.category)
                                          .toSet())
                                        ListTile(
                                            title: Text(cat),
                                            onTap: () => Navigator.pop(context,
                                                {'kind': 'cat', 'cat': cat}))
                                    ])),
                      if (specific)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 24, top: 12),
                            child: SizedBox(
                                width: double.infinity,
                                child: FilledButton(
                                    onPressed: selected.isEmpty
                                        ? null
                                        : () => Navigator.pop(context, {
                                              'kind': 'notes',
                                              'ids': selected.toList()
                                            }),
                                    child:
                                        Text('Use ${selected.length} notes'))))
                    ]))));
    if (result != null && mounted) setState(() => _scope = result);
  }

  Future<void> _history() async {
    final uid = context.read<AuthViewModel>().user?.uid;
    if (uid == null) return;
    await notedSheet<void>(context,
        label: 'Chat history',
        tall: true,
        builder: (context) =>
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Chat history',
                      style: Theme.of(context).textTheme.titleLarge)),
              Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _repo.history(uid),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return const Padding(
                              padding: EdgeInsets.all(24),
                              child:
                                  InlineError('Couldn’t load chat history.'));
                        }
                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final docs = snapshot.data!;
                        if (docs.isEmpty) {
                          return const Padding(
                              padding: EdgeInsets.all(24),
                              child: EmptyState(
                                  title: 'A fresh conversation',
                                  message:
                                      'Your saved AI chats will appear here.'));
                        }
                        return ListView(children: [
                          for (final d in docs)
                            ListTile(
                                title: Text(d['title'] as String? ?? 'New chat',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis),
                                leading: const ReferenceIcon('spark', size: 18),
                                trailing: IconButton(
                                    tooltip: 'Rename chat',
                                    onPressed: () async {
                                      final edit = TextEditingController(
                                          text: d['title'] as String? ?? '');
                                      final title = await showDialog<String>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                                  title:
                                                      const Text('Rename chat'),
                                                  content: TextField(
                                                      controller: edit,
                                                      maxLength: 200,
                                                      autofocus: true),
                                                  actions: [
                                                    TextButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context),
                                                        child: const Text(
                                                            'Cancel')),
                                                    FilledButton(
                                                        onPressed: () =>
                                                            Navigator.pop(
                                                                context,
                                                                edit.text
                                                                    .trim()),
                                                        child:
                                                            const Text('Save'))
                                                  ]));
                                      edit.dispose();
                                      if (title?.isNotEmpty == true) {
                                        try {
                                          await _repo.rename(uid,
                                              d['id'] as String? ?? '', title!);
                                        } catch (error) {
                                          if (context.mounted) {
                                            notedToast(context,
                                                'Couldn’t rename. $error');
                                          }
                                        }
                                      }
                                    },
                                    icon:
                                        const ReferenceIcon('edit', size: 16)),
                                onTap: () async {
                                  try {
                                    final messages = await _repo.messages(
                                        uid, d['id'] as String? ?? '');
                                    if (!mounted || !context.mounted) return;
                                    Navigator.pop(context);
                                    setState(() {
                                      _chatId = d['id'] as String? ?? _chatId;
                                      _messages
                                        ..clear()
                                        ..addAll(messages);
                                      _scope = Map<String, dynamic>.from(
                                          d['scope'] as Map? ??
                                              {'kind': 'all'});
                                      _error = null;
                                    });
                                    _toBottom();
                                  } catch (error) {
                                    if (context.mounted) {
                                      notedToast(context,
                                          'Couldn’t open chat. $error');
                                    }
                                  }
                                })
                        ]);
                      }))
            ]));
  }
}
