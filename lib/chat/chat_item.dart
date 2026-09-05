sealed class ChatItem {
  const ChatItem({required this.id, required this.receivedAt});

  final String id;
  final DateTime receivedAt;
}

enum ChatPowerUpType { messageEffect, gigantifyEmote, celebration }

final class ChatPowerUp extends ChatItem {
  const ChatPowerUp({
    required super.id,
    required super.receivedAt,
    required this.userId,
    required this.userName,
    required this.type,
    required this.bits,
    this.emote,
  });

  final String userId;
  final String userName;
  final ChatPowerUpType type;
  final int bits;
  final ChatEmoteFragment? emote;
}

final class ChatRewardRedemption extends ChatItem {
  const ChatRewardRedemption({
    required super.id,
    required super.receivedAt,
    required this.userId,
    required this.userName,
    required this.rewardId,
    required this.rewardTitle,
    required this.cost,
    required this.userInput,
  });

  final String userId;
  final String userName;
  final String rewardId;
  final String rewardTitle;
  final int cost;
  final String userInput;
}

final class ChatRaid extends ChatItem {
  const ChatRaid({
    required super.id,
    required super.receivedAt,
    required this.userName,
    required this.viewerCount,
    this.profileImageUrl,
    this.sourceChannel,
  });

  final String userName;
  final int viewerCount;
  final String? profileImageUrl;
  final String? sourceChannel;
}

final class ChatUserMessage extends ChatItem {
  const ChatUserMessage({
    required super.id,
    required super.receivedAt,
    required this.userId,
    required this.userName,
    required this.color,
    required this.badges,
    required this.fragments,
    required this.messageType,
    required this.bits,
    required this.reply,
    required this.sourceChannel,
  });

  final String userId;
  final String userName;
  final String? color;
  final List<ChatBadge> badges;
  final List<ChatFragment> fragments;
  final String messageType;
  final int? bits;
  final ChatReply? reply;
  final String? sourceChannel;

  /// The recipient is already shown in the reply context above the body.
  /// Keep the original fragments for message data and only trim their display.
  List<ChatFragment> get displayFragments {
    final context = reply;
    if (context == null || fragments.isEmpty) return fragments;
    final first = fragments.first;
    if (first is! ChatTextFragment && first is! ChatMentionFragment) {
      return fragments;
    }
    final names = {
      context.parentUserName,
      if (context.parentUserLogin case final login? when login.isNotEmpty)
        login,
    }.map(RegExp.escape).join('|');
    final prefix = RegExp(
      '^@(?:$names)(?=\\s|\$)\\s*',
      caseSensitive: false,
    ).firstMatch(first.text);
    if (prefix == null) return fragments;

    final body = <ChatFragment>[];
    final remainder = first.text.substring(prefix.end);
    if (remainder.isNotEmpty) body.add(ChatTextFragment(text: remainder));
    var trimLeadingSpace = remainder.isEmpty;
    for (final fragment in fragments.skip(1)) {
      if (trimLeadingSpace && fragment is ChatTextFragment) {
        final text = fragment.text.trimLeft();
        if (text.isEmpty) continue;
        body.add(ChatTextFragment(text: text));
      } else {
        body.add(fragment);
      }
      trimLeadingSpace = false;
    }
    return body;
  }
}

final class ChatNotice extends ChatItem {
  const ChatNotice({
    required super.id,
    required super.receivedAt,
    required this.noticeType,
    required this.systemMessage,
    required this.userName,
    required this.color,
    required this.badges,
    required this.fragments,
  });

  final String noticeType;
  final String systemMessage;
  final String? userName;
  final String? color;
  final List<ChatBadge> badges;
  final List<ChatFragment> fragments;
}

final class ChatSubscriptionRevoked extends ChatItem {
  const ChatSubscriptionRevoked({
    required super.id,
    required super.receivedAt,
    required this.subscriptionType,
    required this.status,
  });

  final String subscriptionType;
  final String status;
}

final class ChatBadge {
  const ChatBadge({
    required this.setId,
    required this.id,
    required this.info,
    this.broadcasterId,
  });

  final String setId;
  final String id;
  final String info;
  final String? broadcasterId;
}

final class ChatReply {
  const ChatReply({
    required this.parentMessageId,
    required this.parentUserName,
    required this.parentMessageBody,
    this.parentUserLogin,
    this.parentUserId,
  });

  final String parentMessageId;
  final String parentUserName;
  final String parentMessageBody;
  final String? parentUserLogin;
  final String? parentUserId;
}

sealed class ChatFragment {
  const ChatFragment({required this.text});

  final String text;
}

final class ChatTextFragment extends ChatFragment {
  const ChatTextFragment({required super.text});
}

final class ChatMentionFragment extends ChatFragment {
  const ChatMentionFragment({
    required super.text,
    required this.userId,
    required this.userName,
  });

  final String? userId;
  final String? userName;
}

final class ChatEmoteFragment extends ChatFragment {
  const ChatEmoteFragment({
    required super.text,
    required this.id,
    required this.animated,
  });

  final String id;
  final bool animated;

  String get imageUrl => _imageUrl('2.0');
  String get giantImageUrl => _imageUrl('3.0');

  String _imageUrl(String scale) =>
      'https://static-cdn.jtvnw.net/emoticons/v2/$id/'
      '${animated ? 'animated' : 'static'}/dark/$scale';
}

final class ChatCheermoteFragment extends ChatFragment {
  const ChatCheermoteFragment({
    required super.text,
    required this.prefix,
    required this.bits,
    required this.tier,
  });

  final String prefix;
  final int bits;
  final int tier;
}

final class ChatGifFragment extends ChatFragment {
  const ChatGifFragment({
    required super.text,
    required this.id,
    required this.url,
  });

  final String id;
  final String url;
}

final class ChatUnknownFragment extends ChatFragment {
  const ChatUnknownFragment({required super.text, required this.type});

  final String type;
}
