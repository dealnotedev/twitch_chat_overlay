import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'reward subscription uses broadcaster condition and existing WebSocket',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            handler.resolve(
              Response(
                requestOptions: request,
                data: <String, Object?>{'data': []},
              ),
            );
          },
        ),
      );
      final client = TwitchHelixClient(_Auth(), dio: dio);
      await client.createChatSubscriptions(
        sessionId: 'session',
        broadcasterId: 'owner',
        userId: 'owner',
      );
      await client.createRewardSubscription(
        sessionId: 'session',
        broadcasterId: 'owner',
      );
      final reward = requests.last;
      expect(reward.data, {
        'type': 'channel.channel_points_custom_reward_redemption.add',
        'version': '1',
        'condition': {'broadcaster_user_id': 'owner'},
        'transport': {'method': 'websocket', 'session_id': 'session'},
      });
      expect(
        requests.where((r) => (r.data as Map)['type'] == 'channel.raid'),
        isEmpty,
      );
      await client.createBitsSubscription(
        sessionId: 'session',
        broadcasterId: 'owner',
      );
      expect(requests.last.data, {
        'type': 'channel.bits.use',
        'version': '1',
        'condition': {'broadcaster_user_id': 'owner'},
        'transport': {'method': 'websocket', 'session_id': 'session'},
      });
      expect(TwitchAuthClient.authorizationScopes, contains('bits:read'));
      await client.getRewards(broadcasterId: 'owner');
      expect(requests.last.path, '/channel_points/custom_rewards');
      expect(requests.last.queryParameters, {
        'broadcaster_id': 'owner',
        'only_manageable_rewards': false,
      });
      expect(requests.last.headers['Authorization'], 'Bearer test-token');
    },
  );

  test('saved token keeps the session signed in', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesTwitchTokenStore(
      await SharedPreferences.getInstance(),
    );
    await store.write(_token);
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          handler.resolve(
            Response(
              requestOptions: request,
              data: <String, Object?>{
                'user_id': 'owner',
                'login': 'owner',
                'expires_in': 3600,
                'scopes': TwitchAuthClient.authorizationScopes,
              },
            ),
          );
        },
      ),
    );
    final auth = TwitchAuthClient(store, dio: dio);
    await auth.initialize();
    expect(auth.state.status, TwitchAuthStatus.signedIn);
  });
}

final _token = TwitchToken(
  accessToken: 'test-token',
  refreshToken: 'test-refresh',
  clientId: 'client',
  userId: 'owner',
  userLogin: 'owner',
  scopes: TwitchAuthClient.authorizationScopes,
  expiresAt: DateTime.utc(2030),
);

class _Auth implements TwitchAuth {
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async => _token;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
