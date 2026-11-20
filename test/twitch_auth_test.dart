import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token_store.dart';

void main() {
  testWidgets('device sign-in polls with backoff and validates before saving', (
    tester,
  ) async {
    final store = MemoryStore()..token = null;
    final opened = <Uri>[];
    final tokenRequests = <RequestOptions>[];
    RequestOptions? deviceRequest;
    RequestOptions? validationRequest;
    TwitchToken? tokenBeforeValidation;
    final auth = TwitchAuthClient(
      store,
      openBrowser: (uri) async => opened.add(uri),
      dio: mockDio((request, handler) {
        if (request.path.endsWith('/validate')) {
          validationRequest = request;
          tokenBeforeValidation = store.token;
          reply(request, handler, validation);
          return;
        }
        if (request.path.endsWith('/device')) {
          deviceRequest = request;
          reply(request, handler, deviceChallenge);
          return;
        }
        tokenRequests.add(request);
        switch (tokenRequests.length) {
          case 1:
            reject(request, handler, 400, message: 'authorization_pending');
          case 2:
            reject(request, handler, 400, message: 'slow_down');
          default:
            reply(request, handler, rotated);
        }
      }),
    );
    await auth.initialize();
    final signingIn = auth.signIn();
    await tester.pump(Duration.zero);
    final parameters = {
      'client_id': TwitchAuthClient.clientId,
      'scopes': TwitchAuthClient.authorizationScopes.join(' '),
    };
    expect(deviceRequest?.path, 'https://id.twitch.tv/oauth2/device');
    expect(deviceRequest?.contentType, Headers.formUrlEncodedContentType);
    expect(Uri.splitQueryString(deviceRequest!.data as String), parameters);
    expect(auth.state.devicePrompt?.userCode, 'ABCD1234');
    final verificationUri = Uri.parse(
      deviceChallenge['verification_uri'] as String,
    );
    expect(opened, [verificationUri]);
    await auth.openVerificationPage();
    expect(opened, [verificationUri, verificationUri]);

    await tester.pump(const Duration(seconds: 4));
    expect(tokenRequests, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(Duration.zero);
    expect(tokenRequests, hasLength(1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(Duration.zero);
    expect(tokenRequests, hasLength(2));
    await tester.pump(const Duration(seconds: 9));
    expect(tokenRequests, hasLength(2));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(Duration.zero);
    await signingIn;
    expect(tokenRequests, hasLength(3));
    for (final request in tokenRequests) {
      expect(request.path, 'https://id.twitch.tv/oauth2/token');
      expect(request.contentType, Headers.formUrlEncodedContentType);
      expect(Uri.splitQueryString(request.data as String), {
        ...parameters,
        'device_code': 'device-code',
        'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
      });
    }
    expect(validationRequest?.headers['Authorization'], 'OAuth new');
    expect(tokenBeforeValidation, isNull);
    expect(auth.state.status, TwitchAuthStatus.signedIn);
    expect(auth.state.devicePrompt, isNull);
    expect(store.token?.userId, 'owner');
    expect(store.token?.refreshToken, 'new-refresh');
    await auth.signOut();
  });

  for (final (error, failure) in [
    ('access_denied', TwitchAuthFailure.authorizationDenied),
    ('authorization_pending', TwitchAuthFailure.deviceCodeExpired),
  ]) {
    testWidgets('device authorization stops on $failure', (tester) async {
      final store = MemoryStore()..token = null;
      var polls = 0;
      final auth = TwitchAuthClient(
        store,
        openBrowser: (_) async => throw StateError('Browser unavailable'),
        dio: mockDio((request, handler) {
          if (request.path.endsWith('/device')) {
            reply(request, handler, {...deviceChallenge, 'expires_in': 9});
          } else {
            polls++;
            reject(request, handler, 400, message: error);
          }
        }),
      );
      await auth.initialize();
      final signingIn = auth.signIn();
      await tester.pump(Duration.zero);
      expect(auth.state.devicePrompt?.userCode, 'ABCD1234');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(seconds: 4));
      await signingIn;
      expect(auth.state.status, TwitchAuthStatus.failure);
      expect(auth.state.failure, failure);
      expect(auth.state.devicePrompt, isNull);
      expect(store.token, isNull);
      await tester.pump(const Duration(seconds: 20));
      expect(polls, 1);
    });
  }

  test(
    'cancellation discards a late grant and permits a new attempt',
    () async {
      final store = MemoryStore()..token = null;
      final pending = Completer<(RequestOptions, RequestInterceptorHandler)>();
      var challenges = 0;
      final auth = TwitchAuthClient(
        store,
        openBrowser: (_) async {},
        dio: mockDio((request, handler) {
          if (request.path.endsWith('/device')) {
            challenges++;
            reply(request, handler, {
              ...deviceChallenge,
              'interval': 1,
              'user_code': 'CODE$challenges',
            });
          } else if (!pending.isCompleted) {
            pending.complete((request, handler));
          } else {
            reject(request, handler, 400, message: 'authorization_pending');
          }
        }),
      );
      await auth.initialize();
      final firstAttempt = auth.signIn();
      final (request, handler) = await pending.future.timeout(
        const Duration(seconds: 5),
      );
      expect(request.path.endsWith('/token'), isTrue);
      expect(request.cancelToken?.isCancelled, isFalse);

      await auth.cancelSignIn();
      expect(auth.state.status, TwitchAuthStatus.signedOut);
      expect(request.cancelToken?.isCancelled, isTrue);
      final secondPrompt = auth.states
          .firstWhere((state) => state.devicePrompt != null)
          .timeout(const Duration(seconds: 5));
      final secondAttempt = auth.signIn();
      reply(request, handler, rotated);
      await firstAttempt;
      expect((await secondPrompt).devicePrompt?.userCode, 'CODE2');
      expect(store.token, isNull);
      await auth.cancelSignIn();
      await secondAttempt;
    },
  );

  testWidgets(
    'an idle session is validated hourly and detects revoked access',
    (tester) async {
      final store = MemoryStore();
      var validations = 0;
      final auth = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          if (request.path.endsWith('/validate')) {
            if (++validations == 1) {
              reply(request, handler, validation);
            } else {
              reject(request, handler, 401);
            }
          } else {
            reject(request, handler, 400, message: 'Invalid refresh token');
          }
        }),
      );
      final initializing = auth.initialize();
      await tester.pump(Duration.zero);
      await initializing;
      await tester.pump(const Duration(minutes: 59));
      expect(validations, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(validations, 2);
      expect(auth.state.status, TwitchAuthStatus.signedOut);
      expect(auth.state.failure, TwitchAuthFailure.storedSessionExpired);
      expect(store.token, isNull);
      await tester.pump(const Duration(hours: 1));
      expect(validations, 2);
    },
  );

  test(
    'local missing permission survives validation and token refresh',
    () async {
      final store = MemoryStore();
      store.token = store.token!.copyWith(
        debugMissingScopes: ['moderator:read:chatters'],
      );
      final auth = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          reply(
            request,
            handler,
            request.path.endsWith('/token') ? rotated : validation,
          );
        }),
      );
      await auth.initialize();
      expect(auth.state.status, TwitchAuthStatus.signedIn);
      expect(
        auth.state.token!.scopes,
        isNot(contains('moderator:read:chatters')),
      );
      expect(auth.state.token!.scopes, contains('user:read:chat'));
      final refreshed = await auth.validToken(rejectedAccessToken: 'old');
      expect(refreshed.accessToken, 'new');
      expect(refreshed.scopes, isNot(contains('moderator:read:chatters')));
      expect(store.token!.debugMissingScopes, ['moderator:read:chatters']);
    },
  );

  test(
    'startup refreshes rejected stored access token without signing out',
    () async {
      final store = MemoryStore();
      var refreshes = 0;
      final dio = mockDio((request, handler) {
        if (request.path.endsWith('/token')) {
          refreshes++;
          reply(request, handler, rotated);
        } else if (request.headers['Authorization'] == 'OAuth old') {
          reject(request, handler, 401);
        } else {
          reply(request, handler, validation);
        }
      });
      final auth = TwitchAuthClient(store, dio: dio);
      await auth.initialize();
      expect(auth.state.status, TwitchAuthStatus.signedIn);
      expect(refreshes, 1);
      expect(store.token?.accessToken, 'new');
      expect(store.token?.refreshToken, 'new-refresh');
      expect(store.clears, 0);
    },
  );

  test('startup network failure preserves stored account', () async {
    final store = MemoryStore();
    final auth = TwitchAuthClient(
      store,
      dio: mockDio((request, handler) {
        handler.reject(
          DioException(
            requestOptions: request,
            type: DioExceptionType.connectionTimeout,
          ),
        );
      }),
    );
    await auth.initialize();
    expect(store.clears, 0);
    expect(store.token?.refreshToken, 'refresh');
    expect(auth.state.status, TwitchAuthStatus.signedIn);
  });
  for (final status in [429, 500, 503]) {
    test(
      'startup HTTP $status keeps account and recovers on next attempt',
      () async {
        final store = MemoryStore();
        var offline = true;
        final auth = TwitchAuthClient(
          store,
          dio: mockDio((request, handler) {
            if (offline) {
              reject(request, handler, status);
            } else {
              reply(request, handler, validation);
            }
          }),
        );
        await auth.initialize();
        expect(store.clears, 0);
        offline = false;
        expect((await auth.validToken()).accessToken, 'old');
        expect(auth.state.status, TwitchAuthStatus.signedIn);
      },
    );
  }

  for (final status in [400, 401]) {
    test('invalid refresh token ($status) requires login', () async {
      final store = MemoryStore();
      final auth = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          reject(
            request,
            handler,
            request.path.endsWith('/token') ? status : 401,
            message: 'Invalid refresh token',
          );
        }),
      );
      await auth.initialize();
      expect(auth.state.status, TwitchAuthStatus.signedOut);
      expect(auth.state.failure, TwitchAuthFailure.storedSessionExpired);
      expect(store.token, isNull);
    });
  }

  test('refresh service outage preserves session and permits retry', () async {
    final store = MemoryStore();
    var offline = true;
    final auth = TwitchAuthClient(
      store,
      dio: mockDio((request, handler) {
        if (request.path.endsWith('/token')) {
          if (offline) {
            reject(request, handler, 503);
          } else {
            reply(request, handler, rotated);
          }
        } else if (request.headers['Authorization'] == 'OAuth old') {
          reject(request, handler, 401);
        } else {
          reply(request, handler, validation);
        }
      }),
    );
    await auth.initialize();
    expect(store.token?.refreshToken, 'refresh');
    offline = false;
    expect((await auth.validToken()).accessToken, 'new');
    expect(store.clears, 0);
  });

  test(
    'rotated refresh token survives validation outage and app restart',
    () async {
      final store = MemoryStore();
      var refreshes = 0;
      final auth = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          if (request.path.endsWith('/token')) {
            refreshes++;
            final body = Uri.splitQueryString(request.data as String);
            expect(body, {
              'client_id': TwitchAuthClient.clientId,
              'grant_type': 'refresh_token',
              'refresh_token': 'refresh',
            });
            reply(request, handler, rotated);
          } else {
            reject(
              request,
              handler,
              request.headers['Authorization'] == 'OAuth old' ? 401 : 503,
            );
          }
        }),
      );
      await auth.initialize();
      expect(store.token?.refreshToken, 'new-refresh');
      final restarted = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          expect(request.path.endsWith('/validate'), isTrue);
          expect(request.headers['Authorization'], 'OAuth new');
          reply(request, handler, validation);
        }),
      );
      await restarted.initialize();
      expect(restarted.state.status, TwitchAuthStatus.signedIn);
      expect(refreshes, 1);
    },
  );

  test(
    'concurrent near-expiry requests share refresh and encode credentials',
    () async {
      final store = MemoryStore();
      store.token = store.token!.copyWith(refreshToken: 'a+b&c%=');
      var refreshes = 0;
      final auth = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          if (request.path.endsWith('/token')) {
            refreshes++;
            expect(
              Uri.splitQueryString(request.data as String)['refresh_token'],
              'a+b&c%=',
            );
            reply(request, handler, rotated);
          } else {
            reply(request, handler, {
              ...validation,
              'expires_in': request.headers['Authorization'] == 'OAuth old'
                  ? 1
                  : 3600,
            });
          }
        }),
      );
      await auth.initialize();
      final tokens = await Future.wait(
        List.generate(8, (_) => auth.validToken()),
      );
      expect(tokens.every((token) => token.accessToken == 'new'), isTrue);
      expect(refreshes, 1);
    },
  );

  test('sign-out during refresh never restores the account', () async {
    final store = MemoryStore();
    final pending = Completer<void>();
    RequestOptions? refreshRequest;
    RequestInterceptorHandler? refreshHandler;
    final auth = TwitchAuthClient(
      store,
      dio: mockDio((request, handler) {
        if (request.path.endsWith('/token')) {
          refreshRequest = request;
          refreshHandler = handler;
          pending.complete();
        } else {
          reply(request, handler, validation);
        }
      }),
    );
    await auth.initialize();
    final refresh = auth.validToken(rejectedAccessToken: 'old');
    final failed = expectLater(refresh, throwsStateError);
    await pending.future;
    await auth.signOut();
    reply(refreshRequest!, refreshHandler!, rotated);
    await failed;
    expect(auth.state.status, TwitchAuthStatus.signedOut);
    expect(store.token, isNull);
  });

  test(
    'Helix concurrent and late 401s refresh once and replay GET/POST',
    () async {
      final store = MemoryStore();
      var refreshes = 0;
      final auth = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          if (request.path.endsWith('/token')) {
            refreshes++;
            reply(request, handler, rotated);
          } else {
            reply(request, handler, validation);
          }
        }),
      );
      await auth.initialize();
      final oldRequests = <(RequestOptions, RequestInterceptorHandler)>[];
      final ready = Completer<void>();
      final replayed = <RequestOptions>[];
      final client = TwitchHelixClient(
        auth,
        dio: mockDio((request, handler) {
          if (request.headers['Authorization'] == 'Bearer old') {
            oldRequests.add((request, handler));
            if (oldRequests.length == 3) ready.complete();
          } else {
            replayed.add(request);
            reply(request, handler, {'data': []});
          }
        }),
      );
      final rewards = client.getRewards(broadcasterId: 'owner');
      final badges = client.getBadges();
      final message = client.sendMessage(
        broadcasterId: 'owner',
        senderId: 'owner',
        message: 'hello',
      );
      await ready.future;
      reject(oldRequests[0].$1, oldRequests[0].$2, 401);
      reject(oldRequests[1].$1, oldRequests[1].$2, 401);
      await Future.wait<Object>([rewards, badges]);
      reject(oldRequests[2].$1, oldRequests[2].$2, 401);
      await message;
      expect(refreshes, 1);
      expect(replayed.length, 3);
      expect(
        replayed.every(
          (request) => request.headers['Authorization'] == 'Bearer new',
        ),
        isTrue,
      );
      final post = replayed.singleWhere((request) => request.method == 'POST');
      expect((post.data as Map)['message'], 'hello');
      expect(
        replayed
            .singleWhere((request) => request.path.contains('custom_rewards'))
            .queryParameters['broadcaster_id'],
        'owner',
      );
    },
  );

  for (final status in [401, 403, 500]) {
    test('Helix $status has bounded retries', () async {
      var refreshes = 0;
      var requests = 0;
      final auth = TwitchAuthClient(
        MemoryStore(),
        dio: mockDio((request, handler) {
          if (request.path.endsWith('/token')) {
            refreshes++;
            reply(request, handler, rotated);
          } else {
            reply(request, handler, validation);
          }
        }),
      );
      await auth.initialize();
      final client = TwitchHelixClient(
        auth,
        dio: mockDio((request, handler) {
          requests++;
          reject(request, handler, status);
        }),
      );
      await expectLater(client.getBadges(), throwsA(isA<DioException>()));
      expect(requests, status == 401 ? 2 : 1);
      expect(refreshes, status == 401 ? 1 : 0);
      expect(auth.state.status, TwitchAuthStatus.signedIn);
    });
  }
  test('runtime revoked refresh token signs out and clears storage', () async {
    final store = MemoryStore();
    final auth = TwitchAuthClient(
      store,
      dio: mockDio((request, handler) {
        if (request.path.endsWith('/token')) {
          reject(request, handler, 400, message: 'Invalid refresh token');
        } else {
          reply(request, handler, validation);
        }
      }),
    );
    await auth.initialize();
    await expectLater(
      auth.validToken(rejectedAccessToken: 'old'),
      throwsA(isA<Exception>()),
    );
    expect(auth.state.status, TwitchAuthStatus.signedOut);
    expect(store.token, isNull);
  });

  test('sign-out waits for earlier storage write and then clears it', () async {
    final store = BlockingStore();
    final auth = TwitchAuthClient(
      store,
      dio: mockDio((request, handler) {
        reply(
          request,
          handler,
          request.path.endsWith('/token') ? rotated : validation,
        );
      }),
    );
    await auth.initialize();
    store.block = true;
    final failed = expectLater(
      auth.validToken(rejectedAccessToken: 'old'),
      throwsStateError,
    );
    await store.started.future;
    final signOut = auth.signOut();
    store.release.complete();
    await Future.wait([failed, signOut]);
    expect(store.token, isNull);
    expect(auth.state.status, TwitchAuthStatus.signedOut);
  });

  test(
    'refresh response without a new token ends the single-use session',
    () async {
      final store = MemoryStore();
      final auth = TwitchAuthClient(
        store,
        dio: mockDio((request, handler) {
          reply(
            request,
            handler,
            request.path.endsWith('/token')
                ? (Map<String, Object?>.from(rotated)..remove('refresh_token'))
                : validation,
          );
        }),
      );
      await auth.initialize();
      await expectLater(
        auth.validToken(rejectedAccessToken: 'old'),
        throwsA(isA<Exception>()),
      );
      expect(auth.state.status, TwitchAuthStatus.signedOut);
      expect(auth.state.failure, TwitchAuthFailure.storedSessionExpired);
      expect(store.token, isNull);
    },
  );
}

