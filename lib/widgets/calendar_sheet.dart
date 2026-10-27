import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../utils/note_navigation.dart';
import 'noted_ui.dart';
import 'reference_icon.dart';

Future<void> showNotedCalendar(BuildContext context, DateTime initial) =>
    notedSheet<void>(context,
        label: 'Calendar',
        tall: true,
        builder: (_) => CalendarSheet(initial: initial));

class CalendarSheet extends StatefulWidget {
  const CalendarSheet({super.key, required this.initial, this.today});
  final DateTime? today;
  final DateTime initial;
  @override
  State<CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<CalendarSheet> {
  late DateTime _month, _selected;
  final _days = <String, FocusNode>{};
  DateTime? _focused;
  @override
  void dispose() {
    for (final node in _days.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_days.values.any((n) => n.hasFocus)) {
      return KeyEventResult.ignored;
    }
    final shift = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => -1,
      LogicalKeyboardKey.arrowRight => 1,
      LogicalKeyboardKey.arrowUp => -7,
      LogicalKeyboardKey.arrowDown => 7,
      _ => 0,
    };
    if (shift == 0) return KeyEventResult.ignored;
    final base = _focused ?? _selected;
    final next = DateTime(base.year, base.month, base.day + shift);
    _pick(next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _days[dayKey(next)]?.requestFocus();
    });
    return KeyEventResult.handled;
  }

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _month = DateTime(_selected.year, _selected.month);
  }

  void _pick(DateTime d) => setState(() {
        _selected = d;
        _month = DateTime(d.year, d.month);
      });
  @override
  Widget build(BuildContext context) {
    final notes = context.watch<NoteViewModel>().notes;
    final monday =
        context.watch<SettingsViewModel>().settings.weekStart == 'mon';
    final now = widget.today ?? DateTime.now(), theme = Theme.of(context);
    final offset = monday ? (_month.weekday - 1) % 7 : _month.weekday % 7;
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = ((offset + count) / 7).ceil().clamp(5, 6);
    final start = DateTime(_month.year, _month.month, 1 - offset);
    final monthNotes = notes
        .where((n) =>
            n.createdAt.year == _month.year &&
            n.createdAt.month == _month.month)
        .toList();
    final active = monthNotes.map((n) => dayKey(n.createdAt)).toSet().length;
    final dayNotes = notes
        .where((n) => sameDay(n.createdAt, _selected))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Focus(
        onKeyEvent: _key,
        child: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 12),
              child: Row(children: [
                Expanded(
                    child: Semantics(
                        liveRegion: true,
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text.rich(
                                  TextSpan(
                                      text:
                                          '${DateFormat.MMMM().format(_month)} ',
                                      children: [
                                        TextSpan(
                                            text: '${_month.year}',
                                            style: TextStyle(
                                                fontWeight: FontWeight.w400,
                                                color: theme.colorScheme
                                                    .onSurfaceVariant))
                                      ]),
                                  style: theme.textTheme.titleLarge
                                      ?.copyWith(fontSize: 22)),
                              Text(
                                  '${monthNotes.length} notes · $active active days',
                                  style: theme.textTheme.bodySmall)
                            ]))),
                if (!sameDay(_selected, now) ||
                    _month.month != now.month ||
                    _month.year != now.year)
                  TextButton(
                      onPressed: () => _pick(now), child: const Text('Today')),
                IconButton(
                    tooltip: 'Previous month',
                    onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month - 1)),
                    icon: const ReferenceIcon('back', size: 18)),
                IconButton(
                    tooltip: 'Next month',
                    onPressed: () => setState(
                        () => _month = DateTime(_month.year, _month.month + 1)),
                    icon: const ReferenceIcon('next', size: 18)),
              ])),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                for (final d in monday
                    ? ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                    : ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                  Expanded(
                      child: Center(
                          child: Text(d,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(fontSize: 11))))
              ])),
          const SizedBox(height: 6),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Table(children: [
                for (var row = 0; row < rows; row++)
                  TableRow(children: [
                    for (var col = 0; col < 7; col++)
                      Builder(builder: (context) {
                        final d = DateTime(start.year, start.month,
                                start.day + row * 7 + col),
                            selected = sameDay(d, _selected),
                            today = sameDay(d, now);
                        final n =
                            notes.where((n) => sameDay(n.createdAt, d)).length;
                        return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Semantics(
                                selected: selected,
                                label:
                                    '${DateFormat.yMMMMd().format(d)}, $n notes${today ? ', today' : ''}',
                                excludeSemantics: true,
                                child: SizedBox(
                                    height: 48,
                                    child: TextButton(
                                        focusNode: _days.putIfAbsent(
                                            dayKey(d),
                                            () => FocusNode(
                                                debugLabel: dayKey(d))),
                                        onFocusChange: (focused) {
                                          if (focused) _focused = d;
                                        },
                                        style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(44, 48),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                side: today && !selected
                                                    ? BorderSide(
                                                        color: theme.colorScheme
                                                            .primary)
                                                    : BorderSide.none),
                                            backgroundColor: selected
                                                ? theme.colorScheme.onSurface
                                                : null,
                                            foregroundColor: selected
                                                ? theme.scaffoldBackgroundColor
                                                : today
                                                    ? theme.colorScheme.primary
                                                    : theme
                                                        .colorScheme.onSurface
                                                        .withValues(
                                                            alpha: d.month ==
                                                                    _month.month
                                                                ? 1
                                                                : .35)),
                                        onPressed: () => _pick(d),
                                        child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text('${d.day}',
                                                  style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: selected ||
                                                              today
                                                          ? FontWeight.w600
                                                          : FontWeight.w400)),
                                              const SizedBox(height: 4),
                                              ActivityDots(n,
                                                  selected: selected)
                                            ])))));
                      })
                  ])
              ])),
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 16),
              child: Row(children: [
                const ActivityDots(1),
                const SizedBox(width: 6),
                Text('1 note',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                const SizedBox(width: 16),
                const ActivityDots(3),
                const SizedBox(width: 6),
                Text('3+ notes',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11))
              ])),
          const Divider(),
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(
                          '${sameDay(_selected, now) ? 'Today' : DateFormat.EEEE().format(_selected)}, ${DateFormat.MMMd().format(_selected)}',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontSize: 15)),
                      Text(
                          dayNotes.isEmpty
                              ? 'Nothing written'
                              : '${dayNotes.length} notes created',
                          style: theme.textTheme.bodySmall)
                    ])),
                IconButton.filled(
                    tooltip: 'New note on this day',
                    onPressed: () {
                      final target = _selected;
                      Navigator.pop(context);
                      createNote(context, date: target);
                    },
                    style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.onPrimary),
                    icon: const ReferenceIcon('plus', size: 18))
              ])),
          Expanded(
              child: dayNotes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Align(
                          alignment: Alignment.topLeft,
                          child: Text(
                              'A quiet day. Tap + to write something for it.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant))))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: dayNotes.length,
                      itemBuilder: (context, i) {
                        final n = dayNotes[i];
                        return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: Container(
                                width: 6,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: theme.colorScheme.primary
                                        .withValues(alpha: .3),
                                    borderRadius: BorderRadius.circular(4))),
                            title: Text(n.title.isEmpty ? 'Untitled' : n.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w500)),
                            subtitle: Text(
                                '${n.category} · ${DateFormat.jm().format(n.createdAt)}',
                                style: theme.textTheme.bodySmall),
                            trailing: n.isLive
                                ? const LiveBadge()
                                : n.isFavorite
                                    ? const ReferenceIcon('star',
                                        filled: true, size: 16)
                                    : null,
                            onTap: () {
                              Navigator.pop(context);
                              openNote(context, n);
                            });
                      })),
        ]));
  }
}
