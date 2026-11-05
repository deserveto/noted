import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:noted/models/app_release.dart';
import 'package:noted/repositories/update_repository.dart';
import 'package:noted/services/update_service.dart';
import 'package:noted/viewmodels/update_viewmodel.dart';

Map<String, dynamic> releaseJson([int build = 10]) => {
      'id': 'b5fd880d-047e-47ce-b3d0-370947ca9bd1',
      'platform': 'android',
      'channel': 'beta',
      'distribution': 'direct_apk',
      'version': '2.0.1',
      'build_number': build,
      'state': 'published',
      'published_at': '2026-11-01T00:00:00Z',
      'changelog': [
        {'type': 'fixed', 'text': 'More reliable offline notes.'}
      ],
      'object_path': 'android/beta/2.0.1/$build/noted-2.0.1-build-$build.apk',
      'size_bytes': 12345678,
      'sha256': 'a' * 64,
      'min_sdk': 24,
    };

class FakeUpdates extends UpdateRepository {
  int checks = 0, histories = 0, downloads = 0;
  bool installedOnlyRequested = false;
  Object? failure;
  Completer<void>? wait;
  AppRelease? release = AppRelease.fromJson(releaseJson());
  List<AppRelease> releases = [];
  String url =
      'https://trusted.supabase.co/storage/v1/object/sign/app-releases/a.apk?token=private';
  @override
  Future<AppRelease?> check(InstalledApp app) async {
    checks++;
    await wait?.future;
    if (failure != null) throw failure!;
    return release;
  }

  @override
  Future<List<AppRelease>> history(InstalledApp app,
      {bool installedOnly = false}) async {
    installedOnlyRequested = installedOnly;
    histories++;
    if (failure != null) throw failure!;
    return releases;
  }

  @override
  Future<String> download(AppRelease release, InstalledApp app) async {
    downloads++;
    if (failure != null) throw failure!;
    return url;
  }
}

