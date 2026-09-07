import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// A separate animation per occurrence, sharing only the downloaded file.
/// Keep this provider for the lifetime of its message, including offscreen rows.
class ChatGifProvider extends ImageProvider<ChatGifProvider> {
  ChatGifProvider(this.url, {required this.playCount});

  final String url;
  final int playCount;

  @override
  Future<ChatGifProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    ChatGifProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final file = await CachedNetworkImageProvider.defaultCacheManager
          .getSingleFile(url);
      final buffer = await ui.ImmutableBuffer.fromUint8List(
        await file.readAsBytes(),
      );
      return _PlaybackCodec(await decode(buffer), playCount);
    } catch (_) {
      PaintingBinding.instance.imageCache.evict(this);
      rethrow;
    }
  }
}

class _PlaybackCodec implements ui.Codec {
  _PlaybackCodec(this.delegate, this.playCount);

  final ui.Codec delegate;
  final int playCount;

  @override
  int get frameCount => playCount == 0 ? 1 : delegate.frameCount;

  @override
  int get repetitionCount => playCount < 0
      ? -1
      : playCount == 0
      ? 0
      : playCount - 1;

  @override
  Future<ui.FrameInfo> getNextFrame() => delegate.getNextFrame();

  @override
  void dispose() => delegate.dispose();
}
