import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/account_services.dart';
import '../services/media_url_resolver.dart';
import '../widgets/reference_icon.dart';
import '../services/recently_deleted_page.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/settings_viewmodel.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  int _matchingRows = 0;
  String _query = '', _version = 'Loading…';
  final _search = TextEditingController();
  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _version = '${info.version} (${info.buildNumber})');
      }
    }).catchError((Object _) {
      if (mounted) setState(() => _version = 'Unavailable');
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _action(Future<void> Function() action,
      [String? success]) async {
    try {
      await action();
      if (success != null) _toast(success);
    } catch (error) {
      _toast(error.toString());
    }
  }

  Future<void> _clearAiHistory() async {
    final vm = context.read<SettingsViewModel>();
    await clearNotedAIHistory();
    vm.invalidateAiHistory();
  }

  Future<void> _set(String key, Object value) async {
    final vm = context.read<SettingsViewModel>();
    if (key == 'appLock') {
      try {
        if (!await AppLockService().authenticate()) return;
      } catch (error) {
        _toast(error.toString());
        return;
      }
    }
    if (key == 'aiHistory' && value == false) {
      try {
        await _clearAiHistory();
      } catch (error) {
        _toast(error.toString());
        return;
      }
    }
    if (!await vm.update({key: value})) {
      _toast(vm.errorMessage ?? 'Couldn’t save settings.');
    }
  }

  Widget _toggle(String key, String label, [String? desc]) {
    final value =
        context.watch<SettingsViewModel>().settings.toMap()[key] == true;
    return SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        subtitle: desc == null
            ? null
            : Text(desc, style: const TextStyle(fontSize: 12)),
        value: value,
        onChanged: (v) => _set(key, v));
  }

  Widget _choice(String key, String label, Map<String, String> options,
      [String? desc]) {
    final value = context.watch<SettingsViewModel>().settings.toMap()[key];
    return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        title: Text(label, style: const TextStyle(fontSize: 15)),
        subtitle: desc == null
            ? null
            : Text(desc, style: const TextStyle(fontSize: 12)),
        trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 145),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                  child: Text(options[value] ?? '$value',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).hintColor))),
              const ReferenceIcon('next', size: 16)
            ])),
        onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            isScrollControlled: true,
            builder: (sheetContext) => SafeArea(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          if (desc != null) Text(desc),
                          const SizedBox(height: 12),
                          ...options.entries.map((option) => ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                  value == option.key
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  color: value == option.key
                                      ? Theme.of(context).colorScheme.primary
                                      : null),
                              title: Text(option.value),
                              selected: value == option.key,
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _set(key, option.key);
                              }))
                        ])))));
  }

  Widget _row(String label, VoidCallback? action,
          {String? desc, String? value, bool danger = false}) =>
      ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          title: Text(label,
              style: TextStyle(
                  fontSize: 15,
                  color: danger ? Theme.of(context).colorScheme.error : null)),
          subtitle: desc == null
              ? null
              : Text(desc, style: const TextStyle(fontSize: 12)),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (value != null)
              ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: Text(value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13, color: Theme.of(context).hintColor))),
            if (action != null) const ReferenceIcon('next', size: 16)
          ]),
          onTap: action);
  Widget _group(String title, String icon, List<(String, Widget)> rows,
      {String? note}) {
    final selected = rows
        .where((r) => '$title ${r.$1}'
            .toLowerCase()
            .contains(_query.toLowerCase().trim()))
        .toList();
    if (selected.isEmpty) return const SizedBox.shrink();
    _matchingRows += selected.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
          child: Row(children: [
            ReferenceIcon(icon, size: 16, color: Theme.of(context).hintColor),
            const SizedBox(width: 8),
            Text(title.toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    color: Theme.of(context).hintColor))
          ])),
      Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor)),
          child: Column(children: [
            for (var i = 0; i < selected.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              selected[i].$2
            ]
          ])),
      if (note != null && _query.isEmpty)
        Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
            child: Text(note,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)))
    ]);
  }

  Widget _settingsAvatar(String name, String avatarUrl) {
    CircleAvatar circle(String? resolvedUrl) => CircleAvatar(
        radius: 24,
        backgroundColor: const Color(0xFFFFD66B),
        backgroundImage: resolvedUrl != null ? NetworkImage(resolvedUrl) : null,
        child: resolvedUrl != null
            ? null
            : Text(profileInitials(name),
                style: const TextStyle(color: Color(0xFF2F2F2F))));

    if (avatarUrl.trim().isEmpty) return circle(null);
    final immediate = MediaUrlResolver.peekResolved(
      avatarUrl,
      defaultBucket: MediaUrlResolver.avatarsBucket,
    );
    if (immediate != null) return circle(immediate);
    return FutureBuilder<String?>(
      future: MediaUrlResolver.resolve(
        avatarUrl,
        defaultBucket: MediaUrlResolver.avatarsBucket,
      ),
      builder: (context, snapshot) => circle(snapshot.data),
    );
  }

  @override
  Widget build(BuildContext context) {
    _matchingRows = 0;
    final auth = context.watch<AuthViewModel>(),
        vm = context.watch<SettingsViewModel>();
    final s = vm.settings, user = auth.user;
    final notes = context.watch<NoteViewModel>().notes;
    return Scaffold(
        appBar: AppBar(
            leading: IconButton(
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
                icon: const ReferenceIcon('back')),
            title: const Text('Settings',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600))),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            children: [
              TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                      hintText: 'Search settings',
                      prefixIcon: const Center(
                          widthFactor: 1,
                          child: ReferenceIcon('search', size: 16)),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const ReferenceIcon('x', size: 18),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              }))),
              if (vm.errorMessage != null)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(vm.errorMessage!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (_query.isEmpty) ...[
                const SizedBox(height: 16),
                Container(
                    decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border:
                            Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(16)),
                    child: ListTile(
                        contentPadding: const EdgeInsets.all(14),
                        leading: _settingsAvatar(
                            user?.name ?? '', user?.avatarUrl ?? ''),
                        title: Text(user?.name ?? '',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                        subtitle: Text(user?.email ?? '',
                            style: const TextStyle(fontSize: 13)),
                        trailing: const ReferenceIcon('next', size: 16),
                        onTap: () => showEditProfile(context))),
                Padding(
                    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
                    child: Text('THEME',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1,
                            color: Theme.of(context).hintColor))),
                Row(children: [
                  for (final mode in ['light', 'dark', 'system'])
                    Expanded(
                        child: Padding(
                            padding: EdgeInsets.only(
                                right: mode == 'system' ? 0 : 8),
                            child: Semantics(
                                selected: s.theme == mode,
                                button: true,
                                label:
                                    '${mode[0].toUpperCase()}${mode.substring(1)} theme',
                                child: InkWell(
                                    borderRadius: BorderRadius.circular(16),
                                    onTap: () => _set('theme', mode),
                                    child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                width: 2,
                                                color: s.theme == mode
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .primary
                                                    : Theme.of(context)
                                                        .dividerColor)),
                                        child: Column(children: [
                                          ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              child: Row(children: [
                                                for (final dark
                                                    in mode == 'system'
                                                        ? [false, true]
                                                        : [mode == 'dark'])
                                                  Expanded(
                                                      child: Container(
                                                          height: 56,
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(7),
                                                          color: dark
                                                              ? const Color(
                                                                  0xFF1B1E1C)
                                                              : const Color(
                                                                  0xFFF8F7F2),
                                                          child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Container(
                                                                    width: 24,
                                                                    height: 6,
                                                                    decoration: BoxDecoration(
                                                                        color: dark
                                                                            ? const Color(
                                                                                0xFFF1EEE4)
                                                                            : const Color(
                                                                                0xFF2F2F2F),
                                                                        borderRadius:
                                                                            BorderRadius.circular(3))),
                                                                const SizedBox(
                                                                    height: 6),
                                                                Container(
                                                                    height: 24,
                                                                    decoration: BoxDecoration(
                                                                        color: dark
                                                                            ? const Color(
                                                                                0xFF3A3549)
                                                                            : const Color(
                                                                                0xFFD9CCFF),
                                                                        borderRadius:
                                                                            BorderRadius.circular(6)))
                                                              ])))
                                              ])),
                                          const SizedBox(height: 6),
                                          Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                if (s.theme == mode) ...[
                                                  ReferenceIcon('check',
                                                      size: 13,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .primary),
                                                  const SizedBox(width: 4)
                                                ],
                                                Text(
                                                    '${mode[0].toUpperCase()}${mode.substring(1)}',
                                                    style: const TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w500))
                                              ]),
                                        ]))))))
                ]),
              ],
              _group('Account', 'user', [
                (
                  'Edit profile Name and field of study',
                  _row('Edit profile', () => showEditProfile(context),
                      desc: 'Name and field of study')
                ),
                ('Email', _row('Email', null, value: user?.email ?? '')),
                ('Change password', _row('Change password', _password))
              ]),
              _group('Appearance', 'sun', [
                (
                  'Editor text size',
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Expanded(
                                  child: Text('Editor text size',
                                      style: TextStyle(fontSize: 15))),
                              Text('${s.textSize.round()}px',
                                  style: const TextStyle(fontSize: 13))
                            ]),
                        Slider(
                            value: s.textSize.clamp(14, 20),
                            min: 14,
                            max: 20,
                            divisions: 6,
                            label: '${s.textSize.round()}px',
                            onChanged: (v) => _set('textSize', v)),
                        Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12)),
                            child: Text(
                                'Gradient descent is just walking downhill, one small step at a time.',
                                style: TextStyle(
                                    fontSize: s.textSize, height: 1.6)))
                      ]))
                ),
                (
                  'Card density',
                  _choice(
                      'density',
                      'Card density',
                      {'comfortable': 'Comfortable', 'compact': 'Compact'},
                      'How much preview each note card shows')
                ),
                (
                  'Reduce motion',
                  _toggle('reduceMotion', 'Reduce motion',
                      'Minimise animations and transitions')
                )
              ]),
              _group('Writing', 'edit', [
                (
                  'Default category',
                  _choice('defaultCat', 'Default category', {
                    for (final cat in {
                      ...context.watch<NoteViewModel>().categories,
                      'Personal'
                    })
                      cat: cat
                  })
                ),
                (
                  'New note color',
                  _choice('defaultColor', 'New note color', {
                    'auto': 'Rotate automatically',
                    'blue': 'Powder blue',
                    'pink': 'Blush pink',
                    'mint': 'Mint',
                    'yellow': 'Butter yellow',
                    'peach': 'Peach',
                    'lav': 'Lavender'
                  })
                ),
                ('Spell check', _toggle('spellcheck', 'Spell check')),
                ('Show word count', _toggle('wordCount', 'Show word count'))
              ]),
              _group('Library & calendar', 'cal', [
                (
                  'Default view',
                  _choice('defaultView', 'Default view',
                      {'grid': 'Grid', 'list': 'List'})
                ),
                (
                  'Default sort',
                  _choice('defaultSort', 'Default sort', {
                    'Last edited': 'Last edited',
                    'Date created': 'Date created',
                    'Title A–Z': 'Title A–Z'
                  })
                ),
                (
                  'Week starts on',
                  _choice('weekStart', 'Week starts on',
                      {'mon': 'Monday', 'sun': 'Sunday'})
                ),
                (
                  'Show note dots on Home Activity markers in the week strip',
                  _toggle('calendarDots', 'Show note dots on Home',
                      'Activity markers in the week strip')
                )
              ]),
              _group(
                  'Noted AI',
                  'spark',
                  [
                    (
                      'Enable Noted AI',
                      _toggle('aiEnabled', 'Enable Noted AI',
                          'Show AI in the tab bar and editor')
                    ),
                    if (s.aiEnabled) ...[
                      (
                        'Response length',
                        _choice('aiLength', 'Response length', {
                          'concise': 'Concise',
                          'balanced': 'Balanced',
                          'detailed': 'Detailed'
                        })
                      ),
                      (
                        'Tone',
                        _choice('aiTone', 'Tone',
                            {'friendly': 'Friendly', 'academic': 'Academic'})
                      ),
                      (
                        'Always show sources',
                        _toggle('aiSources', 'Always show sources',
                            'List the notes each answer is based on')
                      ),
                      (
                        'Keep chat history',
                        _toggle('aiHistory', 'Keep chat history')
                      ),
                      (
                        'Clear AI chat history',
                        _row(
                            'Clear AI chat history',
                            () => _confirm(
                                'Clear AI chat history?',
                                'This permanently removes your saved AI conversations.',
                                'Clear',
                                () => _action(_clearAiHistory,
                                    'AI chat history cleared')))
                      )
                    ]
                  ],
                  note: 'AI never changes a note without your approval.'),
              _group('Sharing & collaboration', 'people', [
                (
                  'Who can send requests',
                  _choice('requests', 'Who can send requests', {
                    'everyone': 'Everyone',
                    'mutual': 'Friends of connections',
                    'nobody': 'No one'
                  })
                ),
                (
                  'Default live permission',
                  _choice(
                      'livePerm',
                      'Default live permission',
                      {'edit': 'Can edit', 'view': 'Can view'},
                      'For new collaborators')
                ),
                (
                  'Show my presence',
                  _toggle('presence', 'Show my presence',
                      'Let others see when you’re in a live note')
                ),
                (
                  'Allow copies to be re-shared',
                  _toggle('reshare', 'Allow copies to be re-shared')
                )
              ]),
              _group('Notifications', 'bell', [
                ('Live note activity', _toggle('nLive', 'Live note activity')),
                (
                  'Connection requests',
                  _toggle('nRequests', 'Connection requests')
                ),
                (
                  'Notes shared with me',
                  _toggle('nCopies', 'Notes shared with me')
                ),
                (
                  'Weekly recap',
                  _toggle('nRecap', 'Weekly recap', 'A short Sunday summary')
                ),
                (
                  'Quiet hours',
                  _toggle('quietHours', 'Quiet hours',
                      'Silence notifications 10 pm – 7 am')
                )
              ]),
              _group('Privacy & data', 'lock', [
                (
                  'App lock',
                  _toggle('appLock', 'App lock',
                      'Require fingerprint or PIN to open')
                ),
                (
                  'Share anonymous usage data',
                  _toggle('analytics', 'Share anonymous usage data')
                ),
                (
                  'Export all notes',
                  _row('Export all notes',
                      () => _action(() => ExportService().share(notes)),
                      desc: 'Download a JSON file',
                      value: '${notes.length} notes')
                ),
                (
                  'Recently deleted',
                  _row(
                      'Recently deleted',
                      () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                              builder: (_) => const RecentlyDeletedPage())),
                      desc: 'Restore or permanently delete notes')
                ),
                (
                  'Reset settings',
                  _row(
                      'Reset settings',
                      () => _confirm(
                              'Reset all settings?',
                              'Appearance, writing, AI and notification preferences go back to defaults. Your notes aren’t affected.',
                              'Reset', () async {
                            if (await vm.reset()) _toast('Settings reset');
                          }))
                )
              ]),
              _group('Support & about', 'help', [
                (
                  'Send feedback',
                  _row(
                      'Send feedback',
                      () => _action(() async {
                            if (!await launchUrl(Uri(
                                scheme: const String.fromEnvironment(
                                            'NOTED_FEEDBACK_EMAIL')
                                        .isEmpty
                                    ? 'https'
                                    : 'mailto',
                                host: const String.fromEnvironment(
                                            'NOTED_FEEDBACK_EMAIL')
                                        .isEmpty
                                    ? 'github.com'
                                    : null,
                                path: const String.fromEnvironment(
                                            'NOTED_FEEDBACK_EMAIL')
                                        .isEmpty
                                    ? '/deserveto/noted/issues/new'
                                    : const String.fromEnvironment(
                                        'NOTED_FEEDBACK_EMAIL')))) {
                              throw StateError(
                                  'Couldn’t open feedback. Try again after checking your connection.');
                            }
                          }))
                ),
                ('Version', _row('Version', null, value: _version))
              ]),
              if (_query.isNotEmpty && _matchingRows == 0)
                Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Text('No settings match “$_query”.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 14, color: Theme.of(context).hintColor))),
              if (_query.isEmpty) ...[
                const SizedBox(height: 32),
                OutlinedButton(
                    onPressed: () => _confirm(
                            'Log out of Noted?',
                            'Your saved notes will be here when you sign in again.',
                            'Log out', () async {
                          await auth.signOut();
                          if (context.mounted) {
                            Navigator.popUntil(
                                context, (route) => route.isFirst);
                          }
                        }),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56)),
                    child: const Text('Log out')),
                TextButton(
                    onPressed: _delete,
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        minimumSize: const Size.fromHeight(48)),
                    child: const Text('Delete account')),
                Text('Settings apply instantly and sync across your devices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor))
              ],
            ]));
  }

  Future<void> _confirm(String title, String body, String cta,
      Future<void> Function() action) async {
    final accepted = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (c) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(body),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: OutlinedButton(
                                onPressed: () => Navigator.pop(c, false),
                                child: const Text('Cancel'))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: FilledButton(
                                onPressed: () => Navigator.pop(c, true),
                                child: Text(cta)))
                      ])
                    ]))));
    if (accepted == true) await action();
  }

  Future<void> _password() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => const _AccountForm(mode: 'password'));
  }

  Future<void> _delete() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => const _AccountForm(mode: 'delete'));
  }
}

