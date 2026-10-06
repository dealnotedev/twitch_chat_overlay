import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

void main() {
  test(
    'EventSub sends Pong responses without unsolicited Ping frames',
    () async {
      final server = await _FrameServer.start();
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(onRequest: _reply));
      final auth = _Auth();
      final session = EventSubTwitchChatSession(
        auth,
        TwitchHelixClient(auth, dio: dio),
        eventSubUrl: 'ws://127.0.0.1:${server.server.port}',
      );
      addTearDown(() async {
        await session.leave();
        await server.close();
        dio.close(force: true);
      });
      await _fastTimers(() => session.join(broadcasterId: 'owner'));
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(
        server.opcodes,
        contains(10),
        reason: 'Dart must answer server Ping',
      );
      expect(
        server.opcodes,
        isNot(contains(9)),
        reason: 'EventSub prohibits client Ping',
      );
    },
  );

  test('ordinary disconnect resubscribes and preserves chat history', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await h.ready();
    await h.deliver(h.sockets.first, 'before');
    await h.sockets.first.close(4005, 'Network timeout');
    await h.waitForConnections(2);
    await h.ready();
    await h.deliver(h.sockets.last, 'after');
    expect(h.session.state.items.map((i) => i.id), ['before', 'after']);
    expect(h.chatSubscriptions, 10);
  });

  for (final migration in [false, true]) {
    test(
      'refreshes unknown viewer count immediately after ${migration ? 'migration' : 'reconnect'}',
      () async {
        final h = await _Harness.start(
          viewerRequestHandler: (r, handler, index) {
            if (index == 0) {
              handler.reject(DioException(requestOptions: r));
            } else {
              _replyViewers(r, handler, 42);
            }
          },
        );
        addTearDown(h.close);
        await h.ready();
        expect(h.session.state.viewerCount, isNull);
        expect(h.session.state.streamOffline, isFalse);
        if (migration) {
          h.reconnect();
        } else {
          await h.sockets.first.close(4005, 'Network timeout');
        }
        await h.waitForConnections(2);
        await h.ready();
        // The periodic poll is three real seconds away with accelerated timers.
        await _waitUntil(() => h.session.state.viewerCount == 42)
            .timeout(const Duration(milliseconds: 500));
        expect(h.viewerRequests, hasLength(2));
        expect(h.session.state.status, ChatConnectionStatus.connected);
      },
    );

    test(
      'replaces a stalled viewer request after ${migration ? 'migration' : 'reconnect'} and ignores its late reply',
      () async {
        (RequestOptions, RequestInterceptorHandler)? held;
        final h = await _Harness.start(
          viewerRequestHandler: (r, handler, index) {
            if (index == 0) {
              held = (r, handler);
            } else {
              _replyViewers(r, handler, 42);
            }
          },
        );
        addTearDown(h.close);
        await h.ready();
        await _waitUntil(() => held != null);
        if (migration) {
          h.reconnect();
        } else {
          await h.sockets.first.close(4005, 'Network timeout');
        }
        await h.waitForConnections(2);
        await h.ready();
        await _waitUntil(() => h.session.state.viewerCount == 42)
            .timeout(const Duration(milliseconds: 500));
        expect(held!.$1.cancelToken!.isCancelled, isTrue);
        _replyViewers(held!.$1, held!.$2, 999);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(h.session.state.viewerCount, 42);
        expect(h.session.state.status, ChatConnectionStatus.connected);
      },
    );
  }

  test('recovers promptly when the network returns after repeated failures', () async {
    final h = await _Harness.start(refusedUpgrades: 6);
    addTearDown(h.close);
    // The endpoint becomes available after the sixth failed handshake.
    await _waitUntil(() => h.upgradeRequests.length == 6);
    // Scale 20: a 5.5-second maximum backoff fits; the old 30 seconds does not.
    await h.waitForConnections(1).timeout(const Duration(milliseconds: 600));
    await h.ready();
    await h.deliver(h.sockets.last, 'after');
    expect(h.upgradeRequests, hasLength(7));
  });

  test(
    'successful migration inherits subscriptions and closes old transport',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await h.ready();
      h.reconnect();
      await h.waitForConnections(2);
      await h.ready();
      await h.deliver(h.sockets.last, 'after');
      await _waitUntil(() => h.sockets.first.readyState == WebSocket.closed);
      expect(h.chatSubscriptions, 5);
    },
  );

  test(
    'keepalive timeout closes old transport and restores delivery',
    () async {
      final h = await _Harness.start(silentAfterWelcome: true);
      addTearDown(h.close);
      await h.ready();
      await h.deliver(h.sockets.first, 'before');
      await h.waitForConnections(2);
      await h.ready();
      await h.deliver(h.sockets.last, 'after');
      await _waitUntil(() => h.sockets.first.readyState == WebSocket.closed);
      expect(h.errors, isEmpty);
      expect(h.session.state.items.map((i) => i.id), ['before', 'after']);
    },
  );

  test(
    'migration without welcome falls back even after old socket closes',
    () async {
      final h = await _Harness.start(silentMigration: true);
      addTearDown(h.close);
      await h.ready();
      await h.deliver(h.sockets.first, 'before');
      h.reconnect();
      await h.waitForConnections(2);
      await h.deliver(h.sockets.first, 'during');
      final statusDuringMigration = h.session.state.status;
      await h.sockets.first.close(4004, 'Reconnect grace time expired');
      await h.waitForConnections(3);
      await h.ready();
      await h.deliver(h.sockets.last, 'after');
      expect(statusDuringMigration, ChatConnectionStatus.reconnecting);
      expect(h.session.state.items.map((i) => i.id), [
        'before',
        'during',
        'after',
      ]);
      await _waitUntil(() => h.sockets[1].readyState == WebSocket.closed);
    },
  );

  test(
    'initial socket without welcome times out and restores delivery',
    () async {
      final h = await _Harness.start(silentFirst: true);
      addTearDown(h.close);
      await h.waitForConnections(2);
      await h.ready();
      await h.deliver(h.sockets.last, 'after');
      await _waitUntil(() => h.sockets.first.readyState == WebSocket.closed);
    },
  );

  test('stalled initial handshake times out and restores delivery', () async {
    final h = await _Harness.start(holdFirstUpgrade: true);
    addTearDown(h.close);
    await h.waitForConnections(1);
    await h.ready();
    await h.deliver(h.sockets.last, 'after');
    expect(h.upgradeRequests, hasLength(2));
  });

  test(
    'stalled migration handshake recovers after the old socket closes',
    () async {
      final h = await _Harness.start(holdMigrationUpgrade: true);
      addTearDown(h.close);
      await h.ready();
      h.reconnect();
      await _waitUntil(() => h.heldUpgrade != null);
      await h.sockets.first.close(4004, 'Reconnect grace time expired');
      await h.waitForConnections(2);
      await h.ready();
      await h.deliver(h.sockets.last, 'after');
      expect(h.upgradeRequests, hasLength(3));
    },
  );

  test(
    'repeated reconnect frames cannot start concurrent handshakes',
    () async {
      final h = await _Harness.start(holdMigrationUpgrade: true);
      addTearDown(h.close);
      await h.ready();
      h.reconnect();
      await _waitUntil(() => h.heldUpgrade != null);
      h.reconnect();
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(h.upgradeRequests, hasLength(2));
      expect(h.session.state.status, ChatConnectionStatus.reconnecting);
    },
  );

  test('leaving cancels a pending handshake without affecting the next join', () async {
    final h = await _Harness.start(holdFirstUpgrade: true);
    addTearDown(h.close);
    await h.session.leave();
    await _fastTimers(() => h.session.join(broadcasterId: 'other-channel'));
    await h.ready();
    await h.deliver(h.sockets.last, 'after');
    await h.joining;
    // The previous attempt's deadline must not restart the replacement session.
    await Future<void>.delayed(const Duration(milliseconds: 850));
    expect(h.session.state.broadcasterId, 'other-channel');
    expect(h.session.state.status, ChatConnectionStatus.connected);
    expect(h.upgradeRequests, hasLength(2));
    expect(h.sockets, hasLength(1));
  });

  test(
    'stalled message subscription times out and restores delivery',
    () async {
      final h = await _Harness.start(holdMessageSubscription: true);
      addTearDown(h.close);
      await _waitUntil(() => h.heldRequest != null);
      await h.waitForConnections(2);
      await h.ready();
      await h.deliver(h.sockets.last, 'after');
      expect(h.heldRequest!.$1.cancelToken!.isCancelled, isTrue);
      expect(
        h.requests.where(
          (r) =>
              _sessionId(r) == 'session-1' &&
              (r.data as Map)['type'] == TwitchHelixClient.bitsSubscriptionType,
        ),
        isEmpty,
      );
    },
  );

  test(
    'revoked chat authorization closes sockets and requires sign-in',
    () async {
      final h = await _Harness.start();
      addTearDown(h.close);
      await h.ready();
      h.revoke('channel.chat.message', 'authorization_revoked');
      await _waitUntil(() => h.auth.signOutCalls == 1);
      expect(h.session.state.status, ChatConnectionStatus.failure);
      expect(h.auth.state.status, TwitchAuthStatus.signedOut);
      await _waitUntil(() => h.sockets.first.readyState == WebSocket.closed);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(h.sockets, hasLength(1));
    },
  );

  for (final reason in ['version_removed', 'user_removed']) {
    test(
      'chat revocation $reason reports failure without an endless retry',
      () async {
        final h = await _Harness.start();
        addTearDown(h.close);
        await h.ready();
        h.revoke('channel.chat.message', reason);
        await _waitUntil(
          () => h.session.state.status == ChatConnectionStatus.failure,
        );
        await _waitUntil(() => h.sockets.first.readyState == WebSocket.closed);
        expect(h.session.state.error, contains(reason));
        expect(h.auth.signOutCalls, 0);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(h.sockets, hasLength(1));
      },
    );
  }

  test('optional reward revocation keeps ordinary chat available', () async {
    final h = await _Harness.start();
    addTearDown(h.close);
    await h.ready();
    h.revoke(TwitchHelixClient.rewardSubscriptionType, 'version_removed');
    await _waitUntil(() => h.session.state.rewardSubscriptionFailed);
    await h.deliver(h.sockets.first, 'after');
    expect(h.session.state.status, ChatConnectionStatus.connected);
    expect(h.auth.signOutCalls, 0);
    expect(h.sockets, hasLength(1));
  });

  test(
    'Helix timeout cancels a stalled HTTP request outside socket setup',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = Completer<void>();
      final listener = server.listen((r) {
        received.complete();
      });
      CancelToken? cancellation;
      final dio = Dio(BaseOptions(baseUrl: 'http://127.0.0.1:${server.port}'))
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, handler) {
              cancellation = r.cancelToken;
              handler.next(r);
            },
          ),
        );
      addTearDown(() async {
        dio.close(force: true);
        await listener.cancel();
        await server.close(force: true);
      });
      final helix = TwitchHelixClient(_Auth(), dio: dio);
      final timedOut = expectLater(
        _fastTimers(() async {
          await helix.sendMessage(
            broadcasterId: 'owner',
            senderId: 'owner',
            message: 'test',
          );
        }),
        throwsA(isA<TimeoutException>()),
      );
      await received.future.timeout(const Duration(seconds: 2));
      await timedOut;
      expect(cancellation!.isCancelled, isTrue);
    },
  );

  test('leaving during token validation prevents late subscriptions', () async {
    final token = Completer<TwitchToken>();
    final h = await _Harness.start(auth: _Auth(pendingToken: token.future));
    addTearDown(h.close);
    await _waitUntil(() => h.auth.tokenCalls >= 4);
    await h.session.leave();
    token.complete(_token);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(h.requests, isEmpty);
    expect(h.session.state.status, ChatConnectionStatus.idle);
  });

  test('late subscription completion after leaving cannot create Bits subscription', () async {
    final h = await _Harness.start(holdMessageSubscription: true);
    addTearDown(h.close);
    await _waitUntil(() => h.heldRequest != null);
    await h.session.leave();
    h.releaseRequest();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(
      h.requests.where(
        (r) =>
            (r.data as Map)['type'] == TwitchHelixClient.bitsSubscriptionType,
      ),
      isEmpty,
    );
    expect(h.session.state.status, ChatConnectionStatus.idle);
  });
}

