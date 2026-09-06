import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';

final class ChatTimeline {
  // Maps retain insertion order and deduplicate without scanning history.
  final Map<String, ChatItem> _items = {};

  List<ChatItem> get items => List.unmodifiable(_items.values);

  bool apply(ChatMutation mutation) {
    switch (mutation) {
      case AddChatItem(:final item):
        final existing = _items[item.id];
        if (existing != null && (!existing.isHistorical || item.isHistorical)) {
          return false;
        }
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

  /// Replay live events over history, including deletes of previously unseen IDs.
  /// The journal contains every live mutation since joining the channel.
  void restoreHistory(List<ChatItem> history, List<ChatMutation> liveJournal) {
    clear();
    for (final item in history) {
      apply(AddChatItem(item));
    }
    for (final mutation in liveJournal) {
      apply(mutation);
    }
    final positions = {
      for (final (index, id) in _items.keys.indexed) id: index,
    };
    final ordered = _items.values.toList()
      ..sort((a, b) {
        final time = a.receivedAt.compareTo(b.receivedAt);
        return time != 0 ? time : positions[a.id]!.compareTo(positions[b.id]!);
      });
    _items
      ..clear()
      ..addEntries(ordered.map((item) => MapEntry(item.id, item)));
  }
}
