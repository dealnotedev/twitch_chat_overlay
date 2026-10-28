import 'dart:ui';

import 'package:twitch_chat_overlay/platform/overlay_display.dart';

import 'package:twitch_chat_overlay/emotes/emote_options.dart';

import 'package:twitch_chat_overlay/chat/chat_font_weight.dart';

import 'package:twitch_chat_overlay/chat/chat_font_size.dart';

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

/// Fractions of the selected monitor, or of the host for legacy layouts.
final class OverlayLayout {
  const OverlayLayout({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.monitorId,
    this.backgroundOpacity = defaultBackgroundOpacity,
    this.contentOpacity = defaultContentOpacity,
    this.messageLifetimeMinutes = ChatMessageRetention.defaultMinutes,
    this.gifPlayCount = GifPlayback.defaultCount,
    this.chatFontSize = ChatFontSize.defaultSize,
    this.chatFontWeight = ChatFontWeight.defaultWeight,
    this.showViewerCount = true,
    this.showConnectionIndicator = true,
    this.newChatterNotifications = false,
    this.excludedFromCapture = false,
    this.emoteOptions = const ThirdPartyEmoteOptions(),
  });

  const OverlayLayout.defaults()
    : monitorId = null,
      left = 0.69,
      top = 0.08,
      width = 0.28,
      height = 0.72,
      backgroundOpacity = defaultBackgroundOpacity,
      contentOpacity = defaultContentOpacity,
      messageLifetimeMinutes = ChatMessageRetention.defaultMinutes,
      gifPlayCount = GifPlayback.defaultCount,
      chatFontSize = ChatFontSize.defaultSize,
      chatFontWeight = ChatFontWeight.defaultWeight,
      showViewerCount = true,
      showConnectionIndicator = true,
      newChatterNotifications = false,
      excludedFromCapture = false,
      emoteOptions = const ThirdPartyEmoteOptions();

  static const double defaultContentOpacity = 1.0;
  static const double defaultBackgroundOpacity = 0.85;
  static const double minimumWidth = 320;
  static const double minimumHeight = 220;

  final double left;
  final double top;
  final double width;
  final double height;
  final String? monitorId;
  final double backgroundOpacity;
  final double contentOpacity;
  final int messageLifetimeMinutes;
  final int gifPlayCount;
  final double chatFontSize;
  final int chatFontWeight;
  final bool showViewerCount;
  final bool showConnectionIndicator;
  final bool newChatterNotifications;
  final bool excludedFromCapture;
  final ThirdPartyEmoteOptions emoteOptions;

  OverlayLayout withNewChatterNotifications(bool value) => OverlayLayout(
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: gifPlayCount,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    newChatterNotifications: value,
  );

  OverlayLayout withEmoteOptions(ThirdPartyEmoteOptions value) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: gifPlayCount,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
    emoteOptions: value,
  );

  OverlayLayout withExcludedFromCapture(bool value) => OverlayLayout(
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: gifPlayCount,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
    emoteOptions: emoteOptions,
    excludedFromCapture: value,
  );

  OverlayLayout withVisibleComponents({
    bool? showViewerCount,
    bool? showConnectionIndicator,
  }) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: gifPlayCount,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    showViewerCount: showViewerCount ?? this.showViewerCount,
    showConnectionIndicator:
        showConnectionIndicator ?? this.showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
  );

  OverlayLayout withChatFontWeight(int value) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: gifPlayCount,
    chatFontSize: chatFontSize,
    chatFontWeight: ChatFontWeight.normalize(value),
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
  );

  OverlayLayout withChatFontSize(double value) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: gifPlayCount,
    chatFontSize: ChatFontSize.normalize(value),
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
    chatFontWeight: chatFontWeight,
  );

  OverlayLayout withMessageLifetimeMinutes(int value) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    gifPlayCount: gifPlayCount,
    messageLifetimeMinutes: value.clamp(
      ChatMessageRetention.minimumMinutes,
      ChatMessageRetention.maximumMinutes,
    ),
  );

  OverlayLayout withBackgroundOpacity(double value) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: value.clamp(0.0, 1.0),
    contentOpacity: contentOpacity,
    gifPlayCount: gifPlayCount,
    messageLifetimeMinutes: messageLifetimeMinutes,
  );

  OverlayLayout withContentOpacity(double value) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: value.isFinite
        ? value.clamp(0.0, 1.0)
        : defaultContentOpacity,
    gifPlayCount: gifPlayCount,
    messageLifetimeMinutes: messageLifetimeMinutes,
  );

  OverlayLayout withGifPlayCount(int value) => OverlayLayout(
    excludedFromCapture: excludedFromCapture,
    emoteOptions: emoteOptions,
    showViewerCount: showViewerCount,
    showConnectionIndicator: showConnectionIndicator,
    newChatterNotifications: newChatterNotifications,
    chatFontSize: chatFontSize,
    chatFontWeight: chatFontWeight,
    monitorId: monitorId,
    left: left,
    top: top,
    width: width,
    height: height,
    backgroundOpacity: backgroundOpacity,
    contentOpacity: contentOpacity,
    messageLifetimeMinutes: messageLifetimeMinutes,
    gifPlayCount: value.clamp(
      GifPlayback.unlimitedCount,
      GifPlayback.maximumCount,
    ),
  );

  Rect resolve(Size viewport, {OverlayDisplay? display}) {
    if (viewport.isEmpty) return Rect.zero;
    final monitor = monitorId != null && display != null
        ? display.logicalBounds(display.monitorForId(monitorId!))
        : Offset.zero & viewport;
    return _clamp(
      Rect.fromLTWH(
        monitor.left + left * monitor.width,
        monitor.top + top * monitor.height,
        width * monitor.width,
        height * monitor.height,
      ),
      viewport,
    );
  }

  // Adopt the current placement once for settings saved before monitor anchoring.
  OverlayLayout anchorToDisplay(OverlayDisplay display) => monitorId != null
      ? this
      : _fromRect(resolve(display.logicalSize), display.logicalSize, display);

  OverlayLayout moveBy(Offset delta, Size viewport, {OverlayDisplay? display}) {
    return _fromRect(
      resolve(viewport, display: display).shift(delta),
      viewport,
      display,
    );
  }

  OverlayLayout resizeBy(
    ResizeHandle handle,
    Offset delta,
    Size viewport, {
    OverlayDisplay? display,
  }) {
    final current = resolve(viewport, display: display);
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

    return _fromRect(
      Rect.fromLTRB(left, top, right, bottom),
      viewport,
      display,
    );
  }

  OverlayLayout _fromRect(Rect rect, Size viewport, OverlayDisplay? display) {
    if (viewport.isEmpty) return this;
    final clamped = _clamp(rect, viewport);
    final monitor = display?.monitorForRect(clamped);
    final reference = monitor != null
        ? display!.logicalBounds(monitor)
        : Offset.zero & viewport;
    return OverlayLayout(
      monitorId: monitor?.id ?? monitorId,
      excludedFromCapture: excludedFromCapture,
      emoteOptions: emoteOptions,
      showViewerCount: showViewerCount,
      showConnectionIndicator: showConnectionIndicator,
      newChatterNotifications: newChatterNotifications,
      chatFontSize: chatFontSize,
      chatFontWeight: chatFontWeight,
      left: (clamped.left - reference.left) / reference.width,
      top: (clamped.top - reference.top) / reference.height,
      width: clamped.width / reference.width,
      height: clamped.height / reference.height,
      backgroundOpacity: backgroundOpacity,
      contentOpacity: contentOpacity,
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
