import 'package:dio/dio.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';

/// Public history only. This client never receives Twitch OAuth credentials.
final class TwitchRecentMessages {
  TwitchRecentMessages({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: 'https://recent-messages.robotty.de/api/v2',
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              headers: {'User-Agent': 'TwitchChatOverlay/1.0'},
            ),
          );

  final Dio _dio;

  Future<List<ChatItem>> load(String channelLogin) async {
    final login = channelLogin.toLowerCase();
    if (!RegExp(r'^[a-z0-9_]{1,25}$').hasMatch(login)) {
      throw const FormatException('Invalid channel login');
    }
    final response = await _dio
        .get<Object?>('/recent-messages/$login')
        .timeout(const Duration(seconds: 15));
    final data = response.data;
    if (data is! Map || data['messages'] is! List) {
      throw const FormatException('Invalid history response');
    }
    // An informational channel_not_joined error may accompany usable history.
    final timeline = ChatTimeline();
    for (final raw in data['messages'] as List) {
      if (raw is! String) continue;
      final mutation = parseRecentMessage(raw, channelLogin: login);
      if (mutation != null) timeline.apply(mutation);
    }
    return timeline.items;
  }
}

/// IRC parameters can use either a trailing colon or a single plain word.
ChatMutation? parseRecentMessage(String raw, {required String channelLogin}) {
  if (!raw.startsWith('@')) return null;
  final tagsEnd = raw.indexOf(' ');
  if (tagsEnd < 0) return null;
  final tags = <String, String>{};
  for (final tag in raw.substring(1, tagsEnd).split(';')) {
    final separator = tag.indexOf('=');
    if (separator <= 0) continue;
    final value = _unescape(tag.substring(separator + 1));
    if (value.isNotEmpty) tags[tag.substring(0, separator)] = value;
  }
  if (tags['rm-deleted'] == '1') return null;
  var rest = raw.substring(tagsEnd + 1).trimLeft();
  String? login;
  if (rest.startsWith(':')) {
    final prefixEnd = rest.indexOf(' ');
    if (prefixEnd < 0) return null;
    login = rest.substring(1, prefixEnd).split('!').first;
    rest = rest.substring(prefixEnd + 1).trimLeft();
  }
  final parameters = <String>[];
  while (rest.isNotEmpty) {
    if (rest.startsWith(':')) {
      parameters.add(rest.substring(1));
      break;
    }
    final end = rest.indexOf(' ');
    if (end < 0) {
      parameters.add(rest);
      break;
    }
    parameters.add(rest.substring(0, end));
    rest = rest.substring(end + 1).trimLeft();
  }
  if (parameters.length < 2 ||
      parameters[1].toLowerCase() != '#${channelLogin.toLowerCase()}') {
    return null;
  }
  final command = parameters[0];
  if (command == 'CLEARMSG') {
    final id = tags['target-msg-id'];
    return id == null ? null : DeleteChatMessage(id);
  }
  if (command == 'CLEARCHAT') {
    final userId = tags['target-user-id'];
    return userId != null
        ? ClearUserMessages(userId)
        : parameters.length == 2
        ? const ClearChat()
        : null;
  }
  if (command != 'PRIVMSG' && command != 'USERNOTICE') return null;
  final id = tags['id'];
  final timestamp =
      int.tryParse(tags['tmi-sent-ts'] ?? '') ??
      int.tryParse(tags['rm-received-ts'] ?? '');
  // Never invent a fresh timestamp for a historical message.
  if (id == null ||
      timestamp == null ||
      timestamp <= 0 ||
      timestamp > 8640000000000000) {
    return null;
  }
  final receivedAt = DateTime.fromMillisecondsSinceEpoch(
    timestamp,
    isUtc: true,
  );
  final body = parameters.length > 2 ? parameters[2] : '';
  final badgeInfo = _pairs(tags['badge-info']);
  final sourceRoom = tags['source-room-id'];
  final badges = _pairs(tags['source-badges'] ?? tags['badges']).entries
      .map(
        (badge) => ChatBadge(
          setId: badge.key,
          id: badge.value,
          info: badgeInfo[badge.key] ?? '',
          broadcasterId: sourceRoom ?? tags['room-id'],
        ),
      )
      .toList();
  final fragments = _fragments(body, tags['emotes']);
  final name = tags['display-name'] ?? tags['login'] ?? login;
  if (command == 'USERNOTICE') {
    return AddChatItem(
      ChatNotice(
        id: id,
        receivedAt: receivedAt,
        isHistorical: true,
        noticeType: tags['msg-id'] ?? 'notice',
        systemMessage: tags['system-msg'] ?? '',
        userName: name,
        color: tags['color'],
        badges: badges,
        fragments: fragments,
      ),
    );
  }
  final userId = tags['user-id'];
  if (userId == null || name == null || parameters.length < 3) return null;
  final parentId = tags['reply-parent-msg-id'];
  final parentName =
      tags['reply-parent-display-name'] ?? tags['reply-parent-user-login'];
  return AddChatItem(
    ChatUserMessage(
      id: id,
      receivedAt: receivedAt,
      isHistorical: true,
      userId: userId,
      userName: name,
      color: tags['color'],
      badges: badges,
      fragments: fragments,
      messageType: switch (tags['msg-id']) {
        'highlighted-message' => 'channel_points_highlighted',
        'gigantified-emote-message' => 'power_ups_gigantified_emote',
        'animated-message' => 'power_ups_message_effect',
        _ => 'text',
      },
      bits: int.tryParse(tags['bits'] ?? ''),
      reply: parentId != null && parentName != null
          ? ChatReply(
              parentMessageId: parentId,
              parentUserName: parentName,
              parentMessageBody: tags['reply-parent-msg-body'] ?? '',
              parentUserId: tags['reply-parent-user-id'],
              parentUserLogin: tags['reply-parent-user-login'],
            )
          : null,
      sourceChannel: tags['source-room-name'],
    ),
  );
}

