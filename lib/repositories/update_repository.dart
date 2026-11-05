import '../models/app_release.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';

class UpdateRepository {
  UpdateRepository({this.channel = UpdateService.channel});
  final String channel;
  Map<String, dynamic> _request(InstalledApp app, String action) => {
        'action': action,
        'platform': app.platform,
        'channel': channel,
        'distribution': 'direct_apk',
        'build_number': app.build,
        'sdk_int': app.sdk,
      };
  Future<Map<String, dynamic>> _invoke(Map<String, dynamic> body) =>
      SupabaseService.invokeFunction('app-updates', body)
          .timeout(const Duration(seconds: 15));

  Future<AppRelease?> check(InstalledApp app) async {
    final result = await _invoke(_request(app, 'check'));
    final row = result['release'];
    if (!result.containsKey('release')) {
      throw const FormatException('Missing release');
    }
    if (row == null) return null;
    return AppRelease.fromJson(Map<String, dynamic>.from(row as Map));
  }

  Future<List<AppRelease>> history(InstalledApp app,
      {bool installedOnly = false}) async {
    final result = await _invoke({
      ..._request(app, 'history'),
      if (installedOnly) 'installed_only': true
    });
    final rows = result['releases'];
    if (rows is! List || rows.length > 50) {
      throw const FormatException('Invalid history');
    }
    return rows
        .map(
            (row) => AppRelease.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<String> download(AppRelease release, InstalledApp app) async {
    final result =
        await _invoke({..._request(app, 'download'), 'release_id': release.id});
    if (result['url'] is! String) {
      throw const FormatException('Missing download');
    }
    return result['url'] as String;
  }
}
