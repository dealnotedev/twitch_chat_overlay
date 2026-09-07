import 'dart:ui';

import 'package:twitch_chat_overlay/chat/gif_playback.dart';

import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';

enum ResizeHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left,
}

/// The chat rectangle expressed as fractions of the fullscreen overlay host.
final class OverlayLayout {
  const OverlayLayout({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.backgroundOpacity = defaultBackgroundOpacity,
    this.messageLifetimeMinutes = ChatMessageRetention.defaultMinutes,
    this.gifPlayCount = GifPlayback.defaultCount,
  });

  const OverlayLayout.defaults()
    : left = 0.69,
      top = 0.08,
      width = 0.28,
      height = 0.72,
      backgroundOpacity = defaultBackgroundOpacity,
      messageLifetimeMinutes = ChatMessageRetention.defaultMinutes,
      gifPlayCount = GifPlayback.defaultCount;

  static const double defaultBackgroundOpacity = 0.85;
  static const double minimumWidth = 320;
  static const double minimumHeight = 220;

  final double left;
  final double top;
  final double width;
  final double height;
  final double backgroundOpacity;
  final int messageLifetimeMinutes;
  final int gifPlayCount;

  OverlayLayout withMessageLifetimeMinutes(int value) => OverlayLayout(
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    gifPlayCount: gifPlayCount,
    messageLifetimeMinutes: value.clamp(
      ChatMessageRetention.minimumMinutes,
      ChatMessageRetention.maximumMinutes,
    ),
  );

  OverlayLayout withBackgroundOpacity(double value) => OverlayLayout(
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: value.clamp(0.0, 1.0),
    gifPlayCount: gifPlayCount,
    messageLifetimeMinutes: messageLifetimeMinutes,
  );

  OverlayLayout withGifPlayCount(int value) => OverlayLayout(
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: value.clamp(
      GifPlayback.unlimitedCount,
      GifPlayback.maximumCount,
    ),
  );

  Rect resolve(Size viewport) {
    if (viewport.isEmpty) return Rect.zero;
    return _clamp(
      Rect.fromLTWH(
        left * viewport.width,
        top * viewport.height,
        width * viewport.width,
        height * viewport.height,
      ),
      viewport,
    );
  }

  OverlayLayout moveBy(Offset delta, Size viewport) {
    return _fromRect(resolve(viewport).shift(delta), viewport);
  }

  OverlayLayout resizeBy(ResizeHandle handle, Offset delta, Size viewport) {
    final current = resolve(viewport);
    var left = current.left;
    var top = current.top;
    var right = current.right;
    var bottom = current.bottom;

    switch (handle) {
      case ResizeHandle.topLeft:
        left += delta.dx;
        top += delta.dy;
        break;
      case ResizeHandle.top:
        top += delta.dy;
        break;
      case ResizeHandle.topRight:
        right += delta.dx;
        top += delta.dy;
        break;
      case ResizeHandle.right:
        right += delta.dx;
        break;
      case ResizeHandle.bottomRight:
        right += delta.dx;
        bottom += delta.dy;
        break;
      case ResizeHandle.bottom:
        bottom += delta.dy;
        break;
      case ResizeHandle.bottomLeft:
        left += delta.dx;
        bottom += delta.dy;
        break;
      case ResizeHandle.left:
        left += delta.dx;
        break;
    }

    if (right - left < minimumWidth) {
      if (_movesLeft(handle)) {
        left = right - minimumWidth;
      } else {
        right = left + minimumWidth;
      }
    }
    if (bottom - top < minimumHeight) {
      if (_movesTop(handle)) {
        top = bottom - minimumHeight;
      } else {
        bottom = top + minimumHeight;
      }
    }

    return _fromRect(Rect.fromLTRB(left, top, right, bottom), viewport);
  }

  OverlayLayout _fromRect(Rect rect, Size viewport) {
    if (viewport.isEmpty) return this;
    final clamped = _clamp(rect, viewport);
    return OverlayLayout(
      left: clamped.left / viewport.width,
      top: clamped.top / viewport.height,
      width: clamped.width / viewport.width,
      height: clamped.height / viewport.height,
      backgroundOpacity: backgroundOpacity,
      gifPlayCount: gifPlayCount,
      messageLifetimeMinutes: messageLifetimeMinutes,
    );
  }

  static Rect _clamp(Rect rect, Size viewport) {
    final minWidth = minimumWidth.clamp(0, viewport.width).toDouble();
    final minHeight = minimumHeight.clamp(0, viewport.height).toDouble();
    final width = rect.width.clamp(minWidth, viewport.width).toDouble();
    final height = rect.height.clamp(minHeight, viewport.height).toDouble();
    final left = rect.left.clamp(0, viewport.width - width).toDouble();
    final top = rect.top.clamp(0, viewport.height - height).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }

  static bool _movesLeft(ResizeHandle handle) {
    return switch (handle) {
      ResizeHandle.topLeft ||
      ResizeHandle.left ||
      ResizeHandle.bottomLeft => true,
      _ => false,
    };
  }

  static bool _movesTop(ResizeHandle handle) {
    return switch (handle) {
      ResizeHandle.topLeft || ResizeHandle.top || ResizeHandle.topRight => true,
      _ => false,
    };
  }
}
