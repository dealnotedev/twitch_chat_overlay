import 'dart:async';

import 'package:flutter/services.dart';

final class OverlayHostState {
  const OverlayHostState({
    required this.topmost,
    required this.interactive,
    this.excludedFromCapture = false,
  });

  const OverlayHostState.initial()
    : topmost = true,
      interactive = false,
      excludedFromCapture = false;

  final bool topmost;
  final bool interactive;
  final bool excludedFromCapture;

  OverlayHostState copyWith({
    bool? topmost,
    bool? interactive,
    bool? excludedFromCapture,
  }) {
    return OverlayHostState(
      topmost: topmost ?? this.topmost,
      interactive: interactive ?? this.interactive,
      excludedFromCapture: excludedFromCapture ?? this.excludedFromCapture,
    );
  }
}

abstract interface class OverlayHost {
  OverlayHostState get state;
  Stream<OverlayHostState> get states;
  Stream<void> get closeRequests;

  Future<void> initialize({bool excludedFromCapture = false});
  Future<bool> isVisible();
  Future<void> setVisible(bool visible);
  Future<void> setInteractive(bool interactive);
  Future<void> setTopmost(bool topmost);
  Future<void> setExcludedFromCapture(bool excluded);
  Future<void> openUpdater(String locale);
  Future<void> close();
}

final class MethodChannelOverlayHost implements OverlayHost {
  static const MethodChannel _channel = MethodChannel('overlay/window');

  final StreamController<OverlayHostState> _states =
      StreamController<OverlayHostState>.broadcast(sync: true);

  final StreamController<void> _closeRequests =
      StreamController<void>.broadcast(sync: true);

  OverlayHostState _state = const OverlayHostState.initial();
  Future<void>? _initialization;

  @override
  OverlayHostState get state => _state;

  @override
  Stream<OverlayHostState> get states => _states.stream;

  @override
  Stream<void> get closeRequests => _closeRequests.stream;

  @override
  Future<void> initialize({bool excludedFromCapture = false}) =>
      _initialization ??= _initialize(excludedFromCapture);

  Future<void> _initialize(bool excludedFromCapture) async {
    _channel.setMethodCallHandler(_handleNativeCall);
    final rawState = await _channel.invokeMapMethod<String, Object?>(
      'getState',
    );
    _emit(
      OverlayHostState(
        topmost: rawState?['topmost'] as bool? ?? true,
        interactive: rawState?['interactive'] as bool? ?? false,
        excludedFromCapture: rawState?['excludedFromCapture'] as bool? ?? false,
      ),
    );
    if (_state.excludedFromCapture != excludedFromCapture) {
      await setExcludedFromCapture(excludedFromCapture);
    }
  }

  @override
  Future<bool> isVisible() async =>
      await _channel.invokeMethod<bool>('isVisible') ?? true;

  @override
  Future<void> setVisible(bool visible) =>
      _channel.invokeMethod<void>('setVisible', visible);

  @override
  Future<void> setInteractive(bool interactive) async {
    await _channel.invokeMethod<void>('setInteractive', interactive);
    _emit(_state.copyWith(interactive: interactive));
  }

  @override
  Future<void> setTopmost(bool topmost) async {
    await _channel.invokeMethod<void>('setTopmost', topmost);
    _emit(_state.copyWith(topmost: topmost));
  }

  @override
  Future<void> setExcludedFromCapture(bool excluded) async {
    await _channel.invokeMethod<void>('setExcludedFromCapture', excluded);
    _emit(_state.copyWith(excludedFromCapture: excluded));
  }

  @override
  Future<void> openUpdater(String locale) async {
    await setInteractive(false);
    await _channel.invokeMethod<void>('openUpdater', locale);
  }

  @override
  Future<void> close() => _channel.invokeMethod<void>('close');

  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'closeRequested') {
      _closeRequests.add(null);
    } else if (call.method == 'interactionChanged') {
      _emit(_state.copyWith(interactive: call.arguments as bool));
    }
  }

  void _emit(OverlayHostState value) {
    _state = value;
    _states.add(value);
  }
}
