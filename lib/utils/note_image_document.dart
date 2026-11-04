import 'package:dart_quill_delta/dart_quill_delta.dart';
import 'package:flutter/widgets.dart' show TextSelection;
import 'package:flutter_quill/flutter_quill.dart' as quill;

import '../services/media_url_resolver.dart';

/// A private or external image reference found in a Quill document.
class DocumentImageReference {
  const DocumentImageReference({
    required this.index,
    required this.reference,
  });

  final int index;
  final String reference;
}

/// Position-aware helpers for images stored in the canonical Quill document.
///
/// New images are private `noted-media://` references embedded in the document.
/// Legacy trailing attachments remain readable and can be moved into the
/// document without deleting their stored metadata or media.
class NoteImageDocument {
  NoteImageDocument._();

  static List<DocumentImageReference> images(quill.Document document) {
    final found = <DocumentImageReference>[];
    var offset = 0;
    for (final operation in document.toDelta().operations) {
      final length = operation.length ?? 0;
      final data = operation.data;
      if (operation.isInsert &&
          data is Map &&
          data['image'] is String &&
          (data['image'] as String).trim().isNotEmpty) {
        found.add(DocumentImageReference(
          index: offset,
          reference: (data['image'] as String).trim(),
        ));
      }
      offset += length;
    }
    return found;
  }

  static String? imageAt(quill.Document document, int index) {
    for (final image in images(document)) {
      if (image.index == index) return image.reference;
    }
    return null;
  }

  static int? indexOf(
    quill.Document document,
    String reference, {
    int? nearestTo,
  }) {
    final matches = images(document)
        .where((image) => image.reference == reference)
        .toList();
    if (matches.isEmpty) return null;
    if (nearestTo == null) return matches.first.index;
    matches.sort((a, b) =>
        (a.index - nearestTo).abs().compareTo((b.index - nearestTo).abs()));
    return matches.first.index;
  }

  /// Canonical comparison key for an image reference.
  ///
  /// External HTTPS URLs stay as-is. Private storage references are normalized
  /// so a legacy attachment URL and an inline embed path compare equal.
  static String canonicalReference(String reference) {
    final trimmed = reference.trim();
    final parsed = MediaUrlResolver.parsePrivateRef(trimmed);
    if (parsed != null) {
      return MediaUrlResolver.canonicalUri(parsed.bucket, parsed.path);
    }
    return trimmed;
  }

  /// Returns the private canonical URI for an image attachment, if available.
  static String? attachmentReference(Map<String, dynamic> attachment) {
    final url = (attachment['url'] as String?)?.trim() ?? '';
    final path = (attachment['path'] as String?)?.trim() ?? '';
    final parsed = MediaUrlResolver.parsePrivateRef(
      url,
      fallbackPath: path,
    );
    if (parsed != null) {
      return MediaUrlResolver.canonicalUri(parsed.bucket, parsed.path);
    }
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    if (path.isNotEmpty) {
      return MediaUrlResolver.canonicalUri(
          MediaUrlResolver.noteMediaBucket, path);
    }
    return null;
  }

  static String attachmentKey(Map<String, dynamic> attachment) =>
      '${attachment['path'] ?? attachment['url'] ?? attachment['name'] ?? ''}';

  /// Insert an image at [offset] in the live editor and place the caret after it.
  static bool insertImage(
    quill.QuillController controller,
    int offset,
    String reference,
  ) {
    final document = controller.document;
    final maximum = (document.length - 1).clamp(0, document.length);
    final at = offset.clamp(0, maximum);
    if (reference.trim().isEmpty) return false;
    controller.replaceText(at, 0, quill.BlockEmbed.image(reference), null);
    _placeCaretAfterImage(controller, at);
    return true;
  }

  /// Move one image from [from] to the insertion point [to].
  ///
  /// The deletion and insertion are composed as one Quill change so a single
  /// undo/redo restores both positions without duplicating the image or losing
  /// surrounding text.
  static bool moveImage(
    quill.QuillController controller, {
    required int from,
    required int to,
  }) {
    final document = controller.document;
    final reference = imageAt(document, from);
    if (reference == null) return false;
    final maximum = (document.length - 1).clamp(0, document.length);
    final destination = to.clamp(0, maximum);
    // The image already occupies [from]; inserting directly before or after it
    // leaves the visible order unchanged.
    if (destination == from || destination == from + 1) {
      controller.updateSelection(
        TextSelection.collapsed(offset: (from + 1).clamp(0, maximum)),
        quill.ChangeSource.local,
      );
      return true;
    }

    final change = Delta();
    if (destination < from) {
      if (destination > 0) change.retain(destination);
      change.insert({'image': reference});
      if (from - destination > 0) change.retain(from - destination);
      change.delete(1);
    } else {
      if (from > 0) change.retain(from);
      change.delete(1);
      final between = destination - from - 1;
      if (between > 0) change.retain(between);
      change.insert({'image': reference});
    }
    controller.compose(
      change,
      const TextSelection.collapsed(offset: 0),
      quill.ChangeSource.local,
    );
    final placedAt = destination < from ? destination : destination - 1;
    _placeCaretAfterImage(controller, placedAt);
    return true;
  }

  static void _placeCaretAfterImage(
      quill.QuillController controller, int imageIndex) {
    final maximum =
        (controller.document.length - 1).clamp(0, controller.document.length);
    controller.updateSelection(
      TextSelection.collapsed(offset: (imageIndex + 1).clamp(0, maximum)),
      quill.ChangeSource.local,
    );
  }
}

/// Tracks a document insertion point while a picker/upload is in flight.
///
/// Local typing and remote document replacements both flow through
/// [update]; an insertion at the anchor keeps the anchor before the new text,
/// which preserves the user's original intent.
class DocumentInsertionAnchor {
  DocumentInsertionAnchor({
    required quill.Document document,
    required int offset,
  })  : _snapshot = document.toDelta(),
        _offset =
            offset.clamp(0, (document.length - 1).clamp(0, document.length));

  Delta _snapshot;
  int _offset;

  int get offset => _offset;

  void update(quill.Document document) {
    final current = document.toDelta();
    if (current == _snapshot) return;
    final change = _snapshot.diff(current);
    _offset = change
        .transformPosition(_offset, force: false)
        .clamp(0, (document.length - 1).clamp(0, document.length));
    _snapshot = current;
  }
}

/// Follows a specific image through local and remote document changes.
class DocumentImageAnchor {
  DocumentImageAnchor({
    required quill.Document document,
    required this.reference,
    required int index,
  })  : _snapshot = document.toDelta(),
        _index = index,
        _valid = NoteImageDocument.imageAt(document, index) == reference;

  final String reference;
  Delta _snapshot;
  int _index;
  bool _valid;

  int get index => _index;
  bool get isValid => _valid;

  void update(quill.Document document) {
    final current = document.toDelta();
    if (current == _snapshot) {
      _valid =
          _valid && NoteImageDocument.imageAt(document, _index) == reference;
      return;
    }
    final change = _snapshot.diff(current);
    _index = change
        .transformPosition(_index, force: true)
        .clamp(0, (document.length - 1).clamp(0, document.length));
    _snapshot = current;
    _valid = NoteImageDocument.imageAt(document, _index) == reference;
  }
}
