import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/emotes/emote_options.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/overlay/overlay_surface.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

import 'support/fake_tray_factory.dart';

void main() {
  for (final resize in [false, true]) {
    testWidgets(
      '${resize ? 'resize' : 'move'} accumulates pointer events within a frame',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(1920, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        const channel = MethodChannel('overlay/window');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'getState'
              ? {'topmost': true, 'interactive': true}
              : null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: OverlaySurface(
              initialLayout: const OverlayLayout.defaults(),
              layoutStore: _Store(),
              overlayHost: MethodChannelOverlayHost(),
              twitchAuth: _Auth(),
              twitchChat: _Chat(),
              trayFactory: FakeTrayFactory(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final panel = find.byType(ChatPanel);
        final start = resize
            ? Offset(
                tester.getRect(panel).right + 1,
                tester.getRect(panel).center.dy,
              )
            : tester.getCenter(find.byKey(const ValueKey('chat-header')));
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(25, 0));
        await tester.pump();
        final before = tester.getRect(panel);
        await gesture.moveBy(const Offset(10, 0));
        await gesture.moveBy(const Offset(20, 0));
        await tester.pump();
        final after = tester.getRect(panel);
        await gesture.up();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(
          resize ? after.width - before.width : after.left - before.left,
          closeTo(30, .001),
        );
      },
    );
  }
}

class _Auth extends Fake implements TwitchAuth {
  @override
  TwitchAuthState get state =>
      const TwitchAuthState(status: TwitchAuthStatus.signedOut);
  @override
  Stream<TwitchAuthState> get states => const Stream.empty();
  @override
  Future<void> initialize() async {}
}

class _Chat extends Fake implements TwitchChatSession {
  @override
  void setEmoteOptions(ThirdPartyEmoteOptions options) {}
  @override
  ChatState get state => const ChatState.idle();
  @override
  Stream<ChatState> get states => const Stream.empty();
  @override
  Future<void> leave() async {}
}

class _Store extends Fake implements OverlayLayoutStore {
  @override
  Future<void> save(OverlayLayout layout) async {}
}
