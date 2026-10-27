import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'media_url_resolver.dart';
import 'supabase_service.dart';

/// Stores attachments inside the private `note-media` bucket so only authorized
/// note members can mint short-lived signed URLs.
class AttachmentService {
  AttachmentService({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? SupabaseService.client;

  Future<Map<String, dynamic>> upload({
    required String noteId,
    required Uint8List bytes,
    required String type,
    required String name,
    required String contentType,
    int? duration,
  }) async {
    if (bytes.length > 20 * 1024 * 1024) {
      throw StateError('Attachments must be smaller than 20 MB.');
    }
    final uid = _client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) {
      throw StateError('Sign in to attach files.');
    }

    final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final objectPath =
        'users/$uid/notes/$noteId/${DateTime.now().microsecondsSinceEpoch}_$safeName';

    await _client.storage.from(MediaUrlResolver.noteMediaBucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false,
          ),
        );

    final canonicalUri = MediaUrlResolver.canonicalUri(
      MediaUrlResolver.noteMediaBucket,
      objectPath,
    );
    // Warm the signed URL cache immediately so the editor renders without delay.
    await MediaUrlResolver.resolve(
      canonicalUri,
      fallbackPath: objectPath,
      clientOverride: _clientOverride,
    );

    return {
      'type': type,
      'name': name,
      'path': objectPath,
      'url': canonicalUri,
      if (duration != null) 'duration': duration,
    };
  }
}
