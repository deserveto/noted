import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/connection_model.dart';
import '../utils/app_colors.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../widgets/empty_state.dart';

class ConnectionsPage extends StatefulWidget {
  const ConnectionsPage({super.key});

  @override
  State<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends State<ConnectionsPage> {
  final _emailController = TextEditingController();
  bool _showAddConnection = false;
  bool _isSendingRequest = false;
  String? _emailError;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Register dependency on Theme to rebuild when theme changes (fixes IndexedStack cache theme bug)
    Theme.of(context);
    final connections = context.watch<ConnectionViewModel>();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Connections',
                      style:
                          TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: 'Add Connection',
                    onPressed: () {
                      setState(() {
                        _showAddConnection = !_showAddConnection;
                        _emailError = null;
                      });
                    },
                    icon: Icon(
                      _showAddConnection
                          ? Icons.close_rounded
                          : Icons.person_add_alt_1_rounded,
                    ),
                  ),
                ],
              ),
              if (_showAddConnection) ...[
                const SizedBox(height: 14),
                _AddConnectionPanel(
                  controller: _emailController,
                  errorText: _emailError,
                  isLoading: connections.isLoading || _isSendingRequest,
                  onSubmit: () => _sendRequest(context),
                ),
              ],
              if (connections.errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: connections.errorMessage!),
              ],
              const SizedBox(height: 18),
              Expanded(
                child: connections.isLoading && connections.connections.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          _Section(
                            title: 'Incoming Requests',
                            emptyText: 'No incoming requests',
                            children: [
                              for (final connection
                                  in connections.incomingRequests)
                                _ConnectionTile(
                                  connection: connection,
                                  currentUserId: connections.user?.uid ?? '',
                                  trailing: Wrap(
                                    spacing: 4,
                                    children: [
                                      IconButton(
                                        tooltip: 'Accept',
                                        onPressed: () =>
                                            connections.accept(connection),
                                        icon: const Icon(Icons.check_rounded),
                                      ),
                                      IconButton(
                                        tooltip: 'Reject',
                                        onPressed: () =>
                                            connections.reject(connection),
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          _Section(
                            title: 'Connections',
                            emptyText: 'No accepted connections yet',
                            children: [
                              for (final connection
                                  in connections.acceptedConnections)
                                _ConnectionTile(
                                  connection: connection,
                                  currentUserId: connections.user?.uid ?? '',
                                  trailing: IconButton(
                                    tooltip: 'Remove Connection',
                                    onPressed: () => _confirmRemove(
                                        context, connections, connection),
                                    icon: Icon(
                                      Icons.person_remove_alt_1_rounded,
                                      color:
                                          Theme.of(context).colorScheme.error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          _Section(
                            title: 'Sent Requests',
                            emptyText: 'No pending sent requests',
                            children: [
                              for (final connection
                                  in connections.outgoingRequests)
                                _ConnectionTile(
                                  connection: connection,
                                  currentUserId: connections.user?.uid ?? '',
                                  trailing:
                                      const Icon(Icons.hourglass_top_rounded),
                                ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendRequest(BuildContext context) async {
    if (_isSendingRequest) {
      return;
    }

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _emailError = 'Email is required');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _emailError = 'Enter a valid email');
      return;
    }

    FocusScope.of(context).unfocus();
    final connections = context.read<ConnectionViewModel>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _emailError = null;
      _isSendingRequest = true;
    });

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) {
      return;
    }

    final sent = await connections.sendRequest(email);
    if (!mounted) {
      return;
    }

    setState(() => _isSendingRequest = false);
    if (sent) {
      _emailController.clear();
      setState(() => _showAddConnection = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Connection request sent')),
      );
    }
  }

  Future<void> _confirmRemove(
    BuildContext context,
    ConnectionViewModel connections,
    ConnectionModel connection,
  ) async {
    final currentUserId = connections.user?.uid ?? '';
    final otherName = connection.otherName(currentUserId);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove Connection'),
          content: Text(
            'Are you sure you want to remove $otherName from your connections? You can always reconnect later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final removed = await connections.removeConnection(connection);
    if (!context.mounted) return;

    if (removed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$otherName has been removed')),
      );
    }
  }
}

class _AddConnectionPanel extends StatelessWidget {
  const _AddConnectionPanel({
    required this.controller,
    required this.errorText,
    required this.isLoading,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => isLoading ? null : onSubmit(),
            decoration: InputDecoration(
              labelText: 'Friend email',
              prefixIcon: const Icon(Icons.mail_outline_rounded),
              errorText: errorText,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: isLoading ? null : onSubmit,
              icon: isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Send Request'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.emptyText,
    required this.children,
  });

  final String title;
  final String emptyText;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (children.isEmpty)
            EmptyState(
              title: emptyText,
              message: 'Connections will appear here.',
              icon: Icons.group_outlined,
            )
          else
            ...children,
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  const _ConnectionTile({
    required this.connection,
    required this.currentUserId,
    required this.trailing,
  });

  final ConnectionModel connection;
  final String currentUserId;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_outline_rounded)),
        title: Text(connection.otherName(currentUserId)),
        subtitle: Text(connection.otherEmail(currentUserId)),
        trailing: trailing,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.error)),
    );
  }
}
