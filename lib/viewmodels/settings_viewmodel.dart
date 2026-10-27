import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/settings_model.dart';
import '../repositories/settings_repository.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel(this._repository);
  final SettingsRepository _repository;
  StreamSubscription<SettingsModel>? _subscription;
  SettingsModel _settings = const SettingsModel();
  String? _uid;
  String? _errorMessage;
  int _generation = 0, _revision = 0;
  int _aiHistoryEpoch = 0;
  int get aiHistoryEpoch => _aiHistoryEpoch;
  void invalidateAiHistory() {
    _aiHistoryEpoch++;
    notifyListeners();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;
  SettingsModel get settings => _settings;
  String? get errorMessage => _errorMessage;
  void bindUser(String? uid) {
    if (uid == _uid) return;
    _uid = uid;
    _generation++;
    _isLoading = uid != null;
    _subscription?.cancel();
    _settings = const SettingsModel();
    _errorMessage = null;
    notifyListeners();
    if (uid == null) return;
    final generation = _generation;
    var received = false;
    final initialRevision = _revision;
    _repository.cached(uid).then((value) {
      if (generation == _generation &&
          !received &&
          initialRevision == _revision) {
        _settings = value;
        _isLoading = false;
        notifyListeners();
      }
    });
    _subscription = _repository.watch(uid).listen((value) {
      if (generation != _generation) return;
      received = true;
      _isLoading = false;
      _settings = value;
      _errorMessage = null;
      unawaited(_repository.cache(uid, value));
      notifyListeners();
    }, onError: (Object error) {
      if (generation != _generation) return;
      _isLoading = false;
      _errorMessage = error.toString();
      notifyListeners();
    });
  }

  Future<bool> update(Map<String, dynamic> changes) async {
    final uid = _uid;
    if (uid == null) return false;
    final generation = _generation;
    _revision++;
    _settings = _settings.merge(changes);
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.save(uid, _settings, changes: changes);
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      _errorMessage =
          'Couldn’t save settings. Your preferences are kept on this device. $error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> reset() => update(const SettingsModel().toMap());
  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    super.dispose();
  }
}
