/// Artwork comes from Helix; redemption titles and costs come from the event
/// so historical cards keep the price paid even if the reward changes later.
final class TwitchRewardAppearance {
  const TwitchRewardAppearance({this.imageUrl, this.backgroundColor});

  final String? imageUrl;
  final String? backgroundColor;

  static Map<String, TwitchRewardAppearance> parse(Object? data) {
    final rewards = <String, TwitchRewardAppearance>{};
    if (data is! List) return rewards;
    for (final reward in data.whereType<Map>()) {
      final id = reward['id'];
      if (id is! String || id.isEmpty) continue;
      final image = reward['image'];
      final fallback = reward['default_image'];
      String? imageUrl(Object? value) => value is Map
          ? (value['url_2x'] ?? value['url_1x'] ?? value['url_4x']) as String?
          : null;
      rewards[id] = TwitchRewardAppearance(
        imageUrl: imageUrl(image) ?? imageUrl(fallback),
        backgroundColor: reward['background_color'] as String?,
      );
    }
    return Map.unmodifiable(rewards);
  }
}
