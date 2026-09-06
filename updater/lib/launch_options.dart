import 'dart:ui';

import 'package:path/path.dart' as p;

final class LaunchOptions {
  const LaunchOptions({required this.directory, required this.locale});
  final String directory;
  final Locale locale;

  factory LaunchOptions.parse(
    List<String> arguments, {
    required String executable,
    required Locale systemLocale,
  }) {
    var directory = p.dirname(executable);
    if (p.basename(directory).toLowerCase() == 'updater') {
      directory = p.dirname(directory);
    }
    var locale = supportedLocale(systemLocale.toLanguageTag());
    for (var i = 0; i < arguments.length; i++) {
      final option = arguments[i];
      if ((option == '--install-dir' || option == '--locale') &&
          i + 1 < arguments.length &&
          !arguments[i + 1].startsWith('--')) {
        final value = arguments[++i];
        if (option == '--install-dir') {
          directory = p.normalize(p.absolute(value));
        } else {
          locale = supportedLocale(value);
        }
      }
    }
    return LaunchOptions(directory: directory, locale: locale);
  }

  static Locale supportedLocale(String value) => Locale(
    value.replaceAll('_', '-').split('-').first.toLowerCase() == 'uk'
        ? 'uk'
        : 'en',
  );
}
