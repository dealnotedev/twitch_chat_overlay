import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/emotes/third_party_emotes.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_recent_messages.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

const _enabled = ThirdPartyEmoteOptions(sevenTv: true, betterTtv: true);

void main() {
  test('integrations start off and toggle independently without reconnecting', () async {
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            requests.add(r);
            _replyEmotes(r, h);
          },
        ),
      );
    final harness = await _Harness.start(emotes: ThirdPartyEmotes(dio: dio));
    addTearDown(harness.close);
    await harness.ready;
    expect(requests, isEmpty);
    expect(harness.session.state.emoteOptions, const ThirdPartyEmoteOptions());
    final loaded = harness.session.states.firstWhere(
      (s) => s.emoteCatalog.emotes.isNotEmpty,
    );
    harness.session.setEmoteOptions(
      const ThirdPartyEmoteOptions(betterTtv: true),
    );
    await loaded.timeout(const Duration(seconds: 5));
    expect(requests, hasLength(2));
    expect(requests.every((r) => r.uri.host == 'api.betterttv.net'), isTrue);
    harness.session.setEmoteOptions(const ThirdPartyEmoteOptions());
    expect(harness.session.state.emoteCatalog.emotes, isEmpty);
    expect(harness.session.state.status, ChatConnectionStatus.connected);
    harness.session.setEmoteOptions(
      const ThirdPartyEmoteOptions(sevenTv: true),
    );
    // Both the 7TV fixture and the native test catalog have no usable entries.
    await expectLater(harness.session.loadEmotes(), throwsFormatException);
    expect(requests, hasLength(4));
    expect(requests.skip(2).every((r) => r.uri.host == '7tv.io'), isTrue);
    expect(harness.session.state.emoteCatalog.emotes, isEmpty);
    expect(harness.session.state.status, ChatConnectionStatus.connected);
    harness.session.setEmoteOptions(
      const ThirdPartyEmoteOptions(betterTtv: true),
    );
    expect((await harness.session.loadEmotes()).single.name, 'OMEGALUL');
    expect(requests, hasLength(4)); // Re-enabling can reuse the cached set.
    expect(harness.historyRequests, 1);
  });

  test('switching off during loading rejects stale picker results and keeps chat connected', () async {
    final pending = <(RequestOptions, RequestInterceptorHandler)>[];
    final started = Completer<void>();
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) {
            pending.add((r, h));
            if (pending.length == 4) started.complete();
          },
        ),
      );
    final harness = await _Harness.start(
      emotes: ThirdPartyEmotes(dio: dio),
      options: _enabled,
    );
    addTearDown(harness.close);
    await harness.ready;
    await started.future;
    final rejected = expectLater(
      harness.session.loadEmotes(),
      throwsStateError,
    );
    harness.session.setEmoteOptions(const ThirdPartyEmoteOptions());
    for (final (r, h) in pending) {
      _replyEmotes(r, h);
    }
    await rejected;
    expect(harness.session.state.emoteCatalog.emotes, isEmpty);
    expect(harness.session.state.emoteOptions.enabled, isFalse);
    expect(harness.session.state.status, ChatConnectionStatus.connected);
    // A subsequent valid enable must still work after the old load completed.
    harness.session.setEmoteOptions(
      const ThirdPartyEmoteOptions(betterTtv: true),
    );
    expect((await harness.session.loadEmotes()).single.name, 'OMEGALUL');
    expect(pending, hasLength(4));
  });

  test('preloads third-party emotes without opening the picker and resolves history', () async {
    final service = ThirdPartyEmotes(dio: _emoteDio());
    final harness = await _Harness.start(emotes: service, options: _enabled);
    addTearDown(harness.close);
    await harness.ready;
    if (harness.session.state.emoteCatalog.emotes.isEmpty) {
      await harness.session.states
          .firstWhere((s) => s.emoteCatalog.emotes.isNotEmpty)
          .timeout(const Duration(seconds: 5));
    }
    final loaded = harness.session.states.firstWhere((s) => s.items.isNotEmpty);
    harness.completeHistory(['OMEGALUL']);
    final state = await loaded.timeout(const Duration(seconds: 5));
    final message = state.items.single as ChatUserMessage;
    expect(message.isHistorical, isTrue);
    expect(message.fragments.single, isA<ChatTextFragment>());
    expect(
      state.emoteCatalog.resolve(message.fragments).single,
      isA<ChatThirdPartyEmoteFragment>(),
    );
    // This harness deliberately returns an invalid Helix emote response.
    // Optional providers remain usable if the native catalog cannot be loaded.
    expect((await harness.session.loadEmotes()).single.name, 'OMEGALUL');
  });

  test(
    'late third-party requests cannot restore a catalog after leaving',
    () async {
      final pending = <(RequestOptions, RequestInterceptorHandler)>[];
      final started = Completer<void>();
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              pending.add((r, h));
              if (pending.length == 4) started.complete();
            },
          ),
        );
      final harness = await _Harness.start(
        emotes: ThirdPartyEmotes(dio: dio),
        options: _enabled,
      );
      addTearDown(harness.close);
      await harness.ready;
      await started.future;
      // A picker request shares the already pending public HTTP requests.
      final picker = harness.session.loadEmotes();
      final rejected = expectLater(picker, throwsStateError);
      await harness.session.leave();
      for (final (r, h) in pending) {
        _replyEmotes(r, h);
      }
      await rejected;
      expect(harness.session.state.emoteCatalog.emotes, isEmpty);
      expect(harness.session.state.status, ChatConnectionStatus.idle);
    },
  );

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

  static Future<_Harness> start({
    ThirdPartyEmotes? emotes,
    ThirdPartyEmoteOptions options = const ThirdPartyEmoteOptions(),
  }) async {
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
      thirdPartyEmotes: emotes,
      emoteOptions: options,
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

Dio _emoteDio() =>
    Dio()..interceptors.add(InterceptorsWrapper(onRequest: _replyEmotes));

void _replyEmotes(RequestOptions r, RequestInterceptorHandler h) {
  final global = r.path.endsWith('/global');
  h.resolve(
    Response(
      requestOptions: r,
      statusCode: 200,
      data: r.uri.host == '7tv.io'
          ? (global ? {'emotes': []} : {'emote_set': null})
          : (global
                ? [
                    {'id': '1', 'code': 'OMEGALUL', 'animated': false},
                  ]
                : {'channelEmotes': [], 'sharedEmotes': []}),
    ),
  );
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
