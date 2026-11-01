import 'package:flutter/material.dart';
import '../services/supabase_service.dart';

class WorkspaceRepository {
  final _client = SupabaseService.client;
  String get _uid =>
      _client.auth.currentUser?.id ?? (throw StateError('Sign in required'));

  Future<List<Map<String, dynamic>>> list() async =>
      List<Map<String, dynamic>>.from(await _client
          .from('personal_workspaces')
          .select()
          .eq('user_id', _uid)
          .order('name'));
  Future<String> assignment(String noteId) async {
    final row = await _client
        .from('personal_workspace_notes')
        .select('workspace_id')
        .eq('user_id', _uid)
        .eq('note_id', noteId)
        .maybeSingle();
    return row?['workspace_id'] as String? ?? 'default';
  }

  Future<void> assign(String noteId, String workspaceId) async {
    if (workspaceId == 'default') {
      await _client
          .from('personal_workspace_notes')
          .delete()
          .eq('user_id', _uid)
          .eq('note_id', noteId);
    } else {
      await _client.from('personal_workspace_notes').upsert(
          {'user_id': _uid, 'note_id': noteId, 'workspace_id': workspaceId},
          onConflict: 'user_id,note_id');
    }
  }

  Future<void> create(String name) async => _client
      .from('personal_workspaces')
      .insert({'user_id': _uid, 'name': name});
  Future<void> rename(String id, String name) async => _client
      .from('personal_workspaces')
      .update({'name': name})
      .eq('user_id', _uid)
      .eq('id', id);
  Future<void> delete(String id) async => _client
      .from('personal_workspaces')
      .delete()
      .eq('user_id', _uid)
      .eq('id', id);
}

Future<String?> pickWorkspace(BuildContext context, {String? noteId}) async {
  try {
    final repo = WorkspaceRepository();
    final values = await repo.list();
    final current = noteId == null ? null : await repo.assignment(noteId);
    if (!context.mounted) return null;
    return await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
                child: ListView(shrinkWrap: true, children: [
              const ListTile(title: Text('Choose workspace')),
              for (final workspace in [
                {'id': 'default', 'name': 'Default'},
                ...values
              ])
                ListTile(
                    title: Text(workspace['name'] as String),
                    trailing: current == workspace['id']
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(ctx, workspace['id'] as String)),
              ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Manage workspaces'),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const WorkspacesPage()));
                  })
            ])));
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load workspaces. Check your connection.')));
    }
    return null;
  }
}

class WorkspacesPage extends StatefulWidget {
  const WorkspacesPage({super.key});
  @override
  State<WorkspacesPage> createState() => _WorkspacesPageState();
}

class _WorkspacesPageState extends State<WorkspacesPage> {
  late Future<List<Map<String, dynamic>>> _items;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _items = Future.sync(() => WorkspaceRepository().list());
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    final controller =
        TextEditingController(text: item?['name'] as String? ?? '');
    final value = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
                title:
                    Text(item == null ? 'New workspace' : 'Rename workspace'),
                content: TextField(
                    controller: controller, autofocus: true, maxLength: 100),
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
    if (value == null || value.isEmpty) return;
    try {
      final repo = WorkspaceRepository();
      if (item == null) {
        await repo.create(value);
      } else {
        await repo.rename(item['id'] as String, value);
      }
      if (mounted) setState(_refresh);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save workspace.')));
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Delete workspace?'),
                content: const Text('Its notes will return to Default.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Delete'))
                ]));
    if (confirmed != true) return;
    try {
      await WorkspaceRepository().delete(item['id'] as String);
      if (mounted) setState(_refresh);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not delete workspace.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Workspaces'), actions: [
        IconButton(
            tooltip: 'New workspace',
            onPressed: _edit,
            icon: const Icon(Icons.add))
      ]),
      body: FutureBuilder<List<Map<String, dynamic>>>(
          future: _items,
          builder: (ctx, snapshot) {
            if (snapshot.hasError) {
              return Center(
                  child: TextButton(
                      onPressed: () => setState(_refresh),
                      child:
                          const Text('Could not load workspaces. Try again')));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ListView(children: [
              const ListTile(
                  title: Text('Default'),
                  subtitle: Text('Notes without another workspace')),
              for (final item in snapshot.data!)
                ListTile(
                    title: Text(item['name'] as String),
                    trailing: PopupMenuButton<String>(
                        onSelected: (action) =>
                            action == 'rename' ? _edit(item) : _delete(item),
                        itemBuilder: (_) => const [
                              PopupMenuItem(
                                  value: 'rename', child: Text('Rename')),
                              PopupMenuItem(
                                  value: 'delete', child: Text('Delete'))
                            ]))
            ]);
          }));
}
