import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

void main() {
  for (final rejectRewards in [false, true]) {
    test(
      'reward subscription ${rejectRewards ? 'failure preserves chat' : 'delivers cards and artwork'}',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final connectedSocket = Completer<WebSocket>();
        final listener = server.listen((request) async {
          final socket = await WebSocketTransformer.upgrade(request);
          connectedSocket.complete(socket);
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
        final dio = Dio();
        final subscriptionTypes = <String>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              if (request.path == '/eventsub/subscriptions') {
                final type = (request.data as Map)['type'] as String;
                subscriptionTypes.add(type);
                if (rejectRewards &&
                    type == TwitchHelixClient.rewardSubscriptionType) {
                  handler.reject(
                    DioException(
                      requestOptions: request,
                      response: Response(
                        requestOptions: request,
                        statusCode: 403,
                      ),
                      type: DioExceptionType.badResponse,
                    ),
                  );
                  return;
                }
              }
              handler.resolve(
                Response(
                  requestOptions: request,
                  data: <String, Object?>{
                    'data': request.path == '/channel_points/custom_rewards'
                        ? [
                            {
                              'id': 'reward',
                              'image': {'url_2x': 'twitch-reward-image'},
                              'background_color': '#9146FF',
                            },
                          ]
                        : [],
                  },
                ),
              );
            },
          ),
        );
        final auth = _Auth();
        final session = EventSubTwitchChatSession(
          auth,
          TwitchHelixClient(auth, dio: dio),
          eventSubUrl: 'ws://127.0.0.1:${server.port}',
        );
        addTearDown(() async {
          await session.leave();
          if (connectedSocket.isCompleted) {
            await (await connectedSocket.future).close();
          }
          await listener.cancel();
          await server.close(force: true);
          dio.close(force: true);
        });
        final ready = session.states
            .firstWhere(
              (state) =>
                  state.status == ChatConnectionStatus.connected &&
                  (rejectRewards
                      ? state.rewardSubscriptionFailed
                      : state.rewards.containsKey('reward')),
            )
            .timeout(const Duration(seconds: 5));
        await session.join(broadcasterId: 'owner');
        await ready;
        expect(
          subscriptionTypes.where((t) => t == 'channel.chat.message'),
          hasLength(1),
        );
        expect(
          subscriptionTypes.where(
            (t) => t == TwitchHelixClient.rewardSubscriptionType,
          ),
          hasLength(1),
        );
        final socket = await connectedSocket.future;
        final incoming = session.states
            .firstWhere((state) => state.items.isNotEmpty)
            .timeout(const Duration(seconds: 5));
        socket.add(
          jsonEncode({
            'metadata': {
              'message_type': 'notification',
              'message_id': 'delivery-1',
              'subscription_type': rejectRewards
                  ? 'channel.chat.message'
                  : TwitchHelixClient.rewardSubscriptionType,
            },
            'payload': {
              'event': rejectRewards
                  ? {
                      'message_id': 'message',
                      'chatter_user_id': 'viewer',
                      'chatter_user_name': 'Viewer',
                      'message': {
                        'fragments': [
                          {'type': 'text', 'text': 'Still connected'},
                        ],
                      },
                    }
                  : {
                      'id': 'redemption',
                      'user_id': 'viewer',
                      'user_name': 'Viewer',
                      'user_input': '',
                      'reward': {
                        'id': 'reward',
                        'title': 'Hydrate',
                        'cost': 100,
                      },
                    },
            },
          }),
        );
        final received = await incoming;
        expect(received.status, ChatConnectionStatus.connected);
        if (rejectRewards) {
          expect(
            (received.items.single as ChatUserMessage).fragments.single.text,
            'Still connected',
          );
        } else {
          expect(
            (received.items.single as ChatRewardRedemption).rewardTitle,
            'Hydrate',
          );
          expect(received.rewards['reward']?.imageUrl, 'twitch-reward-image');
        }
      },
    );
  }
}

class _Auth implements TwitchAuth {
  @override
  Future<TwitchToken> validToken() async => TwitchToken(
    accessToken: 'test',
    refreshToken: 'test',
    clientId: 'client',
    userId: 'owner',
    userLogin: 'owner',
    scopes: TwitchAuthClient.requiredScopes,
    expiresAt: DateTime.utc(2030),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
