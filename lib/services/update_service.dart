import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'supabase_service.dart';
import '../models/installed_app.dart';
export '../models/installed_app.dart';

class UpdateService {
  UpdateService({String? trustedOrigin})
      : _trustedOrigin = trustedOrigin ?? SupabaseService.supabaseUrl;
  static const channel = String.fromEnvironment('NOTED_UPDATE_CHANNEL');
  final String _trustedOrigin;

  Future<InstalledApp> installed() async {
    final info = await PackageInfo.fromPlatform();
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final sdk = android
        ? await const MethodChannel('com.noted.app/device')
            .invokeMethod<int>('sdkInt')
        : 0;
    final build = int.tryParse(info.buildNumber);
    if (build == null || build <= 0 || (android && (sdk == null || sdk <= 0))) {
      throw const FormatException('Installed build unavailable');
    }
    return InstalledApp(
        version: info.version,
        build: build,
        sdk: sdk ?? 0,
        platform: android ? 'android' : 'unsupported');
  }

  Uri validateDownload(String value) {
    final uri = Uri.tryParse(value), origin = Uri.tryParse(_trustedOrigin);
    if (uri == null ||
        origin == null ||
        origin.scheme != 'https' ||
        origin.host.isEmpty ||
        uri.scheme != 'https' ||
        uri.host != origin.host ||
        uri.port != origin.port ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        !uri.path.startsWith('/storage/v1/object/sign/app-releases/') ||
        (uri.queryParameters['token'] ?? '').isEmpty) {
      throw const FormatException('Untrusted update download');
    }
    return uri;
  }

  Future<bool> launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
