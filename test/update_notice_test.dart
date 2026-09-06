import 'dart:async';

import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/chat/chat_composer.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

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
  Widget app(
    Widget notice,
    String locale, {
    GlobalKey? boundary,
    double textScale = 1,
  }) => MaterialApp(
    locale: Locale(locale),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
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
    expect(find.byType(TextButton), findsNothing);
    await tester.pumpWidget(app(notice(true), 'en'));
    expect(checks, 1);
    result.complete(null);
    await tester.pumpAndSettle();
    expect(find.byType(TextButton), findsNothing);
  });
  for (final locale in ['en', 'uk']) {
    testWidgets(
      '$locale banner keeps click-through mode and launches with its locale',
      (tester) async {
        tester.view.physicalSize = const Size(360, 100);
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
        expect(find.byTooltip(strings.updateNoticeShortcut), findsOneWidget);
        expect(
          tester.widget<TextButton>(find.byType(TextButton)).onPressed,
          null,
        );
        await tester.pumpWidget(app(notice(true), locale, boundary: boundary));
        await tester.pumpAndSettle();
        expect(find.text(strings.updateNoticeTitle('1.2.0')), findsOneWidget);
        final normalHeight = tester.getSize(find.byType(UpdateNotice)).height;
        await tester.pumpWidget(
          app(notice(true), locale, boundary: boundary, textScale: 2.5),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), null);
        expect(
          tester.getSize(find.byType(UpdateNotice)).height,
          greaterThan(normalHeight),
        );
        await tester.pumpWidget(app(notice(true), locale, boundary: boundary));
        await tester.pumpAndSettle();
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
        expect(find.byType(TextButton), findsNothing);
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
    expect(find.byType(TextButton), findsNothing);
  });

  testWidgets('notice sits inside chat between messages and composer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final panelKey = GlobalKey();
    final noticeKey = GlobalKey();
    final boundary = GlobalKey();
    var checks = 0;
    for (final interactive in [false, true]) {
      await tester.pumpWidget(
        app(
          SizedBox(
            height: 280,
            child: ChatPanel(
              key: panelKey,
              authState: const TwitchAuthState(
                status: TwitchAuthStatus.signedIn,
              ),
              chatState: const ChatState(
                status: ChatConnectionStatus.connected,
                items: [],
              ),
              interactive: interactive,
              onSignIn: () async {},
              onSignOut: () async {},
              onSend: (message, {replyTo}) async => throw UnimplementedError(),
              onLoadEmotes: ({bool refresh = false}) async => [],
              messageFooter: UpdateNotice(
                key: noticeKey,
                interactive: interactive,
                onUpdate: (_) async {},
                check: () async {
                  checks++;
                  return '1.1.0';
                },
              ),
            ),
          ),
          'uk',
          boundary: boundary,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), null);
      final notice = tester.getRect(find.byType(UpdateNotice));
      final messages = tester.getRect(find.byType(ListView));
      final panel = tester.getRect(find.byType(ChatPanel));
      expect(notice.top, messages.bottom);
      expect(notice.left, panel.left);
      expect(notice.right, panel.right);
      if (interactive) {
        expect(tester.getRect(find.byType(ChatComposer)).top, notice.bottom);
      } else {
        expect(find.byType(ChatComposer), findsNothing);
        expect(notice.bottom, panel.bottom);
      }
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File(
          'build/previews/inline-notice-${interactive ? 'interactive' : 'locked'}.png',
        );
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    expect(checks, 1);
  });
}
