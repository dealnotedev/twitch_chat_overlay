import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_composer.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_emotes.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_token.dart';

const library = [
  TwitchEmote(
    id: '25',
    name: 'Kappa',
    type: 'globals',
    imageUrl: 'https://static-cdn.jtvnw.net/emoticons/v2/25/static/dark/2.0',
  ),
  TwitchEmote(
    id: '88',
    name: 'SubscriberSmile',
    ownerId: '123',
    ownerName: 'ExampleChannel',
    type: 'subscriptions',
    imageUrl: 'https://static-cdn.jtvnw.net/emoticons/v2/88/static/dark/2.0',
  ),
  TwitchEmote(
    id: '89',
    name: 'FollowerSmile',
    ownerId: '123',
    ownerName: 'ExampleChannel',
    type: 'follower',
    imageUrl: 'https://static-cdn.jtvnw.net/emoticons/v2/88/static/dark/2.0',
  ),
  TwitchEmote(
    id: '26',
    name: 'TemporarySmile',
    type: 'limitedtime',
    imageUrl: 'https://static-cdn.jtvnw.net/emoticons/v2/25/static/dark/2.0',
  ),
];
const sent = SendChatResult(sent: true, messageId: 'sent', dropReason: null);
final messageInput = find.byKey(const ValueKey('chat-message-input'));

