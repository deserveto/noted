import 'package:flutter/material.dart';

class CategoryChips extends StatelessWidget {
  const CategoryChips(
      {super.key,
      required this.categories,
      required this.selectedCategory,
      required this.onSelected});
  final List<String> categories;
  final String selectedCategory;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        values = ['All', ...categories.where((c) => c != 'All')];
    return SizedBox(
        height: 44,
        child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: values.length,
            separatorBuilder: (_, i) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final on = values[i] == selectedCategory;
              return Semantics(
                  selected: on,
                  button: true,
                  child: OutlinedButton(
                      onPressed: () => onSelected(values[i]),
                      style: OutlinedButton.styleFrom(
                          backgroundColor: on
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.surface,
                          foregroundColor: on
                              ? theme.scaffoldBackgroundColor
                              : theme.colorScheme.onSurfaceVariant,
                          side: BorderSide(
                              color: on
                                  ? theme.colorScheme.onSurface
                                  : theme.dividerColor),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(horizontal: 16)),
                      child: Text(values[i],
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500))));
            }));
  }
}
