import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/l10n/locale_preferences.dart';
import 'package:twitch_chat_overlay/main.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/overlay/overlay_surface.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await (FontLoader('Inter')
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-Regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/inter/Inter-SemiBold.ttf')))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  test('restores supported locales and defaults to Ukrainian', () async {
    for (final stored in [null, 'uk', 'en', 'de']) {
      SharedPreferences.setMockInitialValues({
        LocalePreferences.key: ?stored,
      });
      final settings = await LocalePreferences.load();
      expect(settings.value.languageCode, stored == 'en' ? 'en' : 'uk');
      settings.dispose();
    }
  });
  test('rapid switches persist the final language across restarts', () async {
    final settings = await LocalePreferences.load();
    addTearDown(settings.dispose);
    await Future.wait([settings.cycle(), settings.cycle(), settings.cycle()]);
    await settings.flush();
    final reopened = await LocalePreferences.load();
    addTearDown(reopened.dispose);
    expect(reopened.value, const Locale('en'));
  });
  testWidgets(
    'header cycles locale, saves it and updates tray without restarting chat',
    (tester) async {
      tester.view.physicalSize = const Size(900, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const channel = MethodChannel('overlay/window');
      const trayChannel = MethodChannel('tray_manager');
      final calls = <MethodCall>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'getState'
            ? {'interactive': true, 'topmost': true}
            : call.method == 'isVisible'
            ? true
            : null,
      );
      messenger.setMockMethodCallHandler(trayChannel, (call) async {
        calls.add(call);
        return true;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMethodCallHandler(trayChannel, null);
      });
      final settings = await LocalePreferences.load();
      final host = MethodChannelOverlayHost();
      final auth = _Auth();
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: TwitchChatOverlayApp(
            localePreferences: settings,
            initialLayout: const OverlayLayout.defaults(),
            layoutStore: _LayoutStore(),
            overlayHost: host,
            twitchAuth: auth,
            twitchChat: _Chat(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final originalSurface = tester.state(find.byType(OverlaySurface));
      final toggle = find.byKey(const ValueKey('locale-toggle'));
      expect(
        find.descendant(of: toggle, matching: find.text('UK')),
        findsOneWidget,
      );
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await settings.flush();
      expect(
        find.descendant(of: toggle, matching: find.text('EN')),
        findsOneWidget,
      );
      expect(find.text('Sign in with Twitch'), findsOneWidget);
      expect(
        (await SharedPreferences.getInstance()).getString(
          LocalePreferences.key,
        ),
        'en',
      );
      final items =
          (calls.lastWhere((call) => call.method == 'setContextMenu').arguments
                  as Map)['menu']['items']
              as List;
      expect(items.first['label'], 'Hide overlay');
      expect(tester.state(find.byType(OverlaySurface)), same(originalSurface));
      expect(auth.initializations, 1);
      expect(calls.where((call) => call.method == 'setIcon').length, 1);
      expect(tester.takeException(), null);
      await tester.runAsync(() async {
        final image =
            await (boundary.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary)
                .toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('build/previews/language-toggle.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
      await host.setInteractive(false);
      await tester.pumpAndSettle();
      expect(toggle, findsNothing);
      await host.setInteractive(true);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await settings.flush();
      final reopened = await LocalePreferences.load();
      expect(reopened.value, const Locale('uk'));
      reopened.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      settings.dispose();
    },
  );
}

class _Auth extends Fake implements TwitchAuth {
  int initializations = 0;
  @override
  TwitchAuthState get state =>
      const TwitchAuthState(status: TwitchAuthStatus.signedOut);
  @override
  Stream<TwitchAuthState> get states => const Stream.empty();
  @override
  Future<void> initialize() async {
    initializations++;
  }
}

class _Chat extends Fake implements TwitchChatSession {
  @override
  ChatState get state => const ChatState.idle();
  @override
  Stream<ChatState> get states => const Stream.empty();
  @override
  Future<void> leave() async {}
}

class _LayoutStore extends Fake implements OverlayLayoutStore {
  @override
  Future<void> save(OverlayLayout layout) async {}
}
