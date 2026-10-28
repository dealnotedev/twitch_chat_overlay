import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/overlay/overlay_view_model.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chatters.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

void main() {
  test(
    'reconnecting Twitch clears the missing chatter permission immediately',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final listener = server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
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
      final auth = _ReconnectAuth();
      final dio = Dio();
      var chatterLoads = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            if (request.path == '/chat/chatters') chatterLoads++;
            handler.resolve(
              Response(
                requestOptions: request,
                data: <String, Object?>{
                  'data': <Object?>[
                    if (request.path == '/chat/chatters')
                      {
                        'user_id': 'existing',
                        'user_login': 'existing',
                        'user_name': 'Existing',
                      },
                  ],
                  'pagination': <String, Object?>{},
                },
              ),
            );
          },
        ),
      );
      final session = EventSubTwitchChatSession(
        auth,
        TwitchHelixClient(auth, dio: dio),
        eventSubUrl: 'ws://127.0.0.1:${server.port}',
      );
      final viewModel = OverlayViewModel(
        initialLayout: const OverlayLayout.defaults()
            .withNewChatterNotifications(true),
        layoutStore: _LayoutStore(),
        host: _Host(),
        auth: auth,
        chat: session,
      );
      addTearDown(() async {
        viewModel.dispose();
        await session.leave();
        for (final socket in sockets) {
          await socket.close();
        }
        await listener.cancel();
        await server.close(force: true);
        auth.value.dispose();
        dio.close(force: true);
      });
      await _until(
        () =>
            session.state.status == ChatConnectionStatus.connected &&
            viewModel.newChatterIssue.current ==
                NewChatterIssue.authorizationRequired,
      );
      expect(chatterLoads, 0);
      sockets.single.add(
        jsonEncode({
          'metadata': {
            'message_type': 'notification',
            'message_id': 'before-reauth',
            'subscription_type': 'channel.chat.message',
          },
          'payload': {
            'event': {
              'message_id': 'before-reauth',
              'chatter_user_id': 'active',
              'chatter_user_name': 'Active',
              'message': {
                'fragments': [
                  {'type': 'text', 'text': 'Keep this message'},
                ],
              },
            },
          },
        }),
      );
      await _until(() => session.state.items.isNotEmpty);
      await viewModel.signIn();
      // Allow the mocked HTTP futures to finish, without waiting for the poll.
      await _until(() => viewModel.newChatterIssue.current == null).timeout(
        const Duration(seconds: 1),
        onTimeout: () => fail(
          'Permission warning still present after successful reauthorization',
        ),
      );
      expect(
        viewModel.newChatterIssue.current,
        isNull,
        reason: 'Successful reauthorization must clear the permission warning immediately',
      );
      expect(chatterLoads, 1);
      expect(
        sockets,
        hasLength(1),
        reason: 'The existing chat connection should stay open',
      );
      expect(session.state.status, ChatConnectionStatus.connected);
      expect(session.state.items.map((item) => item.id), ['before-reauth']);
      expect(session.state.items.whereType<ChatChatterArrival>(), isEmpty);
    },
  );

  for (final live in [true, false]) {
    test(
      'existing chat activity only suppresses arrivals; Helix alone adds cards (${live ? 'live' : 'offline'})',
      () async {
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
        final auth = _Auth();
        final dio = Dio();
        var users = ['existing'];
        var chatterLoads = 0;
        final subscriptions = <String>[];
        final timers = <_PollTimer>[];
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (request, handler) {
              Object? data = <Object?>[];
              if (request.path == '/streams') {
                data = [
                  if (live)
                    {
                      'id': 'broadcast',
                      'started_at': DateTime.now()
                          .toUtc()
                          .subtract(const Duration(hours: 1))
                          .toIso8601String(),
                      'viewer_count': 10,
                    },
                ];
              } else if (request.path == '/chat/chatters') {
                chatterLoads++;
                data = users
                    .map(
                      (id) => {
                        'user_id': id,
                        'user_login': id,
                        'user_name': id,
                      },
                    )
                    .toList();
              } else if (request.path == '/eventsub/subscriptions') {
                subscriptions.add((request.data as Map)['type'] as String);
              }
              handler.resolve(
                Response(
                  requestOptions: request,
                  data: <String, Object?>{
                    'data': data,
                    'pagination': <String, Object?>{},
                  },
                ),
              );
            },
          ),
        );
        final session = EventSubTwitchChatSession(
          auth,
          TwitchHelixClient(auth, dio: dio),
          eventSubUrl: 'ws://127.0.0.1:${server.port}',
          newChatterNotifications: true,
        );
        addTearDown(() async {
          await session.leave();
          if (connected.isCompleted) await (await connected.future).close();
          await listener.cancel();
          await server.close(force: true);
          dio.close(force: true);
        });

        await runZoned(
          () async {
            await session.join(broadcasterId: 'owner');
            await _until(
              () =>
                  session.state.status == ChatConnectionStatus.connected &&
                  chatterLoads > 0,
            );
            final socket = await connected.future;
            var delivery = 0;
            void send(String type, Map<String, Object?> event) {
              socket.add(
                jsonEncode({
                  'metadata': {
                    'message_type': 'notification',
                    'message_id': 'delivery-${delivery++}',
                    'subscription_type': type,
                    'message_timestamp': DateTime.now()
                        .toUtc()
                        .toIso8601String(),
                  },
                  'payload': {'event': event},
                }),
              );
            }

            send('channel.chat.message', {
              'message_id': 'message',
              'chatter_user_id': 'message-actor',
              'chatter_user_name': 'MessageActor',
              'message': {
                'fragments': [
                  {'type': 'text', 'text': 'Hello'},
                ],
              },
            });
            send(TwitchHelixClient.rewardSubscriptionType, {
              'id': 'redemption',
              'user_id': 'reward-actor',
              'user_name': 'RewardActor',
              'reward': {'id': 'reward', 'title': 'Hydrate', 'cost': 100},
            });
            send(TwitchHelixClient.bitsSubscriptionType, {
              'type': 'power_up',
              'user_id': 'bits-actor',
              'user_name': 'BitsActor',
              'bits': 10,
              'power_up': {'type': 'celebration'},
            });
            send('channel.chat.notification', {
              'message_id': 'notice',
              'notice_type': 'sub',
              'system_message': 'Subscribed',
              'chatter_user_id': 'notice-actor',
              'chatter_user_name': 'NoticeActor',
            });
            await _until(() => session.state.items.length == 4);
            expect(
              session.state.items.whereType<ChatChatterArrival>(),
              isEmpty,
            );
            users = [
              'existing',
              'message-actor',
              'reward-actor',
              'bits-actor',
              'notice-actor',
              'silent',
            ];
            timers.single.fire();
            await _until(
              () => session.state.items
                  .whereType<ChatChatterArrival>()
                  .isNotEmpty,
            );
            expect(
              session.state.items.whereType<ChatChatterArrival>().map(
                (item) => item.userId,
              ),
              ['silent'],
            );
            expect(subscriptions.toSet(), {
              ...TwitchHelixClient.chatSubscriptionTypes,
              TwitchHelixClient.rewardSubscriptionType,
              TwitchHelixClient.bitsSubscriptionType,
            });
            expect(subscriptions, hasLength(7));
          },
          zoneSpecification: ZoneSpecification(
            createPeriodicTimer: (self, parent, zone, duration, callback) {
              if (duration != const Duration(seconds: 30)) {
                return parent.createPeriodicTimer(zone, duration, callback);
              }
              final timer = _PollTimer(callback);
              timers.add(timer);
              return timer;
            },
          ),
        );
      },
    );
  }
}

