import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('reward redemption is one compact, wrapping paragraph', (
    tester,
  ) async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-Bold.ttf')))
        .load();
    for (final locale in ['en', 'uk']) {
      for (final width in [240.0, 120.0]) {
        for (final textScale in [1.0, 2.0]) {
          for (final input in ['', 'Play this song']) {
            final color = input.isEmpty ? const Color(0xFF70DDBB) : null;
            await tester.pumpWidget(
              _app(
                RewardRedemptionCard(
                  redemption: reward(input),
                  userColor: color,
                ),
                locale: Locale(locale),
                width: width,
                textScale: textScale,
              ),
            );
            final paragraph = find.descendant(
              of: find.byType(RewardRedemptionCard),
              matching: find.byType(Text),
            );
            expect(paragraph, findsOneWidget);
            final text = tester.widget<Text>(paragraph);
            final span = text.textSpan! as TextSpan;
            final plain = span.toPlainText(includeSemanticsLabels: false);
            final action = locale == 'uk' ? 'бере' : 'redeems';
            final preposition = locale == 'uk' ? 'за' : 'for';
            expect(
              plain,
              'Viewer $action Choose a song $preposition \uFFFC\u00a01500',
            );
            final name = span.children!.first as TextSpan;
            expect(name.style!.fontWeight, FontWeight.w700);
            expect(name.style!.color, color ?? Colors.white);
            final title = span.children![2] as TextSpan;
            expect(title.style!.fontWeight, FontWeight.w700);
            if (width == 240 && textScale == 1 && input.isEmpty) {
              expect(
                tester.getSize(find.byType(RewardRedemptionCard)).height,
                lessThan(55),
              );
            }
            expect(tester.takeException(), isNull);
          }
        }
      }
    }
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

Widget _app(
  Widget child, {
  Locale locale = const Locale('en'),
  double width = 240,
  double textScale = 1,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(brightness: Brightness.dark, fontFamily: 'Inter'),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  ),
);
