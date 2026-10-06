import 'dart:async';
import 'dart:ui';

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
    required TwitchAuth auth,
    required TwitchChatSession chat,
  }) : _host = host,
       _auth = auth,
       _chat = chat {
    _chat.setEmoteOptions(initialLayout.emoteOptions);
    _frame = register(
      ObservableValue(
        current: OverlayFrameState(layout: initialLayout, host: host.state),
      ),
    );
    _authState = register(ObservableValue(current: auth.state));
    _chatState = register(ObservableValue(current: chat.state));
    _connectionStatus = _chatState.select((state) => state.status);

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
    observe(_chat.states, _onChatState);
    unawaited(_initializeHost());
    unawaited(_auth.initialize());
  }

  late final ObservableValue<OverlayFrameState> _frame;
  late final ObservableValue<TwitchAuthState> _authState;
  late final ObservableValue<ChatState> _chatState;
  late final StreamWithInitial<ChatConnectionStatus> _connectionStatus;

  StreamWithInitial<OverlayFrameState> get frame => _frame;
  StreamWithInitial<TwitchAuthState> get authState => _authState;
  StreamWithInitial<ChatState> get chatState => _chatState;
  StreamWithInitial<ChatConnectionStatus> get connectionStatus =>
      _connectionStatus;
  final OverlayLayoutStore _layoutStore;
  final OverlayHost _host;
  final TwitchAuth _auth;
  final TwitchChatSession _chat;

  void _onChatState(ChatState value) {
    if (!identical(_chatState.current, value)) _chatState.set(value);
  }

  Future<void> _initializeHost() async {
    try {
      await _host.initialize(
        excludedFromCapture: _frame.current.layout.excludedFromCapture,
      );
    } catch (error, stack) {
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
    _authState.set(value);
    if (isDisposed) return;
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
