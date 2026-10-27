import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_service.dart';

class _CachedSignedUrl {
  const _CachedSignedUrl({required this.url, required this.expiresAt});
  final String url;
  final DateTime expiresAt;

  bool get isFresh => DateTime.now().isBefore(expiresAt);
}

/// Resolves private Supabase Storage references (`noted-media://<bucket>/<path>`
/// or raw object paths) into short-lived signed URLs with a per-session TTL cache.
///
/// Signed URLs expire on the server after 60 minutes (`signedUrlTtlSeconds = 3600`);
/// the client refreshes cached entries after 50 minutes and clears all entries on
/// sign-out or account switch.
class MediaUrlResolver {
  MediaUrlResolver._();

  static const int signedUrlTtlSeconds = 3600;
  static const Duration _cacheValidDuration = Duration(minutes: 50);
  static const String schemePrefix = 'noted-media://';
  static const String noteMediaBucket = 'note-media';
  static const String avatarsBucket = 'avatars';

  static final Map<String, _CachedSignedUrl> _cache = {};
  static Future<String> Function(String bucket, String path)? _signerOverride;

  static void setSignerForTesting(
    Future<String> Function(String bucket, String path)? signer,
  ) {
    _signerOverride = signer;
  }

  static void clearCache() {
    _cache.clear();
  }

  static String canonicalUri(String bucket, String path) {
    final clean = path.replaceFirst(RegExp(r'^/+'), '');
    return '$schemePrefix$bucket/$clean';
  }

  static ({String bucket, String path})? parsePrivateRef(
    String reference, {
    String? fallbackPath,
    String defaultBucket = noteMediaBucket,
  }) {
    final trimmed = reference.trim();
    if (trimmed.startsWith(schemePrefix)) {
      final rest = trimmed.substring(schemePrefix.length);
      final slash = rest.indexOf('/');
      if (slash > 0 && slash < rest.length - 1) {
        return (
          bucket: rest.substring(0, slash),
          path: rest.substring(slash + 1),
        );
      }
    }

    final candidatePath = (fallbackPath != null && fallbackPath.trim().isNotEmpty)
        ? fallbackPath.trim()
        : (!trimmed.startsWith('http://') &&
                !trimmed.startsWith('https://') &&
                trimmed.startsWith('users/'))
            ? trimmed
            : '';

    if (candidatePath.isNotEmpty) {
      final clean = candidatePath.replaceFirst(RegExp(r'^/+'), '');
      final bucket = clean.contains('/notes/') ? noteMediaBucket : defaultBucket;
      return (bucket: bucket, path: clean);
    }

    return null;
  }

  /// Synchronous lookup if a fresh signed URL or direct external `https://` URL is ready.
  static String? peekResolved(
    String reference, {
    String? fallbackPath,
    String defaultBucket = noteMediaBucket,
  }) {
    final parsed = parsePrivateRef(
      reference,
      fallbackPath: fallbackPath,
      defaultBucket: defaultBucket,
    );
    if (parsed == null) {
      final trimmed = reference.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final key = '${parsed.bucket}/${parsed.path}';
    final cached = _cache[key];
    if (cached != null && cached.isFresh) {
      return cached.url;
    }
    return null;
  }

  static Future<String?> resolve(
    String reference, {
    String? fallbackPath,
    String defaultBucket = noteMediaBucket,
    SupabaseClient? clientOverride,
  }) async {
    final immediate = peekResolved(
      reference,
      fallbackPath: fallbackPath,
      defaultBucket: defaultBucket,
    );
    if (immediate != null) return immediate;

    final parsed = parsePrivateRef(
      reference,
      fallbackPath: fallbackPath,
      defaultBucket: defaultBucket,
    );
    if (parsed == null) {
      final trimmed = reference.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final key = '${parsed.bucket}/${parsed.path}';
    try {
      final String signed;
      if (_signerOverride != null) {
        signed = await _signerOverride!(parsed.bucket, parsed.path);
      } else {
        final client = clientOverride ?? SupabaseService.maybeClient;
        if (client == null) return null;
        signed = await client.storage
            .from(parsed.bucket)
            .createSignedUrl(parsed.path, signedUrlTtlSeconds);
      }

      _cache[key] = _CachedSignedUrl(
        url: signed,
        expiresAt: DateTime.now().add(_cacheValidDuration),
      );
      return signed;
    } catch (_) {
      return null;
    }
  }
}
