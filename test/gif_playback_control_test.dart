import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/gif_playback_control.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';

void main() {
  for (final locale in ['uk', 'en']) {
    testWidgets('GIF counter supports infinity through 60 ($locale)', (
      tester,
    ) async {
      var count = const OverlayLayout.defaults().gifPlayCount;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return GifPlaybackControl(
                      playCount: count,
                      onChanged: (value) => setState(() => count = value),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final up = find.widgetWithIcon(IconButton, Icons.add_rounded);
      final down = find.widgetWithIcon(IconButton, Icons.remove_rounded);
      expect(find.text('∞'), findsOneWidget);
      expect(tester.widget<IconButton>(down).onPressed, isNull);
      await tester.tap(up);
      await tester.pump();
      expect(count, 0);
      expect(find.text('0'), findsOneWidget);
      await tester.tap(up);
      await tester.pump();
      expect(count, 1);
      expect(find.text('1'), findsOneWidget);
      await tester.tap(down);
      await tester.pump();
      expect(count, 0);
      await tester.tap(down);
      await tester.pump();
      expect(count, -1);
      expect(find.text('∞'), findsOneWidget);
      await tester.tap(up);
      await tester.pump();
      await tester.tap(up);
      await tester.pump();
      Focus.of(tester.element(find.byIcon(Icons.add_rounded))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(count, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(count, 1);
      update(() => count = 59);
      await tester.pump();
      await tester.tap(up);
      await tester.pump();
      expect(count, 60);
      expect(find.text('60'), findsOneWidget);
      expect(tester.widget<IconButton>(up).onPressed, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'GIF count defaults to infinity and survives other settings and reloads',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesOverlayLayoutStore();
      expect((await store.load()).gifPlayCount, -1);
      for (final count in [-1, 0, 1, 17, 60]) {
        final layout = const OverlayLayout.defaults()
            .withGifPlayCount(count)
            .withMessageLifetimeMinutes(13)
            .moveBy(const Offset(20, 20), const Size(1920, 1080))
            .resizeBy(
              ResizeHandle.bottomRight,
              const Offset(20, 20),
              const Size(1920, 1080),
            )
            .withBackgroundOpacity(0.4);
        await store.save(layout);
        final restored = await SharedPreferencesOverlayLayoutStore().load();
        expect(restored.gifPlayCount, count);
        expect(restored.messageLifetimeMinutes, 13);
        expect(restored.backgroundOpacity, 0.4);
      }
    },
  );

  test('GIF count without geometry is loaded and clamped', () async {
    for (final entry in {-5: -1, -1: -1, 0: 0, 120: 60, 12: 12}.entries) {
      SharedPreferences.setMockInitialValues({
        'overlay.gif.playCount': entry.key,
      });
      expect(
        (await SharedPreferencesOverlayLayoutStore().load()).gifPlayCount,
        entry.value,
      );
    }
  });
}
