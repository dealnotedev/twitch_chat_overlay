import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('English and Ukrainian catalogs load independently', () async {
    final english = await AppLocalizations.delegate.load(const Locale('en'));
    final ukrainian = await AppLocalizations.delegate.load(const Locale('uk'));

    expect(english.signInWithTwitch, 'Sign in with Twitch');
    expect(ukrainian.signInWithTwitch, 'Увійти через Twitch');
    expect(english.signInWithTwitch, isNot(ukrainian.signInWithTwitch));
  });
}
