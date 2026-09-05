import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';

final class ChatTimeline {
  // Maps retain insertion order and deduplicate without scanning history.
  final Map<String, ChatItem> _items = {};

  List<ChatItem> get items => List.unmodifiable(_items.values);

  bool apply(ChatMutation mutation) {
    switch (mutation) {
      case AddChatItem(:final item):
        if (_items.containsKey(item.id)) return false;
        _items[item.id] = item;
        return true;
      case DeleteChatMessage(:final messageId):
        return _items.remove(messageId) != null;
      case ClearUserMessages(:final userId):
        final before = _items.length;
        _items.removeWhere(
          (_, item) => switch (item) {
            ChatUserMessage() => item.userId == userId,
            ChatRewardRedemption() => item.userId == userId,
            ChatPowerUp() => item.userId == userId,
            _ => false,
          },
        );
        return before != _items.length;
      case ClearChat():
        if (_items.isEmpty) return false;
        _items.clear();
        return true;
    }
  }

  void clear() => _items.clear();
}
