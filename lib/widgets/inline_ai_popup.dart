import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../repositories/ai_repository.dart';
import 'ai_blocks.dart';
import 'noted_ui.dart';
import 'reference_icon.dart';

/// A focused editor for an explicitly selected passage.
class InlineAiPopup extends StatefulWidget {
  const InlineAiPopup(
      {super.key,
      required this.selection,
      required this.noteId,
      required this.onApply,
      this.repository});
  final String selection;
  final String noteId;
  final bool Function(String markdown, bool replace)? onApply;
  final AiRepository? repository;

  @override
  State<InlineAiPopup> createState() => _InlineAiPopupState();
}

class _InlineAiPopupState extends State<InlineAiPopup> {
  late final AiRepository _repo;
  late final String _chatId;
  final _contentScroll = ScrollController();
  String? _requestId, _action, _error, _tone;
  bool _choosingTone = false;
  static const _tones = <(String, String)>[
    ('Professional', 'Clear and polished for work'),
    ('Friendly', 'Warm and approachable'),
    ('Formal', 'Respectful and more traditional'),
    ('Casual', 'Relaxed and conversational'),
    ('Confident', 'Assured without overstatement'),
    ('Empathetic', 'Thoughtful and understanding'),
    ('Diplomatic', 'Tactful and constructive'),
    ('Persuasive', 'Compelling without exaggeration'),
    ('Academic', 'Precise and analytical'),
    ('Neutral', 'Objective and even-handed'),
  ];
  List<dynamic>? _blocks;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? AiRepository();
    _chatId = _repo.newId();
  }

  @override
  void dispose() {
    _generation++;
    final request = _requestId;
    if (request != null) _repo.stop(request).catchError((Object _) {});
    _contentScroll.dispose();
    super.dispose();
  }

  Future<void> _run(String action, {String? tone}) async {
    if (_requestId != null) return;
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
    final generation = ++_generation;
    final request = _repo.newId();
    setState(() {
      _action = action;
      _tone = tone;
      _choosingTone = false;
      _requestId = request;
      _error = null;
      _blocks = null;
    });
    final instruction = switch (action) {
      'Tone' =>
        'Rewrite in a ${tone!.toLowerCase()} tone, preserving the original meaning and facts',
      'Checklist' => 'Convert into a checklist',
      _ => action,
    };
    try {
      final result = await _repo.ask(
          prompt:
              '$instruction only the selected text. Return only the replacement for that selection. Do not rewrite, summarize, or add information from the rest of the note.',
          scope: {
            'kind': 'notes',
            'ids': [widget.noteId]
          },
          chatId: _chatId,
          requestId: request,
          selection: widget.selection,
          selectionNoteId: widget.noteId,
          selectionOnly: true);
      if (!mounted || generation != _generation) return;
      final blocks = result['blocks'] as List? ?? [];
      setState(() {
        _requestId = null;
        if (blocks.isEmpty ||
            blocks.whereType<Map>().any((b) => b['t'] == 'cards')) {
          _error = 'Could not create an inline suggestion. Try again.';
        } else {
          _blocks = blocks;
        }
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _requestId = null;
          _error =
              'Could not create a suggestion. Check your connection and try again.';
        });
      }
    }
  }

  Future<void> _stop() async {
    final request = _requestId;
    if (request == null) return;
    _generation++;
    setState(() {
      _requestId = null;
      _error = 'Generation stopped.';
    });
    try {
      await _repo.stop(request);
    } catch (_) {}
  }

  void _apply(bool replace) {
    final success = widget.onApply!(blocksMarkdown(_blocks!), replace);
    if (success) {
      notedToast(context, 'Updated your note');
      Navigator.maybePop(context);
    } else {
      notedToast(context, 'The note changed. Select the text again.');
    }
  }

  void _showTonePicker() {
    if (_contentScroll.hasClients) _contentScroll.jumpTo(0);
    setState(() {
      _blocks = null;
      _error = null;
      _choosingTone = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = _requestId != null;
    final hasResult = _blocks != null;
    final dark = theme.brightness == Brightness.dark;
    final actions = <(String, String, Color, Color)>[
      (
        'Rewrite',
        'refresh',
        dark ? const Color(0xFF30463A) : const Color(0xFFE3EFE5),
        dark ? const Color(0xFFA5D1B7) : const Color(0xFF3D765B)
      ),
      (
        'Shorten',
        'shorten',
        dark ? const Color(0xFF493A31) : const Color(0xFFFFEFE2),
        dark ? const Color(0xFFF0C0A5) : const Color(0xFF89553F)
      ),
      (
        'Clarify',
        'spark',
        dark ? const Color(0xFF3B3549) : const Color(0xFFECE6F4),
        dark ? const Color(0xFFD3BFE8) : const Color(0xFF66577A)
      ),
      (
        'Tone',
        'sliders',
        dark ? const Color(0xFF2D4247) : const Color(0xFFE0EFF1),
        dark ? const Color(0xFFB0D7D8) : const Color(0xFF416E73)
      ),
      (
        'Checklist',
        'checkSquare',
        dark ? const Color(0xFF354335) : const Color(0xFFEAF1E3),
        dark ? const Color(0xFFB5D8B3) : const Color(0xFF507C59)
      ),
    ];

    Widget preview(String label, Widget child, {bool suggested = false}) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
        decoration: BoxDecoration(
          color: suggested
              ? (dark ? const Color(0xFF29392F) : const Color(0xFFF1F6EF))
              : scheme.surfaceContainerHighest.withValues(alpha: .60),
          border: Border.all(
              color: suggested
                  ? scheme.primary.withValues(alpha: .24)
                  : theme.dividerColor),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: theme.textTheme.labelMedium?.copyWith(
                  color: suggested ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          DefaultTextStyle.merge(
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
              child: child),
        ]),
      );
    }

    final resultActions = LayoutBuilder(builder: (context, constraints) {
      final width = (constraints.maxWidth - 8) / 2;
      return Wrap(spacing: 8, runSpacing: 8, children: [
        if (widget.onApply != null) ...[
          SizedBox(
              width: width,
              child: FilledButton.icon(
                  onPressed: () => _apply(true),
                  style: FilledButton.styleFrom(
                      backgroundColor: scheme.primary,
                      foregroundColor: scheme.onPrimary,
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  icon: const ReferenceIcon('check', size: 17),
                  label: const Text('Replace', textAlign: TextAlign.center))),
          SizedBox(
              width: width,
              child: OutlinedButton.icon(
                  onPressed: () => _apply(false),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8)),
                  icon: const ReferenceIcon('download', size: 17),
                  label:
                      const Text('Insert below', textAlign: TextAlign.center))),
        ],
        SizedBox(
            width: width,
            child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                      ClipboardData(text: blocksMarkdown(_blocks!)));
                  if (context.mounted) {
                    notedToast(context, 'Copied');
                  }
                },
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: const ReferenceIcon('copy', size: 17),
                label: const Text('Copy'))),
        SizedBox(
            width: width,
            child: OutlinedButton.icon(
                onPressed: () => _run(_action!, tone: _tone),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8)),
                icon: const ReferenceIcon('refresh', size: 17),
                label: const Text('Try again', textAlign: TextAlign.center))),
      ]);
    });

    return Material(
      color: scheme.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: dark ? .42 : .16),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                        color:
                            scheme.primary.withValues(alpha: dark ? .18 : .11),
                        borderRadius: BorderRadius.circular(11)),
                    child: ReferenceIcon('spark',
                        color: scheme.primary, size: 19)),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                      Text(
                          hasResult
                              ? 'Review suggestion'
                              : (_choosingTone ? 'Choose a tone' : 'Ask Noted'),
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontSize: 16)),
                      Text(
                          hasResult
                              ? (_tone == null
                                  ? 'Based on your selection'
                                  : '$_tone tone · Based on your selection')
                              : (_choosingTone
                                  ? 'How should it sound?'
                                  : 'Choose an edit for your selection'),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 11)),
                    ])),
                if (_choosingTone)
                  IconButton(
                      tooltip: 'Back to edits',
                      onPressed: () => setState(() => _choosingTone = false),
                      icon: const ReferenceIcon('back', size: 18),
                      visualDensity: VisualDensity.compact),
                IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.maybePop(context),
                    icon: const ReferenceIcon('x', size: 18),
                    visualDensity: VisualDensity.compact),
              ]),
              const SizedBox(height: 14),
              Flexible(
                  child: Scrollbar(
                      controller: _contentScroll,
                      thumbVisibility: _choosingTone,
                      child: SingleChildScrollView(
                          controller: _contentScroll,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!hasResult &&
                                    !busy &&
                                    _error == null &&
                                    !_choosingTone) ...[
                                  LayoutBuilder(
                                      builder: (context, constraints) {
                                    final scaled =
                                        MediaQuery.textScalerOf(context)
                                                .scale(12) /
                                            12;
                                    final tileWidth =
                                        ((constraints.maxWidth - 16) / 5).clamp(
                                            scaled > 1.15 ? 70.0 : 56.0, 76.0);
                                    return SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (final action in actions)
                                              SizedBox(
                                                  width: tileWidth,
                                                  child: Semantics(
                                                    button: true,
                                                    label: action.$1,
                                                    child: InkWell(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              14),
                                                      onTap: () => action.$1 ==
                                                              'Tone'
                                                          ? _showTonePicker()
                                                          : _run(action.$1),
                                                      child: Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  vertical: 2),
                                                          child: Column(
                                                              mainAxisSize:
                                                                  MainAxisSize
                                                                      .min,
                                                              children: [
                                                                Container(
                                                                    width: 48,
                                                                    height: 48,
                                                                    decoration: BoxDecoration(
                                                                        color: action
                                                                            .$3,
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                                14)),
                                                                    child: ReferenceIcon(
                                                                        action
                                                                            .$2,
                                                                        size:
                                                                            22,
                                                                        color: action
                                                                            .$4)),
                                                                const SizedBox(
                                                                    height: 7),
                                                                Text(action.$1,
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    maxLines: 2,
                                                                    style: theme.textTheme.labelSmall?.copyWith(
                                                                        color: scheme
                                                                            .onSurface,
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight:
                                                                            FontWeight
                                                                                .w500,
                                                                        height:
                                                                            1.2)),
                                                              ])),
                                                    ),
                                                  )),
                                          ]),
                                    );
                                  }),
                                ],
                                if (_choosingTone &&
                                    !busy &&
                                    _error == null) ...[
                                  for (final tone in _tones)
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () =>
                                            _run('Tone', tone: tone.$1),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 8),
                                          child: Row(children: [
                                            Expanded(
                                                child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                  Text(tone.$1,
                                                      style: theme
                                                          .textTheme.labelLarge
                                                          ?.copyWith(
                                                              fontSize: 14)),
                                                  Text(tone.$2,
                                                      style: theme
                                                          .textTheme.bodySmall),
                                                ])),
                                            ReferenceIcon('next',
                                                size: 16,
                                                color: scheme.onSurfaceVariant),
                                          ]),
                                        ),
                                      ),
                                    ),
                                ],
                                if (busy) ...[
                                  Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                          color: scheme.surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      child: Row(children: [
                                        SizedBox(
                                            width: 19,
                                            height: 19,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: scheme.primary)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child: Text(
                                                'Working on your selection',
                                                style: theme
                                                    .textTheme.bodyMedium)),
                                        TextButton(
                                            onPressed: _stop,
                                            child: const Text('Stop')),
                                      ])),
                                ],
                                if (_error != null) ...[
                                  Text(_error!,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(color: scheme.error)),
                                  if (_action != null)
                                    Align(
                                        alignment: Alignment.centerLeft,
                                        child: TextButton.icon(
                                            onPressed: () =>
                                                _run(_action!, tone: _tone),
                                            icon: const ReferenceIcon('refresh',
                                                size: 16),
                                            label: const Text('Try again'))),
                                ],
                                if (hasResult) ...[
                                  if (_tone != null)
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: _showTonePicker,
                                        icon: const ReferenceIcon('sliders',
                                            size: 16),
                                        label: const Text('Change tone'),
                                      ),
                                    ),
                                  preview(
                                      'Before',
                                      Text(widget.selection,
                                          style: theme.textTheme.bodyMedium
                                              ?.copyWith(height: 1.45))),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: Center(
                                          child: ReferenceIcon('downArrow',
                                              color: scheme.primary,
                                              size: 20))),
                                  preview('After', AiBlocks(blocks: _blocks!),
                                      suggested: true),
                                ],
                              ])))),
              if (hasResult) ...[
                const SizedBox(height: 14),
                if (MediaQuery.textScalerOf(context).scale(12) > 15.6)
                  Flexible(child: SingleChildScrollView(child: resultActions))
                else
                  resultActions,
              ],
            ]),
      ),
    );
  }
}
