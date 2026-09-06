import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_recent_messages.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

void main() {
  test(
    'live chat and unseen deletion are preserved during delayed history',
    () async {
      final harness = await _Harness.start();
      addTearDown(harness.close);
      await harness.ready;
      harness.event('channel.chat.message_delete', {'message_id': 'deleted'});
      final incoming = harness.session.states.firstWhere(
        (s) => s.items.any((i) => i.id == 'live'),
      );
      harness.event('channel.chat.message', {
        'message_id': 'live',
        'chatter_user_id': 'viewer',
        'chatter_user_name': 'Viewer',
        'message': {
          'fragments': [
            {'type': 'text', 'text': 'live full message'},
          ],
        },
      });
      await incoming.timeout(const Duration(seconds: 5));
      final loaded = harness.session.states.firstWhere(
        (s) => s.items.any((i) => i.id == 'history'),
      );
      harness.completeHistory(['deleted', 'live', 'history']);
      final state = await loaded.timeout(const Duration(seconds: 5));
      expect(state.items.map((i) => i.id), ['history', 'live']);
      expect(
        (state.items.last as ChatUserMessage).fragments.single.text,
        'live full message',
      );
      expect(state.items.last.isHistorical, isFalse);
      expect(state.status, ChatConnectionStatus.connected);
      expect(harness.historyRequests, 1);
    },
  );

  test('history result from a session that was left is ignored', () async {
    final harness = await _Harness.start();
    addTearDown(harness.close);
    await harness.ready;
    await harness.session.leave();
    harness.completeHistory(['late']);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(harness.session.state.status, ChatConnectionStatus.idle);
    expect(harness.session.state.items, isEmpty);
  });

  test(
    'failed history request leaves chat connected and able to receive messages',
    () async {
      final harness = await _Harness.start();
      addTearDown(harness.close);
      await harness.ready;
      harness.rejectHistory();
      final incoming = harness.session.states.firstWhere(
        (s) => s.items.isNotEmpty,
      );
      harness.event('channel.chat.message', {
        'message_id': 'live',
        'chatter_user_id': 'viewer',
        'chatter_user_name': 'Viewer',
        'message': {
          'fragments': [
            {'type': 'text', 'text': 'Still connected'},
          ],
        },
      });
      final state = await incoming.timeout(const Duration(seconds: 5));
      expect(state.status, ChatConnectionStatus.connected);
      expect(state.items.single.id, 'live');
      expect(state.error, isNull);
    },
  );
}

class _Harness {
  final dio = Dio();
  final historyDio = Dio();
  late final HttpServer server;
  late final StreamSubscription<HttpRequest> listener;
  final socket = Completer<WebSocket>();
  final historyRequest = Completer<void>();
  late final EventSubTwitchChatSession session;
  late final RequestInterceptorHandler historyHandler;
  late final RequestOptions historyOptions;
  int historyRequests = 0;
  int eventId = 0;
  bool historyCompleted = false;

  Future<void> get ready =>
      historyRequest.future.timeout(const Duration(seconds: 5));

  static Future<_Harness> start() async {
    final h = _Harness();
    h.server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    h.listener = h.server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      h.socket.complete(socket);
      socket.add(
        jsonEncode({
          'metadata': {
            'message_type': 'session_welcome',
            'message_id': 'welcome',
          },
          'payload': {
            'session': {'id': 'session', 'keepalive_timeout_seconds': 30},
          },
        }),
      );
    });
    h.dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'data': request.path == '/users'
                    ? [
                        {'id': 'owner', 'login': 'owner'},
                      ]
                    : [],
              },
            ),
          );
        },
      ),
    );
    h.historyDio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          h.historyRequests++;
          h.historyHandler = handler;
          h.historyOptions = request;
          h.historyRequest.complete();
        },
      ),
    );
    final auth = _Auth();
    h.session = EventSubTwitchChatSession(
      auth,
      TwitchHelixClient(auth, dio: h.dio),
      eventSubUrl: 'ws://127.0.0.1:${h.server.port}',
      history: TwitchRecentMessages(dio: h.historyDio),
    );
    await h.session.join(broadcasterId: 'owner');
    return h;
  }

  void event(String type, Map<String, Object?> payload) async {
    (await socket.future).add(
      jsonEncode({
        'metadata': {
          'message_type': 'notification',
          'message_id': 'event-${eventId++}',
          'subscription_type': type,
          'message_timestamp': DateTime.now().toUtc().toIso8601String(),
        },
        'payload': {'event': payload},
      }),
    );
  }

  void completeHistory(List<String> ids) {
    historyCompleted = true;
    final time = DateTime.now()
        .subtract(const Duration(minutes: 1))
        .millisecondsSinceEpoch;
    historyHandler.resolve(
      Response(
        requestOptions: historyOptions,
        data: {
          'messages': [
            for (final id in ids)
              '@id=$id;user-id=viewer;display-name=Viewer;tmi-sent-ts=$time :viewer!v@v PRIVMSG #owner :$id',
          ],
        },
      ),
    );
  }

  void rejectHistory() {
    historyCompleted = true;
    historyHandler.reject(
      DioException(
        requestOptions: historyOptions,
        type: DioExceptionType.connectionTimeout,
      ),
    );
  }

  Future<void> close() async {
    if (historyRequest.isCompleted && !historyCompleted) completeHistory([]);
    await session.leave();
    if (socket.isCompleted) await (await socket.future).close();
    await listener.cancel();
    await server.close(force: true);
    dio.close(force: true);
    historyDio.close(force: true);
  }
}

class _Auth implements TwitchAuth {
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async =>
      TwitchToken(
        accessToken: 'test',
        refreshToken: 'test',
        clientId: 'client',
        userId: 'owner',
        userLogin: 'owner',
        scopes: TwitchAuthClient.authorizationScopes,
        expiresAt: DateTime.utc(2030),
      );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
