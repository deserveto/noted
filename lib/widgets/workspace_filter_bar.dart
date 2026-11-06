import 'package:flutter/material.dart';

import '../models/workspace_model.dart';
import '../viewmodels/note_viewmodel.dart';
import '../views/workspaces_page.dart';
import 'noted_ui.dart';
import 'reference_icon.dart';

class WorkspaceFilterBar extends StatelessWidget {
  const WorkspaceFilterBar({
    super.key,
    required this.workspaces,
    required this.selection,
    required this.selectionLabel,
    required this.status,
    required this.assignmentsKnown,
    required this.errorMessage,
    required this.onSelected,
    required this.onReset,
    required this.onRetry,
  });

  final List<PersonalWorkspace> workspaces;
  final WorkspaceSelection selection;
  final String selectionLabel;
  final WorkspaceLibraryStatus status;
  final bool assignmentsKnown;
  final String? errorMessage;
  final ValueChanged<WorkspaceSelection> onSelected;
  final VoidCallback onReset;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Workspace filter',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: 'Filter notes by workspace',
                  child: OutlinedButton(
                    key: const ValueKey('workspace-filter-button'),
                    onPressed: () => _showChoices(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      shape: const StadiumBorder(),
                      side: BorderSide(color: theme.dividerColor),
                    ),
                    child: Row(
                      children: [
                        const ReferenceIcon('layers', size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            selectionLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const ReferenceIcon('downArrow', size: 16),
                      ],
                    ),
                  ),
                ),
              ),
              if (!selection.isAll) ...[
                const SizedBox(width: 4),
                TextButton(
                  key: const ValueKey('workspace-filter-reset'),
                  onPressed: onReset,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(64, 44),
                  ),
                  child: const Text('Reset'),
                ),
              ],
            ],
          ),
          if (status == WorkspaceLibraryStatus.loading) ...[
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              label: 'Loading workspaces',
              child: const LinearProgressIndicator(minHeight: 2),
            ),
          ] else if (status == WorkspaceLibraryStatus.cached) ...[
            const SizedBox(height: 7),
            if (errorMessage == null)
              Semantics(
                liveRegion: true,
                child: Text(
                  'Saved workspace data',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '$errorMessage Showing saved workspace data.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ),
          ] else if (status == WorkspaceLibraryStatus.unavailable) ...[
            const SizedBox(height: 8),
            InlineError(
              errorMessage ??
                  'Workspace assignments are unavailable. All workspaces still shows every note.',
              onRetry: onRetry,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showChoices(BuildContext context) async {
    final value = await notedSheet<WorkspaceSelection>(
      context,
      label: 'Filter by workspace',
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(
              'Filter by workspace',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            _WorkspaceChoice(
              key: const ValueKey('workspace-option-all'),
              label: 'All workspaces',
              selected: selection.isAll,
              onTap: () => Navigator.pop(context, WorkspaceSelection.all),
            ),
            _WorkspaceChoice(
              key: const ValueKey('workspace-option-default'),
              label: 'Default',
              selected: selection.isDefault,
              enabled: assignmentsKnown,
              onTap: () =>
                  Navigator.pop(context, WorkspaceSelection.defaultWorkspace),
            ),
            for (final workspace in workspaces)
              _WorkspaceChoice(
                key: ValueKey('workspace-option-${workspace.id}'),
                label: workspace.name,
                selected: selection.workspaceId == workspace.id,
                enabled: assignmentsKnown,
                onTap: () => Navigator.pop(
                  context,
                  WorkspaceSelection.named(workspace.id),
                ),
              ),
            if (!assignmentsKnown)
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Text(
                  'Assignments are unavailable until workspace data can be loaded.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const Divider(height: 24),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const ReferenceIcon('gear'),
              title: const Text('Manage workspaces'),
              onTap: () async {
                final navigator = Navigator.of(context);
                Navigator.pop(context);
                await navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => const WorkspacesPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
    if (value != null) onSelected(value);
  }
}

class _WorkspaceChoice extends StatelessWidget {
  const _WorkspaceChoice({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      enabled: enabled,
      child: ListTile(
        enabled: enabled,
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        minVerticalPadding: 12,
        title: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        trailing: selected
            ? ReferenceIcon('check', color: theme.colorScheme.primary)
            : null,
        onTap: enabled ? onTap : null,
      ),
    );
  }
}
