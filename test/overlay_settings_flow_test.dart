import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/overlay/overlay_surface.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

import 'support/fake_tray_factory.dart';

void main() {
  testWidgets(
    'settings preserve chat and draft, dismiss, and reopen from tray',
    (tester) async {
      const viewport = Size(1200, 900);
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const hostChannel = MethodChannel('overlay/window');
      final messenger = tester.binding.defaultBinaryMessenger;
      final trayFactory = FakeTrayFactory();
      messenger.setMockMethodCallHandler(
        hostChannel,
        (call) async => call.method == 'getState'
            ? {'topmost': true, 'interactive': false}
            : null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(hostChannel, null);
      });
      final host = MethodChannelOverlayHost();
      final store = _LayoutStore();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OverlaySurface(
            trayFactory: trayFactory,
            initialLayout: const OverlayLayout(
              left: .64,
              top: .08,
              width: .32,
              height: .8,
            ),
            layoutStore: store,
            overlayHost: host,
            twitchAuth: _Auth(),
            twitchChat: _Chat(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final gear = find.byKey(const ValueKey('settings-toggle'));
      final panel = find.byKey(const ValueKey('overlay-settings-panel'));
      expect(gear, findsNothing);
      // This is the event emitted by the global native hotkey.
      const codec = StandardMethodCodec();
      tester.binding.channelBuffers.push(
        'overlay/window',
        codec.encodeMethodCall(const MethodCall('interactionChanged', true)),
        (_) {},
      );
      await tester.pumpAndSettle();
      expect(gear, findsOneWidget);
      expect(panel, findsNothing);
      final chatRect = tester.getRect(find.byType(ChatPanel));
      await tester.enterText(find.byType(TextField), 'Keep this draft');
      await tester.tap(gear);
      await tester.pumpAndSettle();
      expect(panel, findsOneWidget);
      expect(tester.getRect(find.byType(ChatPanel)), chatRect);
      expect(tester.getRect(panel).right, lessThan(chatRect.left));
      // Escape must close settings even when focus returns to the composer.
      await tester.tap(find.byType(TextField));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(find.text('Keep this draft'), findsOneWidget);
      expect(host.state.interactive, isTrue);
      await tester.tap(gear);
      await tester.pumpAndSettle();
      await tester.tap(gear);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      await tester.tap(gear);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('close-settings')));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      await tester.tap(gear);
      await tester.pumpAndSettle();
      // Moving the chat moves the companion panel and can swap its side.
      await tester.drag(
        find.byKey(const ValueKey('chat-header')),
        const Offset(-620, 0),
      );
      await tester.pumpAndSettle();
      final movedChat = tester.getRect(find.byType(ChatPanel));
      expect(movedChat.size, chatRect.size);
      expect(tester.getRect(panel).left, greaterThan(movedChat.right));
      final opacitySlider = find.byKey(
        const ValueKey('content-transparency-slider'),
      );
      tester.widget<Slider>(opacitySlider).onChanged!(1);
      await tester.pump();
      // Locking saves even a control gesture interrupted before onChangeEnd.
      await tester.tap(find.byTooltip('Lock overlay'));
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      expect(store.saved!.contentOpacity, 0);
      await host.setInteractive(true);
      await tester.pumpAndSettle();
      expect(panel, findsNothing);
      await host.setInteractive(false);
      await tester.pumpAndSettle();
      trayFactory.items[1].click();
      await tester.pumpAndSettle();
      expect(host.state.interactive, isTrue);
      expect(panel, findsOneWidget);
      expect(tester.widget<Slider>(opacitySlider).value, 1);
      expect(
        find.ancestor(of: panel, matching: find.byType(Opacity)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _Auth extends Fake implements TwitchAuth {
  @override
  TwitchAuthState get state =>
      const TwitchAuthState(status: TwitchAuthStatus.signedIn);
  @override
  Stream<TwitchAuthState> get states => const Stream.empty();
  @override
  Future<void> initialize() async {}
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
  OverlayLayout? saved;
  @override
  Future<void> save(OverlayLayout value) async => saved = value;
}
