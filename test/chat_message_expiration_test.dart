import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

void main() {
  for (final interactive in [false, true]) {
    testWidgets(
      'idle rows dissolve then show recent empty state (interactive: $interactive)',
      (tester) async {
        var deletes = 0;
        final item = ChatNotice(
          id: 'expiring',
          receivedAt: DateTime.now().subtract(const Duration(seconds: 59)),
          noticeType: 'announcement',
          systemMessage: 'Expiring message',
          userName: null,
          color: null,
          badges: const [],
          fragments: const [],
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: ChatPanel(
                authState: const TwitchAuthState(
                  status: TwitchAuthStatus.signedIn,
                ),
                chatState: ChatState(
                  status: ChatConnectionStatus.connected,
                  items: [item],
                ),
                interactive: interactive,
                messageLifetimeMinutes: 1,
                onSignIn: () async {},
                onSignOut: () async {},
                onSend: (message, {replyTo}) async => const SendChatResult(
                  sent: true,
                  messageId: 'sent',
                  dropReason: null,
                ),
                onLoadEmotes: ({refresh = false}) async => [],
                onDeleteMessage: (_) async {
                  deletes++;
                },
              ),
            ),
          ),
        );
        final fade = find.byKey(const ValueKey('message-fade-expiring'));
        expect(tester.widget<AnimatedOpacity>(fade).opacity, 1);
        // Stop at the start of the fade: initial rendering consumes real time,
        // so a full-second jump can skip part of the removal animation.
        for (
          var i = 0;
          i < 100 && tester.widget<AnimatedOpacity>(fade).opacity == 1;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(tester.widget<AnimatedOpacity>(fade).opacity, 0);
        await tester.pump(const Duration(milliseconds: 350));
        final transition = tester.widget<FadeTransition>(
          find
              .descendant(of: fade, matching: find.byType(FadeTransition))
              .first,
        );
        expect(transition.opacity.value, greaterThan(0));
        expect(transition.opacity.value, lessThan(1));
        expect(find.text('Expiring message'), findsOneWidget);
        await tester.pump(ChatMessageRetention.fadeDuration);
        expect(find.text('Expiring message'), findsNothing);
        expect(
          find.text('No recent messages.\nNew messages will appear here.'),
          findsOneWidget,
        );
        expect(deletes, 0);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
