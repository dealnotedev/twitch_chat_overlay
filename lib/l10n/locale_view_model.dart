import 'package:flutter/widgets.dart';
import 'package:observable_state/observable_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LocaleFailure { persistence }

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
        sync: true,
      ),
    );
    _saveProcess = register(
      ObservableValue<SimpleFailableProcess>(
        current: const SimpleFailableProcess.initial(),
        sync: true,
      ),
    );
  }

  late final ObservableValue<Locale> _locale;
  late final ObservableValue<SimpleFailableProcess> _saveProcess;

  StreamWithInitial<Locale> get locale => _locale;
  StreamWithInitial<SimpleFailableProcess> get saveProcess => _saveProcess;

  static const key = 'overlay.locale';
  final SharedPreferences _preferences;
  Future<void> _saving = Future<void>.value();
  int _saveGeneration = 0;

  static Future<LocaleViewModel> load() async {
    final preferences = await SharedPreferences.getInstance();
    return LocaleViewModel(preferences);
  }

  Future<void> cycle() {
    if (isDisposed) return Future<void>.value();
    final next = _locale.current.languageCode == 'uk' ? 'en' : 'uk';
    final generation = ++_saveGeneration;
    // Serialize writes so rapid clicks cannot persist an older choice last.
    final saving = _saving = _saving.catchError((Object _) {}).then((_) async {
      try {
        if (!await _preferences.setString(key, next)) {
          throw StateError('Could not save application language');
        }
        if (!isDisposed && generation == _saveGeneration) {
          _saveProcess.set(const SimpleFailableProcess.initial());
        }
      } catch (error, stack) {
        if (!isDisposed && generation == _saveGeneration) {
          _saveProcess.set(
            SimpleFailableProcess.failed(
              LocaleFailure.persistence,
              cause: error,
              stackTrace: stack,
            ),
          );
        }
        Error.throwWithStackTrace(LocalePersistenceException(error), stack);
      }
    });
    // Queue persistence before notifying listeners, which can issue another cycle.
    _locale.set(Locale(next));
    if (!isDisposed && generation == _saveGeneration) {
      _saveProcess.set(const SimpleFailableProcess.loading());
    }
    return saving;
  }

  Future<void> flush() => _saving;
}
