import 'package:flutter/widgets.dart';
import 'package:observable_state/observable_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class LocalePersistenceException implements Exception {
  const LocalePersistenceException(this.cause);
  final Object cause;
  @override
  String toString() => 'LocalePersistenceException: $cause';
}

/// Stores language independently from chat layout and Twitch credentials.
final class LocaleViewModel extends BaseViewModel {
  LocaleViewModel(SharedPreferences preferences) : _preferences = preferences {
    _locale = register(
      ObservableValue(
        current: Locale(preferences.getString(key) == 'en' ? 'en' : 'uk'),
      ),
    );
  }

  late final ObservableValue<Locale> _locale;

  Observable<Locale> get locale => _locale;

  static const key = 'overlay.locale';
  final SharedPreferences _preferences;
  Future<void> _saving = Future<void>.value();

  static Future<LocaleViewModel> load() async {
    final preferences = await SharedPreferences.getInstance();
    return LocaleViewModel(preferences);
  }

  Future<void> cycle() {
    if (isDisposed) return Future<void>.value();
    final next = _locale.current.languageCode == 'uk' ? 'en' : 'uk';
    // Serialize writes so rapid clicks cannot persist an older choice last.
    final saving = _saving = _saving.catchError((Object _) {}).then((_) async {
      try {
        if (!await _preferences.setString(key, next)) {
          throw StateError('Could not save application language');
        }
      } catch (error, stack) {
        Error.throwWithStackTrace(LocalePersistenceException(error), stack);
      }
    });
    // Queue persistence before notifying listeners, which can issue another cycle.
    _locale.set(Locale(next));
    return saving;
  }

  Future<void> flush() => _saving;
}
