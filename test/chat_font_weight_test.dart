import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/chat_font_weight_control.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';

import 'chat_message_actions_test.dart' as fixtures;
import 'chat_reply_display_test.dart' as replies;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'weight persists through font size, other settings and geometry',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = SharedPreferencesOverlayLayoutStore();
      expect((await store.load()).chatFontWeight, 500);
      final layout = const OverlayLayout.defaults()
          .withChatFontWeight(300)
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
      final loaded = await store.load();
      expect(loaded.chatFontWeight, 300);
      expect(loaded.chatFontSize, 18.75);
      expect(loaded.contentOpacity, 0.7);
    },
  );

  test('stored weights are bounded and snapped to supported faces', () async {
    final store = SharedPreferencesOverlayLayoutStore();
    for (final entry in {
      0: 300,
      300: 300,
      1000: 900,
      620: 600,
      780: 800,
    }.entries) {
      SharedPreferences.setMockInitialValues({
        'overlay.messages.fontWeight': entry.key,
      });
      expect((await store.load()).chatFontWeight, entry.value);
    }
  });

  testWidgets(
    'weight slider supports all seven weights and displays its value',
    (tester) async {
      var weight = 300;
      var saves = 0;
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
                  builder: (context, setState) => ChatFontWeightControl(
                    value: weight,
                    onChanged: (value) => setState(() => weight = value),
                    onChangeEnd: () => saves++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final slider = find.byType(Slider);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      for (final expected in [400, 500, 600, 700, 800, 900]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(weight, expected);
        expect(find.text('$expected'), findsOneWidget);
        expect(tester.widget<Slider>(slider).label, '$expected');
      }
      expect(saves, 6);
      await tester.drag(slider, const Offset(-500, 0));
      await tester.pump();
      expect(weight, 300);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('timeline weights change while input and status stay unchanged', (
    tester,
  ) async {
    final items = [
      replies.mappedMessage([
        {'type': 'text', 'text': 'Hello'},
      ]),
      ChatRaid(
        id: 'raid',
        receivedAt: DateTime.now().toUtc(),
        userName: 'Raider',
        viewerCount: 3,
      ),
    ];
    RichText renderedText(Finder text) => tester.widget<RichText>(
      find.descendant(of: text, matching: find.byType(RichText)),
    );
    final body = find.text('Viewer: Hello');
    await tester.pumpWidget(fixtures.app(items));
    final inputStyle = tester
        .widget<EditableText>(find.byType(EditableText))
        .style;
    for (final weight in [300, 400, 500, 600, 700, 800, 900]) {
      await tester.pumpWidget(fixtures.app(items, fontWeight: weight));
      final message = renderedText(body);
      expect(message.text.style!.fontWeight!.value, weight);
      final expectedEmphasis = (weight + 200).clamp(300, 900);
      final spans = <TextSpan>[];
      message.text.visitChildren((span) {
        if (span is TextSpan) spans.add(span);
        return true;
      });
      expect(
        spans
            .firstWhere((span) => span.text == 'Viewer: ')
            .style!
            .fontWeight!
            .value,
        expectedEmphasis,
      );
      expect(
        renderedText(find.text('Raider is raiding!'))
            .text
            .style!
            .fontWeight!
            .value,
        expectedEmphasis,
      );
      expect(
        renderedText(find.text('3 viewers')).text.style!.fontWeight!.value,
        weight,
      );
      expect(
        renderedText(find.text('↳ dare_dale: хм'))
            .text
            .style!
            .fontWeight!
            .value,
        weight,
      );
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).style,
        inputStyle,
      );
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(
      fixtures.app(items, fontWeight: 900, interactive: false),
    );
    final status = tester.element(
      find.byKey(const ValueKey('chat-status-row')),
    );
    expect(DefaultTextStyle.of(status).style.fontWeight, FontWeight.w500);
    expect(tester.takeException(), isNull);
  });
}
