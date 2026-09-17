import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

const _hintText = 'No recent messages.\nNew messages will appear here.';
const _shortcutText = 'Ctrl+Shift+O — open controls';

Widget _app({
  bool interactive = false,
  ChatConnectionStatus status = ChatConnectionStatus.connected,
  List<ChatItem> items = const [],
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ChatPanel(
      authState: const TwitchAuthState(status: TwitchAuthStatus.signedIn),
      chatState: ChatState(status: status, items: items),
      interactive: interactive,
      onSignIn: () async {},
      onSignOut: () async {},
      onSend: (message, {replyTo}) async =>
          const SendChatResult(sent: true, messageId: 'sent', dropReason: null),
      onLoadEmotes: ({refresh = false}) async => [],
    ),
  ),
);

void main() {
  for (final interactive in [false, true]) {
    testWidgets('startup hint expires only outside controls ($interactive)', (
      tester,
    ) async {
      await tester.pumpWidget(_app(interactive: interactive));
      final hint = find.byKey(const ValueKey('startup-chat-hint'));
      expect(find.text(_hintText), findsOneWidget);
      expect(
        find.text(_shortcutText),
        interactive ? findsNothing : findsOneWidget,
      );
      await tester.pump(const Duration(milliseconds: 19999));
      expect(tester.widget<AnimatedOpacity>(hint).opacity, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.widget<AnimatedOpacity>(hint).opacity, interactive ? 1 : 0);
      await tester.pump(const Duration(milliseconds: 250));
      final transition = tester.widget<FadeTransition>(
        find.descendant(of: hint, matching: find.byType(FadeTransition)),
      );
      expect(transition.opacity.value, closeTo(interactive ? 1 : 0.5, 0.01));
      expect(find.text(_hintText), findsOneWidget);
      if (!interactive) {
        expect(
          find.descendant(of: hint, matching: find.text(_shortcutText)),
          findsOneWidget,
        );
      }
      await tester.pump(const Duration(milliseconds: 250));
      expect(hint, interactive ? findsOneWidget : findsNothing);
      expect(find.text(_shortcutText), findsNothing);

      // Connection failures remain visible after the startup hint expires.
      await tester.pumpWidget(_app(status: ChatConnectionStatus.failure));
      expect(find.text('Could not connect to chat'), findsOneWidget);
      await tester.pumpWidget(_app());
      expect(find.text(_hintText), findsNothing);
      await tester.pumpWidget(_app(interactive: true));
      expect(find.text(_hintText), findsOneWidget);
      await tester.pumpWidget(_app());
      expect(find.text(_hintText), findsNothing);

      // A fresh overlay launch gets its own startup hint.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_app());
      expect(find.text(_hintText), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('first message immediately dismisses hint for this launch', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(
      _app(
        items: [
          ChatNotice(
            id: 'first',
            receivedAt: DateTime.now(),
            noticeType: 'announcement',
            systemMessage: 'First message',
            userName: null,
            color: null,
            badges: const [],
            fragments: const [],
          ),
        ],
      ),
    );
    expect(find.text('First message'), findsOneWidget);
    expect(find.text(_hintText), findsNothing);
    expect(find.text(_shortcutText), findsNothing);
    await tester.pumpWidget(_app());
    expect(find.text(_hintText), findsNothing);
    await tester.pump(const Duration(seconds: 25));
    expect(find.text(_hintText), findsNothing);
    await tester.pumpWidget(_app(interactive: true));
    expect(find.text(_hintText), findsOneWidget);
    await tester.pumpWidget(_app());
    expect(find.text(_hintText), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('early reconnect dismisses hint without restarting its timer', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(_app(status: ChatConnectionStatus.reconnecting));
    expect(find.text(_hintText), findsNothing);
    await tester.pumpWidget(_app());
    expect(find.text(_hintText), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('opening controls does not restart the startup countdown', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpWidget(_app(interactive: true));
    expect(find.text(_hintText), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('startup-chat-hint')),
          )
          .opacity,
      1,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_hintText), findsOneWidget);
    await tester.pumpWidget(_app());
    expect(find.text(_hintText), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
