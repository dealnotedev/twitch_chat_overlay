import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_actions.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

import 'twitch_emotes_test.dart' as fixtures;

const sent = SendChatResult(sent: true, messageId: 'sent', dropReason: null);
final input = find.byKey(const ValueKey('chat-message-input'));
TestGesture? activeMouse;

void main() {
  testWidgets(
    'interactive mode and hovered actions preserve message width and height',
    (tester) async {
      final messages = [
        message(
          'a',
          text: 'A long message with enough words to wrap across several lines in this narrow overlay.',
        ),
      ];
      await tester.pumpWidget(app(messages, interactive: false));
      final initial = tester.getSize(find.byType(ChatMessageContent));
      await tester.pumpWidget(app(messages));
      expect(tester.getSize(find.byType(ChatMessageContent)), initial);
      await hover(tester, 'a');
      expect(tester.getSize(find.byType(ChatMessageContent)), initial);
      expect(
        tester
            .getRect(find.byType(ChatMessageActions))
            .contains(tester.getCenter(find.byKey(const ValueKey('reply-a')))),
        isTrue,
      );
      await tester.pumpWidget(app(messages, interactive: false));
      expect(tester.getSize(find.byType(ChatMessageContent)), initial);
      expect(find.byKey(const ValueKey('reply-a')), findsNothing);
    },
  );

  testWidgets(
    'reply preserves draft on cancel, sends the selected parent and retains failed reply',
    (tester) async {
      final requests = <(String, String?)>[];
      var fail = true;
      await tester.pumpWidget(
        app(
          [message('a')],
          send: (text, {String? replyTo}) async {
            requests.add((text, replyTo));
            if (fail) throw StateError('offline');
            return sent;
          },
        ),
      );
      await tester.enterText(input, 'draft');
      await hover(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('reply-a')));
      await tester.pump();
      expect(find.text('Replying to Viewer'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('cancel-reply')));
      await tester.pump();
      expect(tester.widget<TextField>(input).controller!.text, 'draft');
      expect(find.byKey(const ValueKey('reply-preview')), findsNothing);
      await hover(tester, 'a');
      await tester.tap(find.byKey(const ValueKey('reply-a')));
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(requests, [('draft', 'a')]);
      expect(find.byKey(const ValueKey('reply-preview')), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, 'draft');
      fail = false;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(requests, [('draft', 'a'), ('draft', 'a')]);
      expect(tester.widget<TextField>(input).controller!.text, isEmpty);
      expect(find.byKey(const ValueKey('reply-preview')), findsNothing);
    },
  );

  testWidgets('an earlier send does not clear a newer reply or draft', (
    tester,
  ) async {
    final pending = Completer<SendChatResult>();
    await tester.pumpWidget(
      app([
        message('a'),
        message('b', name: 'Second'),
      ], send: (_, {String? replyTo}) => pending.future),
    );
    await hover(tester, 'a');
    await tester.tap(find.byKey(const ValueKey('reply-a')));
    await tester.enterText(input, 'first');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await hover(tester, 'b');
    await tester.tap(find.byKey(const ValueKey('reply-b')));
    await tester.enterText(input, 'next');
    pending.complete(sent);
    await tester.pump();
    expect(find.text('Replying to Second'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, 'next');
  });

  testWidgets('removing a reply target cancels only its preview', (
    tester,
  ) async {
    await tester.pumpWidget(app([message('a')]));
    await hover(tester, 'a');
    await tester.tap(find.byKey(const ValueKey('reply-a')));
    await tester.enterText(input, 'saved draft');
    await tester.pumpWidget(app([]));
    expect(find.byKey(const ValueKey('reply-preview')), findsNothing);
    expect(tester.widget<TextField>(input).controller!.text, 'saved draft');
    expect(find.textContaining('no longer available'), findsOneWidget);
  });

  testWidgets('delete is single-flight and failures preserve the message', (
    tester,
  ) async {
    final pending = Completer<void>();
    final deleted = <String>[];
    await tester.pumpWidget(
      app(
        [message('a')],
        delete: (id) {
          deleted.add(id);
          return pending.future;
        },
      ),
    );
    await hover(tester, 'a');
    final button = find.byKey(const ValueKey('delete-a'));
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    expect(deleted, ['a']);
    pending.completeError(
      const TwitchChatActionException(TwitchChatActionFailure.forbidden),
    );
    await tester.pump();
    expect(find.byType(ChatMessageContent), findsOneWidget);
    expect(
      find.text('Twitch does not allow deleting this message.'),
      findsOneWidget,
    );
    expect(deleted, ['a']);
    expect(find.byType(ChatMessageContent), findsOneWidget);
  });

  testWidgets(
    'own, moderator and expired messages cannot be deleted from Twitch',
    (tester) async {
      await tester.pumpWidget(
        app([
          message('own', user: 'sender'),
          message(
            'mod',
            badges: [
              const ChatBadge(
                setId: 'moderator',
                id: '1',
                info: '',
                broadcasterId: 'sender',
              ),
            ],
          ),
          message('old', age: const Duration(hours: 7)),
        ]),
      );
      for (final id in ['own', 'mod', 'old']) {
        expect(find.byKey(ValueKey('delete-$id')), findsNothing);
        expect(find.byKey(ValueKey('reply-$id')), findsOneWidget);
      }
    },
  );
}

Future<void> hover(WidgetTester tester, String id) async {
  final row = find.ancestor(
    of: find.byKey(ValueKey('reply-$id')),
    matching: find.byType(ChatMessageActions),
  );
  if (activeMouse == null) {
    activeMouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await activeMouse!.addPointer(location: Offset.zero);
    addTearDown(() async {
      await activeMouse?.removePointer();
      activeMouse = null;
    });
  }
  final mouse = activeMouse!;
  await mouse.moveTo(tester.getCenter(row));
  await tester.pump(const Duration(milliseconds: 120));
}

ChatUserMessage message(
  String id, {
  String user = 'viewer',
  String name = 'Viewer',
  String text = 'Original message',
  Duration age = Duration.zero,
  List<ChatBadge> badges = const [],
}) => ChatUserMessage(
  id: id,
  receivedAt: DateTime.now().toUtc().subtract(age),
  userId: user,
  userName: name,
  color: '#BF94FF',
  badges: badges,
  fragments: [ChatTextFragment(text: text)],
  messageType: 'text',
  bits: null,
  reply: null,
  sourceChannel: null,
);

Widget app(
  List<ChatUserMessage> messages, {
  bool interactive = true,
  Future<SendChatResult> Function(String, {String? replyTo})? send,
  Future<void> Function(String)? delete,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 320,
        height: 460,
        child: ChatPanel(
          authState: TwitchAuthState(
            status: TwitchAuthStatus.signedIn,
            token: fixtures.makeToken(),
          ),
          chatState: ChatState(
            status: ChatConnectionStatus.connected,
            items: messages,
            broadcasterId: 'sender',
          ),
          interactive: interactive,
          onSignIn: () async {},
          onSignOut: () async {},
          onSend: send ?? (_, {String? replyTo}) async => sent,
          onDeleteMessage: delete ?? (_) async {},
          onLoadEmotes: ({bool refresh = false}) async => [],
        ),
      ),
    ),
  ),
);