class FakeUpdateService extends UpdateService {
  FakeUpdateService({this.build = 3})
      : super(trustedOrigin: 'https://trusted.supabase.co');
  int build;
  bool launchResult = true;
  int launches = 0;
  @override
  Future<InstalledApp> installed() async => InstalledApp(
      version: '2.0.0', build: build, sdk: 34, platform: 'android');
  @override
  Future<bool> launch(Uri uri) async {
    launches++;
    return launchResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'validated metadata compares numeric build and rejects identity mismatch',
      () {
    final release = AppRelease.fromJson(releaseJson());
    final longVersion = AppRelease.fromJson({
      ...releaseJson(),
      'version': '202611.1.0',
      'object_path': 'android/beta/202611.1.0/10/noted-202611.1.0-build-10.apk'
    });
    expect(longVersion.version, '202611.1.0');
    expect(
        release.isNewerThan(
            const InstalledApp(
                version: '9.99', build: 9, sdk: 34, platform: 'android'),
            'beta'),
        true);
    for (final patch in [
      {'build_number': '10'},
      {'sha256': 'invalid'},
      {'object_path': '../evil.apk'},
      {'changelog': []},
      {'published_at': 'bad'},
      {'size_bytes': -1},
    ]) {
      expect(() => AppRelease.fromJson({...releaseJson(), ...patch}),
          throwsFormatException);
    }
    expect(
        release.isNewerThan(
            const InstalledApp(
                version: '2', build: 10, sdk: 34, platform: 'android'),
            'beta'),
        false);
    expect(
        release.isNewerThan(
            const InstalledApp(
                version: '2', build: 3, sdk: 23, platform: 'android'),
            'beta'),
        false);
    expect(
        release.isNewerThan(
            const InstalledApp(
                version: '2', build: 3, sdk: 34, platform: 'ios'),
            'beta'),
        false);
    expect(
        release.isNewerThan(
            const InstalledApp(
                version: '2', build: 3, sdk: 34, platform: 'android'),
            'stable'),
        false);
  });
  test('coalesces checks, cooldown suppresses requests, manual bypasses',
      () async {
    final repo = FakeUpdates()..wait = Completer<void>();
    final vm = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta');
    vm.bindUser('alice');
    final first = vm.check();
    final second = vm.check(manual: true);
    await Future<void>.delayed(Duration.zero);
    expect(repo.checks, 1);
    repo.wait!.complete();
    await Future.wait([first, second]);
    expect(vm.available, isNotNull);
    await vm.check();
    expect(repo.checks, 1);
    await vm.check(manual: true);
    expect(repo.checks, 2);
    vm.dispose();
  });
  test('Later persists for 24 hours but manual checks can show release',
      () async {
    var now = DateTime.utc(2026, 11, 5);
    final repo = FakeUpdates();
    final vm = UpdateViewModel(repo, FakeUpdateService(),
        channel: 'beta', now: () => now);
    vm.bindUser('alice');
    await vm.check();
    await vm.remindLater();
    expect(vm.shouldPrompt, false);
    await vm.check(manual: true);
    expect(vm.available, isNotNull);
    expect(vm.shouldPrompt, false);
    now = now.add(const Duration(hours: 25));
    await vm.check();
    expect(vm.shouldPrompt, true);
    vm.dispose();
  });
  test('network and launch failures are useful without leaking URLs', () async {
    final repo = FakeUpdates()..failure = StateError('secret-token');
    final service = FakeUpdateService();
    final vm = UpdateViewModel(repo, service, channel: 'beta')
      ..bindUser('alice');
    await vm.check(manual: true);
    expect(vm.message, contains('try again'));
    expect(vm.message, isNot(contains('secret')));
    repo.failure = null;
    await vm.check(manual: true);
    service.launchResult = false;
    expect(await vm.download(vm.available!), false);
    expect(vm.message, contains('browser'));
    for (final url in [
      'http://trusted.supabase.co/a',
      'https://evil.test/a',
      'file:///a',
      'https://trusted.supabase.co:444/a',
      'https://a@trusted.supabase.co/a'
    ]) {
      repo.url = url;
      expect(await vm.download(vm.available!), false);
    }
    expect(service.launches, 1);
    vm.dispose();
  });
  test(
      'fresh install establishes baseline; actual installed upgrade shows notes once',
      () async {
    final repo = FakeUpdates()
      ..releases = [AppRelease.fromJson(releaseJson(5))];
    final first = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
      ..bindUser('alice');
    await first.check();
    expect(first.whatsNew, isNull);
    first.dispose();
    final upgraded =
        UpdateViewModel(repo, FakeUpdateService(build: 5), channel: 'beta')
          ..bindUser('alice');
    await upgraded.check();
    expect(upgraded.whatsNew?.build, 5);
    expect(repo.installedOnlyRequested, true);
    await upgraded.markWhatsNewShown();
    upgraded.dispose();
    final again =
        UpdateViewModel(repo, FakeUpdateService(build: 5), channel: 'beta')
          ..bindUser('alice');
    await again.check();
    expect(again.whatsNew, isNull);
    again.dispose();
  });
  test(
      'account change invalidates in-flight release and history remains authorized',
      () async {
    final repo = FakeUpdates()..wait = Completer<void>();
    final vm = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
      ..bindUser('alice');
    final check = vm.check();
    await Future<void>.delayed(Duration.zero);
    vm.bindUser(null);
    repo.wait!.complete();
    await check;
    expect(vm.available, isNull);
    expect(await vm.history(), isEmpty);
    expect(repo.histories, 0);
    vm.bindUser('bob');
    repo.releases = [AppRelease.fromJson(releaseJson())];
    expect((await vm.history()).length, 1);
    vm.dispose();
  });
  test('installed identity reads numeric package build and native Android SDK',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    PackageInfo.setMockInitialValues(
        appName: 'Noted',
        packageName: 'com.noted.app',
        version: '2.0.1',
        buildNumber: '10',
        buildSignature: '');
    const channel = MethodChannel('com.noted.app/device');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            channel, (call) async => call.method == 'sdkInt' ? 35 : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final app = await UpdateService().installed();
    expect(app.build, 10);
    expect(app.version, '2.0.1');
    expect(app.sdk, 35);
    expect(app.platform, 'android');
  });
  test('reminder survives restart and stays scoped to account and release',
      () async {
    final repo = FakeUpdates();
    final first = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
      ..bindUser('alice');
    await first.check();
    await first.remindLater();
    first.dispose();
    final again = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
      ..bindUser('alice');
    await again.check();
    expect(again.shouldPrompt, false);
    again.bindUser('bob');
    await again.check();
    expect(again.shouldPrompt, true);
    await again.remindLater();
    repo.release = AppRelease.fromJson(releaseJson(11));
    await again.check(manual: true);
    expect(again.shouldPrompt, true);
    again.dispose();
  });
  test('a successful browser handoff never confirms installation', () async {
    final repo = FakeUpdates();
    final vm = UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
      ..bindUser('alice');
    await vm.check();
    expect(await vm.download(vm.available!), true);
    expect(vm.installed!.build, 3);
    expect(vm.whatsNew, isNull);
    vm.dispose();
    final restarted =
        UpdateViewModel(repo, FakeUpdateService(), channel: 'beta')
          ..bindUser('alice');
    await restarted.check();
    expect(restarted.whatsNew, isNull);
    expect(restarted.installed!.build, 3);
    restarted.dispose();
  });
}
