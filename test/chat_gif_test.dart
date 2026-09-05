import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';

const _url =
    'https://media4.giphy.com/media/test/giphy.gif?cid=test&rid=giphy.gif&ct=g';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const mapper = TwitchChatEventMapper();

  for (final idField in ['gif_id', 'id']) {
    test('accepts $idField and preserves the complete GIF URL', () {
      final item =
          (mapper.map(
                _event({idField: 'gif-1', 'url': _url}),
              ) as AddChatItem).item
              as ChatUserMessage;
      final gif = item.fragments[1] as ChatGifFragment;
      expect(gif.id, 'gif-1');
      expect(gif.url, _url);
      expect(gif.text, '[Celebration GIF]');
      expect(item.sourceChannel, 'Partner');
      final timeline = ChatTimeline();
      timeline.apply(AddChatItem(item));
      timeline.apply(const DeleteChatMessage('message-1'));
      expect(timeline.items, isEmpty);
    });
  }

  for (final payload in <Map<String, Object?>>[
    {'gif_id': 'gif-1', 'url': ''},
    {'gif_id': 'gif-1'},
    {'url': _url},
    {'gif_id': 'gif-1', 'url': 'not a URL'},
  ]) {
    test('invalid GIF preserves text: $payload', () {
      final item =
          (mapper.map(_event(payload)) as AddChatItem).item as ChatUserMessage;
      expect(item.fragments[1], isA<ChatUnknownFragment>());
      expect(item.fragments[1].text, '[Celebration GIF]');
    });
  }

  testWidgets('GIF animates in a constrained block and text stays in order', (
    tester,
  ) async {
    final frames = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(_animatedGif);
      expect(codec.frameCount, 2);
      final frames = [await codec.getNextFrame(), await codec.getNextFrame()];
      codec.dispose();
      return frames;
    });
    final completer = MultiFrameImageStreamCompleter(
      codec: Future.value(_DecodedGifCodec(frames!)),
      scale: 1,
    );
    final keepAlive = completer.keepAlive();
    PaintingBinding.instance.imageCache.putIfAbsent(
      const CachedNetworkImageProvider(_url),
      () => completer,
    );
    var frameCount = 0;
    final listener = ImageStreamListener((image, synchronousCall) {
      frameCount++;
      image.dispose();
    });
    completer.addListener(listener);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uk'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: ChatMessageContent(
              prefix: [TextSpan(text: 'Viewer: ')],
              style: TextStyle(fontSize: 13),
              fragments: [
                ChatTextFragment(text: 'Before'),
                ChatGifFragment(
                  text: '[Celebration GIF]',
                  id: 'gif-1',
                  url: _url,
                ),
                ChatTextFragment(text: 'After'),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final gif = find.byType(CachedNetworkImage);
    expect(tester.getSize(gif), const Size(180, 120));
    expect(tester.widget<CachedNetworkImage>(gif).fit, BoxFit.contain);
    expect(
      tester.getTopLeft(find.text('Viewer: Before', findRichText: true)).dy,
      lessThan(tester.getTopLeft(gif).dy),
    );
    expect(
      tester.getTopLeft(find.text('After', findRichText: true)).dy,
      greaterThan(tester.getBottomLeft(gif).dy),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 120));
    expect(frameCount, greaterThan(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    completer.removeListener(listener);
    keepAlive.dispose();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });
}

Map<String, Object?> _event(Map<String, Object?> gif) => {
  'metadata': {'subscription_type': 'channel.chat.message'},
  'payload': {
    'event': {
      'message_id': 'message-1',
      'chatter_user_id': 'viewer',
      'chatter_user_name': 'Viewer',
      'source_broadcaster_user_name': 'Partner',
      'message': {
        'fragments': [
          {'type': 'text', 'text': 'Before'},
          {'type': 'gif', 'text': '[Celebration GIF]', 'gif': gif},
          {'type': 'text', 'text': 'After'},
        ],
      },
    },
  },
};

// Decode real GIF bytes first, then replay frames under the widget test clock.
class _DecodedGifCodec implements ui.Codec {
  _DecodedGifCodec(this.frames);

  final List<ui.FrameInfo> frames;
  int next = 0;

  @override
  int get frameCount => frames.length;
  @override
  int get repetitionCount => -1;
  @override
  void dispose() {
    for (final frame in frames) {
      frame.image.dispose();
    }
  }

  @override
  Future<ui.FrameInfo> getNextFrame() async {
    final frame = frames[next++ % frames.length];
    return _GifFrame(frame.image.clone(), frame.duration);
  }
}

class _GifFrame implements ui.FrameInfo {
  _GifFrame(this.image, this.duration);
  @override
  final ui.Image image;
  @override
  final Duration duration;
}

// Original 1×1 GIF89a fixture: two frames (red/blue), 100 ms each, loop forever.
final _animatedGif = Uint8List.fromList([
  71,
  73,
  70,
  56,
  57,
  97,
  1,
  0,
  1,
  0,
  128,
  0,
  0,
  255,
  0,
  0,
  0,
  0,
  255,
  33,
  255,
  11,
  78,
  69,
  84,
  83,
  67,
  65,
  80,
  69,
  50,
  46,
  48,
  3,
  1,
  0,
  0,
  0,
  33,
  249,
  4,
  0,
  10,
  0,
  0,
  0,
  44,
  0,
  0,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  2,
  2,
  68,
  1,
  0,
  33,
  249,
  4,
  0,
  10,
  0,
  0,
  0,
  44,
  0,
  0,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  2,
  2,
  76,
  1,
  0,
  59,
]);
