import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores language independently from chat layout and Twitch credentials.
final class LocalePreferences extends ValueNotifier<Locale> {
  LocalePreferences._(this._preferences, super.value);

  static const key = 'overlay.locale';
  final SharedPreferences _preferences;
  Future<void> _saving = Future<void>.value();

  static Future<LocalePreferences> load() async {
    final preferences = await SharedPreferences.getInstance();
    final language = preferences.getString(key);
    return LocalePreferences._(
      preferences,
      Locale(language == 'en' ? 'en' : 'uk'),
    );
  }

  Future<void> cycle() {
    final next = value.languageCode == 'uk' ? 'en' : 'uk';
    // Serialize writes so rapid clicks cannot persist an older choice last.
    _saving = _saving.catchError((Object _) {}).then((_) async {
      if (!await _preferences.setString(key, next)) {
        throw StateError('Could not save application language');
      }
    });
    value = Locale(next);
    return _saving;
  }

  Future<void> flush() => _saving;
}
