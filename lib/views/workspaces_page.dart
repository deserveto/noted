import 'package:flutter/material.dart';
import '../models/workspace_model.dart';
import '../repositories/workspace_repository.dart';

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
              ListTile(
                  title: const Text('Default'),
                  trailing: current == WorkspaceSelection.defaultWorkspaceId
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.pop(
                      ctx, WorkspaceSelection.defaultWorkspaceId)),
              for (final workspace in values)
                ListTile(
                    title: Text(workspace.name),
                    trailing: current == workspace.id
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(ctx, workspace.id)),
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
  late Future<List<PersonalWorkspace>> _items;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _items = Future.sync(() => WorkspaceRepository().list());
  }

  Future<void> _edit([PersonalWorkspace? item]) async {
    final controller = TextEditingController(text: item?.name ?? '');
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
        await repo.rename(item.id, value);
      }
      if (mounted) setState(_refresh);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save workspace.')));
      }
    }
  }

  Future<void> _delete(PersonalWorkspace item) async {
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
      await WorkspaceRepository().delete(item.id);
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
      body: FutureBuilder<List<PersonalWorkspace>>(
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
                    title: Text(item.name),
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
