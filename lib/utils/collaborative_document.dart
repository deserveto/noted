import 'package:dart_quill_delta/dart_quill_delta.dart';

import 'document_codec.dart';

/// Rebase local document operations on the current shared document. Inserts,
/// deletes and style changes remain operations rather than whole-note writes.
/// The already committed remote operation wins ties at the same position.
String mergeContent(
    {required String base, required String local, required String remote}) {
  if (local == base) return remote;
  if (remote == base || remote == local) return local;
  final baseDelta =
      Delta.fromJson(DocumentCodec.decode(base).toDelta().toJson());
  final localDelta =
      Delta.fromJson(DocumentCodec.decode(local).toDelta().toJson());
  final remoteDelta =
      Delta.fromJson(DocumentCodec.decode(remote).toDelta().toJson());
  final localChange = baseDelta.diff(localDelta);
  final remoteChange = baseDelta.diff(remoteDelta);
  final rebasedLocal = remoteChange.transform(localChange, true);
  final merged = remoteDelta.compose(rebasedLocal);
  return DocumentCodec.encode(DocumentCodec.fromDelta(merged.toJson()));
}