String _sessionId(RequestOptions request) =>
    ((request.data as Map)['transport'] as Map)['session_id'] as String;

void _reply(RequestOptions r, RequestInterceptorHandler h) =>
    h.resolve(Response(requestOptions: r, data: <String, Object?>{'data': []}));

void _replyViewers(RequestOptions r, RequestInterceptorHandler h, int count) =>
    h.resolve(
      Response(
        requestOptions: r,
        data: <String, Object?>{
          'data': [
            {'viewer_count': count},
          ],
        },
      ),
    );

class _Harness {
  _Harness(this.auth);
  final _Auth auth;
  final dio = Dio();
  final sockets = <WebSocket>[];
  final keepalives = <Timer>[];
  final requests = <RequestOptions>[];
  final viewerRequests = <RequestOptions>[];
  final upgradeRequests = <HttpRequest>[];
  final errors = <Object>[];
  late HttpServer server;
  late StreamSubscription<HttpRequest> listener;
  late EventSubTwitchChatSession session;
  late Future<void> joining;
  HttpRequest? heldUpgrade;
  (RequestOptions, RequestInterceptorHandler)? heldRequest;
  bool requestReleased = false;
  int nextId = 0;

  int get chatSubscriptions => requests
      .where(
        (r) => TwitchHelixClient.chatSubscriptionTypes.contains(
          (r.data as Map)['type'],
        ),
      )
      .length;
  String get url => 'ws://127.0.0.1:${server.port}';

