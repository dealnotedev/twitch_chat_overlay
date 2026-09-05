import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

void main() {
  for (final animated in [false, true]) {
    testWidgets(
      'only the last repeated emote becomes giant (animated: $animated)',
      (tester) async {
        final message = _message(animated: animated);
        await _primeImages(tester, message);
        await tester.pumpWidget(_app(message));
        await tester.pumpAndSettle();
        final images = find.byType(CachedNetworkImage);
        expect(images, findsNWidgets(2));
        final normal = tester.widget<CachedNetworkImage>(images.at(0));
        final giant = tester.widget<CachedNetworkImage>(images.at(1));
        final format = animated ? 'animated' : 'static';
        expect(normal.imageUrl, endsWith('/$format/dark/2.0'));
        expect(giant.imageUrl, endsWith('/$format/dark/3.0'));
        expect(tester.getSize(images.at(0)), const Size(28, 28));
        expect(tester.getSize(images.at(1)), const Size(112, 112));
        expect(giant.fit, BoxFit.contain);
        expect(
          tester.getTopLeft(images.at(1)).dy,
          greaterThan(
            tester
                .getBottomLeft(find.textContaining('After', findRichText: true))
                .dy,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('ordinary messages keep all emotes inline at normal size', (
    tester,
  ) async {
    final message = _message(type: 'text');
    await _primeImages(tester, message);
    await tester.pumpWidget(_app(message));
    await tester.pumpAndSettle();
    expect(find.byType(ChatGiantEmoteImage), findsNothing);
    final images = find.byType(CachedNetworkImage);
    expect(images, findsNWidgets(2));
    for (final element in images.evaluate()) {
      final image = element.widget as CachedNetworkImage;
      expect(image.imageUrl, endsWith('/static/dark/2.0'));
      expect(tester.getSize(find.byWidget(image)), const Size(28, 28));
    }
  });

  testWidgets(
    'giant emote fits a narrow message and reserves its loading space',
    (tester) async {
      final message = _message();
      await _primeImages(tester, message);
      await tester.pumpWidget(_app(message, width: 90));
      await tester.pumpAndSettle();
      final content = tester.getRect(find.byType(ChatMessageContent));
      final giant = find.descendant(
        of: find.byType(ChatGiantEmoteImage),
        matching: find.byType(CachedNetworkImage),
      );
      final rect = tester.getRect(giant);
      expect(rect.width, content.width);
      expect(rect.height, rect.width);
      expect(rect.left, greaterThanOrEqualTo(content.left));
      expect(rect.right, lessThanOrEqualTo(content.right));
      final image = tester.widget<CachedNetworkImage>(giant);
      expect(
        image.placeholder!(tester.element(giant), image.imageUrl),
        isA<SizedBox>(),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('power-up without an emote preserves the message text', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_message(emotes: false)));
    await tester.pumpAndSettle();
    expect(find.byType(ChatGiantEmoteImage), findsNothing);
    expect(find.textContaining('Before', findRichText: true), findsOneWidget);
    expect(find.textContaining('After', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

ChatUserMessage _message({
  String type = 'power_ups_gigantified_emote',
  bool animated = false,
  bool emotes = true,
}) {
  Map<String, Object?> emote() => {
    'type': 'emote',
    'text': 'Kappa',
    'emote': {
      'id': '25',
      'format': ['static', if (animated) 'animated'],
    },
  };
  final mutation = const TwitchChatEventMapper().map({
    'metadata': {'subscription_type': 'channel.chat.message'},
    'payload': {
      'event': {
        'message_id': 'giant-message',
        'chatter_user_id': 'viewer',
        'chatter_user_name': 'Viewer',
        'message_type': type,
        'message': {
          'fragments': [
            {'type': 'text', 'text': 'Before '},
            if (emotes) emote(),
            {'type': 'text', 'text': ' middle '},
            if (emotes) emote(),
            {'type': 'text', 'text': ' After'},
          ],
        },
      },
    },
  });
  return (mutation as AddChatItem).item as ChatUserMessage;
}

Widget _app(ChatUserMessage message, {double width = 320}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: width,
        height: 500,
        child: ChatPanel(
          authState: const TwitchAuthState(status: TwitchAuthStatus.signedIn),
          chatState: ChatState(
            status: ChatConnectionStatus.connected,
            items: [message],
          ),
          interactive: false,
          onSignIn: () async {},
          onSignOut: () async {},
          onSend: (_, {String? replyTo}) async =>
              throw StateError('Sending is not used in this test'),
          onLoadEmotes: ({bool refresh = false}) async => [],
        ),
      ),
    ),
  ),
);

Future<void> _primeImages(WidgetTester tester, ChatUserMessage message) async {
  final urls = {
    for (final emote in message.fragments.whereType<ChatEmoteFragment>()) ...[
      emote.imageUrl,
      emote.giantImageUrl,
    ],
  };
  final keepAlives = <ImageStreamCompleterHandle>[];
  for (final url in urls) {
    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawCircle(
        const Offset(14, 14),
        12,
        Paint()..color = const Color(0xFFBF94FF),
      );
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
      CachedNetworkImageProvider(url),
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
