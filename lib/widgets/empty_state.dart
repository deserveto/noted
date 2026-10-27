import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class EmptyState extends StatelessWidget {
  const EmptyState(
      {super.key,
      required this.title,
      required this.message,
      this.icon = Icons.notes_rounded,
      this.actionLabel,
      this.onAction});
  final String title, message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Theme.of(context).dividerColor)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ExcludeSemantics(
            child: SizedBox(
                width: 80,
                height: 66,
                child: Stack(children: [
                  Positioned(
                      left: 8,
                      top: 4,
                      child: Transform.rotate(
                          angle: -.1,
                          child: Container(
                              width: 44,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: AppColors.noteColorFor(
                                      Theme.of(context).brightness, 0),
                                  borderRadius: BorderRadius.circular(10))))),
                  Positioned(
                      right: 8,
                      child: Transform.rotate(
                          angle: .1,
                          child: Container(
                              width: 44,
                              height: 48,
                              decoration: BoxDecoration(
                                  color: AppColors.noteColorFor(
                                      Theme.of(context).brightness, 3),
                                  borderRadius: BorderRadius.circular(10)))))
                ]))),
        Text(title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        if (actionLabel != null) ...[
          const SizedBox(height: 20),
          FilledButton(onPressed: onAction, child: Text(actionLabel!))
        ],
      ]));
}
