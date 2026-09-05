import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

import 'twitch_emotes_test.dart' as fixtures;

Matcher failure(TwitchChatActionFailure value) => throwsA(
  isA<TwitchChatActionException>().having((e) => e.failure, 'failure', value),
);

void reject(RequestOptions r, RequestInterceptorHandler h, int status) =>
    h.reject(
      DioException(
        requestOptions: r,
        response: Response(requestOptions: r, statusCode: status),
      ),
    );

void main() {
  test(
    'deletes exactly one message and accepts the empty 204 response',
    () async {
      final requests = <RequestOptions>[];
      final client = TwitchHelixClient(
        fixtures.FakeAuth(),
        dio: fixtures.mockDio((r, h) {
          requests.add(r);
          h.resolve(
            Response<Map<String, Object?>>(requestOptions: r, statusCode: 204),
          );
        }),
      );
      await client.deleteMessage(
        broadcasterId: 'channel',
        moderatorId: 'sender',
        messageId: 'target',
      );
      expect(requests, hasLength(1));
      expect(requests.single.method, 'DELETE');
      expect(requests.single.path, '/moderation/chat');
      expect(requests.single.queryParameters, {
        'broadcaster_id': 'channel',
        'moderator_id': 'sender',
        'message_id': 'target',
      });
      expect(requests.single.headers['Authorization'], 'Bearer access');
      for (final ids in [
        ('', 'sender', 'target'),
        ('channel', '', 'target'),
        ('channel', 'sender', '  '),
      ]) {
        await expectLater(
          client.deleteMessage(
            broadcasterId: ids.$1,
            moderatorId: ids.$2,
            messageId: ids.$3,
          ),
          throwsArgumentError,
        );
      }
      expect(requests, hasLength(1));
    },
  );

  test('wrong identity never issues deletion', () async {
    final auth = fixtures.FakeAuth()
      ..token = fixtures.makeToken(user: 'different');
    var calls = 0;
    final client = TwitchHelixClient(
      auth,
      dio: fixtures.mockDio((r, h) {
        calls++;
        fixtures.reply(r, h, {});
      }),
    );
    await expectLater(
      client.deleteMessage(
        broadcasterId: 'channel',
        moderatorId: 'sender',
        messageId: 'target',
      ),
      failure(TwitchChatActionFailure.sessionChanged),
    );
    expect(calls, 0);
  });

  for (final status in [400, 401, 403, 404, 503]) {
    test('delete preserves Twitch failure $status', () async {
      final client = TwitchHelixClient(
        fixtures.FakeAuth(),
        dio: fixtures.mockDio((r, h) => reject(r, h, status)),
      );
      await expectLater(
        client.deleteMessage(
          broadcasterId: 'channel',
          moderatorId: 'sender',
          messageId: 'target',
        ),
        status == 401 || status == 503
            ? throwsA(isA<DioException>())
            : failure(
                status == 404
                    ? TwitchChatActionFailure.messageUnavailable
                    : TwitchChatActionFailure.forbidden,
              ),
      );
    });
  }

  for (final action in ['delete', 'reply']) {
    test('$action cannot retry as a different account after a 401', () async {
      final auth = fixtures.FakeAuth();
      var calls = 0;
      final client = TwitchHelixClient(
        auth,
        dio: fixtures.mockDio((r, h) {
          calls++;
          auth.token = fixtures.makeToken(user: 'different');
          reject(r, h, 401);
        }),
      );
      await expectLater(
        action == 'delete'
            ? client.deleteMessage(
                broadcasterId: 'channel',
                moderatorId: 'sender',
                messageId: 'target',
              )
            : client.sendMessage(
                broadcasterId: 'channel',
                senderId: 'sender',
                message: 'Hello',
                replyParentMessageId: 'target',
              ),
        failure(TwitchChatActionFailure.sessionChanged),
      );
      expect(calls, 1);
      expect(auth.refreshes, 1);
    });
  }

  test('session sends a real reply and removes a message only after Twitch confirms', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final connected = Completer<WebSocket>();
    final listener = server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      connected.complete(socket);
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
    final requests = <RequestOptions>[];
    var failDelete = true;
    final auth = fixtures.FakeAuth();
    final dio = fixtures.mockDio((r, h) {
      if (r.path == '/moderation/chat') {
        requests.add(r);
        if (failDelete) {
          reject(r, h, 503);
        } else {
          h.resolve(
            Response<Map<String, Object?>>(requestOptions: r, statusCode: 204),
          );
        }
      } else if (r.path == '/chat/messages') {
        requests.add(r);
        fixtures.reply(r, h, {
          'data': [
            {'is_sent': true, 'message_id': 'sent'},
          ],
        });
      } else {
        fixtures.reply(r, h, {'data': []});
      }
    });
    final session = EventSubTwitchChatSession(
      auth,
      TwitchHelixClient(auth, dio: dio),
      eventSubUrl: 'ws://127.0.0.1:${server.port}',
    );
    addTearDown(() async {
      await session.leave();
      if (connected.isCompleted) await (await connected.future).close();
      await listener.cancel();
      await server.close(force: true);
      dio.close(force: true);
    });
    final ready = session.states
        .firstWhere((s) => s.status == ChatConnectionStatus.connected)
        .timeout(const Duration(seconds: 5));
    await session.join(broadcasterId: 'sender');
    await ready;
    final socket = await connected.future;
    void emit(String delivery, String type, Map<String, Object?> event) =>
        socket.add(
          jsonEncode({
            'metadata': {
              'message_type': 'notification',
              'message_id': delivery,
              'subscription_type': type,
            },
            'payload': {'event': event},
          }),
        );
    final incoming = session.states
        .firstWhere((s) => s.items.length == 3)
        .timeout(const Duration(seconds: 5));
    for (final id in ['target', 'other', 'own']) {
      emit(id, 'channel.chat.message', {
        'message_id': id,
        'chatter_user_id': id == 'own' ? 'sender' : 'viewer',
        'chatter_user_name': 'Viewer',
        'message': {
          'fragments': [
            {'type': 'text', 'text': 'Hello'},
          ],
        },
      });
    }
    await incoming;
    expect((await session.send('Reply body', replyTo: 'target')).sent, isTrue);
    expect(requests.single.method, 'POST');
    expect(requests.single.data, {
      'broadcaster_id': 'sender',
      'sender_id': 'sender',
      'message': 'Reply body',
      'reply_parent_message_id': 'target',
    });
    await expectLater(
      session.deleteMessage('own'),
      failure(TwitchChatActionFailure.forbidden),
    );
    expect(requests, hasLength(1));
    await expectLater(
      session.deleteMessage('target'),
      throwsA(isA<DioException>()),
    );
    expect(session.state.items.map((i) => i.id), ['target', 'other', 'own']);
    failDelete = false;
    await session.deleteMessage('target');
    expect(session.state.items.map((i) => i.id), ['other', 'own']);
    await expectLater(
      session.send('Stale reply', replyTo: 'target'),
      failure(TwitchChatActionFailure.messageUnavailable),
    );
    expect(requests, hasLength(3));
    // A duplicate EventSub deletion must leave unrelated messages intact.
    emit('deleted', 'channel.chat.message_delete', {'message_id': 'target'});
    final cleared = session.states
        .firstWhere((s) => s.items.length == 1)
        .timeout(const Duration(seconds: 5));
    emit('deleted-other', 'channel.chat.message_delete', {
      'message_id': 'other',
    });
    await cleared;
    expect(session.state.items.single.id, 'own');
  });
}
