import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/updates/update_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  Widget app(Widget notice, String locale, {GlobalKey? boundary}) =>
      MaterialApp(
        locale: Locale(locale),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark().copyWith(
          textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Inter'),
        ),
        home: RepaintBoundary(
          key: boundary,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(padding: const EdgeInsets.all(20), child: notice),
            ),
          ),
        ),
      );
  testWidgets('checks once, stays hidden while loading and when up to date', (
    tester,
  ) async {
    final result = Completer<String?>();
    var checks = 0;
    final key = GlobalKey();
    Widget notice(bool interactive) => UpdateNotice(
      key: key,
      interactive: interactive,
      onUpdate: (_) async {},
      check: () {
        checks++;
        return result.future;
      },
    );
    await tester.pumpWidget(app(notice(false), 'en'));
    expect(find.byType(FilledButton), findsNothing);
    await tester.pumpWidget(app(notice(true), 'en'));
    expect(checks, 1);
    result.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
  });
  for (final locale in ['en', 'uk']) {
    testWidgets(
      '$locale banner keeps click-through mode and launches with its locale',
      (tester) async {
        tester.view.physicalSize = const Size(760, 210);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final strings = await AppLocalizations.delegate.load(Locale(locale));
        final key = GlobalKey();
        final boundary = GlobalKey();
        final launches = <String>[];
        Widget notice(bool interactive) => UpdateNotice(
          key: key,
          interactive: interactive,
          check: () async => '1.2.0',
          onUpdate: (language) async => launches.add(language),
        );
        await tester.pumpWidget(app(notice(false), locale, boundary: boundary));
        await tester.pumpAndSettle();
        expect(find.text(strings.updateNoticeShortcut), findsOneWidget);
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          null,
        );
        await tester.pumpWidget(app(notice(true), locale, boundary: boundary));
        await tester.pumpAndSettle();
        expect(find.text(strings.updateNoticeDetail), findsOneWidget);
        expect(tester.takeException(), null);
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/previews/update-notice-$locale.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
        await tester.tap(find.text(strings.updateNow));
        await tester.pumpAndSettle();
        expect(launches, [locale]);
        expect(find.byType(FilledButton), findsNothing);
      },
    );
  }
  testWidgets('compact banner survives launch failure and can be dismissed', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final strings = await AppLocalizations.delegate.load(const Locale('en'));
    await tester.pumpWidget(
      app(
        UpdateNotice(
          interactive: true,
          check: () async => '1.2.0',
          onUpdate: (_) async => throw PlatformException(code: 'launch'),
        ),
        'en',
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    await tester.tap(find.text(strings.updateNow));
    await tester.pumpAndSettle();
    expect(find.text(strings.updateLaunchFailed), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.tap(find.byTooltip(strings.updateDismiss));
    await tester.pumpAndSettle();
    expect(find.byType(FilledButton), findsNothing);
  });
}