void main() {
  test('emote insertion replaces selection and separates adjacent tokens', () {
    final result = insertChatEmote(
      const TextEditingValue(
        text: 'hello OLDworld',
        selection: TextSelection(baseOffset: 6, extentOffset: 9),
      ),
      'Kappa',
    )!;
    expect(result.text, 'hello Kappa world');
    expect(result.selection.baseOffset, 12);
    expect(
      insertChatEmote(const TextEditingValue(text: 'hello'), 'Kappa')?.text,
      'hello Kappa ',
    );
    expect(
      insertChatEmote(
        const TextEditingValue(
          text: 'hello ',
          selection: TextSelection.collapsed(offset: 6),
        ),
        'Kappa',
      )?.text,
      'hello Kappa ',
    );
  });

  test(
    'insertion respects the message limit without cutting an emote or Unicode',
    () {
      final full = List.filled(500, 'a').join();
      expect(insertChatEmote(TextEditingValue(text: full), 'Kappa'), isNull);
      final emoji = List.filled(492, '😀').join();
      final result = insertChatEmote(TextEditingValue(text: emoji), 'Kappa')!;
      expect(result.text.characters.length, 499);
      expect(result.selection.baseOffset, result.text.length);
    },
  );

  testWidgets('logout and send flank the input; emotes stay inside it', (
    tester,
  ) async {
    await primeEmoteImages(tester);
    await tester.pumpWidget(app());
    final frame = tester.getRect(
      find.byKey(const ValueKey('chat-input-frame')),
    );
    expect(
      tester.getRect(find.byTooltip('Sign out of Twitch')).right,
      lessThanOrEqualTo(frame.left),
    );
    expect(
      tester.getRect(find.byTooltip('Send')).left,
      greaterThanOrEqualTo(frame.right),
    );
    expect(frame.contains(tester.getCenter(find.byTooltip('Emotes'))), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'searches sender emotes, inserts at the cursor and sends with Enter',
    (tester) async {
      final messages = <String>[];
      await primeEmoteImages(tester);
      await tester.pumpWidget(
        app(
          onSend: (message) async {
            messages.add(message);
            return sent;
          },
        ),
      );
      await tester.enterText(messageInput, 'hello world');
      final controller = tester.widget<TextField>(messageInput).controller!;
      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.tap(find.byTooltip('Emotes'));
      await tester.pump();
      await tester.pump();
      final search = find.widgetWithText(TextField, 'Search emotes');
      await tester.enterText(search, 'kapp');
      await tester.pump();
      expect(find.byKey(const ValueKey('emote-88')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('emote-25')));
      await tester.pump();
      expect(controller.text, 'hello Kappa world');
      expect(
        tester.widget<TextField>(messageInput).focusNode!.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(messages, ['hello Kappa world']);
      expect(controller.text, isEmpty);
      expect(find.byKey(const ValueKey('chat-emote-picker')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permission prompt preserves the draft and uses explicit authorization',
    (tester) async {
      var authorizations = 0;
      await primeEmoteImages(tester);
      await tester.pumpWidget(
        app(
          load: ({bool refresh = false}) async =>
              throw const TwitchEmotePermissionRequired(),
          authorize: () async {
            authorizations++;
          },
        ),
      );
      await tester.enterText(messageInput, 'draft');
      await tester.tap(find.byTooltip('Emotes'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Connect emotes'), findsOneWidget);
      expect(tester.widget<TextField>(messageInput).controller!.text, 'draft');
      await tester.tap(find.text('Connect emotes'));
      await tester.pump();
      expect(authorizations, 1);
    },
  );

  testWidgets(
    'loading failures can retry and the picker remains inside a narrow chat',
    (tester) async {
      var loads = 0;
      await primeEmoteImages(tester);
      await tester.pumpWidget(
        app(
          width: 320,
          height: 340,
          load: ({bool refresh = false}) async {
            if (++loads == 1) throw StateError('offline');
            return library;
          },
        ),
      );
      await tester.tap(find.byTooltip('Emotes'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(loads, 2);
      final panel = tester.getRect(find.byType(ChatPanel));
      final picker = tester.getRect(
        find.byKey(const ValueKey('chat-emote-picker')),
      );
      expect(picker.left, greaterThanOrEqualTo(panel.left));
      expect(picker.right, lessThanOrEqualTo(panel.right));
      expect(picker.top, greaterThanOrEqualTo(panel.top));
      expect(
        picker.bottom,
        lessThan(tester.getTopLeft(find.byType(ChatComposer)).dy),
      );
      await tester.tap(find.byKey(const ValueKey('close-emotes')));
      await tester.pump();
      expect(find.byKey(const ValueKey('chat-emote-picker')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('groups by owner without category subtitles or panel tooltips', (
    tester,
  ) async {
    await primeEmoteImages(tester);
    await tester.pumpWidget(app());
    await tester.tap(find.byTooltip('Emotes'));
    await tester.pump();
    await tester.pump();
    final picker = find.byKey(const ValueKey('chat-emote-picker'));
    expect(
      find.descendant(of: picker, matching: find.byType(Tooltip)),
      findsNothing,
    );
    expect(find.text('ExampleChannel'), findsOneWidget);
    expect(find.text('Subscribers'), findsNothing);
    expect(find.text('Followers'), findsNothing);
    expect(find.textContaining(RegExp(r'^\d+$')), findsNothing);
    expect(find.byType(Scrollbar), findsNothing);
    expect(
      find.descendant(of: picker, matching: find.byType(RawScrollbar)),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.byKey(const ValueKey('emote-88'))).dy,
      tester.getCenter(find.byKey(const ValueKey('emote-89'))).dy,
    );
    expect(find.text('Twitch'), findsOneWidget);
    expect(find.text('Global emotes'), findsNothing);
    expect(find.text('Limited-time emotes'), findsNothing);
    expect(
      tester.getCenter(find.byKey(const ValueKey('emote-25'))).dy,
      tester.getCenter(find.byKey(const ValueKey('emote-26'))).dy,
    );
    expect(
      tester.getTopLeft(find.text('ExampleChannel')).dy,
      lessThan(tester.getTopLeft(find.byKey(const ValueKey('emote-88'))).dy),
    );
    final search = find.widgetWithText(TextField, 'Search emotes');
    await tester.enterText(search, 'examplechannel');
    await tester.pump();
    expect(find.byKey(const ValueKey('emote-88')), findsOneWidget);
    expect(find.text('Twitch'), findsNothing);
  });

  testWidgets('only the refresh button requests a forced reload', (
    tester,
  ) async {
    await primeEmoteImages(tester);
    final requests = <bool>[];
    await tester.pumpWidget(
      app(
        load: ({bool refresh = false}) async {
          requests.add(refresh);
          return library;
        },
      ),
    );
    await tester.tap(find.byTooltip('Emotes'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('close-emotes')));
    await tester.pump();
    await tester.tap(find.byTooltip('Emotes'));
    await tester.pump();
    await tester.pump();
    expect(requests, [false, false]);
    await tester.tap(find.byKey(const ValueKey('refresh-emotes')));
    await tester.pump();
    await tester.pump();
    expect(requests, [false, false, true]);
  });

  testWidgets('a completed send does not erase a newer draft', (tester) async {
    final pending = Completer<SendChatResult>();
    await primeEmoteImages(tester);
    await tester.pumpWidget(app(onSend: (_) => pending.future));
    await tester.enterText(messageInput, 'first');
    await tester.tap(find.byTooltip('Send'));
    await tester.pump();
    await tester.enterText(messageInput, 'next draft');
    pending.complete(sent);
    await tester.pump();
    expect(
      tester.widget<TextField>(messageInput).controller!.text,
      'next draft',
    );
  });

  testWidgets('locking the overlay discards a pending emote panel', (
    tester,
  ) async {
    final pending = Completer<List<TwitchEmote>>();
    await primeEmoteImages(tester);
    await tester.pumpWidget(
      app(load: ({bool refresh = false}) => pending.future),
    );
    await tester.tap(find.byTooltip('Emotes'));
    await tester.pump();
    await tester.pumpWidget(app(interactive: false));
    pending.complete(library);
    await tester.pump();
    expect(find.byKey(const ValueKey('chat-emote-picker')), findsNothing);
    expect(find.byType(ChatComposer), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Widget app({
  double width = 400,
  double height = 440,
  bool interactive = true,
  Future<List<TwitchEmote>> Function({bool refresh})? load,
  Future<void> Function()? authorize,
  Future<SendChatResult> Function(String)? onSend,
}) => MaterialApp(
  scrollBehavior: const MaterialScrollBehavior().copyWith(scrollbars: false),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData.dark(),
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: height,
        child: ChatPanel(
          authState: TwitchAuthState(
            status: TwitchAuthStatus.signedIn,
            token: TwitchToken(
              accessToken: 'fixture',
              refreshToken: 'fixture',
              clientId: 'client',
              userId: 'sender',
              userLogin: 'sender',
              scopes: TwitchAuthClient.authorizationScopes,
              expiresAt: DateTime.utc(2030),
            ),
          ),
          chatState: const ChatState(
            status: ChatConnectionStatus.connected,
            items: [],
          ),
          interactive: interactive,
          onSignIn: authorize ?? () async {},
          onSignOut: () async {},
          onSend: onSend ?? (_) async => sent,
          onLoadEmotes: load ?? ({bool refresh = false}) async => library,
        ),
      ),
    ),
  ),
);

Future<void> primeEmoteImages(WidgetTester tester) async {
  final keepAlives = <ImageStreamCompleterHandle>[];
  for (final imageUrl in library.map((emote) => emote.imageUrl).toSet()) {
    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawCircle(
        const Offset(14, 14),
        12,
        Paint()..color = const Color(0xFFBF94FF),
      );
      canvas.drawCircle(const Offset(10, 11), 2, Paint());
      canvas.drawCircle(const Offset(18, 11), 2, Paint());
      final picture = recorder.endRecording();
      final image = await picture.toImage(28, 28);
      picture.dispose();
      return image;
    });
    final completer = OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: image!)),
    );
    keepAlives.add(completer.keepAlive());
    PaintingBinding.instance.imageCache.putIfAbsent(
      CachedNetworkImageProvider(imageUrl),
      () => completer,
    );
  }
  addTearDown(() {
    for (final keepAlive in keepAlives) {
      keepAlive.dispose();
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}
