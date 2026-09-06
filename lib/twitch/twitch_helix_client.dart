import 'package:dio/dio.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_emotes.dart';
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

  /// A null count means the channel is offline, not a failed request.
  Future<int?> getViewerCount({required String broadcasterId}) async {
    final response = await _request(
      '/streams',
      queryParameters: {'user_id': broadcasterId},
    ).timeout(const Duration(seconds: 20));
    final data = response.data?['data'];
    if (data is! List) throw const FormatException('Invalid stream response');
    if (data.isEmpty) return null;
    final stream = data.first;
    final count = stream is Map ? stream['viewer_count'] : null;
    if (count is! int || count < 0) {
      throw const FormatException('Invalid viewer count');
    }
    return count;
  }

  Future<String> getChannelLogin({required String broadcasterId}) async {
    final response = await _request(
      '/users',
      queryParameters: {'id': broadcasterId},
    );
    final data = response.data?['data'];
    if (data is List) {
      for (final user in data) {
        if (user is Map &&
            user['id'] == broadcasterId &&
            user['login'] is String) {
          return user['login'] as String;
        }
      }
    }
    throw const FormatException('Channel login unavailable');
  }

  // Only metadata is cached here; its lifetime is the client/app session.
  (String, String)? _emoteContext;
  List<TwitchEmote>? _emoteCache;
  Future<List<TwitchEmote>>? _emoteLoad;

  static const rewardSubscriptionType =
      'channel.channel_points_custom_reward_redemption.add';

  static const bitsSubscriptionType = 'channel.bits.use';

  Future<void> createBitsSubscription({
    required String sessionId,
    required String broadcasterId,
  }) async {
    await _post(
      '/eventsub/subscriptions',
      data: {
        'type': bitsSubscriptionType,
        'version': '1',
        'condition': {'broadcaster_user_id': broadcasterId},
        'transport': {'method': 'websocket', 'session_id': sessionId},
      },
    );
  }

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

  /// Includes only emotes Twitch grants to the authenticated sender.
  Future<List<TwitchEmote>> getUserEmotes({
    required String broadcasterId,
    bool refresh = false,
  }) async {
    final token = await _auth.validToken();
    final context = (token.userId, broadcasterId);
    if (_emoteContext != context) {
      _emoteContext = context;
      _emoteCache = null;
      _emoteLoad = null;
    }
    if (_emoteLoad case final pending?) return pending;
    if (!refresh && _emoteCache != null) return _emoteCache!;

    final request = _fetchUserEmotes(token.userId, broadcasterId);
    _emoteLoad = request;
    try {
      final emotes = await request;
      if (identical(_emoteLoad, request)) _emoteCache = emotes;
      return emotes;
    } finally {
      if (identical(_emoteLoad, request)) _emoteLoad = null;
    }
  }

  Future<List<TwitchEmote>> _fetchUserEmotes(
    String userId,
    String broadcasterId,
  ) async {
    final emotes = <String, TwitchEmote>{};
    final seenCursors = <String>{};
    String? cursor;
    do {
      final response = await _request(
        '/chat/emotes/user',
        emoteUserId: userId,
        queryParameters: {
          'user_id': userId,
          'broadcaster_id': broadcasterId,
          'after': ?cursor,
        },
      );
      final data = response.data?['data'];
      final template = response.data?['template'];
      if (data is! List || template is! String) {
        throw const FormatException('Invalid user emote response');
      }
      for (final entry in data) {
        final emote = TwitchEmote.parse(entry, template);
        if (emote != null) emotes[emote.id] = emote;
      }
      final pagination = response.data?['pagination'];
      cursor = pagination is Map ? pagination['cursor'] as String? : null;
      if (cursor == '') cursor = null;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw StateError('Repeated user emote pagination cursor');
      }
    } while (cursor != null);
    final ownerIds = emotes.values
        .map((e) => e.ownerId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final owners = <String, String>{};
    // Get Users accepts at most 100 IDs, using repeated id query parameters.
    for (var start = 0; start < ownerIds.length; start += 100) {
      final response = await _request(
        '/users',
        emoteUserId: userId,
        queryParameters: {'id': ownerIds.skip(start).take(100).toList()},
      );
      final data = response.data?['data'];
      if (data is! List) throw const FormatException('Invalid emote owners');
      for (final owner in data) {
        if (owner is! Map) continue;
        final id = owner['id'];
        final displayName = owner['display_name'];
        final login = owner['login'];
        if (id is! String) continue;
        if (displayName is String && displayName.isNotEmpty) {
          owners[id] = displayName;
        } else if (login is String && login.isNotEmpty) {
          owners[id] = login;
        }
      }
    }
    final result =
        emotes.values
            .map((e) => e.withOwnerName(owners[e.ownerId] ?? ''))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    return List.unmodifiable(result);
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
    final response = await _request(
      '/chat/messages',
      method: 'POST',
      actorUserId: senderId,
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

  Future<void> deleteMessage({
    required String broadcasterId,
    required String moderatorId,
    required String messageId,
  }) async {
    // Omitting message_id clears the entire room: this API only deletes one.
    if (messageId.trim().isEmpty ||
        broadcasterId.trim().isEmpty ||
        moderatorId.trim().isEmpty) {
      throw ArgumentError('A channel, moderator and message ID are required');
    }
    try {
      await _request(
        '/moderation/chat',
        method: 'DELETE',
        actorUserId: moderatorId,
        queryParameters: {
          'broadcaster_id': broadcasterId,
          'moderator_id': moderatorId,
          'message_id': messageId,
        },
      );
    } on DioException catch (error) {
      final failure = switch (error.response?.statusCode) {
        400 || 403 => TwitchChatActionFailure.forbidden,
        404 => TwitchChatActionFailure.messageUnavailable,
        _ => null,
      };
      if (failure != null) throw TwitchChatActionException(failure);
      rethrow;
    }
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
    String? emoteUserId,
    String? actorUserId,
  }) async {
    var token = await _auth.validToken();
    for (var attempt = 0; ; attempt++) {
      if (actorUserId != null && token.userId != actorUserId) {
        throw const TwitchChatActionException(
          TwitchChatActionFailure.sessionChanged,
        );
      }
      if (emoteUserId != null) {
        if (token.userId != emoteUserId) {
          throw StateError('Sender changed while loading emotes');
        }
      }
      try {
        return await _dio.request<Map<String, Object?>>(
          path,
          data: data,
          queryParameters: queryParameters,
          options: Options(
            method: method,
            listFormat: ListFormat.multi,
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
