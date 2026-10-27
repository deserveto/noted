import 'package:flutter/material.dart';
import 'settings_viewmodel.dart';

class ThemeViewModel extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  SettingsViewModel? _settings;
  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  void bindSettings(SettingsViewModel settings) {
    if (identical(settings, _settings)) return;
    _settings?.removeListener(_sync);
    _settings = settings;
    settings.addListener(_sync);
    _sync();
  }

  void _sync() {
    final next = switch (_settings?.settings.theme) {
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.light
    };
    if (next == _themeMode) return;
    _themeMode = next;
    notifyListeners();
  }

  void setTheme(String value) {
    if (_settings != null) {
      _settings!.update({'theme': value});
    } else {
      _themeMode = switch (value) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light
      };
      notifyListeners();
    }
  }

  void setDarkMode(bool enabled) => setTheme(enabled ? 'dark' : 'light');
  @override
  void dispose() {
    _settings?.removeListener(_sync);
    super.dispose();
  }
}
