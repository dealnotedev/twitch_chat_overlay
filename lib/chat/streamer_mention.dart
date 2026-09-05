import 'package:twitch_chat_overlay/chat/chat_item.dart';

/// Identifies direct mentions and replies to the channel's broadcaster.
final class StreamerMentionTarget {
  StreamerMentionTarget({required this.userId, String? login})
    : login = login == null || login.isEmpty ? null : login,
      textPattern = login == null || login.isEmpty
          ? null
          : RegExp(
              '(?<![\\p{L}\\p{N}_@/])@${RegExp.escape(login)}'
              '(?![\\p{L}\\p{N}_])',
              caseSensitive: false,
              unicode: true,
            );

  final String userId;
  final String? login;
  final RegExp? textPattern;

  bool matchesMention(ChatMentionFragment fragment) {
    final id = fragment.userId;
    if (id != null && id.isNotEmpty) return id == userId;
    return textPattern?.hasMatch(fragment.text) ?? false;
  }

  bool isAddressedBy(ChatUserMessage message) {
    if (message.userId == userId) return false;
    final reply = message.reply;
    if (reply != null) {
      final id = reply.parentUserId;
      if (id != null && id.isNotEmpty) {
        if (id == userId) return true;
      } else if (login != null &&
          (reply.parentUserLogin ?? reply.parentUserName).toLowerCase() ==
              login!.toLowerCase()) {
        return true;
      }
    }
    return message.fragments.any(
      (fragment) => switch (fragment) {
        ChatMentionFragment() => matchesMention(fragment),
        ChatTextFragment() => textPattern?.hasMatch(fragment.text) ?? false,
        _ => false,
      },
    );
  }
}
