import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/viewer_count.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

import 'dart:async';

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

void main() {
  for (final locale in ['en', 'uk']) {
    testWidgets(
      'viewer display supports offline and unknown counts ($locale)',
      (tester) async {
        Future<void> show(int? count, {bool offline = false}) =>
            tester.pumpWidget(
              MaterialApp(
                locale: Locale(locale),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Center(
                    child: SizedBox(
                      width: 110,
                      child: ViewerCount(count: count, offline: offline),
                    ),
                  ),
                ),
              ),
            );
        await show(0);
        await tester.pumpAndSettle();
        expect(find.text('0'), findsOneWidget);
        await show(null);
        expect(find.text('—'), findsOneWidget);
        await show(null, offline: true);
        expect(
          find.text(locale == 'en' ? 'Offline' : 'Поза ефіром'),
          findsOneWidget,
        );
        await show(123456789);
        expect(tester.takeException(), isNull);
      },
    );
  }
  test(
    'viewer endpoint distinguishes live, offline and malformed responses',
    () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      Object? data = [
        {'viewer_count': 0},
      ];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            expect(request.path, '/streams');
            expect(request.queryParameters, {'user_id': 'owner'});
            expect(request.headers['Authorization'], 'Bearer test-token');
            expect(request.headers['Client-Id'], 'client');
            handler.resolve(
              Response(
                requestOptions: request,
                data: <String, Object?>{'data': data},
              ),
            );
          },
        ),
      );
      final helix = TwitchHelixClient(_Auth(), dio: dio);
      expect(await helix.getViewerCount(broadcasterId: 'owner'), 0);
      data = [
        {'viewer_count': 12345},
      ];
      expect(await helix.getViewerCount(broadcasterId: 'owner'), 12345);
      data = [];
      expect(await helix.getViewerCount(broadcasterId: 'owner'), isNull);
      for (final invalid in [
        null,
        {},
        [{}],
        [
          {'viewer_count': -1},
        ],
        [
          {'viewer_count': '12'},
        ],
      ]) {
        data = invalid;
        await expectLater(
          helix.getViewerCount(broadcasterId: 'owner'),
          throwsFormatException,
        );
      }
    },
  );

  test('polls every minute, recovers after failure, ignores late results and stops on leave', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final sockets = <WebSocket>[];
    final listener = server.listen((request) async {
      sockets.add(await WebSocketTransformer.upgrade(request));
    });
    final dio = Dio();
    final requests = <(RequestOptions, RequestInterceptorHandler)>[];
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          if (request.path == '/streams') {
            requests.add((request, handler));
          } else {
            handler.resolve(
              Response(
                requestOptions: request,
                data: <String, Object?>{'data': []},
              ),
            );
          }
        },
      ),
    );
    final auth = _Auth();
    final session = EventSubTwitchChatSession(
      auth,
      TwitchHelixClient(auth, dio: dio),
      eventSubUrl: 'ws://127.0.0.1:${server.port}',
    );
    final timers = <_ManualTimer>[];
    addTearDown(() async {
      await session.leave();
      for (final socket in sockets) {
        await socket.close();
      }
      await listener.cancel();
      await server.close(force: true);
      dio.close(force: true);
    });
    Future<void> flush() async {
      for (var i = 0; i < 10; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    void resolve(int index, Object? data) {
      final (request, handler) = requests[index];
      handler.resolve(
        Response(
          requestOptions: request,
          data: <String, Object?>{'data': data},
        ),
      );
    }

    await runZoned(
      () async {
        await session.join(broadcasterId: 'owner');
        await flush();
        expect(requests, hasLength(1));
        expect(timers, hasLength(1));
        resolve(0, [
          {'viewer_count': 120},
        ]);
        await flush();
        expect(session.state.viewerCount, 120);

        // Joining the same channel does not create another polling timer.
        await session.join(broadcasterId: 'owner');
        expect(timers, hasLength(1));
        timers.last.fire();
        await flush();
        expect(requests, hasLength(2));
        timers.last.fire();
        await flush();
        expect(requests, hasLength(2)); // No overlapping loads.
        resolve(1, []);
        await flush();
        expect(session.state.streamOffline, isTrue);
        expect(session.state.viewerCount, isNull);

        timers.last.fire();
        await flush();
        final (request, handler) = requests[2];
        handler.reject(DioException(requestOptions: request));
        await flush();
        expect(session.state.streamOffline, isFalse);
        expect(session.state.viewerCount, isNull);
        expect(session.state.status, ChatConnectionStatus.connecting);

        timers.last.fire();
        await flush();
        resolve(3, [
          {'viewer_count': 0},
        ]);
        await flush();
        expect(session.state.viewerCount, 0);
        expect(session.state.streamOffline, isFalse);

        timers.last.fire();
        await flush();
        final oldTimer = timers.last;
        await session.join(broadcasterId: 'other');
        await flush();
        expect(oldTimer.isActive, isFalse);
        expect(requests.last.$1.queryParameters, {'user_id': 'other'});
        resolve(5, [
          {'viewer_count': 42},
        ]);
        await flush();
        resolve(4, [
          {'viewer_count': 999},
        ]);
        await flush();
        expect(session.state.viewerCount, 42);

        timers.last.fire();
        await flush();
        await session.leave();
        expect(timers.every((timer) => !timer.isActive), isTrue);
        resolve(6, [
          {'viewer_count': 888},
        ]);
        await flush();
        expect(session.state.viewerCount, isNull);
        expect(session.state.status, ChatConnectionStatus.idle);
      },
      zoneSpecification: ZoneSpecification(
        createPeriodicTimer: (self, parent, zone, duration, callback) {
          if (duration == const Duration(minutes: 1)) {
            final timer = _ManualTimer(callback);
            timers.add(timer);
            return timer;
          }
          return parent.createPeriodicTimer(zone, duration, callback);
        },
      ),
    );
  });
}

class _ManualTimer implements Timer {
  _ManualTimer(this.callback);
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (isActive) {
      tick++;
      callback(this);
    }
  }
}

class _Auth implements TwitchAuth {
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async =>
      TwitchToken(
        accessToken: 'test-token',
        refreshToken: 'refresh',
        clientId: 'client',
        userId: 'owner',
        userLogin: 'owner',
        scopes: TwitchAuthClient.authorizationScopes,
        expiresAt: DateTime.utc(2030),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
