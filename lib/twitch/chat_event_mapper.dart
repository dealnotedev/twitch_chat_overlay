import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';

final class TwitchChatEventMapper {
  const TwitchChatEventMapper();

  ChatMutation? map(Map<String, Object?> envelope) {
    final metadata = _map(envelope['metadata']);
    final payload = _map(envelope['payload']);
    final event = _map(payload['event']);
    final subscriptionType =
        metadata['subscription_type'] as String? ??
        (_map(payload['subscription'])['type'] as String?);
    final receivedAt =
        DateTime.tryParse(metadata['message_timestamp'] as String? ?? '') ??
        DateTime.now().toUtc();

    switch (subscriptionType) {
      case 'channel.chat.message':
        return _message(event, receivedAt);
      case 'channel.bits.use':
        return _powerUp(event, receivedAt, metadata);
      case 'channel.chat.notification':
        return _notice(event, receivedAt);
      case 'channel.channel_points_custom_reward_redemption.add':
        return _rewardRedemption(event, receivedAt);
      case 'channel.chat.message_delete':
        final id = _requiredString(event, 'message_id');
        return id == null ? null : DeleteChatMessage(id);
      case 'channel.chat.clear_user_messages':
        final id = _requiredString(event, 'target_user_id');
        return id == null ? null : ClearUserMessages(id);
      case 'channel.chat.clear':
        return const ClearChat();
      default:
        return null;
    }
  }

  AddChatItem? _message(Map<String, Object?> event, DateTime receivedAt) {
    final id = _requiredString(event, 'message_id');
    final userId = _requiredString(event, 'chatter_user_id');
    final userName = _requiredString(event, 'chatter_user_name');
    if (id == null || userId == null || userName == null) return null;

    final replyJson = _map(event['reply']);
    final parentId = replyJson['parent_message_id'] as String?;
    final parentName = replyJson['parent_user_name'] as String?;
    final parentBody = replyJson['parent_message_body'] as String?;

    return AddChatItem(
      ChatUserMessage(
        id: id,
        receivedAt: receivedAt,
        userId: userId,
        userName: userName,
        color: event['color'] as String?,
        badges: _eventBadges(event),
        fragments: _fragments(_map(event['message'])['fragments']),
        messageType: event['message_type'] as String? ?? 'text',
        bits: _map(event['cheer'])['bits'] as int?,
        reply: parentId != null && parentName != null && parentBody != null
            ? ChatReply(
                parentMessageId: parentId,
                parentUserName: parentName,
                parentUserLogin: replyJson['parent_user_login'] as String?,
                parentMessageBody: parentBody,
              )
            : null,
        sourceChannel: event['source_broadcaster_user_name'] as String?,
      ),
    );
  }

  AddChatItem? _powerUp(
    Map<String, Object?> event,
    DateTime receivedAt,
    Map<String, Object?> metadata,
  ) {
    // Cheers already arrive as chat messages. Only confirmed Power-up payments
    // belong here; free broadcaster uses do not generate channel.bits.use.
    if (event['type'] != 'power_up') return null;
    final id = _requiredString(metadata, 'message_id');
    final userId = _requiredString(event, 'user_id');
    final userName = _requiredString(event, 'user_name');
    final bits = event['bits'];
    final powerUp = _map(event['power_up']);
    final type = switch (powerUp['type']) {
      'message_effect' => ChatPowerUpType.messageEffect,
      'gigantify_an_emote' => ChatPowerUpType.gigantifyEmote,
      'celebration' => ChatPowerUpType.celebration,
      _ => null,
    };
    if (id == null ||
        userId == null ||
        userName == null ||
        bits is! int ||
        bits <= 0 ||
        type == null) {
      return null;
    }
    final emote = _map(powerUp['emote']);
    final emoteId = _requiredString(emote, 'id');
    return AddChatItem(
      ChatPowerUp(
        id: 'bits:$id',
        receivedAt: receivedAt,
        userId: userId,
        userName: userName,
        type: type,
        bits: bits,
        emote: emoteId == null
            ? null
            : ChatEmoteFragment(
                text: emote['name'] as String? ?? '',
                id: emoteId,
                animated: false,
              ),
      ),
    );
  }

  AddChatItem? _notice(Map<String, Object?> event, DateTime receivedAt) {
    final id = _requiredString(event, 'message_id');
    if (id == null) return null;
    final type = event['notice_type'] as String? ?? 'unknown';
    if (type == 'raid' || type == 'shared_chat_raid') {
      final raid = _map(event[type]);
      final userName = _requiredString(raid, 'user_name');
      final viewers = raid['viewer_count'];
      if (userName != null && viewers is int && viewers >= 0) {
        return AddChatItem(
          ChatRaid(
            id: id,
            receivedAt: receivedAt,
            userName: userName,
            viewerCount: viewers,
            profileImageUrl: _requiredString(raid, 'profile_image_url'),
            sourceChannel: _requiredString(
              event,
              'source_broadcaster_user_name',
            ),
          ),
        );
      }
    }
    final systemMessage = event['system_message'] as String?;
    if (systemMessage == null) return null;

    return AddChatItem(
      ChatNotice(
        id: id,
        receivedAt: receivedAt,
        noticeType: type,
        systemMessage: systemMessage,
        userName: event['chatter_user_name'] as String?,
        color: event['color'] as String?,
        badges: _eventBadges(event),
        fragments: _fragments(_map(event['message'])['fragments']),
      ),
    );
  }

