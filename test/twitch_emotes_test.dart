import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_emotes.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

const template =
    'https://static-cdn.jtvnw.net/emoticons/v2/{{id}}/{{format}}/{{theme_mode}}/{{scale}}';

void main() {
  test(
    'loads every page for the sender and current channel, deduplicating IDs',
    () async {
      final requests = <RequestOptions>[];
      final client = TwitchHelixClient(
        FakeAuth(),
        dio: mockDio((request, handler) {
          requests.add(request);
          final second = request.queryParameters['after'] == 'next';
          reply(request, handler, {
            'data': second
                ? [
                    emote('1', 'Kappa'),
                    emote('2', 'SubscriberSmile'),
                    {'id': 'bad'},
                  ]
                : [emote('1', 'Kappa')],
            'template': template,
            'pagination': second ? {} : {'cursor': 'next'},
          });
        }),
      );
      final result = await client.getUserEmotes(broadcasterId: 'channel');
      expect(result.map((e) => e.name), ['Kappa', 'SubscriberSmile']);
      expect(
        result.first.imageUrl,
        'https://static-cdn.jtvnw.net/emoticons/v2/1/static/dark/2.0',
      );
      expect(requests, hasLength(2));
      expect(requests[0].path, '/chat/emotes/user');
      expect(requests[0].queryParameters, {
        'user_id': 'sender',
        'broadcaster_id': 'channel',
      });
      expect(requests[1].queryParameters, {
        'user_id': 'sender',
        'broadcaster_id': 'channel',
        'after': 'next',
      });
      expect(requests[0].headers['Authorization'], 'Bearer access');
    },
  );

  test(
    'optional emote permission leaves existing chat sessions valid',
    () async {
      final auth = FakeAuth()
        ..token = makeToken(scopes: TwitchAuthClient.requiredScopes);
      var requested = false;
      final client = TwitchHelixClient(
        auth,
        dio: mockDio((r, h) {
          requested = true;
          reply(r, h, {});
        }),
      );
      expect(
        TwitchAuthClient.authorizationScopes,
        contains(TwitchAuthClient.emotesScope),
      );
      expect(
        TwitchAuthClient.requiredScopes,
        isNot(contains(TwitchAuthClient.emotesScope)),
      );
      await expectLater(
        client.getUserEmotes(broadcasterId: 'channel'),
        throwsA(isA<TwitchEmotePermissionRequired>()),
      );
      expect(requested, isFalse);
    },
  );

  test(
    'refreshes an expired access token and retries the same sender request',
    () async {
      final auth = FakeAuth();
      var calls = 0;
      final client = TwitchHelixClient(
        auth,
        dio: mockDio((r, h) {
          calls++;
          if (calls == 1) {
            h.reject(
              DioException(
                requestOptions: r,
                response: Response(statusCode: 401, requestOptions: r),
              ),
            );
          } else {
            expect(r.headers['Authorization'], 'Bearer refreshed');
            expect(r.queryParameters['user_id'], 'sender');
            reply(r, h, {
              'data': [emote('1', 'Kappa')],
              'template': template,
              'pagination': {},
            });
          }
        }),
      );
      expect(
        await client.getUserEmotes(broadcasterId: 'channel'),
        hasLength(1),
      );
      expect(auth.refreshes, 1);
      expect(calls, 2);
    },
  );

  test('does not mix catalogs if the account changes between pages', () async {
    final auth = FakeAuth();
    var requests = 0;
    final client = TwitchHelixClient(
      auth,
      dio: mockDio((r, h) {
        requests++;
        auth.token = makeToken(user: 'different-sender');
        reply(r, h, {
          'data': [emote('1', 'Kappa')],
          'template': template,
          'pagination': {'cursor': 'next'},
        });
      }),
    );
    await expectLater(
      client.getUserEmotes(broadcasterId: 'channel'),
      throwsStateError,
    );
    expect(requests, 1);
  });

  test(
    'repeated cursors fail instead of looping or returning a partial library',
    () async {
      var requests = 0;
      final client = TwitchHelixClient(
        FakeAuth(),
        dio: mockDio((r, h) {
          requests++;
          reply(r, h, {
            'data': [],
            'template': template,
            'pagination': {'cursor': 'same'},
          });
        }),
      );
      await expectLater(
        client.getUserEmotes(broadcasterId: 'channel'),
        throwsStateError,
      );
      expect(requests, 2);
    },
  );

  test(
    'shares an in-flight load and caches the list until explicit refresh',
    () async {
      var calls = 0;
      final client = TwitchHelixClient(
        FakeAuth(),
        dio: mockDio((r, h) {
          calls++;
          reply(r, h, {
            'data': [emote('$calls', 'Emote$calls')],
            'template': template,
          });
        }),
      );
      final results = await Future.wait([
        client.getUserEmotes(broadcasterId: 'channel'),
        client.getUserEmotes(broadcasterId: 'channel'),
      ]);
      expect(calls, 1);
      expect(identical(results[0], results[1]), isTrue);
      expect(
        identical(
          await client.getUserEmotes(broadcasterId: 'channel'),
          results[0],
        ),
        isTrue,
      );
      expect(calls, 1);
      final refreshed = await client.getUserEmotes(
        broadcasterId: 'channel',
        refresh: true,
      );
      expect(calls, 2);
      expect(refreshed.single.name, 'Emote2');
      expect(
        identical(
          await client.getUserEmotes(broadcasterId: 'channel'),
          refreshed,
        ),
        isTrue,
      );
      expect(calls, 2);
      expect(() => refreshed.clear(), throwsUnsupportedError);
    },
  );

  test(
    'failed loads retry and a failed refresh preserves the last good list',
    () async {
      var calls = 0;
      var fail = true;
      final client = TwitchHelixClient(
        FakeAuth(),
        dio: mockDio((r, h) {
          calls++;
          if (fail) {
            h.reject(DioException(requestOptions: r));
          } else {
            reply(r, h, {
              'data': [emote('1', 'Kappa')],
              'template': template,
            });
          }
        }),
      );
      await expectLater(
        client.getUserEmotes(broadcasterId: 'channel'),
        throwsA(isA<DioException>()),
      );
      fail = false;
      final result = await client.getUserEmotes(broadcasterId: 'channel');
      expect(calls, 2);
      fail = true;
      await expectLater(
        client.getUserEmotes(broadcasterId: 'channel', refresh: true),
        throwsA(isA<DioException>()),
      );
      expect(
        identical(await client.getUserEmotes(broadcasterId: 'channel'), result),
        isTrue,
      );
      expect(calls, 3);
    },
  );

  test(
    'cache is isolated by sender and channel and rechecks permission',
    () async {
      final auth = FakeAuth();
      var calls = 0;
      final client = TwitchHelixClient(
        auth,
        dio: mockDio((r, h) {
          calls++;
          reply(r, h, {
            'data': [emote('$calls', 'Emote$calls')],
            'template': template,
          });
        }),
      );
      await client.getUserEmotes(broadcasterId: 'one');
      await client.getUserEmotes(broadcasterId: 'two');
      auth.token = makeToken(user: 'new-sender');
      final result = await client.getUserEmotes(broadcasterId: 'two');
      expect(calls, 3);
      expect(result.single.name, 'Emote3');
      auth.token = makeToken(
        user: 'new-sender',
        scopes: TwitchAuthClient.requiredScopes,
      );
      await expectLater(
        client.getUserEmotes(broadcasterId: 'two'),
        throwsA(isA<TwitchEmotePermissionRequired>()),
      );
      expect(calls, 3);
    },
  );

  test(
    'late old-channel responses do not replace the current cached list',
    () async {
      final oldStarted = Completer<void>();
      late void Function() completeOld;
      var calls = 0;
      final client = TwitchHelixClient(
        FakeAuth(),
        dio: mockDio((r, h) {
          calls++;
          final channel = r.queryParameters['broadcaster_id'] as String;
          void complete() => reply(r, h, {
            'data': [emote(channel, channel)],
            'template': template,
          });
          if (channel == 'old') {
            completeOld = complete;
            oldStarted.complete();
          } else {
            complete();
          }
        }),
      );
      final old = client.getUserEmotes(broadcasterId: 'old');
      await oldStarted.future;
      final current = await client.getUserEmotes(broadcasterId: 'current');
      completeOld();
      await old;
      expect(
        identical(
          await client.getUserEmotes(broadcasterId: 'current'),
          current,
        ),
        isTrue,
      );
      expect(calls, 2);
    },
  );

  test(
    'resolves unique owners in batches of 100 and caches their names',
    () async {
      var catalogCalls = 0;
      final batches = <List<String>>[];
      final client = TwitchHelixClient(
        FakeAuth(),
        dio: mockDio((r, h) {
          if (r.path == '/users') {
            final ids = (r.queryParameters['id'] as List).cast<String>();
            batches.add(ids);
            expect(r.uri.queryParametersAll['id'], ids);
            reply(r, h, {
              'data': [
                for (final id in ids)
                  {'id': id, 'display_name': 'Owner$id', 'login': 'owner$id'},
              ],
            });
          } else {
            catalogCalls++;
            reply(r, h, {
              'data': [
                for (var i = 1; i <= 101; i++)
                  {
                    ...emote('$i', 'Smile$i'),
                    'owner_id': '$i',
                    'emote_type': 'subscriptions',
                  },
                {
                  ...emote('duplicate-owner', 'AnotherSmile'),
                  'owner_id': '1',
                  'emote_type': 'follower',
                },
              ],
              'template': template,
            });
          }
        }),
      );
      final result = await client.getUserEmotes(broadcasterId: 'channel');
      expect(batches.map((batch) => batch.length), [100, 1]);
      expect(result.first.ownerId, '1');
      expect(result.first.ownerName, 'Owner1');
      expect(result.first.type, 'follower');
      await client.getUserEmotes(broadcasterId: 'channel');
      expect(catalogCalls, 1);
      expect(batches, hasLength(2));
    },
  );

  test('uses supported CDN variants and ignores malformed emotes', () {
    final data = emote('animated', 'Dance')
      ..['format'] = ['animated']
      ..['theme_mode'] = ['light']
      ..['scale'] = ['1.0'];
    expect(
      TwitchEmote.parse(data, template)?.imageUrl,
      'https://static-cdn.jtvnw.net/emoticons/v2/animated/animated/light/1.0',
    );
    expect(TwitchEmote.parse({'id': 'no-name'}, template), isNull);
    expect(TwitchEmote.parse(data, 'file:///private/{{id}}'), isNull);
  });
}

