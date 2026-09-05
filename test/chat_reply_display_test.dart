import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';

import 'chat_message_actions_test.dart' as fixtures;

void main() {
  for (final structured in [false, true]) {
    testWidgets('reply hides leading recipient (structured: $structured)', (
      tester,
    ) async {
      final fragments = <Map<String, Object?>>[
        if (structured) ...[
          {
            'type': 'mention',
            'text': '@dare_dale',
            'mention': {'user_id': 'parent-user', 'user_name': 'dare_dale'},
          },
          {'type': 'text', 'text': ' шо? @dare_dale'},
        ] else
          {'type': 'text', 'text': '@dare_dale шо? @dare_dale'},
      ];
      final message = mappedMessage(fragments);
      await tester.pumpWidget(fixtures.app([message]));
      expect(find.text('↳ dare_dale: хм'), findsOneWidget);
      expect(
        find.text('Viewer: шо? @dare_dale', findRichText: true),
        findsOneWidget,
      );
      expect(
        message.fragments.map((fragment) => fragment.text).join(),
        '@dare_dale шо? @dare_dale',
      );
    });
  }

  for (final body in [
    '@someone hi',
    '@dare_dale_extra hi',
    'hi @dare_dale',
    'hi',
  ]) {
    testWidgets('reply preserves body: $body', (tester) async {
      await tester.pumpWidget(
        fixtures.app([
          mappedMessage([
            {'type': 'text', 'text': body},
          ]),
        ]),
      );
      expect(find.text('Viewer: $body', findRichText: true), findsOneWidget);
    });
  }

  testWidgets('ordinary mentions stay visible without reply metadata', (
    tester,
  ) async {
    await tester.pumpWidget(
      fixtures.app([
        mappedMessage([
          {'type': 'text', 'text': '@dare_dale hi'},
        ], reply: false),
      ]),
    );
    expect(
      find.text('Viewer: @dare_dale hi', findRichText: true),
      findsOneWidget,
    );
  });

  test('reply login matching preserves media fragments and later mentions', () {
    final message = mappedMessage([
      {'type': 'mention', 'text': '@DARE_DALE'},
      {'type': 'text', 'text': ' '},
      {
        'type': 'emote',
        'text': 'Kappa',
        'emote': {
          'id': '25',
          'format': ['animated'],
        },
      },
      {'type': 'text', 'text': ' '},
      {'type': 'mention', 'text': '@someone'},
      {
        'type': 'gif',
        'text': 'GIF',
        'gif': {'id': 'gif', 'url': 'https://example.com/a.gif'},
      },
    ], parentName: 'Локалізоване імʼя');
    expect(message.displayFragments, orderedEquals(message.fragments.skip(2)));
    expect(message.displayFragments.first, isA<ChatEmoteFragment>());
    expect(message.displayFragments.last, isA<ChatGifFragment>());
    expect(message.fragments.first.text, '@DARE_DALE');
  });
  testWidgets('reward input stays in a deletable message only', (tester) async {
    final message = fixtures.message('reward-message', text: 'Play this song');
    final reward = ChatRewardRedemption(
      id: 'redemption:1',
      receivedAt: DateTime.now().toUtc(),
      userId: 'viewer',
      userName: 'Viewer',
      rewardId: 'reward',
      rewardTitle: 'Choose a song',
      cost: 1000,
      userInput: 'Play this song',
    );
    String? deleted;
    await tester.pumpWidget(
      fixtures.app(
        [message, reward],
        delete: (id) async {
          deleted = id;
        },
      ),
    );
    expect(
      find.textContaining('Play this song', findRichText: true),
      findsOneWidget,
    );
    await fixtures.hover(tester, message.id);
    await tester.tap(find.byKey(ValueKey('delete-${message.id}')));
    await tester.pump();
    expect(deleted, message.id);
    await tester.pumpWidget(fixtures.app([reward]));
    expect(
      find.textContaining('Play this song', findRichText: true),
      findsNothing,
    );
    expect(
      find.textContaining('Choose a song', findRichText: true),
      findsOneWidget,
    );
  });
}

ChatUserMessage mappedMessage(
  List<Map<String, Object?>> fragments, {
  bool reply = true,
  String parentName = 'dare_dale',
}) =>
    (const TwitchChatEventMapper().map({
          'metadata': {'subscription_type': 'channel.chat.message'},
          'payload': {
            'event': {
              'message_id': 'reply',
              'chatter_user_id': 'viewer',
              'chatter_user_name': 'Viewer',
              'message': {'fragments': fragments},
              if (reply)
                'reply': {
                  'parent_message_id': 'parent',
                  'parent_user_id': 'parent-user',
                  'parent_user_login': 'dare_dale',
                  'parent_user_name': parentName,
                  'parent_message_body': 'хм',
                },
            },
          },
        }) as AddChatItem).item
        as ChatUserMessage;
