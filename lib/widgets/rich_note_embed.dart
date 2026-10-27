import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../services/media_url_resolver.dart';

/// Keeps imported documents readable when they contain inline media.
class RichNoteEmbed extends quill.EmbedBuilder {
  const RichNoteEmbed();

  @override
  String get key => 'image';

  @override
  Widget build(BuildContext context, quill.EmbedContext embedContext) {
    final embed = embedContext.node.value;
    final raw = '${embed.data}'.trim();
    final uri = Uri.tryParse(raw);
    final isImage = embed.type == 'image';
    final fallback = Container(
      padding: const EdgeInsets.all(16),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Text(isImage ? 'Image unavailable' : 'Embedded ${embed.type}'),
    );
    if (!isImage || raw.isEmpty) {
      return fallback;
    }

    final privateRef = MediaUrlResolver.parsePrivateRef(raw);
    final isExternalHttps = uri?.scheme == 'https' && uri!.host.isNotEmpty;
    if (privateRef == null && !isExternalHttps) {
      return fallback;
    }

    Widget buildImage(String resolvedUrl) => ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280),
          child: Image.network(
            resolvedUrl,
            fit: BoxFit.contain,
            semanticLabel: 'Note image',
            errorBuilder: (_, error, stackTrace) => fallback,
          ),
        );

    final immediate = MediaUrlResolver.peekResolved(raw);
    if (immediate != null) {
      return buildImage(immediate);
    }

    return FutureBuilder<String?>(
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
        return buildImage(resolved);
      },
    );
  }
}
