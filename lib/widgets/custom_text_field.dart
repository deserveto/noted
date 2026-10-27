import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  const CustomTextField(
      {required this.controller,
      required this.label,
      this.hint,
      this.icon,
      this.keyboardType,
      this.obscureText = false,
      this.maxLines = 1,
      this.validator,
      this.onChanged,
      this.autofillHints,
      this.textInputAction,
      this.onFieldSubmitted,
      super.key});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final int maxLines;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged, onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: theme.dividerColor));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: obscureText ? 1 : maxLines,
          validator: validator,
          onChanged: onChanged,
          autofillHints: autofillHints,
          textInputAction: textInputAction,
          onFieldSubmitted: onFieldSubmitted,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: theme.colorScheme.surface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: theme.colorScheme.primary)),
              errorBorder: border.copyWith(
                  borderSide: BorderSide(color: theme.colorScheme.error)),
              prefixIcon: icon == null ? null : Icon(icon, size: 20)))
    ]);
  }
}
