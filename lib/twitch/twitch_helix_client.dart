import 'package:dio/dio.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_rewards.dart';

final class SendChatResult {
  const SendChatResult({
    required this.sent,
    required this.messageId,
    required this.dropReason,
  });

  final bool sent;
  final String? messageId;
  final String? dropReason;
}

final class TwitchHelixClient {
  TwitchHelixClient(this._auth, {Dio? dio})
    : _dio = dio ?? Dio(BaseOptions(baseUrl: 'https://api.twitch.tv/helix'));

  static const List<String> chatSubscriptionTypes = [
    'channel.chat.message',
    'channel.chat.notification',
    'channel.chat.message_delete',
    'channel.chat.clear_user_messages',
    'channel.chat.clear',
  ];

  final TwitchAuth _auth;
  final Dio _dio;

  static const rewardSubscriptionType =
      'channel.channel_points_custom_reward_redemption.add';

  Future<void> createRewardSubscription({
    required String sessionId,
    required String broadcasterId,
  }) async {
    await _post(
      '/eventsub/subscriptions',
      data: {
        'type': rewardSubscriptionType,
        'version': '1',
        'condition': {'broadcaster_user_id': broadcasterId},
        'transport': {'method': 'websocket', 'session_id': sessionId},
      },
    );
  }

  Future<Map<String, TwitchRewardAppearance>> getRewards({
    required String broadcasterId,
  }) async {
    final response = await _request(
      '/channel_points/custom_rewards',
      queryParameters: {
        'broadcaster_id': broadcasterId,
        'only_manageable_rewards': false,
      },
    );
    return TwitchRewardAppearance.parse(response.data?['data']);
  }

  /// Both endpoints accept our existing user token without additional scopes.
  Future<TwitchBadgeSet> getBadges({String? broadcasterId}) async {
    final response = await _request(
      broadcasterId == null ? '/chat/badges/global' : '/chat/badges',
      queryParameters: broadcasterId == null
          ? null
          : {'broadcaster_id': broadcasterId},
    );
    return TwitchBadges.parse(response.data?['data']);
  }

  Future<void> createChatSubscriptions({
    required String sessionId,
    required String broadcasterId,
    required String userId,
  }) async {
    await Future.wait(
      chatSubscriptionTypes.map(
        (type) => _post(
          '/eventsub/subscriptions',
          data: {
            'type': type,
            'version': '1',
            'condition': {
              'broadcaster_user_id': broadcasterId,
              'user_id': userId,
            },
            'transport': {'method': 'websocket', 'session_id': sessionId},
          },
        ),
      ),
    );
  }

  Future<SendChatResult> sendMessage({
    required String broadcasterId,
    required String senderId,
    required String message,
    String? replyParentMessageId,
  }) async {
    final response = await _post(
      '/chat/messages',
      data: {
        'broadcaster_id': broadcasterId,
        'sender_id': senderId,
        'message': message,
        'reply_parent_message_id': ?replyParentMessageId,
      },
    );
    final entries = response.data?['data'];
    final first = entries is List && entries.isNotEmpty
        ? (entries.first as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final reason = first['drop_reason'];
    return SendChatResult(
      sent: first['is_sent'] as bool? ?? false,
      messageId: first['message_id'] as String?,
      dropReason: reason is Map ? reason['message'] as String? : null,
    );
  }

  Future<Response<Map<String, Object?>>> _post(
    String path, {
    required Map<String, Object?> data,
  }) => _request(path, method: 'POST', data: data);

  Future<Response<Map<String, Object?>>> _request(
    String path, {
    String method = 'GET',
    Map<String, Object?>? data,
    Map<String, Object?>? queryParameters,
  }) async {
    var token = await _auth.validToken();
    for (var attempt = 0; ; attempt++) {
      try {
        return await _dio.request<Map<String, Object?>>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: Options(
            method: method,
            headers: {
              'Authorization': 'Bearer ${token.accessToken}',
              'Client-Id': token.clientId,
            },
          ),
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 401 || attempt != 0) rethrow;
        // Refresh once and replay only the rejected request. Concurrent/late
        // 401s for the same token share the already refreshed credentials.
        token = await _auth.validToken(rejectedAccessToken: token.accessToken);
      }
    }
  }
}
