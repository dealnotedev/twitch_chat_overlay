import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/message_lifetime_control.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';

void main() {
  testWidgets('compact buttons change minutes and support unlimited lifetime', (
    tester,
  ) async {
    var minutes = 5;
    late StateSetter update;
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
                builder: (context, setState) {
                  update = setState;
                  return MessageLifetimeControl(
                    minutes: minutes,
                    onChanged: (value) => setState(() => minutes = value),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(EditableText), findsNothing);
    final up = find.widgetWithIcon(IconButton, Icons.add_rounded);
    final down = find.widgetWithIcon(IconButton, Icons.remove_rounded);
    expect(
      tester.getCenter(down).dx,
      lessThan(tester.getCenter(find.text('5 хв')).dx),
    );
    expect(
      tester.getCenter(up).dx,
      greaterThan(tester.getCenter(find.text('5 хв')).dx),
    );
    expect(tester.getCenter(up).dy, tester.getCenter(down).dy);
    expect(tester.getSize(find.byType(MessageLifetimeControl)).height, 36);
    await tester.tap(up);
    await tester.pump();
    expect(minutes, 6);
    await tester.tap(down);
    await tester.pump();
    expect(minutes, 5);
    Focus.of(tester.element(find.byIcon(Icons.remove_rounded))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(minutes, 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(minutes, 5);
    update(() => minutes = 1);
    await tester.pump();
    await tester.tap(down);
    await tester.pump();
    expect(minutes, 0);
    expect(find.text('-'), findsOneWidget);
    expect(tester.widget<IconButton>(down).onPressed, isNull);
    await tester.tap(up);
    await tester.pump();
    expect(minutes, 1);
    expect(find.text('1 хв'), findsOneWidget);
    update(() => minutes = 60);
    await tester.pump();
    expect(tester.widget<IconButton>(up).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  test('lifetime persists and survives geometry and opacity changes', () async {
    SharedPreferences.setMockInitialValues({});
    final store = SharedPreferencesOverlayLayoutStore();
    expect((await store.load()).messageLifetimeMinutes, 0);
    final layout = const OverlayLayout.defaults()
        .withMessageLifetimeMinutes(17)
        .moveBy(const Offset(20, 20), const Size(1920, 1080))
        .resizeBy(
          ResizeHandle.bottomRight,
          const Offset(20, 20),
          const Size(1920, 1080),
        )
        .withBackgroundOpacity(0.4);
    await store.save(layout);
    expect((await store.load()).messageLifetimeMinutes, 17);
    await store.save(layout.withMessageLifetimeMinutes(0));
    expect((await store.load()).messageLifetimeMinutes, 0);
  });

  test('stored lifetime without geometry is loaded and clamped', () async {
    final store = SharedPreferencesOverlayLayoutStore();
    for (final entry in {-1: 0, 0: 0, 120: 60, 12: 12}.entries) {
      SharedPreferences.setMockInitialValues({
        'overlay.messages.lifetimeMinutes': entry.key,
      });
      expect((await store.load()).messageLifetimeMinutes, entry.value);
    }
  });
}
