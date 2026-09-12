import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/chat_font_size_control.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';

import 'chat_message_actions_test.dart' as fixtures;
import 'chat_reply_display_test.dart' as replies;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('font size survives persistence and other layout changes', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesOverlayLayoutStore();
    expect((await store.load()).chatFontSize, 13.5);
    final layout = const OverlayLayout.defaults()
        .withChatFontSize(18.75)
        .withContentOpacity(0.7)
        .withBackgroundOpacity(0.4)
        .withMessageLifetimeMinutes(5)
        .withGifPlayCount(3)
        .moveBy(const Offset(20, 20), const Size(1920, 1080))
        .resizeBy(
          ResizeHandle.bottomRight,
          const Offset(20, 20),
          const Size(1920, 1080),
        );
    await store.save(layout);
    expect((await store.load()).chatFontSize, 18.75);
  });

  test('stored font sizes are bounded and snapped to quarter pixels', () async {
    final store = SharedPreferencesOverlayLayoutStore();
    for (final entry in {
      8.0: 12.0,
      30.0: 24.0,
      15.3: 15.25,
      double.nan: 13.5,
      double.infinity: 13.5,
    }.entries) {
      SharedPreferences.setMockInitialValues({
        'overlay.messages.fontSize': entry.key,
      });
      expect((await store.load()).chatFontSize, entry.value);
    }
  });

  testWidgets('slider displays fractions and keyboard changes by 0.25', (
    tester,
  ) async {
    var size = 18.5;
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('uk'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, setState) => ChatFontSizeControl(
                  value: size,
                  onChanged: (value) => setState(() => size = value),
                  onChangeEnd: () => saved = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('18,5'), findsOneWidget);
    final slider = find.byType(Slider);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(size, 18.75);
    expect(find.text('18,75'), findsOneWidget);
    expect(tester.widget<Slider>(slider).label, '18,75');
    expect(saved, isTrue);
    await tester.drag(slider, const Offset(500, 0));
    await tester.pump();
    expect(size, 24);
    await tester.drag(slider, const Offset(-500, 0));
    await tester.pump();
    expect(size, 12);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'only timeline text scales, including replies and event captions',
    (tester) async {
      final items = [
        replies.mappedMessage([
          {'type': 'text', 'text': 'Hello'},
        ]),
        ChatRaid(
          id: 'raid',
          receivedAt: DateTime.now().toUtc(),
          userName: 'Raider',
          viewerCount: 3,
          sourceChannel: 'Source',
        ),
      ];
      List<double> effectiveSizes(Finder finder) => tester
          .widgetList<RichText>(finder)
          .map((text) => text.textScaler.scale(text.text.style!.fontSize!))
          .toList();
      final timelineText = find.descendant(
        of: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Text),
        ),
        matching: find.byType(RichText),
      );
      await tester.pumpWidget(fixtures.app(items));
      final baseSizes = effectiveSizes(timelineText);
      final inputSize = tester.getSize(fixtures.input);
      final inputScale = MediaQuery.textScalerOf(
        tester.element(fixtures.input),
      );
      expect(baseSizes, containsAll([13.5, 10.5, 11.5]));
      for (final size in [12.0, 18.75, 24.0]) {
        await tester.pumpWidget(fixtures.app(items, fontSize: size));
        final sizes = effectiveSizes(timelineText);
        expect(sizes.length, baseSizes.length);
        for (var i = 0; i < sizes.length; i++) {
          expect(sizes[i], closeTo(baseSizes[i] * size / 13.5, 0.001));
        }
        expect(tester.getSize(fixtures.input), inputSize);
        expect(
          MediaQuery.textScalerOf(tester.element(fixtures.input)),
          inputScale,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        fixtures.app(items, fontSize: 24, interactive: false),
      );
      final status = find.byKey(const ValueKey('chat-status-row'));
      expect(MediaQuery.textScalerOf(tester.element(status)).scale(11), 11);
      expect(tester.takeException(), isNull);
    },
  );
}
