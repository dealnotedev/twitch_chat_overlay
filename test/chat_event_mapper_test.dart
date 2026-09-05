import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';

void main() {
  const mapper = TwitchChatEventMapper();

  test('maps every supported message fragment and reply metadata', () {
    final mutation = mapper.map(
      _envelope('channel.chat.message', {
        'message_id': 'message-1',
        'chatter_user_id': 'user-1',
        'chatter_user_name': 'Viewer',
        'color': '#00FF7F',
        'message_type': 'power_ups_gigantified_emote',
        'badges': [
          {'set_id': 'subscriber', 'id': '12', 'info': '14'},
        ],
        'cheer': {'bits': 100},
        'reply': {
          'parent_message_id': 'parent-1',
          'parent_user_name': 'Streamer',
          'parent_message_body': 'Hello',
        },
        'message': {
          'fragments': [
            {'type': 'text', 'text': 'Hi '},
            {
              'type': 'mention',
              'text': '@Streamer',
              'mention': {'user_id': 'streamer-1', 'user_name': 'Streamer'},
            },
            {
              'type': 'emote',
              'text': 'Kappa',
              'emote': {
                'id': '25',
                'format': ['static', 'animated'],
              },
            },
            {
              'type': 'cheermote',
              'text': 'Cheer100',
              'cheermote': {'prefix': 'cheer', 'bits': 100, 'tier': 100},
            },
            {
              'type': 'gif',
              'text': 'GIF',
              'gif': {'id': 'gif-1', 'url': 'https://example.com/a.gif'},
            },
          ],
        },
      }),
    );

    final message = (mutation as AddChatItem).item as ChatUserMessage;
    expect(message.messageType, 'power_ups_gigantified_emote');
    expect(message.bits, 100);
    expect(message.reply?.parentMessageId, 'parent-1');
    expect(message.badges.single.setId, 'subscriber');
    expect(message.fragments, hasLength(5));
    expect(message.fragments[0], isA<ChatTextFragment>());
    expect(message.fragments[1], isA<ChatMentionFragment>());
    expect(message.fragments[2], isA<ChatEmoteFragment>());
    expect((message.fragments[2] as ChatEmoteFragment).animated, isTrue);
    expect(message.fragments[3], isA<ChatCheermoteFragment>());
    expect(message.fragments[4], isA<ChatGifFragment>());
  });

  test('maps a chat notification', () {
    final mutation = mapper.map(
      _envelope('channel.chat.notification', {
        'message_id': 'notice-1',
        'notice_type': 'resub',
        'system_message': 'Viewer subscribed for 12 months!',
        'chatter_user_name': 'Viewer',
        'message': {
          'fragments': [
            {'type': 'text', 'text': 'Great stream!'},
          ],
        },
      }),
    );

    final notice = (mutation as AddChatItem).item as ChatNotice;
    expect(notice.noticeType, 'resub');
    expect(notice.systemMessage, contains('12 months'));
    expect(notice.fragments.single.text, 'Great stream!');
  });

  test('moderation mutations change the timeline', () {
    final timeline = ChatTimeline();
    timeline.apply(
      mapper.map(
        _envelope('channel.chat.message', {
          'message_id': 'message-1',
          'chatter_user_id': 'user-1',
          'chatter_user_name': 'Viewer',
          'message': {
            'fragments': [
              {'type': 'text', 'text': 'Hi'},
            ],
          },
        }),
      )!,
    );
    expect(timeline.items, hasLength(1));

    timeline.apply(
      mapper.map(
        _envelope('channel.chat.message_delete', {'message_id': 'message-1'}),
      )!,
    );
    expect(timeline.items, isEmpty);
  });

  test('unknown fragment degrades to text instead of being dropped', () {
    final mutation = mapper.map(
      _envelope('channel.chat.message', {
        'message_id': 'message-1',
        'chatter_user_id': 'user-1',
        'chatter_user_name': 'Viewer',
        'message': {
          'fragments': [
            {'type': 'future_type', 'text': 'future payload'},
          ],
        },
      }),
    );
    final message = (mutation as AddChatItem).item as ChatUserMessage;
    expect(message.fragments.single, isA<ChatUnknownFragment>());
    expect(message.fragments.single.text, 'future payload');
  });
}

Map<String, Object?> _envelope(
  String subscriptionType,
  Map<String, Object?> event,
) {
  return {
    'metadata': {
      'message_id': 'envelope-$subscriptionType',
      'message_type': 'notification',
      'message_timestamp': '2026-09-04T20:00:00Z',
      'subscription_type': subscriptionType,
    },
    'payload': {'event': event},
  };
}