const deviceChallenge = <String, Object?>{
  'device_code': 'device-code',
  'user_code': 'ABCD1234',
  'verification_uri':
      'https://www.twitch.tv/activate?public=true&device-code=ABCD1234',
  'interval': 5,
  'expires_in': 1800,
};

const validation = <String, Object?>{
  'client_id': TwitchAuthClient.clientId,
  'user_id': 'owner',
  'login': 'owner',
  'expires_in': 3600,
  'scopes': TwitchAuthClient.authorizationScopes,
};
const rotated = <String, Object?>{
  'access_token': 'new',
  'refresh_token': 'new-refresh',
  'expires_in': 3600,
  'scope': TwitchAuthClient.authorizationScopes,
};

Dio mockDio(void Function(RequestOptions, RequestInterceptorHandler) respond) {
  return Dio()..interceptors.add(InterceptorsWrapper(onRequest: respond));
}

void reply(
  RequestOptions request,
  RequestInterceptorHandler handler,
  Map<String, Object?> data,
) {
  handler.resolve(
    Response<Map<String, Object?>>(
      requestOptions: request,
      data: data,
      statusCode: 200,
    ),
  );
}

void reject(
  RequestOptions request,
  RequestInterceptorHandler handler,
  int status, {
  String message = 'Unauthorized',
}) {
  handler.reject(
    DioException(
      requestOptions: request,
      type: DioExceptionType.badResponse,
      response: Response<Map<String, Object?>>(
        requestOptions: request,
        statusCode: status,
        data: {'message': message},
      ),
    ),
  );
}

class MemoryStore implements TwitchTokenStore {
  TwitchToken? token = TwitchToken(
    accessToken: 'old',
    refreshToken: 'refresh',
    clientId: TwitchAuthClient.clientId,
    userId: 'owner',
    userLogin: 'streamer',
    scopes: const ['user:read:chat', 'user:write:chat'],
    expiresAt: DateTime.utc(2030),
  );
  int clears = 0;
  @override
  Future<TwitchToken?> read() async => token;
  @override
  Future<void> write(TwitchToken value) async {
    token = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    token = null;
  }
}

class BlockingStore extends MemoryStore {
  bool block = false;
  final started = Completer<void>();
  final release = Completer<void>();
  @override
  Future<void> write(TwitchToken value) async {
    if (block) {
      started.complete();
      await release.future;
    }
    await super.write(value);
  }
}
