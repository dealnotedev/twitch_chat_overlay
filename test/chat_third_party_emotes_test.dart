import 'package:observable_state/observable_state.dart';

import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/chat_emote_picker.dart';
import 'package:twitch_chat_overlay/chat/chat_emote_scope.dart';
import 'package:twitch_chat_overlay/chat/chat_gif_provider.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';
import 'package:twitch_chat_overlay/chat/gif_playback.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

const wide = ChatEmote(
  id: '1',
  name: 'Wide',
  imageUrl: 'https://example.com/wide.webp',
  provider: EmoteProvider.sevenTv,
  aspectRatio: 2,
);
const dance = ChatEmote(
  id: '1',
  name: 'Dance',
  imageUrl: 'https://example.com/dance.gif',
  provider: EmoteProvider.betterTtv,
  animated: true,
);
const native = ChatEmoteFragment(text: 'Kappa', id: '25', animated: false);

void main() {
  testWidgets(
    'late catalog updates live and historical rows without changing their text',
    (tester) async {
      await prime(tester);
      final items = [message('live'), message('history', historical: true)];
      Widget app(EmoteCatalog catalog) => shell(
        SizedBox(
          width: 320,
          height: 400,
          child: ChatPanel(
            authSource: StreamWithInitial.value(
              const TwitchAuthState(status: TwitchAuthStatus.signedIn),
            ),
            chatSource: StreamWithInitial.value(
              ChatState(
                status: ChatConnectionStatus.connected,
                items: items,
                emoteCatalog: catalog,
              ),
            ),
            interactive: false,
            onSignIn: () async {},
            onSignOut: () async {},
            onSend: (_, {String? replyTo}) async => throw UnimplementedError(),
            onLoadEmotes: ({bool refresh = false}) async => [],
          ),
        ),
      );
      await tester.pumpWidget(app(const EmoteCatalog.empty()));
      expect(
        find.textContaining('Wide Dance', findRichText: true),
        findsNWidgets(2),
      );
      await tester.pumpWidget(app(EmoteCatalog([wide, dance])));
      await tester.pumpAndSettle();
      for (
        var i = 0;
        i < 100 &&
            tester
                .widgetList<RawImage>(find.byType(RawImage))
                .any((image) => image.image == null);
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final images = find.byType(Image);
      expect(images, findsNWidgets(4));
      final wideImages = find.byWidgetPredicate(
        (w) => w is Image && w.image is CachedNetworkImageProvider,
      );
      expect(tester.getSize(wideImages.first), const Size(56, 28));
      final animatedImages = find.byWidgetPredicate(
        (w) => w is Image && w.image is ChatGifProvider,
      );
      expect(tester.getSize(animatedImages.first), const Size(84, 28));
      expect(
        (tester.widget<Image>(animatedImages.first).image as ChatGifProvider)
            .playCount,
        0,
      );
      expect(
        items.every((item) => item.fragments.single.text == 'Wide Dance'),
        isTrue,
      );
      await tester.pumpWidget(app(const EmoteCatalog.empty()));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(
        find.textContaining('Wide Dance', findRichText: true),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a third-party emote after a Twitch emote does not steal its giant effect',
    (tester) async {
      await prime(tester);
      await tester.pumpWidget(
        shell(
          ChatEmoteScope(
            catalog: EmoteCatalog([wide]),
            child: const SizedBox(
              width: 180,
              child: ChatMessageContent(
                fragments: [
                  native,
                  ChatTextFragment(text: ' Wide'),
                ],
                gigantifyEmote: true,
                style: TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final giant = tester.widget<ChatGiantEmoteImage>(
        find.byType(ChatGiantEmoteImage),
      );
      expect(giant.fragment, same(native));
      expect(find.byType(Image), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('wide emotes fit a narrow content area', (tester) async {
    await prime(tester);
    await tester.pumpWidget(
      shell(
        ChatEmoteScope(
          catalog: EmoteCatalog([wide]),
          child: const SizedBox(
            width: 40,
            child: ChatMessageContent(
              fragments: [ChatTextFragment(text: 'Wide')],
              style: TextStyle(fontSize: 14),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Image)).width, lessThanOrEqualTo(38));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'picker separates providers, searches and selects the sendable code',
    (tester) async {
      await prime(tester);
      ChatEmote? selected;
      await tester.pumpWidget(
        shell(
          SizedBox(
            width: 320,
            height: 320,
            child: ChatEmotePicker(
              emotes: Future.value([wide, dance]),
              tapGroup: Object(),
              onSelected: (emote) => selected = emote,
              onReload: () {},
              onClose: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('7TV'), findsOneWidget);
      expect(find.text('BetterTTV'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Search emotes'),
        'dance',
      );
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('emote-${wide.key}')), findsNothing);
      await tester.tap(find.byKey(ValueKey('emote-${dance.key}')));
      expect(selected?.name, 'Dance');
      expect(tester.takeException(), isNull);
    },
  );
}

ChatUserMessage message(String id, {bool historical = false}) =>
    ChatUserMessage(
      id: id,
      receivedAt: DateTime.now().toUtc(),
      isHistorical: historical,
      userId: 'viewer',
      userName: 'Viewer',
      color: null,
      badges: const [],
      fragments: const [ChatTextFragment(text: 'Wide Dance')],
      messageType: 'text',
      bits: null,
      reply: null,
      sourceChannel: null,
    );

Widget shell(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Center(child: GifPlayback(playCount: 0, child: child)),
  ),
);

Future<void> prime(WidgetTester tester) async {
  final cache = _Cache();
  CachedNetworkImageProvider.defaultCacheManager = cache;
  final handles = <ImageStreamCompleterHandle>[];
  for (final (url, width) in [
    (wide.imageUrl, 56),
    (dance.imageUrl, 84),
    (native.giantImageUrl, 28),
  ]) {
    final image = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.purple, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(width, 28);
      picture.dispose();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      cache.files[url] = cache.fs.file('image-${cache.files.length}.png')
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
      return image;
    });
    final completer = OneFrameImageStreamCompleter(
      Future.value(ImageInfo(image: image!)),
    );
    handles.add(completer.keepAlive());
    PaintingBinding.instance.imageCache.putIfAbsent(
      CachedNetworkImageProvider(url),
      () => completer,
    );
  }
  addTearDown(() {
    CachedNetworkImageProvider.defaultCacheManager = _Cache();
    for (final handle in handles) {
      handle.dispose();
    }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}

class _Cache extends Fake implements BaseCacheManager {
  final fs = MemoryFileSystem();
  final files = <String, File>{};
  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async => files[url]!;
}
