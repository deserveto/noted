import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_release.dart';
import '../repositories/update_repository.dart';
import '../services/update_service.dart';

/// Advisory updates have no authority over authentication or note persistence.
class UpdateViewModel extends ChangeNotifier {
  UpdateViewModel(
    this._repository,
    this._service, {
    this.channel = UpdateService.channel,
    DateTime Function()? now,
    this.checkCooldown = const Duration(hours: 6),
    this.reminderCooldown = const Duration(hours: 24),
  }) : _now = now ?? DateTime.now;
  final UpdateRepository _repository;
  final UpdateService _service;
  final String channel;
  final DateTime Function() _now;
  final Duration checkCooldown, reminderCooldown;
  String? _uid;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _checking;
  Future<void>? _initializing;
  DateTime? _lastCheck, _remindAfter;
  InstalledApp? installed;
  AppRelease? available, whatsNew;
  String? message;
  String? downloadError;
  bool downloading = false;
  bool get checking => _checking != null;
  bool get enabled => _uid != null && channel == 'beta';
  String get _installKey => 'updates.$channel.installed';
  String get _pendingKey => 'updates.$channel.upgraded';
  String get _reminderKey => 'updates.$_uid.$channel.${available?.build}.later';
  bool get shouldPrompt =>
      available != null &&
      (_remindAfter == null || !_now().isBefore(_remindAfter!));

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void bindUser(String? uid) {
    if (_uid == uid) return;
    _uid = uid;
    _generation++;
    available = whatsNew = null;
    message = null;
    downloadError = null;
    _lastCheck = _remindAfter = null;
    _emit();
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    try {
      installed = await _service.installed();
      final prefs = await SharedPreferences.getInstance();
      final previous = prefs.getInt(_installKey);
      if (previous != null && installed!.build > previous) {
        await prefs.setInt(_pendingKey, installed!.build);
      }
      await prefs.setInt(_installKey, installed!.build);
    } catch (_) {
      _initializing = null;
    }
    _emit();
  }

  Future<void> check({bool manual = false}) {
    if (_checking != null) return _checking!;
    if (!enabled) {
      if (manual) {
        message =
            'Beta updates are unavailable for this build. Check the configured channel and sign in.';
      }
      return Future.value();
    }
    if (!manual &&
        _lastCheck != null &&
        _now().difference(_lastCheck!) < checkCooldown) {
      return Future.value();
    }
    final generation = _generation;
    final future = _check(generation);
    _checking = future;
    _emit();
    return future.whenComplete(() {
      _checking = null;
      _emit();
    });
  }

  Future<void> _check(int generation) async {
    _lastCheck = _now();
    try {
      await initialize();
      if (generation != _generation || _disposed) return;
      final app = installed;
      if (app == null || app.platform != 'android') {
        throw StateError('Unsupported');
      }
      _lastCheck = _now();
      final release = await _repository.check(app);
      if (generation != _generation || _disposed) return;
      available =
          release != null && release.isNewerThan(app, channel) ? release : null;
      final prefs = await SharedPreferences.getInstance();
      if (generation != _generation || _disposed) return;
      final remind = prefs.getInt(_reminderKey);
      _remindAfter =
          remind == null ? null : DateTime.fromMillisecondsSinceEpoch(remind);
      message = available == null
          ? 'You’re up to date.'
          : 'A beta update is available.';
      if (prefs.getInt(_pendingKey) == app.build) {
        try {
          final releases = await _repository.history(app, installedOnly: true);
          if (generation != _generation || _disposed) return;
          whatsNew = releases
              .where(
                  (r) => r.build == app.build && r.compatibleWith(app, channel))
              .firstOrNull;
        } catch (_) {
          /* Retry release notes on a later check, including offline. */
        }
      }
    } catch (_) {
      if (generation == _generation && !_disposed) {
        available = null;
        message =
            'Updates are unavailable. Check your connection and sign-in status, then try again.';
      }
    }
  }

  Future<void> remindLater() async {
    if (available == null) return;
    _remindAfter = _now().add(reminderCooldown);
    final key = _reminderKey, after = _remindAfter!;
    try {
      await (await SharedPreferences.getInstance())
          .setInt(key, after.millisecondsSinceEpoch);
    } catch (_) {/* Keep the session reminder even if preferences fail. */}
    _emit();
  }

  Future<void> markWhatsNewShown() async {
    whatsNew = null;
    try {
      await (await SharedPreferences.getInstance()).remove(_pendingKey);
    } catch (_) {}
    _emit();
  }

  Future<List<AppRelease>> history() async {
    if (!enabled) return [];
    final generation = _generation;
    await initialize();
    final app = installed;
    if (app == null || generation != _generation) return [];
    final releases = await _repository.history(app);
    if (generation != _generation || _disposed) return [];
    return releases.where((r) => r.compatibleWith(app, channel)).toList();
  }

  Future<bool> download(AppRelease release) async {
    if (downloading ||
        !enabled ||
        installed == null ||
        !release.isNewerThan(installed!, channel)) {
      return false;
    }
    final generation = _generation;
    downloading = true;
    message = null;
    downloadError = null;
    _emit();
    try {
      final value = await _repository.download(release, installed!);
      if (generation != _generation || _disposed) return false;
      final uri = _service.validateDownload(value);
      if (!await _service.launch(uri)) {
        message = 'Couldn’t open your browser. Please try again.';
        downloadError = message;
        return false;
      }
      await remindLater();
      return true;
    } catch (_) {
      message =
          'Download unavailable. The release may have been withdrawn. Check for updates and try again.';
      downloadError = message;
      return false;
    } finally {
      downloading = false;
      _emit();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