Future<void> _until(bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Session did not settle');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

class _Auth extends Fake implements TwitchAuth {
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async =>
      TwitchToken(
        accessToken: 'token',
        refreshToken: 'refresh',
        clientId: 'client',
        userId: 'owner',
        userLogin: 'owner',
        scopes: TwitchAuthClient.authorizationScopes,
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );
}

class _ReconnectAuth extends Fake implements TwitchAuth {
  final value = ObservableValue<TwitchAuthState>(
    current: const TwitchAuthState.loading(),
  );
  @override
  TwitchAuthState get state => value.current;
  @override
  Stream<TwitchAuthState> get states => value.changes;
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async =>
      state.token!;

  TwitchToken _token({required bool missingScope}) => TwitchToken(
    accessToken: missingScope ? 'before' : 'after',
    refreshToken: 'refresh',
    clientId: 'client',
    userId: 'owner',
    userLogin: 'owner',
    scopes: TwitchAuthClient.authorizationScopes,
    debugMissingScopes: missingScope ? ['moderator:read:chatters'] : [],
    expiresAt: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  Future<void> initialize() async => value.set(
    TwitchAuthState(
      status: TwitchAuthStatus.signedIn,
      token: _token(missingScope: true),
    ),
  );

  @override
  Future<void> signIn() async {
    value.set(const TwitchAuthState(status: TwitchAuthStatus.authorizing));
    value.set(
      TwitchAuthState(
        status: TwitchAuthStatus.signedIn,
        token: _token(missingScope: false),
      ),
    );
  }
}

class _Host extends Fake implements OverlayHost {
  @override
  OverlayHostState get state => const OverlayHostState.initial();
  @override
  Stream<OverlayHostState> get states => const Stream.empty();
  @override
  Future<void> initialize({bool excludedFromCapture = false}) async {}
  @override
  Future<void> setInteractive(bool interactive) async {}
}

class _LayoutStore extends Fake implements OverlayLayoutStore {
  @override
  Future<void> save(OverlayLayout layout) async {}
}

class _PollTimer implements Timer {
  _PollTimer(this.callback);
  final void Function(Timer) callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  void fire() {
    if (isActive) {
      tick++;
      callback(this);
    }
  }

  @override
  void cancel() => isActive = false;
}
