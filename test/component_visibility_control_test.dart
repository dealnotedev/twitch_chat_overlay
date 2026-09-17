import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/component_visibility_control.dart';

void main() {
  for (final locale in ['en', 'uk']) {
    testWidgets(
      'component checkboxes wrap and toggle independently ($locale)',
      (tester) async {
        var viewers = true;
        var connection = true;
        var width = 320.0;
        late StateSetter update;
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return SizedBox(
                    width: width,
                    child: ComponentVisibilityControl(
                      showViewerCount: viewers,
                      showConnectionIndicator: connection,
                      onShowViewerCountChanged: (value) =>
                          setState(() => viewers = value),
                      onShowConnectionIndicatorChanged: (value) =>
                          setState(() => connection = value),
                    ),
                  );
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final checkboxes = find.byType(Checkbox);
        expect(checkboxes, findsNWidgets(2));
        expect(
          tester.getCenter(checkboxes.last).dy,
          greaterThan(tester.getCenter(checkboxes.first).dy),
        );
        await tester.tap(checkboxes.first);
        await tester.pump();
        expect(viewers, isFalse);
        expect(connection, isTrue);
        await tester.tap(
          find.text(
            locale == 'en' ? 'Connection indicator' : 'Індикатор підключення',
          ),
        );
        await tester.pump();
        expect(connection, isFalse);
        update(() => width = 700);
        await tester.pump();
        expect(
          tester.getCenter(checkboxes.last).dy,
          tester.getCenter(checkboxes.first).dy,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
