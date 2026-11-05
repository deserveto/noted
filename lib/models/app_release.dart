import 'installed_app.dart';

class ReleaseChange {
  const ReleaseChange(this.type, this.text);
  final String type, text;
}

/// Untrusted network metadata is validated before it reaches the UI.
class AppRelease {
  AppRelease._(
      {required this.id,
      required this.platform,
      required this.channel,
      required this.distribution,
      required this.version,
      required this.build,
      required this.publishedAt,
      required this.objectPath,
      required this.sizeBytes,
      required this.sha256,
      required this.minSdk,
      required this.changes});
  final String id, platform, channel, distribution, version, objectPath, sha256;
  final int build, sizeBytes, minSdk;
  final DateTime publishedAt;
  final List<ReleaseChange> changes;

  factory AppRelease.fromJson(Map<String, dynamic> json) {
    Never invalid() => throw const FormatException('Invalid release metadata');
    String string(String key, RegExp pattern) {
      final value = json[key];
      if (value is! String || !pattern.hasMatch(value)) invalid();
      return value;
    }

    int integer(String key, int max) {
      final value = json[key];
      if (value is! int || value <= 0 || value > max) invalid();
      return value;
    }

    final id = string('id',
        RegExp(r'^[a-fA-F0-9]{8}-(?:[a-fA-F0-9]{4}-){3}[a-fA-F0-9]{12}$'));
    final version = string('version', RegExp(r'^\d+\.\d+\.\d+$'));
    if (version.length > 40) invalid();
    final channel = string('channel', RegExp(r'^[a-z][a-z0-9_-]{0,31}$'));
    final build = integer('build_number', 2100000000);
    final size = integer('size_bytes', 536870912);
    final sdk = integer('min_sdk', 1000);
    if (sdk < 24) invalid();
    if (json['platform'] != 'android' ||
        json['distribution'] != 'direct_apk' ||
        json['state'] != 'published') {
      invalid();
    }
    final path =
        'android/$channel/$version/$build/noted-$version-build-$build.apk';
    if (json['object_path'] != path) invalid();
    final hash = string('sha256', RegExp(r'^[a-f0-9]{64}$'));
    final published = DateTime.tryParse(
        json['published_at'] is String ? json['published_at'] as String : '');
    if (published == null) invalid();
    final entries = json['changelog'];
    if (entries is! List || entries.isEmpty || entries.length > 30) invalid();
    final changes = <ReleaseChange>[];
    for (final entry in entries) {
      if (entry is! Map ||
          !const ['added', 'changed', 'fixed'].contains(entry['type']) ||
          entry['text'] is! String ||
          (entry['text'] as String).trim().isEmpty ||
          (entry['text'] as String).length > 500) {
        invalid();
      }
      changes.add(ReleaseChange(
          entry['type'] as String, (entry['text'] as String).trim()));
    }
    return AppRelease._(
        id: id,
        platform: 'android',
        channel: channel,
        distribution: 'direct_apk',
        version: version,
        build: build,
        publishedAt: published.toUtc(),
        objectPath: path,
        sizeBytes: size,
        sha256: hash,
        minSdk: sdk,
        changes: List.unmodifiable(changes));
  }

  bool compatibleWith(InstalledApp app, String targetChannel) =>
      platform == app.platform &&
      channel == targetChannel &&
      distribution == 'direct_apk' &&
      minSdk <= app.sdk;
  bool isNewerThan(InstalledApp app, String targetChannel) =>
      compatibleWith(app, targetChannel) && build > app.build;
  String get sizeLabel =>
      '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
