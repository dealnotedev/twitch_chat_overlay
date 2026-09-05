import 'package:twitch_chat_overlay/chat/chat_item.dart';

/// Twitch identifies a badge by both its set and its version (not badge-info).
final class TwitchBadgeImage {
  const TwitchBadgeImage({required this.url, required this.title});

  final String url;
  final String title;
}

typedef TwitchBadgeSet = Map<String, Map<String, TwitchBadgeImage>>;

final class TwitchBadges {
  const TwitchBadges([this.channels = const {}]);

  /// The empty channel ID holds global badges; channel versions override them.
  final Map<String, TwitchBadgeSet> channels;

  TwitchBadgeImage? resolve(ChatBadge badge) =>
      channels[badge.broadcasterId]?[badge.setId]?[badge.id] ??
      channels['']?[badge.setId]?[badge.id];

  static TwitchBadgeSet parse(Object? data) {
    final result = <String, Map<String, TwitchBadgeImage>>{};
    if (data is! List) return result;
    for (final set in data.whereType<Map>()) {
      final setId = set['set_id'];
      final versions = set['versions'];
      if (setId is! String || versions is! List) continue;
      final images = <String, TwitchBadgeImage>{};
      for (final version in versions.whereType<Map>()) {
        final id = version['id'];
        final url = version['image_url_2x'] ?? version['image_url_1x'];
        if (id is! String || url is! String || url.isEmpty) continue;
        images[id] = TwitchBadgeImage(
          url: url,
          title: version['title'] as String? ?? setId,
        );
      }
      result[setId] = Map.unmodifiable(images);
    }
    return Map.unmodifiable(result);
  }
}
