enum EmoteProvider {
  twitch('Twitch'),
  sevenTv('7TV'),
  betterTtv('BetterTTV');

  const EmoteProvider(this.label);
  final String label;
}

/// Provider-independent catalog entry. Twitch permissions remain in Helix.
class ChatEmote {
  const ChatEmote({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.provider,
    this.thumbnailUrl,
    this.animated = false,
    this.aspectRatio,
    this.channel = false,
    this.ownerId = '',
    this.ownerName = '',
  });

  final String id;
  final String name;
  final String imageUrl;
  final String? thumbnailUrl;
  final EmoteProvider provider;
  final bool animated;
  final double? aspectRatio;
  final bool channel;
  final String ownerId;
  final String ownerName;

  // A 7TV emote can occur under several aliases in the same set.
  String get key => '${provider.name}:$id:$name';
}