String profileInitials(String name) => name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join()
        .isEmpty
    ? '?'
    : name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
Future<void> showEditProfile(BuildContext context) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => const _AccountForm(mode: 'profile'));

Future<void> showPasswordRecoverySheet(BuildContext context) =>
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => const _AccountForm(mode: 'recovery'));

class _AccountForm extends StatefulWidget {
  const _AccountForm({required this.mode});
  final String mode;
  @override
  State<_AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<_AccountForm> {
  final _form = GlobalKey<FormState>();
  final _a = TextEditingController(),
      _b = TextEditingController(),
      _c = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _avatarUrl;
  @override
  void initState() {
    super.initState();
    if (widget.mode == 'profile') {
      final u = context.read<AuthViewModel>().user;
      _a.text = u?.name ?? '';
      _avatarUrl = u?.avatarUrl;
      _b.text = u?.fieldOfStudy ?? '';
    }
  }

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.mode == 'profile',
        deleting = widget.mode == 'delete',
        recovery = widget.mode == 'recovery';
    final title = profile
        ? 'Edit profile'
        : deleting
            ? 'Delete your account?'
            : recovery
                ? 'Set new password'
                : 'Change password';
    Widget field(String label, TextEditingController controller,
            {bool secret = false, String? Function(String?)? validator}) =>
        Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextFormField(
                controller: controller,
                obscureText: secret,
                validator: validator,
                decoration: InputDecoration(labelText: label),
                autovalidateMode: AutovalidateMode.onUserInteraction));
    return SafeArea(
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 24 + MediaQuery.viewInsetsOf(context).bottom),
            child: Form(
                key: _form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: deleting
                                  ? Theme.of(context).colorScheme.error
                                  : null)),
                      if (deleting)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                'This permanently removes your notes, connections and live-note memberships. Export your notes first if you want to keep them.')),
                      if (recovery)
                        const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                                'Choose a new password for your Noted account.')),
                      if (profile)
                        Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                                onPressed: _busy ? null : _pickAvatar,
                                icon: const Icon(Icons.add_a_photo_outlined),
                                label: const Text('Change photo'))),
                      if (!recovery)
                        field(
                            profile
                                ? 'Name'
                                : deleting
                                    ? 'Type DELETE to confirm'
                                    : 'Current password',
                            _a,
                            secret: !profile && !deleting,
                            validator: (v) => deleting
                                ? (v == 'DELETE'
                                    ? null
                                    : 'Type DELETE to confirm.')
                                : (v?.trim().isNotEmpty == true
                                    ? null
                                    : profile
                                        ? 'Name can’t be empty.'
                                        : 'Enter your current password.')),
                      field(
                          profile
                              ? 'Field of study'
                              : deleting
                                  ? 'Current password'
                                  : 'New password',
                          _b,
                          secret: !profile,
                          validator: profile
                              ? null
                              : (v) =>
                                  v == null || v.length < (deleting ? 1 : 8)
                                      ? deleting
                                          ? 'Enter your current password.'
                                          : 'Use at least 8 characters.'
                                      : null),
                      if (!profile && !deleting) ...[
                        ValueListenableBuilder(
                            valueListenable: _b,
                            builder: (context, value, child) {
                              final text = value.text;
                              final strength = (text.length >= 8 ? 1 : 0) +
                                  (RegExp('[A-Z]').hasMatch(text) &&
                                          RegExp('[a-z]').hasMatch(text)
                                      ? 1
                                      : 0) +
                                  (RegExp(r'\d|[^\w]').hasMatch(text) ? 1 : 0);
                              return Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        LinearProgressIndicator(
                                            value: strength / 3, minHeight: 4),
                                        const SizedBox(height: 4),
                                        Text(
                                            text.isEmpty
                                                ? '8+ characters, mixed case and a number or symbol'
                                                : [
                                                    'Weak',
                                                    'Weak',
                                                    'Okay',
                                                    'Strong'
                                                  ][strength],
                                            style:
                                                const TextStyle(fontSize: 12))
                                      ]));
                            }),
                        field('Confirm new password', _c,
                            secret: true,
                            validator: (v) =>
                                v != _b.text ? 'Passwords don’t match.' : null)
                      ],
                      if (_error != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error))),
                      const SizedBox(height: 20),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                              onPressed: _busy ? null : _save,
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : Text(profile
                                      ? 'Save'
                                      : deleting
                                          ? 'Delete account'
                                          : recovery
                                              ? 'Set new password'
                                              : 'Update password'))),
                    ]))));
  }

  Future<void> _pickAvatar() async {
    try {
      final picked = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 85);
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _busy = true;
        _error = null;
      });
      final url = await context
          .read<AuthViewModel>()
          .uploadAvatar(await picked.readAsBytes());
      if (mounted) {
        setState(() {
          _avatarUrl = url;
          _busy = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString();
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final auth = context.read<AuthViewModel>();
    final ok = widget.mode == 'profile'
        ? await auth.updateProfile(
            name: _a.text, fieldOfStudy: _b.text, avatarUrl: _avatarUrl)
        : widget.mode == 'delete'
            ? await auth.deleteAccount(_b.text)
            : widget.mode == 'recovery'
                ? await auth.completePasswordRecovery(_b.text)
                : await auth.changePassword(
                    currentPassword: _a.text, newPassword: _b.text);
    if (!mounted) return;
    if (ok) {
      if (widget.mode == 'delete') {
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        Navigator.pop(context);
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.mode == 'profile'
              ? 'Profile updated'
              : widget.mode == 'delete'
                  ? 'Account deleted'
                  : 'Password changed')));
    } else {
      setState(() {
        _busy = false;
        _error = auth.errorMessage;
      });
    }
  }
}
