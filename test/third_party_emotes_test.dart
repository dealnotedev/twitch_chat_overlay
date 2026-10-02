import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';
import 'package:twitch_chat_overlay/emotes/third_party_emotes.dart';

const _enabled = ThirdPartyEmoteOptions(sevenTv: true, betterTtv: true);

void main() {
  test('default options perform no public API requests', () async {
    var requests = 0;
    final service = ThirdPartyEmotes(
      dio: mock((r, h) {
        requests++;
        emptyReply(r, h);
      }),
    );
    expect((await service.load('123')).emotes, isEmpty);
    expect(requests, 0);
  });

  test(
    'loads all four public sets, aliases, shared BTTV and supported CDN sizes',
    () async {
      final requests = <RequestOptions>[];
      final service = ThirdPartyEmotes(
        dio: mock((r, h) {
          requests.add(r);
          expect(
            r.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('authorization')),
          );
          expect(
            r.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('client-id')),
          );
          final global = r.path.endsWith('/global');
          if (r.uri.host == '7tv.io') {
            final set = {
              'emotes': [
                seven(global ? 'Global7' : 'ChannelAlias'),
                if (!global) seven('SecondAlias'),
              ],
            };
            reply(r, h, global ? set : {'emote_set': set});
          } else {
            reply(
              r,
              h,
              global
                  ? [bttv('GlobalB')]
                  : {
                      'channelEmotes': [bttv('ChannelB')],
                      'sharedEmotes': [bttv('SharedB', animated: true)],
                    },
            );
          }
        }),
      );
      final catalog = await service.load('123', options: _enabled);
      expect(requests, hasLength(4));
      expect(
        catalog.emotes.map((e) => e.name),
        containsAll([
          'Global7',
          'GlobalB',
          'ChannelAlias',
          'SecondAlias',
          'ChannelB',
          'SharedB',
        ]),
      );
      final alias = catalog.emotes.firstWhere((e) => e.name == 'ChannelAlias');
      expect(alias.imageUrl, 'https://cdn.7tv.app/emote/seven/2x.webp');
      expect(
        alias.thumbnailUrl,
        'https://cdn.7tv.app/emote/seven/2x_static.webp',
      );
      expect(alias.aspectRatio, 2);
      expect(alias.animated, isTrue);
      expect(alias.channel, isTrue);
      expect(
        catalog.emotes
            .where((e) => e.provider == EmoteProvider.sevenTv)
            .map((e) => e.key)
            .toSet(),
        hasLength(3),
      );
      final shared = catalog.emotes.firstWhere((e) => e.name == 'SharedB');
      expect(shared.imageUrl, 'https://cdn.betterttv.net/emote/bttv/2x');
      expect(shared.animated, isTrue);
    },
  );

  test(
    'channel overrides global and 7TV wins only within the same scope',
    () async {
      final service = ThirdPartyEmotes(
        dio: mock((r, h) {
          if (r.uri.host == '7tv.io') {
            reply(
              r,
              h,
              r.path.endsWith('/global')
                  ? {
                      'emotes': [seven('Conflict'), seven('ChannelWins')],
                    }
                  : {
                      'emote_set': {
                        'emotes': [seven('Conflict')],
                      },
                    },
            );
          } else {
            reply(
              r,
              h,
              r.path.endsWith('/global')
                  ? [bttv('Conflict')]
                  : {
                      'channelEmotes': [bttv('Conflict'), bttv('ChannelWins')],
                      'sharedEmotes': [],
                    },
            );
          }
        }),
      );
      final emotes = (await service.load('123', options: _enabled)).emotes;
      expect(emotes, hasLength(2));
      expect(
        emotes.firstWhere((e) => e.name == 'Conflict').provider,
        EmoteProvider.sevenTv,
      );
      expect(
        emotes.firstWhere((e) => e.name == 'ChannelWins').provider,
        EmoteProvider.betterTtv,
      );
    },
  );

  for (final options in [
    const ThirdPartyEmoteOptions(sevenTv: false, betterTtv: false),
    const ThirdPartyEmoteOptions(betterTtv: true),
    const ThirdPartyEmoteOptions(sevenTv: true),
  ]) {
    test(
      'disabled providers never issue requests (${options.sevenTv}/${options.betterTtv})',
      () async {
        final requests = <RequestOptions>[];
        final service = ThirdPartyEmotes(
          dio: mock((r, h) {
            requests.add(r);
            emptyReply(r, h);
          }),
        );
        expect((await service.load('123', options: options)).emotes, isEmpty);
        expect(
          requests.where((r) => r.uri.host == '7tv.io'),
          hasLength(options.sevenTv ? 2 : 0),
        );
        expect(
          requests.where((r) => r.uri.host == 'api.betterttv.net'),
          hasLength(options.betterTtv ? 2 : 0),
        );
      },
    );
  }

  test(
    '404 channel and a failing provider leave global emotes available',
    () async {
      final service = ThirdPartyEmotes(
        dio: mock((r, h) {
          if (r.uri.host == '7tv.io') {
            reject(r, h, 503);
          } else if (r.path.endsWith('/global')) {
            reply(r, h, [bttv('Working')]);
          } else {
            reject(r, h, 404);
          }
        }),
      );
      expect(
        (await service.load('123', options: _enabled)).emotes.single.name,
        'Working',
      );
    },
  );

  test(
    'cached sets expire; a failed refresh preserves data and backs off',
    () async {
      var now = DateTime.utc(2026);
      var fail = false;
      var requests = 0;
      final service = ThirdPartyEmotes(
        now: () => now,
        dio: mock((r, h) {
          requests++;
          if (fail) {
            reply(r, h, {'malformed': true});
          } else if (r.uri.host == '7tv.io') {
            reply(
              r,
              h,
              r.path.endsWith('/global')
                  ? {
                      'emotes': [seven('Saved')],
                    }
                  : {'emote_set': null},
            );
          } else {
            emptyReply(r, h);
          }
        }),
      );
      expect(
        (await service.load('123', options: _enabled)).emotes.single.name,
        'Saved',
      );
      await service.load('123', options: _enabled);
      expect(requests, 4);
      now = now.add(const Duration(minutes: 31));
      await service.load('123', options: _enabled);
      expect(requests, 8);
      fail = true;
      expect(
        (await service.load(
          '123',
          options: _enabled,
          refresh: true,
        )).emotes.single.name,
        'Saved',
      );
      expect(requests, 12);
      await service.load('123', options: _enabled);
      expect(requests, 12);
      now = now.add(const Duration(seconds: 31));
      await service.load('123', options: _enabled);
      expect(requests, 16);
    },
  );

  test('shares pending requests and keeps channel catalogs isolated', () async {
    final pending = <(RequestOptions, RequestInterceptorHandler)>[];
    final started = Completer<void>();
    final service = ThirdPartyEmotes(
      dio: mock((r, h) {
        pending.add((r, h));
        if (pending.length == 6) started.complete();
      }),
    );
    final old = service.load('old', options: _enabled);
    final repeated = service.load('old', options: _enabled);
    final current = service.load('current', options: _enabled);
    await started.future;
    expect(pending, hasLength(6));
    for (final (r, h) in pending) {
      if (r.uri.host == '7tv.io' && !r.path.endsWith('/global')) {
        reply(r, h, {
          'emote_set': {
            'emotes': [seven(r.uri.pathSegments.last)],
          },
        });
      } else {
        emptyReply(r, h);
      }
    }
    expect((await old).emotes.single.name, 'old');
    expect((await repeated).emotes.single.name, 'old');
    expect((await current).emotes.single.name, 'current');
    expect(
      (await service.load('current', options: _enabled)).emotes.single.name,
      'current',
    );
    expect(pending, hasLength(6));
  });

  test(
    'ignores malformed entries, unsupported images and overlay modifiers',
    () async {
      final good = seven('Valid');
      final zero = seven('Overlay');
      (zero['data'] as Map)['flags'] = 256;
      final badUrl = seven('BadUrl');
      ((badUrl['data'] as Map)['host'] as Map)['url'] = 'file:///private';
      final unsupported = seven('AvifOnly');
      ((unsupported['data'] as Map)['host'] as Map)['files'] = [
        imageFile('2x.avif', 'AVIF', 128, 64),
      ];
      final service = ThirdPartyEmotes(
        dio: mock((r, h) {
          if (r.uri.host == '7tv.io' && r.path.endsWith('/global')) {
            reply(r, h, {
              'emotes': [
                null,
                {'id': 'broken'},
                zero,
                badUrl,
                unsupported,
                good,
              ],
            });
          } else if (r.uri.host == 'api.betterttv.net' &&
              r.path.endsWith('/global')) {
            reply(r, h, [
              null,
              {'id': 'broken'},
              {...bttv('Modifier'), 'modifier': true},
            ]);
          } else {
            emptyReply(r, h);
          }
        }),
      );
      expect(
        (await service.load('123', options: _enabled)).emotes.single.name,
        'Valid',
      );
    },
  );

  test('resolves exact case-sensitive tokens and preserves text and native fragments', () {
    const emote = ChatEmote(
      id: '1',
      name: 'OMEGALUL',
      imageUrl: 'https://example.com/1.webp',
      provider: EmoteProvider.sevenTv,
    );
    final catalog = EmoteCatalog([emote]);
    const native = ChatEmoteFragment(
      text: 'OMEGALUL',
      id: '25',
      animated: false,
    );
    const mention = ChatMentionFragment(
      text: 'OMEGALUL',
      userId: '1',
      userName: 'OMEGALUL',
    );
    final original = [
      const ChatTextFragment(
        text: '😀  OMEGALUL\tomegalul OMEGALUL! xOMEGALUL https://example.com/OMEGALUL\nOMEGALUL ',
      ),
      native,
      mention,
    ];
    final resolved = catalog.resolve(original);
    expect(resolved.whereType<ChatThirdPartyEmoteFragment>(), hasLength(2));
    expect(
      resolved.map((f) => f.text).join(),
      original.map((f) => f.text).join(),
    );
    expect(resolved, containsAll([same(native), same(mention)]));
    expect(original.first, isA<ChatTextFragment>());
    expect(const EmoteCatalog.empty().resolve(original), same(original));
  });
}

