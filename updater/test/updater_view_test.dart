import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlay_updater/update_controller.dart';
import 'package:overlay_updater/l10n/generated/updater_localizations.dart';
import 'package:overlay_updater/updater_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('../assets/fonts/inter/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('../assets/fonts/inter/Inter-Medium.ttf'))
      ..addFont(rootBundle.load('../assets/fonts/inter/Inter-SemiBold.ttf'))
      ..addFont(rootBundle.load('../assets/fonts/inter/Inter-Bold.ttf'));
    await loader.load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  final notes = File('../CHANGELOG.md').readAsStringSync();
  for (final language in ['en', 'uk']) {
    final strings = lookupUpdaterLocalizations(Locale(language));
    final states = {
      'ready': UpdatePresentation(
        phase: UpdatePhase.available,
        title: strings.availableTitle,
        detail: strings.packageSize(language == 'uk' ? '13,8' : '13.8'),
        action: strings.updateOverlay,
        current: '1.0.1+2',
        latest: '1.1.0',
        notes: notes,
        progress: 0,
      ),
      'downloading': UpdatePresentation(
        phase: UpdatePhase.downloading,
        title: strings.downloadTitle,
        detail: strings.downloadProgress('8.7', '13.8'),
        action: strings.downloadingAction,
        busy: true,
        current: '1.0.1+2',
        latest: '1.1.0',
        notes: notes,
        progress: .63,
      ),
      'error': UpdatePresentation(
        phase: UpdatePhase.error,
        title: strings.errorTitle,
        detail: strings.networkError,
        action: strings.retry,
        current: '1.0.1+2',
        latest: '1.1.0',
        notes: notes,
        progress: 0,
      ),
      'complete': UpdatePresentation(
        phase: UpdatePhase.done,
        title: strings.doneTitle,
        detail: strings.doneDetail,
        action: strings.openOverlay,
        current: '1.1.0+3',
        latest: '1.1.0',
        notes: notes,
        progress: 1,
      ),
    };
    for (final entry in states.entries) {
      testWidgets(
        'renders $language ${entry.key} without overflow and exposes appropriate actions',
        (tester) async {
          tester.view.physicalSize = const Size(720, 680);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          var clicked = 0;
          var cancelled = 0;
          final boundary = GlobalKey();
          await tester.pumpWidget(
            MaterialApp(
              theme: updaterTheme(),
              locale: Locale(language),
              localizationsDelegates:
                  UpdaterLocalizations.localizationsDelegates,
              supportedLocales: UpdaterLocalizations.supportedLocales,
              home: RepaintBoundary(
                key: boundary,
                child: UpdaterView(
                  state: entry.value,
                  onAction: () => clicked++,
                  onCancel: () => cancelled++,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), null);
          await tester.tap(find.byType(FilledButton));
          expect(clicked, entry.value.busy ? 0 : 1);
          if (entry.key == 'downloading') {
            await tester.tap(find.text(strings.cancelDownload));
            expect(cancelled, 1);
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            final output = File('build/previews/${entry.key}-$language.png');
            await output.parent.create(recursive: true);
            await output.writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        },
      );
    }
    testWidgets('$language fits the minimum window size with long errors', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(660, 610);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          theme: updaterTheme(),
          locale: Locale(language),
          localizationsDelegates: UpdaterLocalizations.localizationsDelegates,
          supportedLocales: UpdaterLocalizations.supportedLocales,
          home: UpdaterView(
            state: UpdatePresentation(
              phase: UpdatePhase.error,
              title: strings.errorTitle,
              detail: strings.fileError * 3,
              notes: notes * 10,
              current: '1.0.1+2',
              latest: '1.1.0',
              action: strings.retry,
            ),
            onAction: () {},
            onCancel: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
    });
  }
}
