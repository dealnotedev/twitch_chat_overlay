import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_settings_panel.dart';

void main() {
  for (final locale in ['en', 'uk']) {
    testWidgets('all settings remain reachable on a small screen ($locale)', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      for (final (viewport, initialLayout) in [
        (const Size(360, 640), const OverlayLayout.defaults()),
        (const Size(640, 360), const OverlayLayout.defaults()),
        // The minimum-height chat at the bottom edge still allows scrolling.
        (
          const Size(1200, 900),
          const OverlayLayout(left: .6, top: 1, width: .3, height: 220 / 900),
        ),
        // A tall chat at the top edge has no independent settings height cap.
        (
          const Size(1200, 900),
          const OverlayLayout(left: .1, top: 0, width: .3, height: 1),
        ),
      ]) {
        await tester.binding.setSurfaceSize(viewport);
        var layout = initialLayout;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: MediaQuery(
              data: MediaQueryData(
                size: viewport,
                textScaler: TextScaler.linear(1.3),
              ),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => Stack(
                    children: [
                      Positioned.fromRect(
                        rect: OverlaySettingsPanel.placeBeside(
                          layout.resolve(viewport),
                          viewport,
                        ),
                        child: OverlaySettingsPanel(
                          layout: layout,
                          onChanged: (value) => setState(() => layout = value),
                          onChangeEnd: () {},
                          onClose: () {},
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final panel = tester.getRect(find.byType(OverlaySettingsPanel));
        final chat = layout.resolve(viewport);
        expect(panel.top, chat.top);
        expect(panel.bottom, chat.bottom);
        expect(panel.left, greaterThanOrEqualTo(0));
        expect(panel.right, lessThanOrEqualTo(viewport.width));
        expect(panel.top, greaterThanOrEqualTo(0));
        expect(panel.bottom, lessThanOrEqualTo(viewport.height));
        final connection = find.byType(Checkbox).last;
        await tester.ensureVisible(connection);
        await tester.pumpAndSettle();
        await tester.tap(connection);
        await tester.pumpAndSettle();
        expect(layout.showConnectionIndicator, isFalse);
        final sevenTv = find.byKey(const ValueKey('integration-7tv'));
        final bttv = find.byKey(const ValueKey('integration-bttv'));
        expect(layout.emoteOptions.enabled, isFalse);
        await tester.ensureVisible(sevenTv);
        await tester.pumpAndSettle();
        await tester.tap(sevenTv);
        await tester.pumpAndSettle();
        expect(layout.emoteOptions.sevenTv, isTrue);
        expect(layout.emoteOptions.betterTtv, isFalse);
        await tester.ensureVisible(bttv);
        await tester.pumpAndSettle();
        await tester.tap(bttv);
        await tester.pumpAndSettle();
        expect(layout.emoteOptions.betterTtv, isTrue);
        expect(
          find.text(locale == 'en' ? 'Integrations' : 'Інтеграції'),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('close-settings')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
