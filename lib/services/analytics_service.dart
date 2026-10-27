import 'package:flutter/foundation.dart';

/// Privacy-first, consent-gated analytics coordinator replacing `firebase_analytics`.
/// Strictly disabled by default (`enabled == false`) and never transmits events
/// unless the user explicitly enables `Settings > Privacy > Usage analytics`.
class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  bool _enabled = false;
  final List<Map<String, Object?>> _debugBuffer = [];

  bool get isEnabled => _enabled;

  @visibleForTesting
  List<Map<String, Object?>> get recordedEvents =>
      List.unmodifiable(_debugBuffer);

  Future<void> setCollectionEnabled(bool enabled) async {
    _enabled = enabled;
    if (!enabled) {
      _debugBuffer.clear();
    }
  }

  Future<void> logEvent(
    String name, [
    Map<String, Object?> parameters = const {},
  ]) async {
    if (!_enabled) return;
    if (_debugBuffer.length >= 200) {
      _debugBuffer.removeAt(0);
    }
    _debugBuffer.add({
      'name': name,
      'parameters': parameters,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    });
  }

  @visibleForTesting
  void resetForTesting() {
    _enabled = false;
    _debugBuffer.clear();
  }
}