  AddChatItem? _rewardRedemption(
    Map<String, Object?> event,
    DateTime receivedAt,
  ) {
    final id = _requiredString(event, 'id');
    final userId = _requiredString(event, 'user_id');
    final userName = _requiredString(event, 'user_name');
    final reward = _map(event['reward']);
    final rewardId = _requiredString(reward, 'id');
    final title = _requiredString(reward, 'title');
    final cost = reward['cost'];
    if (id == null ||
        userId == null ||
        userName == null ||
        rewardId == null ||
        title == null ||
        cost is! int ||
        cost < 0) {
      return null;
    }
    return AddChatItem(
      ChatRewardRedemption(
        id: 'redemption:$id',
        receivedAt:
            DateTime.tryParse(event['redeemed_at'] as String? ?? '') ??
            receivedAt,
        userId: userId,
        userName: userName,
        rewardId: rewardId,
        rewardTitle: title,
        cost: cost,
        userInput: event['user_input'] as String? ?? '',
      ),
    );
  }

  List<ChatBadge> _eventBadges(Map<String, Object?> event) {
    final sourceId = _requiredString(event, 'source_broadcaster_user_id');
    final useSource = sourceId != null && event['source_badges'] is List;
    return _badges(
      useSource ? event['source_badges'] : event['badges'],
      useSource ? sourceId : event['broadcaster_user_id'] as String?,
    );
  }

  List<ChatBadge> _badges(Object? value, String? broadcasterId) {
    return _list(value)
        .map(_map)
        .map(
          (badge) => ChatBadge(
            setId: badge['set_id'] as String? ?? 'unknown',
            id: badge['id'] as String? ?? '',
            info: badge['info'] as String? ?? '',
            broadcasterId: broadcasterId,
          ),
        )
        .toList(growable: false);
  }

  List<ChatFragment> _fragments(Object? value) {
    return _list(value)
        .map(_map)
        .map((fragment) {
          final type = fragment['type'] as String? ?? 'unknown';
          final text = fragment['text'] as String? ?? '';
          return switch (type) {
            'text' => ChatTextFragment(text: text),
            'mention' => ChatMentionFragment(
              text: text,
              userId: _map(fragment['mention'])['user_id'] as String?,
              userName: _map(fragment['mention'])['user_name'] as String?,
            ),
            'emote' => _emote(fragment, text),
            'cheermote' => _cheermote(fragment, text),
            'gif' => _gif(fragment, text),
            _ => ChatUnknownFragment(text: text, type: type),
          };
        })
        .toList(growable: false);
  }

  ChatFragment _emote(Map<String, Object?> fragment, String text) {
    final emote = _map(fragment['emote']);
    final id = emote['id'] as String?;
    if (id == null) return ChatUnknownFragment(text: text, type: 'emote');
    final formats = _list(emote['format']).whereType<String>();
    return ChatEmoteFragment(
      text: text,
      id: id,
      animated: formats.contains('animated'),
    );
  }

  ChatFragment _cheermote(Map<String, Object?> fragment, String text) {
    final cheer = _map(fragment['cheermote']);
    return ChatCheermoteFragment(
      text: text,
      prefix: cheer['prefix'] as String? ?? '',
      bits: cheer['bits'] as int? ?? 0,
      tier: cheer['tier'] as int? ?? 0,
    );
  }

  ChatFragment _gif(Map<String, Object?> fragment, String text) {
    final gif = _map(fragment['gif']);
    // Twitch's July 2026 changelog uses gif_id; the reference also lists id.
    final id = _requiredString(gif, 'gif_id') ?? _requiredString(gif, 'id');
    final url = _requiredString(gif, 'url');
    final uri = url == null ? null : Uri.tryParse(url);
    if (id == null ||
        uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty) {
      return ChatUnknownFragment(text: text, type: 'gif');
    }
    // Keep the original URL, including all query parameters, as Twitch requires.
    return ChatGifFragment(text: text, id: id, url: url!);
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    return const {};
  }

  static List<Object?> _list(Object? value) {
    return value is List ? value.cast<Object?>() : const [];
  }

  static String? _requiredString(Map<String, Object?> map, String key) {
    final value = map[key];
    return value is String && value.isNotEmpty ? value : null;
  }
}
