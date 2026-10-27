import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  const CustomButton(
      {required this.label,
      required this.onPressed,
      this.icon,
      this.isLoading = false,
      this.isSecondary = false,
      super.key});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isLoading, isSecondary;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = isSecondary
        ? theme.colorScheme.onSurface
        : theme.scaffoldBackgroundColor;
    final background =
        isSecondary ? theme.colorScheme.surface : theme.colorScheme.onSurface;
    return SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton(
            onPressed: isLoading ? null : onPressed,
            style: FilledButton.styleFrom(
                backgroundColor: background,
                foregroundColor: foreground,
                disabledBackgroundColor: background.withValues(alpha: .6),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                        color: isSecondary
                            ? theme.dividerColor
                            : Colors.transparent)),
                textStyle: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (isLoading) ...[
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: foreground)),
                const SizedBox(width: 10)
              ] else if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8)
              ],
              Flexible(
                  child:
                      Text(label, maxLines: 1, overflow: TextOverflow.ellipsis))
            ])));
  }
}