  static Future<_Harness> start({
    bool silentMigration = false,
    bool silentFirst = false,
    bool silentAfterWelcome = false,
    bool holdMessageSubscription = false,
    bool holdFirstUpgrade = false,
    bool holdMigrationUpgrade = false,
    int refusedUpgrades = 0,
    void Function(RequestOptions, RequestInterceptorHandler, int)?
    viewerRequestHandler,
    _Auth? auth,
  }) async {
    final h = _Harness(auth ?? _Auth());
    h.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    h.listener = h.server.listen((r) async {
      h.upgradeRequests.add(r);
      if (h.upgradeRequests.length <= refusedUpgrades) {
        r.response.statusCode = HttpStatus.serviceUnavailable;
        await r.response.close();
        return;
      }
      if ((holdFirstUpgrade && h.upgradeRequests.length == 1) ||
          (holdMigrationUpgrade &&
              r.uri.path == '/migration' &&
              h.heldUpgrade == null)) {
        h.heldUpgrade = r;
        return;
      }
      final ws = await WebSocketTransformer.upgrade(r);
      h.sockets.add(ws);
      ws.listen((_) {}, onError: (Object _) {});
      final silent =
          (silentMigration && r.uri.path == '/migration') ||
          (silentFirst && h.sockets.length == 1);
      if (!silent) {
        h.frame(ws, 'session_welcome', {
          'session': {
            'id': 'session-${h.sockets.length}',
            'keepalive_timeout_seconds': 30,
          },
        });
        if (!silentAfterWelcome || h.sockets.length != 1) {
          h.keepalives.add(
            Timer.periodic(const Duration(milliseconds: 100), (_) {
              if (ws.readyState == WebSocket.open) {
                h.frame(ws, 'session_keepalive', {});
              }
            }),
          );
        }
      }
    });
    h.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (r, handler) {
          if (r.path == '/streams') {
            final index = h.viewerRequests.length;
            h.viewerRequests.add(r);
            if (viewerRequestHandler != null) {
              viewerRequestHandler(r, handler, index);
              return;
            }
          }
          if (r.path == '/eventsub/subscriptions') {
            h.requests.add(r);
            if (holdMessageSubscription &&
                h.heldRequest == null &&
                (r.data as Map)['type'] == 'channel.chat.message') {
              h.heldRequest = (r, handler);
              return;
            }
          }
          _reply(r, handler);
        },
      ),
    );
    h.session = EventSubTwitchChatSession(
      h.auth,
      TwitchHelixClient(h.auth, dio: h.dio),
      eventSubUrl: h.url,
    );
    h.joining = _fastTimers(
      () => h.session.join(broadcasterId: 'owner'),
      onError: (error, stack) => h.errors.add(error),
    );
    if (holdFirstUpgrade) {
      await _waitUntil(() => h.heldUpgrade != null);
    } else {
      await h.joining;
    }
    return h;
  }

  void frame(WebSocket ws, String type, Map<String, Object?> payload) => ws.add(
    jsonEncode({
      'metadata': {'message_type': type, 'message_id': 'frame-${nextId++}'},
      'payload': payload,
    }),
  );

  void reconnect() => frame(sockets.first, 'session_reconnect', {
    'session': {'reconnect_url': '$url/migration'},
  });

  void revoke(String type, String status) =>
      frame(sockets.first, 'revocation', {
        'subscription': {'type': type, 'status': status},
      });

  Future<void> deliver(WebSocket ws, String id) async {
    ws.add(
      jsonEncode({
        'metadata': {
          'message_type': 'notification',
          'message_id': 'delivery-${nextId++}',
          'subscription_type': 'channel.chat.message',
        },
        'payload': {
          'event': {
            'message_id': id,
            'chatter_user_id': 'viewer',
            'chatter_user_name': 'Viewer',
            'message': {
              'fragments': [
                {'type': 'text', 'text': id},
              ],
            },
          },
        },
      }),
    );
    await _waitUntil(() => session.state.items.any((i) => i.id == id));
  }

  Future<void> ready() =>
      _waitUntil(() => session.state.status == ChatConnectionStatus.connected);
  Future<void> waitForConnections(int count) =>
      _waitUntil(() => sockets.length >= count);

  void releaseRequest() {
    if (heldRequest case final pending? when !requestReleased) {
      requestReleased = true;
      _reply(pending.$1, pending.$2);
    }
  }

  Future<void> close() async {
    for (final timer in keepalives) {
      timer.cancel();
    }
    await session.leave();
    await joining;
    releaseRequest();
    for (final ws in sockets) {
      await ws.close();
    }
    await listener.cancel();
    await server.close(force: true);
    dio.close(force: true);
    expect(
      errors,
      isEmpty,
      reason: 'Connection lifecycle must not leak asynchronous errors',
    );
  }
}

