import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

abstract interface class TwitchTokenStore {
  Future<TwitchToken?> read();
  Future<void> write(TwitchToken token);
  Future<void> clear();
}

final class SharedPreferencesTwitchTokenStore implements TwitchTokenStore {
  static const String tokenKey = 'twitch_oauth';

  SharedPreferencesTwitchTokenStore([this._preferences]);

  final SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ?? SharedPreferences.getInstance();

  @override
  Future<TwitchToken?> read() async {
    final preferences = await _prefs;
    final value = preferences.getString(tokenKey);
    if (value == null) return null;
    try {
      return TwitchToken.fromJson(value);
    } on Object {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(TwitchToken token) async {
    final preferences = await _prefs;
    await preferences.setString(tokenKey, token.toJson());
  }

  @override
  Future<void> clear() async {
    final preferences = await _prefs;
    await preferences.remove(tokenKey);
  }
}
