import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_event_card.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';
import 'package:twitch_chat_overlay/twitch/twitch_rewards.dart';

void main() {
  const mapper = TwitchChatEventMapper();
  ChatRewardRedemption reward(String input) =>
      (mapper.map(
            _event('channel.channel_points_custom_reward_redemption.add', {
              'id': 'redeem-1',
              'user_id': 'viewer',
              'user_name': 'Viewer',
              'redeemed_at': '2026-09-05T10:00:00Z',
              'user_input': input,
              'reward': {
                'id': 'reward-1',
                'title': 'Choose a song',
                'cost': 1500,
              },
            }),
          ) as AddChatItem).item
          as ChatRewardRedemption;

  test('redemptions with and without input keep price and timestamp', () {
    final item = reward('Play this song');
    expect(item.userInput, 'Play this song');
    expect(item.rewardTitle, 'Choose a song');
    expect(item.cost, 1500);
    expect(item.receivedAt, DateTime.utc(2026, 9, 5, 10));
    expect(reward('').userInput, isEmpty);
    expect(
      mapper.map(
        _event('channel.channel_points_custom_reward_redemption.add', {
          'id': 'incomplete',
        }),
      ),
      isNull,
    );
  });

  for (final shared in [false, true]) {
    test(
      'maps ${shared ? 'shared' : 'local'} raid to a single dedicated card',
      () {
        final type = shared ? 'shared_chat_raid' : 'raid';
        final item =
            (mapper.map(
                  _event('channel.chat.notification', {
                    'message_id': 'raid-1',
                    'notice_type': type,
                    'system_message': 'Incoming raid',
                    if (shared)
                      'source_broadcaster_user_name': 'PartnerChannel',
                    type: {
                      'user_name': 'Raider',
                      'viewer_count': 42,
                      'profile_image_url':
                          'https://static-cdn.jtvnw.net/avatar.png',
                    },
                  }),
                ) as AddChatItem).item
                as ChatRaid;
        expect(item.userName, 'Raider');
        expect(item.viewerCount, 42);
        expect(item.profileImageUrl, endsWith('/avatar.png'));
        expect(item.sourceChannel, shared ? 'PartnerChannel' : null);
      },
    );
  }

  test('malformed raid details preserve the system notice', () {
    final item = (mapper.map(
      _event('channel.chat.notification', {
        'message_id': 'raid-1',
        'notice_type': 'raid',
        'system_message': 'Incoming raid',
        'raid': null,
      }),
    ) as AddChatItem).item;
    expect(item, isA<ChatNotice>());
  });

  test(
    'redelivery does not duplicate rewards and user clearing removes input',
    () {
      final timeline = ChatTimeline();
      expect(timeline.apply(AddChatItem(reward('A viewer message'))), isTrue);
      expect(timeline.apply(AddChatItem(reward('A viewer message'))), isFalse);
      expect(timeline.items, hasLength(1));
      expect(timeline.apply(const ClearUserMessages('someone-else')), isFalse);
      expect(timeline.apply(const ClearUserMessages('viewer')), isTrue);
      expect(timeline.items, isEmpty);
    },
  );

  test('reward artwork uses custom images or the Twitch default image', () {
    final images = TwitchRewardAppearance.parse([
      {
        'id': 'custom',
        'background_color': '#FF0000',
        'image': {'url_2x': 'custom-image'},
        'default_image': {'url_2x': 'default-image'},
      },
      {
        'id': 'default',
        'image': null,
        'default_image': {'url_2x': 'default-image'},
      },
      {'id': 'missing'},
    ]);
    expect(images['custom']?.imageUrl, 'custom-image');
    expect(images['custom']?.backgroundColor, '#FF0000');
    expect(images['default']?.imageUrl, 'default-image');
    expect(images['missing']?.imageUrl, isNull);
  });

  testWidgets('reward card is readable before artwork loads', (tester) async {
    await tester.pumpWidget(
      _app(RewardRedemptionCard(redemption: reward('Play this song'))),
    );
    expect(find.text('Viewer redeemed a reward'), findsOneWidget);
    expect(find.text('Choose a song'), findsOneWidget);
    expect(find.text('1500 Channel Points'), findsOneWidget);
    expect(find.text('Play this song'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(_app(RewardRedemptionCard(redemption: reward(''))));
    expect(find.text('Choose a song'), findsOneWidget);
    expect(find.text('Play this song'), findsNothing);
  });

  testWidgets('raid viewer plurals and shared origin fit a narrow overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RaidCard(
          raid: ChatRaid(
            id: 'raid',
            receivedAt: DateTime.utc(2026),
            userName: 'Raider',
            viewerCount: 22,
            sourceChannel: 'PartnerChannel',
          ),
        ),
        locale: const Locale('uk'),
      ),
    );
    expect(find.text('Raider починає рейд!'), findsOneWidget);
    expect(find.text('22 глядачі'), findsOneWidget);
    expect(find.text('зі спільного чату: PartnerChannel'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, Object?> _event(String type, Map<String, Object?> event) => {
  'metadata': {'subscription_type': type},
  'payload': {'event': event},
};

Widget _app(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  home: Scaffold(
    body: Center(child: SizedBox(width: 240, child: child)),
  ),
);
