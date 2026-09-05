import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';

final class ChatTimeline {
  ChatTimeline({this.maximumItems = 500});

  final int maximumItems;
  final List<ChatItem> _items = [];

  List<ChatItem> get items => List.unmodifiable(_items);

  bool apply(ChatMutation mutation) {
    switch (mutation) {
      case AddChatItem(:final item):
        if (_items.any((existing) => existing.id == item.id)) return false;
        _items.add(item);
        final overflow = _items.length - maximumItems;
        if (overflow > 0) _items.removeRange(0, overflow);
        return true;
      case DeleteChatMessage(:final messageId):
        final before = _items.length;
        _items.removeWhere((item) => item.id == messageId);
        return before != _items.length;
      case ClearUserMessages(:final userId):
        final before = _items.length;
        _items.removeWhere(
          (item) => switch (item) {
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
