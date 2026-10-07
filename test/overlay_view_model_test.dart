import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/emotes/emote_options.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/overlay/overlay_view_model.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

void main() {
  test(
    'capture success publishes the updated layout with a completed process',
    () async {
      final host = _Host();
      final store = _Store();
      final viewModel = _model(host, store);
      addTearDown(viewModel.dispose);
      addTearDown(host.value.dispose);
      final events = <OverlayFrameState>[];
      final subscription = viewModel.frame.changes.listen(events.add);
      addTearDown(subscription.cancel);
      final changing = viewModel.changeCaptureExclusion(true);
      expect(events.single.captureExclusionProcess.isActive, isTrue);
      expect(events.single.layout.excludedFromCapture, isFalse);
      host.pending.complete();
      await changing;
      expect(events.last.layout.excludedFromCapture, isTrue);
      expect(events.last.captureExclusionProcess.isActive, isFalse);
      expect(
        events
            .where((state) => state.layout.excludedFromCapture)
            .every((state) => !state.captureExclusionProcess.isActive),
        isTrue,
      );
      expect(store.saved, same(events.last.layout));
    },
  );

  test(
    'capture initialization failure publishes rollback and feedback together',
    () async {
      final host = _Host(failInitialize: true);
      final viewModel = _model(host, _Store(), excluded: true);
      addTearDown(viewModel.dispose);
      addTearDown(host.value.dispose);
      final events = <OverlayFrameState>[];
      final subscription = viewModel.frame.changes.listen(events.add);
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(events.single.layout.excludedFromCapture, isFalse);
      expect(
        events.single.captureExclusionProcess.error,
        OverlayFailure.captureExclusion,
      );
    },
  );

  test(
    'chat listeners immediately see the new projected connection status',
    () async {
      final host = _Host();
      final chat = _Chat();
      final viewModel = _model(host, _Store(), chat: chat);
      addTearDown(viewModel.dispose);
      addTearDown(host.value.dispose);
      addTearDown(chat.value.dispose);
      final observed = <ChatConnectionStatus>[];
      final subscription = viewModel.chatState.changes.listen(
        (_) => observed.add(viewModel.connectionStatus.current),
      );
      addTearDown(subscription.cancel);
      chat.value.set(
        const ChatState(status: ChatConnectionStatus.connected, items: []),
      );
      expect(observed, [ChatConnectionStatus.connected]);
    },
  );

  test('chat and sign-in views read the services without copies', () {
    final host = _Host();
    final chat = _Chat();
    final viewModel = _model(host, _Store(), chat: chat);
    addTearDown(viewModel.dispose);
    addTearDown(host.value.dispose);
    addTearDown(chat.value.dispose);
    const next = ChatState(status: ChatConnectionStatus.connected, items: []);
    chat.value.set(next);
    expect(viewModel.chatState.current, same(next));
    expect(viewModel.chatState, same(viewModel.chatState));
    expect(viewModel.signedIn.current, isFalse);
  });
}

OverlayViewModel _model(
  _Host host,
  _Store store, {
  bool excluded = false,
  _Chat? chat,
}) => OverlayViewModel(
  initialLayout: const OverlayLayout.defaults().withExcludedFromCapture(
    excluded,
  ),
  layoutStore: store,
  host: host,
  auth: _Auth(),
  chat: chat ?? _Chat(),
);

class _Host extends Fake implements OverlayHost {
  _Host({this.failInitialize = false});
  final bool failInitialize;
  final pending = Completer<void>();
  final value = ObservableValue<OverlayHostState>(
    current: const OverlayHostState.initial(),
  );
  @override
  OverlayHostState get state => value.current;
  @override
  Stream<OverlayHostState> get states => value.changes;
  @override
  Future<void> initialize({bool excludedFromCapture = false}) async {
    if (failInitialize) throw PlatformException(code: 'capture');
  }

  @override
  Future<void> setExcludedFromCapture(bool excluded) async {
    await pending.future;
    value.set(state.copyWith(excludedFromCapture: excluded));
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
  final value = ObservableValue<ChatState>(current: const ChatState.idle());
  @override
  ChatState get state => value.current;
  @override
  Stream<ChatState> get states => value.changes;
  @override
  void setEmoteOptions(ThirdPartyEmoteOptions options) {}
  @override
  Future<void> leave() async => value.dispose();
}

class _Store extends Fake implements OverlayLayoutStore {
  OverlayLayout? saved;
  @override
  Future<void> save(OverlayLayout layout) async => saved = layout;
}
