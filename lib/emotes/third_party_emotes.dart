import 'package:dio/dio.dart';
import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';
import 'package:twitch_chat_overlay/emotes/emote_options.dart';

export 'package:twitch_chat_overlay/emotes/emote_options.dart';

/// Public requests use a separate client, without Twitch OAuth headers.
final class ThirdPartyEmotes {
  ThirdPartyEmotes({Dio? dio, DateTime Function()? now})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 5),
              receiveTimeout: const Duration(seconds: 8),
            ),
          ),
      _now = now ?? DateTime.now;

  final Dio _dio;
  final DateTime Function() _now;
  final Map<String, _CachedSet> _cache = {};
  final Map<String, Future<List<ChatEmote>>> _pending = {};

  Future<EmoteCatalog> load(
    String broadcasterId, {
    ThirdPartyEmoteOptions options = const ThirdPartyEmoteOptions(),
    bool refresh = false,
  }) async {
    final id = Uri.encodeComponent(broadcasterId);
    // Channel sets override globals, then 7TV wins within the same scope.
    final sets = await Future.wait([
      if (options.betterTtv)
        _loadSet(
          'https://api.betterttv.net/3/cached/emotes/global',
          (data) => _bttv(data, channel: false),
          refresh: refresh,
        ),
      if (options.sevenTv)
        _loadSet(
          'https://7tv.io/v3/emote-sets/global',
          (data) => _sevenTv(_map(data)['emotes'], channel: false),
          refresh: refresh,
        ),
      if (options.betterTtv)
        _loadSet(
          'https://api.betterttv.net/3/cached/users/twitch/$id',
          (data) {
            final user = _map(data);
            return [
              ..._bttv(user['sharedEmotes'], channel: true),
              ..._bttv(user['channelEmotes'], channel: true),
            ];
          },
          refresh: refresh,
          missingIsEmpty: true,
        ),
      if (options.sevenTv)
        _loadSet(
          'https://7tv.io/v3/users/twitch/$id',
          (data) {
            final user = _map(data);
            if (user.containsKey('emote_set') && user['emote_set'] == null) {
              return [];
            }
            return _sevenTv(_map(user['emote_set'])['emotes'], channel: true);
          },
          refresh: refresh,
          missingIsEmpty: true,
        ),
    ]);
    return EmoteCatalog(sets.expand((set) => set));
  }

  Future<List<ChatEmote>> _loadSet(
    String url,
    List<ChatEmote> Function(Object?) parse, {
    required bool refresh,
    bool missingIsEmpty = false,
  }) async {
    if (_pending[url] case final request?) return request;
    final cached = _cache[url];
    if (!refresh && cached != null && _now().isBefore(cached.expiresAt)) {
      return cached.emotes;
    }
    final request = _fetchSet(url, parse, missingIsEmpty: missingIsEmpty);
    _pending[url] = request;
    try {
      return await request;
    } finally {
      _pending.remove(url);
    }
  }

  Future<List<ChatEmote>> _fetchSet(
    String url,
    List<ChatEmote> Function(Object?) parse, {
    required bool missingIsEmpty,
  }) async {
    var ttl = const Duration(minutes: 30);
    List<ChatEmote> emotes;
    try {
      final response = await _dio
          .get<Object?>(url)
          .timeout(const Duration(seconds: 10));
      emotes = List.unmodifiable(parse(response.data));
    } catch (error) {
      if (missingIsEmpty &&
          error is DioException &&
          error.response?.statusCode == 404) {
        emotes = const [];
      } else {
        // Keep the last good set on timeouts, rate limits or malformed replies.
        emotes = _cache[url]?.emotes ?? const [];
        ttl = const Duration(seconds: 30);
      }
    }
    _cache[url] = _CachedSet(emotes, _now().add(ttl));
    // Bound metadata retained across channel changes. Images use the disk cache.
    if (_cache.length > 32) _cache.remove(_cache.keys.first);
    return emotes;
  }

  static List<ChatEmote> _bttv(Object? data, {required bool channel}) {
    if (data is! List) throw const FormatException('Invalid BTTV emote set');
    return [for (final entry in data) ?_bttvEmote(entry, channel)];
  }

  static ChatEmote? _bttvEmote(Object? entry, bool channel) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final name = entry['code'];
    if (!_validText(id) || !_validText(name)) return null;
    // Modifier composition is a separate feature; do not render overlays as standalone images.
    if (entry['modifier'] == true) return null;
    return ChatEmote(
      id: id as String,
      name: name as String,
      imageUrl: 'https://cdn.betterttv.net/emote/${Uri.encodeComponent(id)}/2x',
      provider: EmoteProvider.betterTtv,
      animated: entry['animated'] == true || entry['imageType'] == 'gif',
      channel: channel,
    );
  }

  static List<ChatEmote> _sevenTv(Object? data, {required bool channel}) {
    if (data is! List) throw const FormatException('Invalid 7TV emote set');
    return [for (final entry in data) ?_sevenTvEmote(entry, channel)];
  }

  static ChatEmote? _sevenTvEmote(Object? entry, bool channel) {
    if (entry is! Map) return null;
    final id = entry['id'];
    final name = entry['name']; // Set alias, which may differ from data.name.
    final data = entry['data'];
    if (!_validText(id) || !_validText(name) || data is! Map) return null;
    final flags = data['flags'];
    final activeFlags = entry['flags'];
    if ((flags is int && flags & 256 != 0) ||
        (activeFlags is int && activeFlags & 1 != 0)) {
      return null; // ZERO_WIDTH, including per-set overrides.
    }
    final host = data['host'];
    if (host is! Map || host['url'] is! String || host['files'] is! List) {
      return null;
    }
    var base = host['url'] as String;
    if (base.startsWith('//')) base = 'https:$base';
    final uri = Uri.tryParse(base);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      return null;
    }
    final files = (host['files'] as List)
        .whereType<Map>()
        .where(
          (file) =>
              file['name'] is String &&
              const ['WEBP', 'PNG', 'GIF'].contains(file['format']) &&
              file['width'] is num &&
              (file['width'] as num) > 0 &&
              file['height'] is num &&
              (file['height'] as num) > 0,
        )
        .toList();
    if (files.isEmpty) return null;
    int rank(Map file) =>
        (file['format'] == 'WEBP' ? 0 : 1000) +
        ((file['height'] as num) - 64).abs().toInt();
    files.sort((a, b) => rank(a).compareTo(rank(b)));
    final file = files.first;
    final filename = file['name'] as String;
    String url(String name) =>
        '${base.replaceFirst(RegExp(r'/+$'), '')}/${Uri.encodeComponent(name)}';
    return ChatEmote(
      id: id as String,
      name: name as String,
      imageUrl: url(filename),
      thumbnailUrl: file['static_name'] is String
          ? url(file['static_name'] as String)
          : null,
      provider: EmoteProvider.sevenTv,
      animated:
          data['animated'] == true ||
          (file['frame_count'] is num && (file['frame_count'] as num) > 1),
      aspectRatio: (file['width'] as num) / (file['height'] as num),
      channel: channel,
    );
  }

  static bool _validText(Object? value) =>
      value is String && value.isNotEmpty && !RegExp(r'\s').hasMatch(value);
  static Map _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid emote response');
    return value;
  }
}

final class _CachedSet {
  const _CachedSet(this.emotes, this.expiresAt);
  final List<ChatEmote> emotes;
  final DateTime expiresAt;
}
