import 'package:twitch_chat_overlay/chat/chat_item.dart';

enum TwitchChatActionFailure { forbidden, messageUnavailable, sessionChanged }

final class TwitchChatActionException implements Exception {
  const TwitchChatActionException(this.failure);
  final TwitchChatActionFailure failure;
}

/// Helix cannot delete broadcaster/other moderator messages or messages older
/// than six hours. Shared Chat badges belong to their source channel.
bool canDeleteTwitchMessage(
  ChatUserMessage message,
  String broadcasterId, {
  DateTime? now,
}) {
  if (message.id.trim().isEmpty || message.userId == broadcasterId) {
    return false;
  }
  if ((now ?? DateTime.now().toUtc()).difference(message.receivedAt) >=
      const Duration(hours: 6)) {
    return false;
  }
  return !message.badges.any(
    (badge) =>
        (badge.broadcasterId == null || badge.broadcasterId == broadcasterId) &&
        (badge.setId == 'broadcaster' || badge.setId == 'moderator'),
  );
}
