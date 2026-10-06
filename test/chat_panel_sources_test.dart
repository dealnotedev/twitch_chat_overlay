import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/chat/viewer_count.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

Widget _app({
  required StreamWithInitial<TwitchAuthState> auth,
  required StreamWithInitial<ChatState> chat,
  bool interactive = false,
}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: ChatPanel(
      authSource: auth,
      chatSource: chat,
      interactive: interactive,
      onSignIn: () async {},
      onSignOut: () async {},
      onSend: (_, {String? replyTo}) => throw UnimplementedError(),
      onLoadEmotes: ({bool refresh = false}) async => [],
    ),
  ),
);

ChatState _chat(int viewers) => ChatState(
  status: ChatConnectionStatus.connected,
  items: const [],
  viewerCount: viewers,
);

void main() {
  testWidgets('replacing auth source follows new events and ignores old ones', (
    tester,
  ) async {
    final oldAuth = ObservableValue<TwitchAuthState>(
      current: const TwitchAuthState(status: TwitchAuthStatus.signedOut),
      sync: true,
    );
    final newAuth = ObservableValue<TwitchAuthState>(
      current: const TwitchAuthState.loading(),
      sync: true,
    );
    final chat = ObservableValue<ChatState>(current: const ChatState.idle());
    addTearDown(oldAuth.dispose);
    addTearDown(newAuth.dispose);
    addTearDown(chat.dispose);
    await tester.pumpWidget(_app(auth: oldAuth, chat: chat, interactive: true));
    await tester.pumpWidget(_app(auth: newAuth, chat: chat, interactive: true));
    newAuth.set(const TwitchAuthState(status: TwitchAuthStatus.signedOut));
    await tester.pump();
    expect(find.text('Sign in with Twitch'), findsOneWidget);
    oldAuth.set(const TwitchAuthState.loading());
    await tester.pump();
    expect(find.text('Sign in with Twitch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'replacing chat source uses its snapshot and follows only its events',
    (tester) async {
      final auth = ObservableValue<TwitchAuthState>(
        current: const TwitchAuthState(status: TwitchAuthStatus.signedIn),
        sync: true,
      );
      final oldChat = ObservableValue<ChatState>(current: _chat(1), sync: true);
      final newChat = ObservableValue<ChatState>(current: _chat(2), sync: true);
      addTearDown(auth.dispose);
      addTearDown(oldChat.dispose);
      addTearDown(newChat.dispose);
      await tester.pumpWidget(_app(auth: auth, chat: oldChat));
      await tester.pumpWidget(_app(auth: auth, chat: newChat));
      expect(tester.widget<ViewerCount>(find.byType(ViewerCount)).count, 2);
      newChat.set(_chat(3));
      await tester.pump();
      expect(tester.widget<ViewerCount>(find.byType(ViewerCount)).count, 3);
      oldChat.set(_chat(99));
      await tester.pump();
      expect(tester.widget<ViewerCount>(find.byType(ViewerCount)).count, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
