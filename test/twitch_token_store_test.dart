import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OAuth callback uses the familiar localhost endpoint', () {
    expect(TwitchAuthClient.oauthRedirectUrl, 'http://localhost:3000');
  });

  test('stores Twitch auth in the familiar SharedPreferences format', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesTwitchTokenStore(preferences);
    final token = TwitchToken(
      accessToken: 'access',
      refreshToken: 'refresh',
      clientId: 'client',
      userId: 'broadcaster',
      userLogin: 'streamer',
      scopes: const ['user:read:chat', 'user:write:chat'],
      expiresAt: DateTime.utc(2030),
    );

    await store.write(token);

    final raw = preferences.getString(
      SharedPreferencesTwitchTokenStore.tokenKey,
    );
    final json = jsonDecode(raw!) as Map<String, dynamic>;
    expect(json, {
      'broadcasterId': 'broadcaster',
      'accessToken': 'access',
      'refreshToken': 'refresh',
      'client_id': 'client',
    });

    final restored = await store.read();
    expect(restored?.accessToken, 'access');
    expect(restored?.refreshToken, 'refresh');
    expect(restored?.userId, 'broadcaster');

    await store.clear();
    expect(
      preferences.getString(SharedPreferencesTwitchTokenStore.tokenKey),
      isNull,
    );
  });

  test('removes malformed stored auth', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesTwitchTokenStore.tokenKey: '{broken',
    });
    final preferences = await SharedPreferences.getInstance();
    final store = SharedPreferencesTwitchTokenStore(preferences);

    expect(await store.read(), isNull);
    expect(
      preferences.getString(SharedPreferencesTwitchTokenStore.tokenKey),
      isNull,
    );
  });
}
