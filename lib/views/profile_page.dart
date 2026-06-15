import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/auth_viewmodel.dart';
import '../viewmodels/connection_viewmodel.dart';
import '../viewmodels/note_viewmodel.dart';
import '../viewmodels/theme_viewmodel.dart';
import '../widgets/custom_button.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthViewModel>();
    final notes = context.watch<NoteViewModel>();
    final connections = context.watch<ConnectionViewModel>();
    final theme = context.watch<ThemeViewModel>();
    final materialTheme = Theme.of(context);
    final user = auth.user;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Profile',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 34),
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: materialTheme.colorScheme.primary,
                      child: Text(
                        _initials(user?.name ?? 'Student'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      user?.name ?? 'Student',
                      style: materialTheme.textTheme.titleLarge?.copyWith(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user?.email ?? '',
                      style: materialTheme.textTheme.bodyMedium?.copyWith(
                        color: materialTheme.colorScheme.onSurface.withValues(
                          alpha: 0.62,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 34),
              _ProfileMetric(label: 'Total Notes', value: notes.totalNotes),
              const SizedBox(height: 12),
              _ProfileMetric(
                  label: 'Favorite Notes', value: notes.totalFavorites),
              const SizedBox(height: 12),
              _ProfileMetric(
                label: 'Connections',
                value: connections.acceptedConnections.length,
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: materialTheme.dividerColor),
                ),
                child: SwitchListTile(
                  value: theme.isDarkMode,
                  onChanged: theme.setDarkMode,
                  title: const Text(
                    'Dark Mode',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('Switch between light and dark theme'),
                  secondary: const Icon(Icons.dark_mode_outlined),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const Spacer(),
              CustomButton(
                label: 'Logout',
                icon: Icons.logout_rounded,
                isLoading: auth.isLoading,
                onPressed: () => context.read<AuthViewModel>().signOut(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return 'ST';
    }
    if (parts.length == 1) {
      final value = parts.first;
      return value.substring(0, value.length > 1 ? 2 : 1).toUpperCase();
    }
    return parts
        .take(2)
        .map((part) => part.isEmpty ? '' : part.substring(0, 1))
        .join()
        .toUpperCase();
  }
}

class _ProfileMetric extends StatelessWidget {
  const _ProfileMetric({
    required this.label,
    required this.value,
  });

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
