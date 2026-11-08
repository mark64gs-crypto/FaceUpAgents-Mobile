import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';

class SettingsStore {
  SettingsStore(this._prefs, this._secure);

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secure;

  static const _themeKey = 'app_theme';
  static const _fontKey = 'app_font';
  static const _languageKey = 'app_language';
  static const _imageResolutionKey = 'image_resolution';
  static const _modelPrefix = 'model_';

  static Future<SettingsStore> open() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsStore(prefs, const FlutterSecureStorage());
  }

  AppThemeChoice readTheme() {
    final raw = _prefs.getString(_themeKey);
    return AppThemeChoice.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => AppThemeChoice.system,
    );
  }

  AppFontChoice readFont() {
    final raw = _prefs.getString(_fontKey);
    return AppFontChoice.values.firstWhere(
      (value) => value.name == raw,
      orElse: () => AppFontChoice.inter,
    );
  }

  AppLanguage readLanguage() {
    return AppLanguage.fromCode(_prefs.getString(_languageKey));
  }

  ImageResolution readImageResolution() {
    return ImageResolution.fromStorage(_prefs.getString(_imageResolutionKey));
  }

  Future<void> writeTheme(AppThemeChoice value) =>
      _prefs.setString(_themeKey, value.name);

  Future<void> writeFont(AppFontChoice value) =>
      _prefs.setString(_fontKey, value.name);

  Future<void> writeLanguage(AppLanguage value) =>
      _prefs.setString(_languageKey, value.code);

  Future<void> writeImageResolution(ImageResolution value) =>
      _prefs.setString(_imageResolutionKey, value.apiValue);

  ModelOption? readModel(ModelCategory category) {
    final raw = _prefs.getString('$_modelPrefix${category.storageKey}');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final model = ModelOption.fromJson(decoded);
      if (model.id.isEmpty) return null;
      return model;
    } on FormatException {
      return null;
    }
  }

  Future<void> writeModel(ModelOption model) {
    return _prefs.setString(
      '$_modelPrefix${model.category.storageKey}',
      jsonEncode(model.toJson()),
    );
  }

  Future<void> clearModel(ModelCategory category) {
    return _prefs.remove('$_modelPrefix${category.storageKey}');
  }

  Future<Map<AiProviderType, String>> readKeys() async {
    final result = <AiProviderType, String>{};
    for (final provider in AiProviderType.values) {
      try {
        final value = await _secure.read(key: _secureKey(provider));
        if (value != null && value.trim().isNotEmpty) {
          result[provider] = value;
        }
      } on Exception {
        // A locked or unavailable keystore should not prevent the app opening.
      }
    }
    return result;
  }

  Future<void> writeKey(AiProviderType provider, String apiKey) async {
    final trimmed = apiKey.trim();
    if (trimmed.isEmpty) {
      await _secure.delete(key: _secureKey(provider));
      return;
    }
    await _secure.write(key: _secureKey(provider), value: trimmed);
  }

  String _secureKey(AiProviderType provider) =>
      'api_key_${provider.storageKey}';
}
