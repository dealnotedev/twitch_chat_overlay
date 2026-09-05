import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';

void main() {
  const viewport = Size(1920, 1080);

  test('default layout resolves inside the viewport', () {
    final rect = const OverlayLayout.defaults().resolve(viewport);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(viewport.width));
    expect(rect.bottom, lessThanOrEqualTo(viewport.height));
  });

  test('moving clamps the chat window to the viewport', () {
    final moved = const OverlayLayout.defaults().moveBy(
      const Offset(10000, 10000),
      viewport,
    );
    final rect = moved.resolve(viewport);
    expect(rect.right, viewport.width);
    expect(rect.bottom, viewport.height);
  });

  test('resizing never goes below the minimum size', () {
    final resized = const OverlayLayout.defaults().resizeBy(
      ResizeHandle.bottomRight,
      const Offset(-10000, -10000),
      viewport,
    );
    final rect = resized.resolve(viewport);
    expect(rect.width, closeTo(OverlayLayout.minimumWidth, 0.0001));
    expect(rect.height, closeTo(OverlayLayout.minimumHeight, 0.0001));
  });

  test('normalized layout follows a resolution change', () {
    const layout = OverlayLayout(left: 0.5, top: 0.25, width: 0.4, height: 0.5);
    expect(
      layout.resolve(const Size(1000, 800)),
      const Rect.fromLTWH(500, 200, 400, 400),
    );
    expect(
      layout.resolve(const Size(2000, 1600)),
      const Rect.fromLTWH(1000, 400, 800, 800),
    );
  });
}
