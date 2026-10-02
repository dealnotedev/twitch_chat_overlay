import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';

final class EmoteCatalog {
  const EmoteCatalog.empty() : emotes = const [], _byName = const {};

  /// Entries are ordered from lowest to highest priority by the loader.
  factory EmoteCatalog(Iterable<ChatEmote> entries) {
    final names = <String, ChatEmote>{};
    for (final emote in entries) {
      names[emote.name] = emote;
    }
    return EmoteCatalog._(
      List.unmodifiable(names.values),
      Map.unmodifiable(names),
    );
  }

  const EmoteCatalog._(this.emotes, this._byName);

  final List<ChatEmote> emotes;
  final Map<String, ChatEmote> _byName;
  static final _tokens = RegExp(r'\S+');

  /// Only plain text is eligible; native emotes, mentions and URLs stay intact.
  /// Original fragments remain available for copying, replies and moderation.
  List<ChatFragment> resolve(List<ChatFragment> fragments) {
    if (_byName.isEmpty) return fragments;
    final result = <ChatFragment>[];
    for (final fragment in fragments) {
      if (fragment is! ChatTextFragment) {
        result.add(fragment);
        continue;
      }
      var cursor = 0;
      for (final token in _tokens.allMatches(fragment.text)) {
        final emote = _byName[token.group(0)];
        if (emote == null) continue;
        if (cursor < token.start) {
          result.add(
            ChatTextFragment(
              text: fragment.text.substring(cursor, token.start),
            ),
          );
        }
        result.add(ChatThirdPartyEmoteFragment(emote: emote));
        cursor = token.end;
      }
      if (cursor == 0) {
        result.add(fragment);
      } else if (cursor < fragment.text.length) {
        result.add(ChatTextFragment(text: fragment.text.substring(cursor)));
      }
    }
    return result;
  }
}
