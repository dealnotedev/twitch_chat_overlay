import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OAuth callback uses the configured localhost endpoint', () {
    expect(TwitchAuthClient.oauthRedirectUrl, 'http://localhost:3000');
  });

  test(
    'local missing-scope fixture survives persistence and server scope updates',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesTwitchTokenStore();
      final token = TwitchToken(
        accessToken: 'access',
        refreshToken: 'refresh',
        clientId: 'client',
        userId: 'owner',
        userLogin: 'owner',
        scopes: const ['user:read:chat', 'moderator:read:chatters'],
        debugMissingScopes: const ['moderator:read:chatters'],
        expiresAt: DateTime.utc(2030),
      );
      await store.write(token);
      final saved = (await store.read())!;
      expect(saved.scopes, ['user:read:chat']);
      expect(saved.debugMissingScopes, ['moderator:read:chatters']);
      final validated = saved.copyWith(
        scopes: const ['user:read:chat', 'moderator:read:chatters'],
      );
      expect(validated.scopes, ['user:read:chat']);
      expect(validated.accessToken, 'access');
      expect(validated.refreshToken, 'refresh');
      await store.write(validated);
      expect((await store.read())!.scopes, ['user:read:chat']);
    },
  );

  test('persists and restores every Twitch session field', () async {
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
      'userId': 'broadcaster',
      'accessToken': 'access',
      'refreshToken': 'refresh',
      'clientId': 'client',
      'userLogin': 'streamer',
      'scopes': ['user:read:chat', 'user:write:chat'],
      'expiresAt': '2030-01-01T00:00:00.000Z',
    });

    final restored = await store.read();
    expect(restored?.accessToken, 'access');
    expect(restored?.refreshToken, 'refresh');
    expect(restored?.userId, 'broadcaster');
    expect(restored?.clientId, token.clientId);
    expect(restored?.userLogin, token.userLogin);
    expect(restored?.scopes, token.scopes);
    expect(restored?.expiresAt, token.expiresAt);

    await store.clear();
    expect(
      preferences.getString(SharedPreferencesTwitchTokenStore.tokenKey),
      isNull,
    );
  });

  test('rejects stored sessions in alternate or incomplete formats', () async {
    final current = jsonDecode(
      TwitchToken(
        accessToken: 'access',
        refreshToken: 'refresh',
        clientId: 'client',
        userId: 'owner',
        userLogin: 'streamer',
        scopes: const ['user:read:chat'],
        expiresAt: DateTime.utc(2030),
      ).toJson(),
    ) as Map<String, dynamic>;
    for (final fields in [
      {
        'broadcasterId': 'owner',
        'accessToken': 'access',
        'refreshToken': 'refresh',
        'client_id': 'client',
      },
      {
        'user_id': 'owner',
        'access_token': 'access',
        'refresh_token': 'refresh',
        'client_id': 'client',
        'expires_at': '2030-01-01T00:00:00Z',
      },
      {...current}..remove('expiresAt'),
      {...current}..remove('scopes'),
      {...current, 'expiresAt': 'invalid'},
    ]) {
      SharedPreferences.setMockInitialValues({
        SharedPreferencesTwitchTokenStore.tokenKey: jsonEncode(fields),
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesTwitchTokenStore(preferences);
      expect(await store.read(), isNull);
      expect(
        preferences.containsKey(SharedPreferencesTwitchTokenStore.tokenKey),
        false,
      );
    }
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
