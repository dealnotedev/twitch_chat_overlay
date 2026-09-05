import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/chat/viewer_count.dart';
import 'package:twitch_chat_overlay/chat/chat_composer.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
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
  testWidgets(
    'locked signed-in chat fills the frame and retains connection status',
    (tester) async {
      const viewport = Size(1920, 1080);
      const layout = OverlayLayout.defaults();
      await tester.binding.setSurfaceSize(viewport);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();

      const hostChannel = MethodChannel('overlay/window');
      const trayChannel = MethodChannel('tray_manager');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        hostChannel,
        (call) async => call.method == 'getState'
            ? {'topmost': true, 'interactive': false}
            : null,
      );
      messenger.setMockMethodCallHandler(trayChannel, (_) async => true);
      addTearDown(() {
        messenger.setMockMethodCallHandler(hostChannel, null);
        messenger.setMockMethodCallHandler(trayChannel, null);
      });
      final authUpdates = StreamController<TwitchAuthState>();
      final chatUpdates = StreamController<ChatState>();
      addTearDown(authUpdates.close);
      addTearDown(chatUpdates.close);
      final host = MethodChannelOverlayHost();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: OverlaySurface(
            initialLayout: layout,
            layoutStore: _LayoutStore(),
            overlayHost: host,
            twitchAuth: _Auth(
              status: TwitchAuthStatus.signedIn,
              updates: authUpdates.stream,
            ),
            twitchChat: _Chat(
              initialState: const ChatState(
                status: ChatConnectionStatus.connected,
                viewerCount: 1234,
                items: [],
              ),
              updates: chatUpdates.stream,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final frame = layout.resolve(viewport).deflate(1);
      expect(find.text('TWITCH CHAT'), findsNothing);
      expect(tester.getRect(find.byType(ChatPanel)), frame);
      expect(tester.getRect(find.byType(ListView)), frame);
      expect(find.bySemanticsLabel('Chat connected'), findsOneWidget);
      final dot = find.byKey(const ValueKey('chat-connected-dot'));
      final indicator = tester.getRect(dot);
      expect(indicator.size, const Size(7, 7));
      final statusRow = find.byKey(const ValueKey('chat-status-row'));
      final viewers = find.byType(ViewerCount);
      expect(find.descendant(of: statusRow, matching: viewers), findsOneWidget);
      expect(find.descendant(of: statusRow, matching: dot), findsOneWidget);
      expect(tester.widget<ViewerCount>(viewers).count, 1234);
      expect(find.text('1,234'), findsOneWidget);
      expect(find.bySemanticsLabel('Viewers: 1,234'), findsOneWidget);
      expect(tester.getRect(statusRow).top - frame.top, closeTo(8, 0.001));
      expect(tester.getCenter(viewers).dy, closeTo(indicator.center.dy, 0.001));
      expect(indicator.left - tester.getRect(viewers).right, closeTo(8, 0.001));
      expect(frame.right - indicator.right, closeTo(8, 0.001));
      final decoration =
          tester.widget<Container>(dot).decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF52D273));
      expect(decoration.shape, BoxShape.circle);
      expect(
        find.text('No recent messages.\nNew messages will appear here.'),
        findsOneWidget,
      );

      await host.setInteractive(true);
      await tester.pumpAndSettle();
      expect(find.text('TWITCH CHAT'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byTooltip('Lock overlay'), findsOneWidget);
      expect(find.byType(ChatComposer), findsOneWidget);
      expect(find.bySemanticsLabel('Chat connected'), findsNothing);
      await tester.tap(find.byTooltip('Lock overlay'));
      await tester.pumpAndSettle();
      expect(find.text('TWITCH CHAT'), findsNothing);
      expect(tester.getRect(find.byType(ListView)), frame);

      final notice = ChatNotice(
        id: 'retained',
        receivedAt: DateTime.now(),
        noticeType: 'announcement',
        systemMessage: 'Retained chat message',
        userName: null,
        color: null,
        badges: const [],
        fragments: const [],
      );
      for (final entry in {
        ChatConnectionStatus.connecting: 'Connecting to EventSub…',
        ChatConnectionStatus.reconnecting: 'reconnecting',
        ChatConnectionStatus.failure: 'Could not connect to chat',
        ChatConnectionStatus.idle: 'Waiting for connection…',
        ChatConnectionStatus.connected: 'Chat connected',
      }.entries) {
        chatUpdates.add(ChatState(status: entry.key, items: [notice]));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel(entry.value), findsOneWidget);
        expect(find.text('Retained chat message'), findsOneWidget);
        expect(
          find.text('No recent messages.\nNew messages will appear here.'),
          findsNothing,
        );
        expect(find.text('TWITCH CHAT'), findsNothing);
        expect(tester.getRect(find.byType(ListView)), frame);
      }

      chatUpdates.add(
        const ChatState(status: ChatConnectionStatus.connected, items: []),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No recent messages.\nNew messages will appear here.'),
        findsOneWidget,
      );
      chatUpdates.add(
        const ChatState(status: ChatConnectionStatus.failure, items: []),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No recent messages.\nNew messages will appear here.'),
        findsNothing,
      );
      expect(find.text('Could not connect to chat'), findsOneWidget);

      authUpdates.add(
        const TwitchAuthState(status: TwitchAuthStatus.signedOut),
      );
      await tester.pumpAndSettle();
      expect(find.text('TWITCH CHAT'), findsOneWidget);
      expect(find.bySemanticsLabel('Chat connected'), findsNothing);
      expect(tester.getRect(find.byType(ChatPanel)).top, frame.top + 42);
      await host.setInteractive(true);
      await tester.pumpAndSettle();
      expect(find.text('TWITCH CHAT'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('Sign in with Twitch'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}

class _Auth extends Fake implements TwitchAuth {
  _Auth({
    this.status = TwitchAuthStatus.signedOut,
    this.updates = const Stream.empty(),
  });

  final TwitchAuthStatus status;
  final Stream<TwitchAuthState> updates;
  final authorization = Completer<void>();
  bool signInCalled = false;

  @override
  TwitchAuthState get state => TwitchAuthState(status: status);

  @override
  Stream<TwitchAuthState> get states => updates;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> signIn() {
    signInCalled = true;
    return authorization.future;
  }
}

class _Chat extends Fake implements TwitchChatSession {
  _Chat({
    this.initialState = const ChatState.idle(),
    this.updates = const Stream.empty(),
  });

  final ChatState initialState;
  final Stream<ChatState> updates;
  @override
  ChatState get state => initialState;

  @override
  Stream<ChatState> get states => updates;

  @override
  Future<void> leave() async {}
}

class _LayoutStore extends Fake implements OverlayLayoutStore {}
