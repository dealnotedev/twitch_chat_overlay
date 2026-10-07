import 'dart:async';

import 'package:flutter/services.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

enum OverlayFailure { captureExclusion }

final class OverlayFrameState {
  const OverlayFrameState({
    required this.layout,
    required this.host,
    this.settingsOpen = false,
    this.captureExclusionProcess = const SimpleFailableProcess.initial(),
  });

  final OverlayLayout layout;
  final OverlayHostState host;
  final bool settingsOpen;
  final SimpleFailableProcess captureExclusionProcess;

  OverlayFrameState copyWith({
    OverlayLayout? layout,
    OverlayHostState? host,
    bool? settingsOpen,
    SimpleFailableProcess? captureExclusionProcess,
  }) => OverlayFrameState(
    layout: layout ?? this.layout,
    host: host ?? this.host,
    settingsOpen: settingsOpen ?? this.settingsOpen,
    captureExclusionProcess:
        captureExclusionProcess ?? this.captureExclusionProcess,
  );
}

final class OverlayViewModel extends BaseViewModel {
  OverlayViewModel({
    required OverlayLayout initialLayout,
    required this._layoutStore,
    required OverlayHost host,
    required this._auth,
    required this._chat,
  }) : _host = host {
    _chat.setEmoteOptions(initialLayout.emoteOptions);
    _frame = register(
      ObservableValue(
        current: OverlayFrameState(layout: initialLayout, host: host.state),
      ),
    );
    observe(_host.states, (hostState) {
      if (!hostState.interactive && _frame.current.settingsOpen) {
        unawaited(saveLayout());
      }
      _frame.set(
        _frame.current.copyWith(
          host: hostState,
          settingsOpen: hostState.interactive && _frame.current.settingsOpen,
        ),
      );
    });
    observe(_auth.states, _onAuthState);
    unawaited(_initializeHost());
    unawaited(_auth.initialize());
  }

  late final ObservableValue<OverlayFrameState> _frame;
  // Views over the services' own state: no copies to keep in sync.
  late final Observable<TwitchAuthState> authState = Observable.of(
    () => _auth.state,
    _auth.states,
  );
  late final Observable<ChatState> chatState = Observable.of(
    () => _chat.state,
    _chat.states,
  );
  late final Observable<bool> signedIn = authState.select(
    (state) => state.status == TwitchAuthStatus.signedIn,
  );
  late final Observable<ChatConnectionStatus> connectionStatus = chatState
      .select((state) => state.status);

  Observable<OverlayFrameState> get frame => _frame;
  final OverlayLayoutStore _layoutStore;
  final OverlayHost _host;
  final TwitchAuth _auth;
  final TwitchChatSession _chat;

  Future<void> _initializeHost() async {
    try {
      await _host.initialize(
        excludedFromCapture: _frame.current.layout.excludedFromCapture,
      );
    } on PlatformException catch (error, stack) {
      if (isDisposed) return;
      _frame.set(
        _frame.current.copyWith(
          layout: _frame.current.layout.withExcludedFromCapture(
            _host.state.excludedFromCapture,
          ),
          captureExclusionProcess: SimpleFailableProcess.failed(
            OverlayFailure.captureExclusion,
            cause: error,
            stackTrace: stack,
          ),
        ),
      );
    }
  }

  Future<void> openSettings() async {
    if (isDisposed) return;
    await _host.setInteractive(true);
    if (!isDisposed && _host.state.interactive) {
      _frame.set(_frame.current.copyWith(settingsOpen: true));
    }
  }

  void toggleSettings() {
    if (isDisposed) return;
    if (_frame.current.settingsOpen) {
      closeSettings();
    } else {
      _frame.set(_frame.current.copyWith(settingsOpen: true));
    }
  }

  void closeSettings() {
    if (isDisposed || !_frame.current.settingsOpen) return;
    unawaited(saveLayout());
    _frame.set(_frame.current.copyWith(settingsOpen: false));
  }

  void updateLayout(OverlayLayout layout) {
    if (isDisposed) return;
    _frame.set(_frame.current.copyWith(layout: layout));
    if (!isDisposed) _chat.setEmoteOptions(layout.emoteOptions);
  }

  void move(Offset delta, Size viewport) =>
      updateLayout(_frame.current.layout.moveBy(delta, viewport));

  void resize(ResizeHandle handle, Offset delta, Size viewport) =>
      updateLayout(_frame.current.layout.resizeBy(handle, delta, viewport));

  Future<void> saveLayout() => _layoutStore.save(_frame.current.layout);

  Future<void> changeCaptureExclusion(bool excluded) async {
    if (isDisposed || _frame.current.captureExclusionProcess.isActive) return;
    _frame.set(
      _frame.current.copyWith(
        captureExclusionProcess: const SimpleFailableProcess.loading(),
      ),
    );
    if (isDisposed) return;
    try {
      await _host.setExcludedFromCapture(excluded);
    } catch (error, stack) {
      if (!isDisposed) {
        _frame.set(
          _frame.current.copyWith(
            captureExclusionProcess: SimpleFailableProcess.failed(
              OverlayFailure.captureExclusion,
              cause: error,
              stackTrace: stack,
            ),
          ),
        );
      }
      return;
    }
    if (isDisposed) return;
    _frame.set(
      _frame.current.copyWith(
        layout: _frame.current.layout.withExcludedFromCapture(excluded),
        captureExclusionProcess: const SimpleFailableProcess.initial(),
      ),
    );
    if (isDisposed) return;
    await saveLayout();
  }

  Future<void> lock() => _host.setInteractive(false);

  Future<void> signIn() async {
    if (isDisposed) return;
    await _host.setInteractive(false);
    if (!isDisposed) await _auth.signIn();
  }

  Future<void> signOut() => _auth.signOut();

  void _onAuthState(TwitchAuthState value) {
    final token = value.token;
    if (value.status == TwitchAuthStatus.signedIn && token != null) {
      unawaited(_chat.join(broadcasterId: token.userId));
    } else if (value.status == TwitchAuthStatus.signedOut ||
        value.status == TwitchAuthStatus.failure) {
      unawaited(_chat.leave());
    }
  }

  @override
  void dispose() {
    if (isDisposed) return;
    super.dispose();
    unawaited(_chat.leave());
  }
}
