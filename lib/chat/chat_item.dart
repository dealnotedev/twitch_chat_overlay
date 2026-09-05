sealed class ChatItem {
  const ChatItem({required this.id, required this.receivedAt});

  final String id;
  final DateTime receivedAt;
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
  });

  final String parentMessageId;
  final String parentUserName;
  final String parentMessageBody;
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
