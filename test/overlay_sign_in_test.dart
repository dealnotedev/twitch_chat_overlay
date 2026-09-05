import 'dart:async';

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

void main() {
  testWidgets('sign in exits interactive mode before starting authorization', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const hostChannel = MethodChannel('overlay/window');
    const trayChannel = MethodChannel('tray_manager');
    final messenger = tester.binding.defaultBinaryMessenger;
    final locked = Completer<void>();
    final host = MethodChannelOverlayHost();
    final auth = _Auth();
    final interactionRequests = <bool>[];
    messenger.setMockMethodCallHandler(hostChannel, (call) async {
      if (call.method == 'getState') {
        return {'topmost': true, 'interactive': true};
      }
      if (call.method == 'setInteractive') {
        interactionRequests.add(call.arguments as bool);
        await locked.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(trayChannel, (_) async => true);
    addTearDown(() {
      messenger.setMockMethodCallHandler(hostChannel, null);
      messenger.setMockMethodCallHandler(trayChannel, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OverlaySurface(
          initialLayout: const OverlayLayout.defaults(),
          layoutStore: _LayoutStore(),
          overlayHost: host,
          twitchAuth: auth,
          twitchChat: _Chat(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(host.state.interactive, isTrue);

    await tester.tap(find.text('Sign in with Twitch'));
    await tester.pump();
    expect(interactionRequests, [false]);
    expect(auth.signInCalled, isFalse);

    locked.complete();
    await tester.pumpAndSettle();
    expect(host.state.interactive, isFalse);
    expect(
      tester.widget<ChatPanel>(find.byType(ChatPanel)).interactive,
      isFalse,
    );
    expect(auth.signInCalled, isTrue);
    expect(auth.authorization.isCompleted, isFalse);

    auth.authorization.complete();
    await tester.pump();
    expect(host.state.interactive, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _Auth extends Fake implements TwitchAuth {
  final authorization = Completer<void>();
  bool signInCalled = false;

  @override
  TwitchAuthState get state =>
      const TwitchAuthState(status: TwitchAuthStatus.signedOut);

  @override
  Stream<TwitchAuthState> get states => const Stream.empty();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> signIn() {
    signInCalled = true;
    return authorization.future;
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

class _LayoutStore extends Fake implements OverlayLayoutStore {}
