import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';

void main() {
  const viewport = Size(1920, 1080);

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'content opacity persists through other settings and geometry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesOverlayLayoutStore();
      expect((await store.load()).contentOpacity, 1);
      final layout = const OverlayLayout.defaults()
          .withContentOpacity(0.35)
          .withBackgroundOpacity(0.2)
          .withMessageLifetimeMinutes(5)
          .withGifPlayCount(3)
          .moveBy(const Offset(20, 20), viewport)
          .resizeBy(ResizeHandle.bottomRight, const Offset(20, 20), viewport);
      await store.save(layout);
      final loaded = await store.load();
      expect(loaded.contentOpacity, 0.35);
      expect(loaded.backgroundOpacity, 0.2);
      expect(loaded.messageLifetimeMinutes, 5);
      expect(loaded.gifPlayCount, 3);
    },
  );

  test(
    'content opacity loads without geometry and handles invalid values',
    () async {
      final store = SharedPreferencesOverlayLayoutStore();
      for (final entry in {
        -1.0: 0.0,
        2.0: 1.0,
        0.4: 0.4,
        double.nan: 1.0,
      }.entries) {
        SharedPreferences.setMockInitialValues({
          'overlay.content.opacity': entry.key,
        });
        expect((await store.load()).contentOpacity, entry.value);
      }
    },
  );

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
