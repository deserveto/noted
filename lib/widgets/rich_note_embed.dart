import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../services/media_url_resolver.dart';
import 'reference_icon.dart';

typedef NoteImageMoveCallback = void Function(String reference, int index);

/// Keeps imported documents readable when they contain inline media.
class RichNoteEmbed extends quill.EmbedBuilder {
  const RichNoteEmbed({this.onMove});

  final NoteImageMoveCallback? onMove;

  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final embed = embedContext.node.value;
    return NoteImageEmbed(
      reference: '${embed.data}'.trim(),
      type: embed.type,
      index: embedContext.node.documentOffset,
      onMove: embedContext.readOnly ? null : onMove,
    );
  }
}

/// Rendered inline image with an optional explicit movement control.
class NoteImageEmbed extends StatelessWidget {
  const NoteImageEmbed({
    required this.reference,
    required this.type,
    required this.index,
    this.onMove,
    super.key,
  });

  final String reference;
  final String type;
  final int index;
  final NoteImageMoveCallback? onMove;

  @override
  Widget build(BuildContext context) {
    final raw = reference.trim();
    final uri = Uri.tryParse(raw);
    final isImage = type == 'image';
    final fallback = Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(isImage ? 'Image unavailable' : 'Embedded $type'),
    );
    if (!isImage || raw.isEmpty) {
      return fallback;
    }

    final privateRef = MediaUrlResolver.parsePrivateRef(raw);
    final isExternalHttps = uri?.scheme == 'https' && uri!.host.isNotEmpty;
    if (privateRef == null && !isExternalHttps) {
      return fallback;
    }

    final immediate = MediaUrlResolver.peekResolved(raw);
    final Widget image;
    if (immediate != null) {
      image = _loadedImage(immediate, fallback);
    } else {
      image = FutureBuilder<String?>(
        future: MediaUrlResolver.resolve(raw),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const LinearProgressIndicator(),
            );
          }
          final resolved = snapshot.data;
          if (resolved == null || resolved.isEmpty) {
            return fallback;
          }
          return _loadedImage(resolved, fallback);
        },
      );
    }
    if (onMove == null) return image;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        image,
        Positioned(
          right: 4,
          top: 4,
          child: IconButton.filledTonal(
            tooltip: 'Move image',
            onPressed: () => onMove!(raw, index),
            style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
            icon: const ReferenceIcon('target', size: 18),
          ),
        ),
      ],
    );
  }

  Widget _loadedImage(String resolvedUrl, Widget fallback) => ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: Image.network(
          resolvedUrl,
          fit: BoxFit.contain,
          semanticLabel: 'Note image',
          errorBuilder: (_, error, stackTrace) => fallback,
        ),
      );
}
