import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/note_model.dart';
import '../utils/app_colors.dart';
import '../utils/markdown_formatter.dart';

class NoteCard extends StatelessWidget {
  const NoteCard({
    required this.note,
    required this.color,
    required this.onTap,
    required this.onFavoritePressed,
    this.compact = false,
    super.key,
  });

  final NoteModel note;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onFavoritePressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final onCard =
        color.computeLuminance() > 0.45 ? AppColors.text : AppColors.darkText;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ).copyWith(color: onCard),
                    ),
                  ),
                  InkResponse(
                    onTap: onFavoritePressed,
                    radius: 20,
                    child: Icon(
                      note.isFavorite
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 20,
                      color: onCard,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  MarkdownFormatter.toPlainText(note.content),
                  maxLines: compact ? 2 : 7,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    height: 1.35,
                    fontSize: 13,
                  ).copyWith(color: onCard),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _MetaChip(label: '#${note.category}', baseColor: color),
                  if (note.ownerName.isNotEmpty)
                    _MetaChip(label: 'By ${note.ownerName}', baseColor: color),
                  _MetaChip(
                    label: DateFormat('dd MMM yyyy').format(note.updatedAt),
                    baseColor: color,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.label,
    required this.baseColor,
  });

  final String label;
  final Color baseColor;

  @override
  Widget build(BuildContext context) {
    final isLight = baseColor.computeLuminance() > 0.45;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isLight
            ? Colors.white.withValues(alpha: 0.78)
            : Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isLight ? AppColors.text : AppColors.darkText,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