String _unescape(String value) {
  final result = StringBuffer();
  for (var i = 0; i < value.length; i++) {
    if (value[i] != r'\') {
      result.write(value[i]);
    } else if (++i < value.length) {
      result.write(switch (value[i]) {
        ':' => ';',
        's' => ' ',
        'r' => '\r',
        'n' => '\n',
        final character => character,
      });
    }
  }
  return result.toString();
}

Map<String, String> _pairs(String? value) => {
  for (final pair in (value ?? '').split(','))
    if (pair.indexOf('/') > 0)
      pair.substring(0, pair.indexOf('/')): pair.substring(
        pair.indexOf('/') + 1,
      ),
};

List<ChatFragment> _fragments(String body, String? emotes) {
  // Twitch IRC emote offsets count Unicode code points, not UTF-16 units.
  final characters = body.runes.toList();
  final spans = <({int start, int end, String id})>[];
  for (final emote in (emotes ?? '').split('/')) {
    final colon = emote.indexOf(':');
    if (colon <= 0) continue;
    final id = emote.substring(0, colon);
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) continue;
    for (final range in emote.substring(colon + 1).split(',')) {
      final bounds = range.split('-');
      if (bounds.length != 2) continue;
      final start = int.tryParse(bounds[0]);
      final end = int.tryParse(bounds[1]);
      if (start != null &&
          end != null &&
          start >= 0 &&
          end >= start &&
          end < characters.length) {
        spans.add((start: start, end: end + 1, id: id));
      }
    }
  }
  spans.sort((a, b) => a.start.compareTo(b.start));
  final result = <ChatFragment>[];
  var cursor = 0;
  String text(int start, int end) =>
      String.fromCharCodes(characters.sublist(start, end));
  for (final span in spans) {
    if (span.start < cursor) continue;
    if (span.start > cursor) {
      result.add(ChatTextFragment(text: text(cursor, span.start)));
    }
    result.add(
      ChatEmoteFragment(
        text: text(span.start, span.end),
        id: span.id,
        animated: false,
      ),
    );
    cursor = span.end;
  }
  if (cursor < characters.length) {
    result.add(ChatTextFragment(text: text(cursor, characters.length)));
  }
  return result;
}