Map<String, Object?> emote(String id, String name) => {
  'id': id,
  'name': name,
  'format': ['static', 'animated'],
  'theme_mode': ['light', 'dark'],
  'scale': ['1.0', '2.0', '3.0'],
};
Dio mockDio(void Function(RequestOptions, RequestInterceptorHandler) respond) =>
    Dio()..interceptors.add(InterceptorsWrapper(onRequest: respond));
void reply(
  RequestOptions request,
  RequestInterceptorHandler handler,
  Map<String, Object?> data,
) => handler.resolve(
  Response<Map<String, Object?>>(
    requestOptions: request,
    data: data,
    statusCode: 200,
  ),
);
TwitchToken makeToken({
  String user = 'sender',
  List<String> scopes = TwitchAuthClient.authorizationScopes,
}) => TwitchToken(
  accessToken: 'access',
  refreshToken: 'refresh',
  clientId: 'client',
  userId: user,
  userLogin: user,
  scopes: scopes,
  expiresAt: DateTime.utc(2030),
);

class FakeAuth implements TwitchAuth {
  TwitchToken token = makeToken();
  int refreshes = 0;
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async {
    if (rejectedAccessToken != null) {
      refreshes++;
      token = token.copyWith(accessToken: 'refreshed');
    }
    return token;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
