import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/chat/streamer_mention.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

ChatUserMessage message({
  String id = 'message',
  String text = 'hello',
  String user = 'viewer',
  String type = 'text',
  Map<String, Object?>? reply,
  List<Map<String, Object?>>? fragments,
}) =>
    (const TwitchChatEventMapper().map({
          'metadata': {'subscription_type': 'channel.chat.message'},
          'payload': {
            'event': {
              'message_id': id,
              'chatter_user_id': user,
              'chatter_user_name': 'Viewer',
              'message_type': type,
              'reply': reply,
              'message': {
                'fragments':
                    fragments ??
                    [
                      {'type': 'text', 'text': text},
                    ],
              },
            },
          },
        }) as AddChatItem).item
        as ChatUserMessage;

Map<String, Object?> reply({String? id, String login = 'streamer'}) => {
  'parent_message_id': 'parent',
  'parent_user_id': id,
  'parent_user_login': login,
  'parent_user_name': 'Display name',
  'parent_message_body': 'Question',
};

void main() {
  final target = StreamerMentionTarget(
    userId: 'broadcaster',
    login: 'streamer',
  );
  test('matches complete mentions with case and punctuation', () {
    for (final text in [
      '@streamer hello',
      'Hi @STREAMER!',
      '(@streamer)',
      '@streamer: yes',
    ]) {
      expect(target.isAddressedBy(message(text: text)), isTrue, reason: text);
    }
    for (final text in [
      'streamer',
      '@streamer_extra',
      '@streamer123',
      'mail@streamer.com',
      'https://example.com/@streamer',
      '@other',
    ]) {
      expect(target.isAddressedBy(message(text: text)), isFalse, reason: text);
    }
    expect(
      target.isAddressedBy(message(text: '@streamer', user: 'broadcaster')),
      isFalse,
    );
  });

  test('structured IDs are authoritative even without a login', () {
    final anonymousTarget = StreamerMentionTarget(userId: 'broadcaster');
    for (final id in ['broadcaster', 'other']) {
      final item = message(
        fragments: [
          {
            'type': 'mention',
            'text': '@streamer',
            'mention': {'user_id': id, 'user_name': 'Localized name'},
          },
        ],
      );
      expect(target.isAddressedBy(item), id == 'broadcaster');
      expect(anonymousTarget.isAddressedBy(item), id == 'broadcaster');
    }
  });

  test(
    'recognizes replies without an inline mention and preserves parent ID',
    () {
      final item = message(reply: reply(id: 'broadcaster'));
      expect(item.reply!.parentUserId, 'broadcaster');
      expect(target.isAddressedBy(item), isTrue);
      expect(target.isAddressedBy(message(reply: reply(id: 'other'))), isFalse);
      expect(
        target.isAddressedBy(message(reply: reply(login: 'STREAMER'))),
        isTrue,
      );
    },
  );

  test(
    'session retains more than 500 items, deduplicates and still moderates',
    () {
      final timeline = ChatTimeline();
      for (var i = 0; i < 1200; i++) {
        timeline.apply(
          AddChatItem(message(id: '$i', user: i.isEven ? 'even' : 'odd')),
        );
      }
      expect(timeline.items.length, 1200);
      expect(timeline.items.first.id, '0');
      expect(timeline.items.last.id, '1199');
      expect(timeline.apply(AddChatItem(message(id: '0'))), isFalse);
      expect(timeline.apply(const DeleteChatMessage('0')), isTrue);
      expect(timeline.apply(const ClearUserMessages('odd')), isTrue);
      expect(timeline.items.length, 599);
      expect(timeline.items.first.id, '2');
      timeline.apply(const ClearChat());
      expect(timeline.items, isEmpty);
      expect(timeline.apply(AddChatItem(message(id: '0'))), isTrue);
      timeline.clear();
      expect(timeline.items, isEmpty);
    },
  );

  for (final opacity in [0.0, 1.0]) {
    testWidgets('mention is readable and paints at opacity $opacity', (
      tester,
    ) async {
      await tester.pumpWidget(
        app(message(text: 'Hi @STREAMER!'), opacity: opacity),
      );
      await tester.pumpAndSettle();
      final card = tester.widget<Container>(
        find.byKey(const ValueKey('streamer-mention-message')),
      );
      final decoration = card.decoration! as BoxDecoration;
      expect(decoration.border!.top.color, isNotNull);
      expect((decoration.border! as Border).left.color.a, 1);
      expect(
        find.text('@ Viewer: Hi @STREAMER!', findRichText: true),
        findsOneWidget,
      );
      final spans = tester
          .widgetList<RichText>(find.byType(RichText))
          .expand((widget) => flatten(widget.text));
      final mention = spans.where((span) => span.text == '@STREAMER').single;
      expect(mention.style!.fontWeight, FontWeight.w700);
      expect(mention.style!.color, const Color(0xFFF0E6FF));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mention retains Channel Points and Power-up labels', (
    tester,
  ) async {
    for (final type in [
      'channel_points_highlighted',
      'power_ups_message_effect',
    ]) {
      await tester.pumpWidget(
        app(message(text: '@streamer hello', type: type)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('@ Viewer: @streamer hello', findRichText: true),
        findsOneWidget,
      );
      if (type == 'channel_points_highlighted') {
        expect(
          find.byKey(const ValueKey('highlighted-message-message')),
          findsOneWidget,
        );
        expect(find.text('Highlighted message'), findsOneWidget);
      } else {
        expect(find.byIcon(Icons.diamond_outlined), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    }
  });
}

Iterable<TextSpan> flatten(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? <InlineSpan>[]) {
      yield* flatten(child);
    }
  }
}

Widget app(ChatUserMessage message, {double opacity = 1}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        height: 460,
        child: BackgroundOpacity(
          opacity: opacity,
          child: ChatPanel(
            authState: TwitchAuthState(
              status: TwitchAuthStatus.signedIn,
              token: TwitchToken(
                accessToken: 'test',
                refreshToken: 'test',
                clientId: 'test',
                userId: 'broadcaster',
                userLogin: 'streamer',
                scopes: const [],
                expiresAt: DateTime.utc(2030),
              ),
            ),
            chatState: ChatState(
              status: ChatConnectionStatus.connected,
              broadcasterId: 'broadcaster',
              items: [message],
            ),
            interactive: false,
            onSignIn: () async {},
            onSignOut: () async {},
            onSend: (_, {String? replyTo}) async => throw UnimplementedError(),
            onLoadEmotes: ({bool refresh = false}) async => [],
          ),
        ),
      ),
    ),
  ),
);
