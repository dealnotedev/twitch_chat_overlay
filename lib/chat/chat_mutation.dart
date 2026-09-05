import 'package:twitch_chat_overlay/chat/chat_item.dart';

sealed class ChatMutation {
  const ChatMutation();
}

final class AddChatItem extends ChatMutation {
  const AddChatItem(this.item);

  final ChatItem item;
}

final class DeleteChatMessage extends ChatMutation {
  const DeleteChatMessage(this.messageId);

  final String messageId;
}

final class ClearUserMessages extends ChatMutation {
  const ClearUserMessages(this.userId);

  final String userId;
}

final class ClearChat extends ChatMutation {
  const ClearChat();
}
