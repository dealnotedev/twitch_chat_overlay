import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

void main() {
  test(
    'channel overrides global by exact set/version, never subscription info',
    () {
      final badges = TwitchBadges({
        '': TwitchBadges.parse([
          _set('subscriber', '12', 'global'),
          _set('moderator', '1', 'mod'),
        ]),
        'source': TwitchBadges.parse([_set('subscriber', '12', 'custom')]),
        'other': TwitchBadges.parse([_set('subscriber', '12', 'other')]),
      });
      expect(
        badges
            .resolve(
              const ChatBadge(
                setId: 'subscriber',
                id: '12',
                info: '14',
                broadcasterId: 'source',
              ),
            )
            ?.url,
        'custom',
      );
      expect(
        badges
            .resolve(
              const ChatBadge(
                setId: 'moderator',
                id: '1',
                info: '',
                broadcasterId: 'source',
              ),
            )
            ?.url,
        'mod',
      );
      expect(
        badges
            .resolve(
              const ChatBadge(
                setId: 'subscriber',
                id: '12',
                info: '',
                broadcasterId: 'other',
              ),
            )
            ?.url,
        'other',
      );
      expect(
        badges.resolve(
          const ChatBadge(
            setId: 'subscriber',
            id: '14',
            info: '12',
            broadcasterId: 'source',
          ),
        ),
        isNull,
      );
      expect(
        badges.resolve(const ChatBadge(setId: 'unknown', id: '1', info: '')),
        isNull,
      );
    },
  );

  test('parses arbitrary custom badges and falls back to 1x', () {
    final parsed = TwitchBadges.parse([
      {
        'set_id': 'custom',
        'versions': [
          {'id': 'anything', 'image_url_1x': 'small', 'title': 'Custom badge'},
          {'id': 'missing-image'},
        ],
      },
      {'set_id': 'invalid'},
    ]);
    expect(parsed['custom']?['anything']?.url, 'small');
    expect(parsed['custom']?['anything']?.title, 'Custom badge');
    expect(parsed['custom'], hasLength(1));
  });

  for (final type in ['channel.chat.message', 'channel.chat.notification']) {
    test(
      '$type uses source channel badges, including an empty source list',
      () {
        final event = <String, Object?>{
          'message_id': 'message',
          'chatter_user_id': 'viewer',
          'chatter_user_name': 'Viewer',
          'system_message': 'Subscribed',
          'broadcaster_user_id': 'local',
          'source_broadcaster_user_id': 'source',
          'badges': [
            {'set_id': 'moderator', 'id': '1', 'info': ''},
          ],
          'source_badges': [
            {'set_id': 'subscriber', 'id': '12', 'info': '14'},
          ],
        };
        List<ChatBadge> mapped() {
          final mutation = const TwitchChatEventMapper().map({
            'metadata': {'subscription_type': type},
            'payload': {'event': event},
          }) as AddChatItem;
          return switch (mutation.item) {
            ChatUserMessage item => item.badges,
            ChatNotice item => item.badges,
            _ => throw StateError('Unexpected item'),
          };
        }

        expect(mapped().single.broadcasterId, 'source');
        expect(mapped().single.setId, 'subscriber');
        event['source_badges'] = <Object?>[];
        expect(mapped(), isEmpty);
        event['source_badges'] = null;
        expect(mapped().single.broadcasterId, 'local');
        expect(mapped().single.setId, 'moderator');
      },
    );
  }

  test(
    'Helix loads both catalogs with existing token and channel query',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio(BaseOptions(baseUrl: 'https://api.twitch.tv/helix'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) {
            requests.add(request);
            handler.resolve(
              Response(
                requestOptions: request,
                data: <String, Object?>{
                  'data': [_set('moderator', '1', 'official-image')],
                },
              ),
            );
          },
        ),
      );
      final client = TwitchHelixClient(_Auth(), dio: dio);
      expect(
        (await client.getBadges())['moderator']?['1']?.url,
        'official-image',
      );
      await client.getBadges(broadcasterId: 'channel');
      expect(requests[0].path, '/chat/badges/global');
      expect(requests[0].queryParameters, isEmpty);
      expect(requests[1].path, '/chat/badges');
      expect(requests[1].queryParameters, {'broadcaster_id': 'channel'});
      expect(requests[1].headers['Authorization'], 'Bearer test-access');
      expect(requests[1].headers['Client-Id'], 'test-client');
    },
  );
}

Map<String, Object?> _set(String setId, String id, String url) => {
  'set_id': setId,
  'versions': [
    {'id': id, 'image_url_2x': url, 'title': setId},
  ],
};

class _Auth implements TwitchAuth {
  @override
  Future<TwitchToken> validToken({String? rejectedAccessToken}) async =>
      TwitchToken(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
        clientId: 'test-client',
        userId: 'viewer',
        userLogin: 'viewer',
        scopes: TwitchAuthClient.requiredScopes,
        expiresAt: DateTime.utc(2030),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
