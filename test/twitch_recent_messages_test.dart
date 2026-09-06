import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';
import 'package:twitch_chat_overlay/twitch/twitch_recent_messages.dart';

const timestamp = 1788690000000;
String line(
  String id, {
  String tags = '',
  String text = ':hello',
  String command = 'PRIVMSG',
  String channel = 'owner',
}) =>
    '@id=$id;user-id=viewer;display-name=Viewer;tmi-sent-ts=$timestamp;$tags :viewer!v@v PRIVMSG #$channel $text'
        .replaceFirst(' PRIVMSG ', ' $command ');
ChatUserMessage message(
  String id, {
  bool history = false,
  DateTime? time,
  String user = 'viewer',
}) => ChatUserMessage(
  id: id,
  receivedAt: time ?? DateTime.fromMillisecondsSinceEpoch(timestamp),
  isHistorical: history,
  userId: user,
  userName: user,
  color: null,
  badges: const [],
  fragments: [ChatTextFragment(text: id)],
  messageType: 'text',
  bits: null,
  reply: null,
  sourceChannel: null,
);

void main() {
  test('parses plain final parameter, original timestamp, escaped reply and badges', () {
    final result = parseRecentMessage(
      line(
        'id',
        text: 'Kappa',
        tags: r'color=#123456;badges=moderator/1,subscriber/12;badge-info=subscriber/14;room-id=owner-id;reply-parent-msg-id=parent;reply-parent-display-name=Other;reply-parent-msg-body=hello\sworld\:;reply-parent-user-login=other',
      ),
      channelLogin: 'owner',
    ) as AddChatItem;
    final item = result.item as ChatUserMessage;
    expect(item.isHistorical, isTrue);
    expect(item.receivedAt.millisecondsSinceEpoch, timestamp);
    expect(item.fragments.single.text, 'Kappa');
    expect(item.badges.last.info, '14');
    expect(item.reply?.parentMessageBody, 'hello world;');
    expect(item.reply?.parentUserLogin, 'other');
  });

  test(
    'maps Unicode emote offsets and ignores malformed or overlapping spans',
    () {
      final result = parseRecentMessage(
        line(
          'id',
          text: ':😀 Kappa hi',
          tags: 'emotes=25:2-6,2-6,90-95/bad:wrong',
        ),
        channelLogin: 'owner',
      ) as AddChatItem;
      final fragments = (result.item as ChatUserMessage).fragments;
      expect(fragments.map((f) => f.text), ['😀 ', 'Kappa', ' hi']);
      expect((fragments[1] as ChatEmoteFragment).id, '25');
    },
  );

  test('skips deleted, foreign, malformed and undated history', () {
    for (final raw in [
      line('gone', tags: 'rm-deleted=1'),
      line('other', channel: 'other'),
      line('undated').replaceAll('tmi-sent-ts=$timestamp', 'tmi-sent-ts=bad'),
      line('overflow').replaceAll('$timestamp', '999999999999999999'),
      '@bad',
      ':server ROOMSTATE #owner',
    ]) {
      expect(parseRecentMessage(raw, channelLogin: 'owner'), isNull);
    }
    final result = parseRecentMessage(
      line('fallback')
          .replaceAll('tmi-sent-ts=$timestamp', 'rm-received-ts=$timestamp'),
      channelLogin: 'owner',
    ) as AddChatItem;
    expect(result.item.receivedAt.millisecondsSinceEpoch, timestamp);
  });

  test('preserves notices and parses moderation commands', () {
    final result = parseRecentMessage(
      line(
        'notice',
        command: 'USERNOTICE',
        tags: r'msg-id=sub;system-msg=Viewer\ssubscribed!',
      ),
      channelLogin: 'owner',
    ) as AddChatItem;
    expect((result.item as ChatNotice).systemMessage, 'Viewer subscribed!');
    expect(result.item.isHistorical, isTrue);
    expect(
      parseRecentMessage(
        '@target-msg-id=id :server CLEARMSG #owner :hello',
        channelLogin: 'owner',
      ),
      isA<DeleteChatMessage>(),
    );
    expect(
      parseRecentMessage(
        '@target-user-id=viewer :server CLEARCHAT #owner :viewer',
        channelLogin: 'owner',
      ),
      isA<ClearUserMessages>(),
    );
    expect(
      parseRecentMessage(
        '@room-id=1 :server CLEARCHAT #owner',
        channelLogin: 'owner',
      ),
      isA<ClearChat>(),
    );
  });

  test('loads available history despite informational error and applies moderation', () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (request, handler) {
          expect(request.path, '/recent-messages/owner');
          expect(request.headers.containsKey('Authorization'), isFalse);
          handler.resolve(
            Response(
              requestOptions: request,
              data: {
                'messages': [
                  line('deleted'),
                  line('kept'),
                  123,
                  '@target-msg-id=deleted :server CLEARMSG #owner :hello',
                ],
                'error_code': 'channel_not_joined',
              },
            ),
          );
        },
      ),
    );
    expect(
      (await TwitchRecentMessages(dio: dio).load('OWNER')).map((m) => m.id),
      ['kept'],
    );
  });

  test('live messages win duplicates and replace later historical copies', () {
    final timeline = ChatTimeline();
    final live = message('same');
    timeline.restoreHistory(
      [
        message('same', history: true),
        message('old', history: true, time: DateTime(2020)),
      ],
      [AddChatItem(live)],
    );
    expect(timeline.items.map((m) => m.id), ['old', 'same']);
    expect(timeline.items.last, same(live));
    expect(timeline.apply(AddChatItem(message('old'))), isTrue);
    expect(timeline.items.first.isHistorical, isFalse);
    expect(timeline.apply(AddChatItem(live)), isFalse);
  });

  test(
    'replays unseen deletion and user clearing without losing later chat',
    () {
      final timeline = ChatTimeline();
      timeline.restoreHistory(
        [
          message('deleted', history: true, user: 'other'),
          message('user-cleared', history: true),
          message('kept', history: true, user: 'third'),
        ],
        [
          const DeleteChatMessage('deleted'),
          const ClearUserMessages('viewer'),
          AddChatItem(message('new')),
        ],
      );
      expect(timeline.items.map((m) => m.id), ['kept', 'new']);
      timeline.restoreHistory(
        [message('old', history: true)],
        [const ClearChat(), AddChatItem(message('after-clear'))],
      );
      expect(timeline.items.map((m) => m.id), ['after-clear']);
    },
  );

  testWidgets(
    'expired history is hidden immediately and cannot reappear on updates',
    (tester) async {
      final recent = ChatMessageRetention();
      addTearDown(recent.dispose);
      final old = message(
        'old',
        history: true,
        time: DateTime.now().subtract(const Duration(minutes: 6)),
      );
      final fresh = message(
        'fresh',
        history: true,
        time: DateTime.now().subtract(const Duration(minutes: 4)),
      );
      recent.update([old, fresh], 5);
      expect(recent.items, [fresh]);
      expect(recent.isFading('old'), isFalse);
      await tester.pump(const Duration(seconds: 59));
      expect(recent.isFading('fresh'), isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(recent.isFading('fresh'), isTrue);
      await tester.pump(ChatMessageRetention.fadeDuration);
      expect(recent.items, isEmpty);
      recent.update([old, fresh], 0);
      expect(recent.items, isEmpty);
    },
  );

  testWidgets('unlimited lifetime displays all available historical messages', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    addTearDown(recent.dispose);
    final old = message('old', history: true, time: DateTime(2020));
    recent.update([old], 0);
    await tester.pump(const Duration(days: 7));
    expect(recent.items, [old]);
  });
}