Future<void> _waitUntil(bool Function() done) async {
  final end = DateTime.now().add(const Duration(seconds: 4));
  while (!done()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Condition was not satisfied');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

// Accelerate application deadlines while keeping real sockets and frame parsing.
Future<void> _fastTimers(
  Future<void> Function() work, {
  void Function(Object, StackTrace)? onError,
}) => runZoned(
  work,
  zoneSpecification: ZoneSpecification(
    handleUncaughtError: onError == null
        ? null
        : (self, parent, zone, error, stack) => onError(error, stack),
    createTimer: (self, parent, zone, duration, callback) => parent.createTimer(
      zone,
      Duration(microseconds: duration.inMicroseconds ~/ 20),
      callback,
    ),
    createPeriodicTimer: (self, parent, zone, duration, callback) =>
        parent.createPeriodicTimer(
          zone,
          Duration(microseconds: duration.inMicroseconds ~/ 20),
          callback,
        ),
  ),
);

class _FrameServer {
  late HttpServer server;
  late StreamSubscription<HttpRequest> listener;
  final sockets = <Socket>[];
  final timers = <Timer>[];
  final opcodes = <int>[];
  int frameId = 0;

  static Future<_FrameServer> start() async {
    final h = _FrameServer();
    h.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    h.listener = h.server.listen((r) async {
      final key = r.headers.value('Sec-WebSocket-Key')!;
      r.response.statusCode = 101;
      r.response.headers.set('Upgrade', 'websocket');
      r.response.headers.set('Connection', 'Upgrade');
      r.response.headers.set(
        'Sec-WebSocket-Accept',
        base64Encode(
          sha1
              .convert(
                utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
              )
              .bytes,
        ),
      );
      final ws = await r.response.detachSocket(writeHeaders: true);
      h.sockets.add(ws);
      final buffer = <int>[];
      ws.listen((bytes) {
        buffer.addAll(bytes);
        while (buffer.length >= 2) {
          final opcode = buffer[0] & 15;
          var length = buffer[1] & 127;
          var offset = 2;
          if (length == 126) {
            if (buffer.length < 4) return;
            length = (buffer[2] << 8) | buffer[3];
            offset = 4;
          }
          if (length == 127) throw StateError('Unexpected huge control frame');
          final masked = (buffer[1] & 128) != 0;
          final start = offset + (masked ? 4 : 0);
          if (buffer.length < start + length) return;
          final payload = List<int>.generate(
            length,
            (i) => buffer[start + i] ^ (masked ? buffer[offset + i % 4] : 0),
          );
          buffer.removeRange(0, start + length);
          h.opcodes.add(opcode);
          if (opcode == 9) ws.add([0x8a, payload.length, ...payload]);
          if (opcode == 8) {
            ws.add([0x88, payload.length, ...payload]);
            unawaited(ws.flush().then((_) => ws.destroy()));
            return;
          }
        }
      }, onError: (Object _) {});
      h.frame(ws, 'session_welcome', {
        'session': {'id': 'raw', 'keepalive_timeout_seconds': 30},
      });
      h.timers.add(
        Timer.periodic(const Duration(milliseconds: 100), (_) {
          h.frame(ws, 'session_keepalive', {});
          ws.add([
            0x89,
            0,
          ]); // Standard server Ping; the client must return Pong.
        }),
      );
    });
    return h;
  }

  void frame(Socket ws, String type, Map<String, Object?> payload) {
    final data = utf8.encode(
      jsonEncode({
        'metadata': {'message_type': type, 'message_id': 'raw-${frameId++}'},
        'payload': payload,
      }),
    );
    final header = data.length < 126
        ? [0x81, data.length]
        : [0x81, 126, data.length >> 8, data.length & 255];
    ws.add([...header, ...data]);
  }

  Future<void> close() async {
    for (final timer in timers) {
      timer.cancel();
    }
    for (final ws in sockets) {
      ws.destroy();
    }
    await listener.cancel();
    await server.close(force: true);
  }
}

final _token = TwitchToken(
  accessToken: 'test',
  refreshToken: 'test',
  clientId: 'client',
  userId: 'owner',
  userLogin: 'owner',
  scopes: TwitchAuthClient.authorizationScopes,
  expiresAt: DateTime.utc(2030),
);

class _Auth implements TwitchAuth {
  _Auth({this.pendingToken});
  final Future<TwitchToken>? pendingToken;
  int signOutCalls = 0;
  int tokenCalls = 0;
  @override
  TwitchAuthState state = TwitchAuthState(
    status: TwitchAuthStatus.signedIn,
    token: _token,
  );

  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async {
    tokenCalls++;
    return pendingToken ?? _token;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    state = const TwitchAuthState(status: TwitchAuthStatus.signedOut);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
