import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/app_colors.dart';
import '../utils/app_routes.dart';
import '../viewmodels/settings_viewmodel.dart';
import '../widgets/noted_ui.dart';
import '../widgets/reference_icon.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

enum _Lens {
  notes('Notes'),
  workspaces('Workspaces'),
  ask('Ask Noted');

  const _Lens(this.label);
  final String label;
}

class _WelcomePageState extends State<WelcomePage> {
  _Lens _lens = _Lens.notes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context) ||
        context.select((SettingsViewModel vm) => vm.settings.reduceMotion);
    final folio = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 4,
          children: [
            for (final lens in _Lens.values)
              Semantics(
                selected: lens == _lens,
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor:
                        lens == _lens ? colors.onPrimary : colors.onSurface,
                    backgroundColor:
                        lens == _lens ? colors.primary : Colors.transparent,
                  ),
                  onPressed: () => setState(() => _lens = lens),
                  child: Text(lens.label),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: reduced ? Duration.zero : const Duration(milliseconds: 200),
          child: _Folio(key: ValueKey(_lens), lens: _lens),
        ),
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: NotedBrand(size: 30),
                  ),
                  const SizedBox(height: 24),
                  Text.rich(
                    TextSpan(
                      text: 'Quiet focus for\n',
                      children: [
                        TextSpan(
                          text: 'notes and shared work.',
                          style: TextStyle(
                            fontFamily: 'Newsreader',
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w400,
                            fontVariations: const [FontVariation('opsz', 34)],
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                    style: theme.textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Keep your notes in one place, organize projects in workspaces, and choose who can view or edit shared notes.',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: reduced
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 6 * (1 - value)),
                        child: child,
                      ),
                    ),
                    child: folio,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.signUp),
                    child: const Text('Create an account'),
                  ),
                  TextButton(
                    style:
                        TextButton.styleFrom(minimumSize: const Size(44, 44)),
                    onPressed: () =>
                        Navigator.pushNamed(context, AppRoutes.signIn),
                    child: const Text('Sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Folio extends StatelessWidget {
  const _Folio({super.key, required this.lens});

  final _Lens lens;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (label, title, details) = switch (lens) {
      _Lens.notes => (
          'Sample note · Strategy',
          'Q4 product rollout',
          [
            ('check', 'Confirm sign-in permissions'),
            ('check', 'Share the rollout brief'),
            ('mic', '1:15 voice note'),
          ],
        ),
      _Lens.workspaces => (
          'Sample workspaces',
          'A place for each project',
          [
            ('layers', 'Operations'),
            ('layers', 'Client delivery'),
            ('layers', 'Personal')
          ],
        ),
      _Lens.ask => (
          'Sample answer',
          'What needs to happen before launch?',
          [
            ('check', 'Confirm sign-in permissions'),
            ('check', 'Share the rollout brief'),
            ('notes', 'Source: Q4 product rollout'),
          ],
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: lens == _Lens.notes
            ? AppColors.noteColor(theme.brightness, 'yellow')
            : colors.surface,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: colors.onSurface)),
          const SizedBox(height: 4),
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          for (final (icon, detail) in details)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  ReferenceIcon(icon, size: 16, color: colors.onSurface),
                  const SizedBox(width: 8),
                  Expanded(child: Text(detail)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