Dio mock(void Function(RequestOptions, RequestInterceptorHandler) handler) =>
    Dio()..interceptors.add(InterceptorsWrapper(onRequest: handler));

void reply(RequestOptions r, RequestInterceptorHandler h, Object data) =>
    h.resolve(Response(requestOptions: r, statusCode: 200, data: data));

void reject(RequestOptions r, RequestInterceptorHandler h, int status) =>
    h.reject(
      DioException(
        requestOptions: r,
        response: Response(requestOptions: r, statusCode: status),
      ),
    );

void emptyReply(RequestOptions r, RequestInterceptorHandler h) {
  final global = r.path.endsWith('/global');
  reply(
    r,
    h,
    r.uri.host == '7tv.io'
        ? (global ? {'emotes': []} : {'emote_set': null})
        : (global ? [] : {'channelEmotes': [], 'sharedEmotes': []}),
  );
}

Map<String, Object?> bttv(String name, {bool animated = false}) => {
  'id': 'bttv',
  'code': name,
  'animated': animated,
  'imageType': animated ? 'gif' : 'png',
};

Map<String, Object?> imageFile(
  String name,
  String format,
  int width,
  int height,
) => {
  'name': name,
  'format': format,
  'width': width,
  'height': height,
  'static_name': name.replaceFirst('.', '_static.'),
  'frame_count': 3,
};

Map<String, Object?> seven(String name) => {
  'id': 'seven',
  'name': name,
  'data': {
    'name': 'OriginalName',
    'animated': true,
    'flags': 0,
    'host': {
      'url': '//cdn.7tv.app/emote/seven',
      'files': [
        imageFile('2x.avif', 'AVIF', 128, 64),
        imageFile('4x.webp', 'WEBP', 256, 128),
        imageFile('1x.webp', 'WEBP', 64, 32),
        imageFile('2x.webp', 'WEBP', 128, 64),
      ],
    },
  },
};
