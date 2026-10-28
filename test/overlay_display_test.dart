import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/platform/overlay_display.dart';

const _primary = OverlayMonitor(
  id: 'primary',
  bounds: Rect.fromLTWH(0, 0, 1920, 1080),
  primary: true,
);
const _single = OverlayDisplay(
  bounds: Rect.fromLTWH(0, 0, 1920, 1080),
  scale: 1,
  monitors: [_primary],
);

OverlayDisplay _dual(Offset secondary, {double scale = 1}) => OverlayDisplay(
  bounds: _primary.bounds.expandToInclude(secondary & const Size(1920, 1080)),
  scale: scale,
  monitors: [
    _primary,
    OverlayMonitor(id: 'secondary', bounds: secondary & const Size(1920, 1080)),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('legacy geometry adopts its current monitor without moving', () {
    final display = _dual(const Offset(-1920, 0));
    const legacy = OverlayLayout(left: .7, top: .1, width: .2, height: .6);
    final anchored = legacy.anchorToDisplay(display);
    expect(anchored.monitorId, 'primary');
    expect(
      anchored.resolve(display.logicalSize, display: display),
      legacy.resolve(display.logicalSize),
    );
  });

  for (final secondary in [
    const Offset(1920, 0),
    const Offset(-1920, 0),
    const Offset(0, -1080),
    const Offset(0, 1080),
  ]) {
    test('adding and removing a monitor at $secondary preserves placement', () {
      final layout = const OverlayLayout.defaults().anchorToDisplay(_single);
      final before = layout.resolve(_single.logicalSize, display: _single);
      final dual = _dual(secondary);
      final after = layout.resolve(dual.logicalSize, display: dual);
      expect(after.shift(dual.bounds.topLeft), rectMoreOrLessEquals(before));
      expect(
        layout
            .anchorToDisplay(dual)
            .resolve(_single.logicalSize, display: _single),
        rectMoreOrLessEquals(before),
      );
    });
  }

  test('host DPI changes preserve the physical chat rectangle', () {
    final layout = const OverlayLayout.defaults().anchorToDisplay(_single);
    final before = layout.resolve(_single.logicalSize, display: _single);
    final display = _dual(const Offset(-1920, 0), scale: 1.5);
    final logical = layout.resolve(display.logicalSize, display: display);
    final physical = Rect.fromLTWH(
      display.bounds.left + logical.left * display.scale,
      display.bounds.top + logical.top * display.scale,
      logical.width * display.scale,
      logical.height * display.scale,
    );
    expect(physical, rectMoreOrLessEquals(before));
  });

  test(
    'dragging to a second monitor updates and persists the anchor',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesOverlayLayoutStore();
      final display = _dual(const Offset(1920, 0));
      final layout = const OverlayLayout.defaults()
          .anchorToDisplay(_single)
          .moveBy(const Offset(1920, 0), display.logicalSize, display: display)
          .resizeBy(
            ResizeHandle.bottom,
            const Offset(0, -50),
            display.logicalSize,
            display: display,
          )
          .withContentOpacity(.5)
          .withBackgroundOpacity(.4)
          .withGifPlayCount(2)
          .withMessageLifetimeMinutes(10)
          .withChatFontSize(18)
          .withChatFontWeight(500)
          .withVisibleComponents(showViewerCount: false)
          .withNewChatterNotifications(true)
          .withEmoteOptions(const OverlayLayout.defaults().emoteOptions)
          .withExcludedFromCapture(true);
      expect(layout.monitorId, 'secondary');
      await store.save(layout);
      final restored = await store.load();
      expect(restored.monitorId, 'secondary');
      expect(
        restored.resolve(display.logicalSize, display: display),
        layout.resolve(display.logicalSize, display: display),
      );

      // The unavailable monitor's placement remains saved, while chat stays visible.
      final fallback = restored.resolve(_single.logicalSize, display: _single);
      expect(fallback.left, greaterThanOrEqualTo(0));
      expect(fallback.right, lessThanOrEqualTo(1920));
      expect(restored.monitorId, 'secondary');
      expect(
        restored.resolve(display.logicalSize, display: display).left,
        greaterThan(1920),
      );
    },
  );

  test('monitor resolution changes retain proportional placement', () {
    const display = OverlayDisplay(
      bounds: Rect.fromLTWH(0, 0, 2560, 1440),
      scale: 1,
      monitors: [
        OverlayMonitor(
          id: 'primary',
          bounds: Rect.fromLTWH(0, 0, 2560, 1440),
          primary: true,
        ),
      ],
    );
    final layout = const OverlayLayout(
      left: .5,
      top: .25,
      width: .4,
      height: .5,
    ).anchorToDisplay(_single);
    expect(
      layout.resolve(display.logicalSize, display: display),
      const Rect.fromLTWH(1280, 360, 1024, 720),
    );
  });

  test('invalid or transient empty native display data is ignored', () {
    for (final raw in [
      null,
      {},
      {'left': 0, 'top': 0, 'width': 1920, 'height': 1080, 'scale': 0},
      {
        'left': 0,
        'top': 0,
        'width': 1920,
        'height': 1080,
        'scale': 1,
        'monitors': [],
      },
    ]) {
      expect(OverlayDisplay.fromNative(raw), isNull);
    }
  });
}
