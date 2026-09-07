import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/gif_playback.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';

const _url =
    'https://media4.giphy.com/media/test/giphy.gif?cid=test&rid=giphy.gif&ct=g';

void main() {
  final binding = _GifTestBinding();
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

  setUp(() async {
    final codec = await ui.instantiateImageCodec(_animatedGif);
    expect(codec.frameCount, 2);
    expect(codec.repetitionCount, -1);
    binding.frames = [await codec.getNextFrame(), await codec.getNextFrame()];
    codec.dispose();
    binding.codecs.clear();
    CachedNetworkImageProvider.defaultCacheManager = _GifCache();
  });
  tearDown(() {
    binding.imageCache.clear();
    binding.imageCache.clearLiveImages();
    for (final frame in binding.frames) {
      frame.image.dispose();
    }
  });

  testWidgets(
    'GIF plays one cycle, holds its last frame and preserves layout',
    (tester) async {
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 180,
            child: ChatMessageContent(
              prefix: [TextSpan(text: 'Viewer: ')],
              style: TextStyle(fontSize: 13),
              fragments: [
                ChatTextFragment(text: 'Before'),
                _fragment,
                ChatTextFragment(text: 'After'),
              ],
            ),
          ),
        ),
      );
      final gif = find.byType(Image);
      expect(tester.getSize(gif), const Size(180, 120));
      expect(tester.widget<Image>(gif).fit, BoxFit.contain);
      expect(
        tester.getTopLeft(find.text('Viewer: Before', findRichText: true)).dy,
        lessThan(tester.getTopLeft(gif).dy),
      );
      expect(
        tester.getTopLeft(find.text('After', findRichText: true)).dy,
        greaterThan(tester.getBottomLeft(gif).dy),
      );
      await _loaded(tester, binding, 1);
      expect(_shownImage(tester).isCloneOf(binding.frames.first.image), isTrue);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(_shownImage(tester).isCloneOf(binding.frames.last.image), isTrue);
      await tester.pump(const Duration(seconds: 10));
      expect(_shownImage(tester).isCloneOf(binding.frames.last.image), isTrue);
      expect(binding.codecs.single.next, 2);
      expect(binding.codecs.single.disposed, isTrue);
      expect(tester.getSize(gif), const Size(180, 120));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'scroll and rebuild preserve playback; new messages play separately',
    (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final ids = ['first', for (var i = 0; i < 30; i++) 'text-$i'];
      await tester.pumpWidget(_listHost(ids, scroll));
      await _loaded(tester, binding, 1);
      final firstState = tester.state(find.byType(ChatGifImage));
      final firstProvider = tester.widget<Image>(find.byType(Image)).image;
      // Scroll away during the first cycle, then return after it finishes.
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      scroll.jumpTo(0);
      await tester.pump();
      expect(tester.state(find.byType(ChatGifImage)), same(firstState));
      expect(_shownImage(tester).isCloneOf(binding.frames.last.image), isTrue);
      expect(binding.codecs, hasLength(1));

      await tester.pumpWidget(_listHost(['second', ...ids], scroll));
      await _loaded(tester, binding, 2);
      final secondImage = find.descendant(
        of: find.byKey(const ValueKey('second')),
        matching: find.byType(RawImage),
      );
      expect(
        tester
            .widget<RawImage>(secondImage)
            .image!
            .isCloneOf(binding.frames.first.image),
        isTrue,
      );
      final providers = tester
          .widgetList<Image>(find.byType(Image))
          .map((image) => image.image)
          .toList();
      expect(providers, contains(firstProvider));
      expect(providers.toSet(), hasLength(2));
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump(const Duration(seconds: 3));
      expect(binding.codecs.map((codec) => codec.next), everyElement(2));
      expect(binding.codecs.every((codec) => codec.disposed), isTrue);

      // Removing a kept-alive message must release it and its image cache entry.
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pump();
      await tester.pumpWidget(_listHost(ids.skip(1).toList(), scroll));
      await tester.pump();
      expect(firstState.mounted, isFalse);
      expect(binding.imageCache.containsKey(firstProvider), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final count in [2, 60]) {
    testWidgets('GIF stops after exactly $count complete plays', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(const ChatGifImage(fragment: _fragment), playCount: count),
      );
      await _loaded(tester, binding, 1);
      for (var i = 0; i < count * 2 + 5; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(binding.codecs.single.next, count * 2);
      expect(binding.codecs.single.disposed, isTrue);
      expect(_shownImage(tester).isCloneOf(binding.frames.last.image), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'default is unlimited and changing the setting applies to existing GIFs',
    (tester) async {
      expect(GifPlayback.defaultCount, -1);
      await tester.pumpWidget(
        _host(
          const ChatGifImage(fragment: _fragment),
          playCount: GifPlayback.defaultCount,
        ),
      );
      await _loaded(tester, binding, 1);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(binding.codecs.single.next, greaterThan(4));
      expect(binding.codecs.single.disposed, isFalse);
      await tester.pumpWidget(
        _host(const ChatGifImage(fragment: _fragment), playCount: 2),
      );
      await _loaded(tester, binding, 2);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(binding.codecs.first.disposed, isTrue);
      expect(binding.codecs.last.next, 4);
      expect(binding.codecs.last.disposed, isTrue);
      await tester.pumpWidget(
        _host(const ChatGifImage(fragment: _fragment), playCount: 2),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(binding.codecs, hasLength(2));
      expect(_shownImage(tester).isCloneOf(binding.frames.last.image), isTrue);
      await tester.pumpWidget(
        _host(const ChatGifImage(fragment: _fragment), playCount: -1),
      );
      await _loaded(tester, binding, 3);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(binding.codecs.last.next, greaterThan(4));
      expect(binding.codecs.last.disposed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(binding.codecs.last.disposed, isTrue);
    },
  );
  testWidgets(
    'zero displays only the first frame and can switch to animation',
    (tester) async {
      await tester.pumpWidget(
        _host(const ChatGifImage(fragment: _fragment), playCount: 0),
      );
      await _loaded(tester, binding, 1);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(binding.codecs.single.next, 1);
      expect(_shownImage(tester).isCloneOf(binding.frames.first.image), isTrue);
      await tester.pumpWidget(
        _host(const ChatGifImage(fragment: _fragment), playCount: 1),
      );
      await _loaded(tester, binding, 2);
      await tester.pump(const Duration(milliseconds: 120));
      await tester.pump();
      expect(binding.codecs.first.disposed, isTrue);
      expect(binding.codecs.last.next, 2);
      expect(_shownImage(tester).isCloneOf(binding.frames.last.image), isTrue);
      await tester.pumpWidget(
        _host(const ChatGifImage(fragment: _fragment), playCount: 0),
      );
      await _loaded(tester, binding, 3);
      await tester.pump(const Duration(seconds: 10));
      expect(binding.codecs.last.next, 1);
      expect(_shownImage(tester).isCloneOf(binding.frames.first.image), isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(binding.codecs.last.disposed, isTrue);
    },
  );
  testWidgets('failed GIF keeps its reserved size and fallback text', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const SizedBox(
          width: 180,
          child: ChatGifImage(
            fragment: ChatGifFragment(
              text: '[Missing GIF]',
              id: 'missing',
              url: 'https://example.com/missing.gif',
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    });
    await tester.pump();
    expect(find.textContaining('[Missing GIF]'), findsOneWidget);
    expect(tester.getSize(find.byType(Image)), const Size(180, 120));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

const _fragment = ChatGifFragment(
  text: '[Celebration GIF]',
  id: 'gif-1',
  url: _url,
);

Widget _host(Widget child, {int playCount = 1}) => MaterialApp(
  locale: const Locale('uk'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: GifPlayback(
      playCount: playCount,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

Widget _listHost(List<String> ids, ScrollController scroll) => _host(
  SizedBox(
    height: 360,
    width: 180,
    child: ListView.builder(
      controller: scroll,
      itemExtent: 200,
      scrollCacheExtent: const ScrollCacheExtent.pixels(0),
      itemCount: ids.length,
      findChildIndexCallback: (key) {
        final index = ids.indexOf((key as ValueKey<String>).value);
        return index < 0 ? null : index;
      },
      itemBuilder: (_, index) => RepaintBoundary(
        key: ValueKey(ids[index]),
        child: ids[index].startsWith('text-')
            ? Text(ids[index])
            : const ChatGifImage(fragment: _fragment),
      ),
    ),
  ),
);

ui.Image _shownImage(WidgetTester tester) =>
    tester.widget<RawImage>(find.byType(RawImage)).image!;

Future<void> _loaded(
  WidgetTester tester,
  _GifTestBinding binding,
  int count,
) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 100 && binding.codecs.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  expect(binding.codecs, hasLength(count));
  await tester.pump();
  await tester.pump();
}

class _GifCache extends Fake implements BaseCacheManager {
  final File file = MemoryFileSystem().file('animation.gif')
    ..writeAsBytesSync(_animatedGif);

  @override
  Future<File> getSingleFile(
    String url, {
    String? key,
    Map<String, String>? headers,
  }) async {
    if (url != _url) throw StateError('Image unavailable');
    return file;
  }
}

// Real GIF frames, replayed under the widget test clock after byte loading.
class _GifTestBinding extends AutomatedTestWidgetsFlutterBinding {
  List<ui.FrameInfo> frames = [];
  final List<_DecodedGifCodec> codecs = [];

  @override
  Future<ui.Codec> instantiateImageCodecWithSize(
    ui.ImmutableBuffer buffer, {
    ui.TargetImageSizeCallback? getTargetSize,
  }) async {
    buffer.dispose();
    final codec = _DecodedGifCodec([
      for (final frame in frames)
        _GifFrame(frame.image.clone(), frame.duration),
    ]);
    codecs.add(codec);
    return codec;
  }
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
  bool disposed = false;

  @override
  int get frameCount => frames.length;
  @override
  int get repetitionCount => -1;
  @override
  void dispose() {
    disposed = true;
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
