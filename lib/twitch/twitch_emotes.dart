final class TwitchEmote {
  const TwitchEmote({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.ownerId = '',
    this.ownerName = '',
    this.type = 'none',
  });

  final String id;
  final String name;
  final String imageUrl;
  final String ownerId;
  final String ownerName;
  final String type;

  TwitchEmote withOwnerName(String name) => TwitchEmote(
    id: id,
    name: this.name,
    imageUrl: imageUrl,
    ownerId: ownerId,
    ownerName: name,
    type: type,
  );

  static TwitchEmote? parse(Object? value, String template) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      return null;
    }
    String? choose(Object? values, List<String> preferences) {
      if (values is! List) return null;
      for (final preference in preferences) {
        if (values.contains(preference)) return preference;
      }
      return null;
    }

    // Static thumbnails keep the picker calm; animated-only emotes still work.
    final format = choose(value['format'], ['static', 'animated']);
    final theme = choose(value['theme_mode'], ['dark', 'light']);
    final scale = choose(value['scale'], ['2.0', '1.0', '3.0']);
    if (format == null || theme == null || scale == null) return null;
    final url = template
        .replaceAll('{{id}}', Uri.encodeComponent(id))
        .replaceAll('{{format}}', format)
        .replaceAll('{{theme_mode}}', theme)
        .replaceAll('{{scale}}', scale);
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        url.contains('{{')) {
      return null;
    }
    final ownerId = value['owner_id'];
    final type = value['emote_type'];
    return TwitchEmote(
      id: id,
      name: name,
      imageUrl: url,
      ownerId: ownerId is String && ownerId != '0' ? ownerId : '',
      type: type is String ? type : 'none',
    );
  }
}
