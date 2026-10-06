import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:twitch_chat_overlay/widgets/overlay_action_button.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/chat/gif_playback.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/overlay/overlay_settings_panel.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/platform/overlay_tray.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/updates/update_notice.dart';

class OverlaySurface extends StatefulWidget {
  const OverlaySurface({
    required this.initialLayout,
    required this.layoutStore,
    required this.overlayHost,
    required this.twitchAuth,
    required this.twitchChat,
    this.trayFactory = const TrayFactory(),
    this.onCycleLocale,
    this.beforeExit,
    super.key,
  });

  final OverlayLayout initialLayout;
  final OverlayLayoutStore layoutStore;
  final OverlayHost overlayHost;
  final TwitchAuth twitchAuth;
  final TwitchChatSession twitchChat;
  final TrayFactory trayFactory;
  final VoidCallback? onCycleLocale;
  final Future<void> Function()? beforeExit;

  @override
  State<OverlaySurface> createState() => _OverlaySurfaceState();
}

class _OverlaySurfaceState extends State<OverlaySurface> {
  late OverlayLayout _layout;
  late OverlayHostState _hostState;
  late TwitchAuthState _authState;
  late ChatState _chatState;
  StreamSubscription<OverlayHostState>? _hostSubscription;
  StreamSubscription<TwitchAuthState>? _authSubscription;
  StreamSubscription<ChatState>? _chatSubscription;
  OverlayTray? _tray;
  bool _settingsOpen = false;
  bool _changingCaptureExclusion = false;
  bool _captureExclusionFailed = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleSettingsKey);
    _layout = widget.initialLayout;
    widget.twitchChat.setEmoteOptions(_layout.emoteOptions);
    _hostState = widget.overlayHost.state;
    _authState = widget.twitchAuth.state;
    _chatState = widget.twitchChat.state;
    _hostSubscription = widget.overlayHost.states.listen((state) {
      if (!mounted) return;
      if (!state.interactive && _settingsOpen) _saveLayout();
      setState(() {
        _hostState = state;
        if (!state.interactive) _settingsOpen = false;
      });
    });
    _authSubscription = widget.twitchAuth.states.listen(_onAuthState);
    _chatSubscription = widget.twitchChat.states.listen((state) {
      if (mounted) setState(() => _chatState = state);
    });
    unawaited(_initializeHost());
    unawaited(widget.twitchAuth.initialize());
  }

  Future<void> _initializeHost() async {
    try {
      await widget.overlayHost.initialize(
        excludedFromCapture: _layout.excludedFromCapture,
      );
    } on PlatformException {
      if (!mounted) return;
      setState(() {
        _layout = _layout.withExcludedFromCapture(
          widget.overlayHost.state.excludedFromCapture,
        );
        _captureExclusionFailed = true;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tray case final tray?) {
      unawaited(
        tray
            .updateLocalizations(AppLocalizations.of(context))
            .catchError(_reportTrayError),
      );
      return;
    }
    final tray = OverlayTray(
      factory: widget.trayFactory,
      host: widget.overlayHost,
      onConfigure: _openSettingsFromTray,
      beforeExit: () async {
        await widget.layoutStore.save(_layout);
        await widget.beforeExit?.call();
      },
    );
    _tray = tray;
    unawaited(
      tray
          .initialize(AppLocalizations.of(context))
          .catchError(_reportTrayError),
    );
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleSettingsKey);
    unawaited(_tray?.dispose());
    _hostSubscription?.cancel();
    _authSubscription?.cancel();
    _chatSubscription?.cancel();
    unawaited(widget.twitchChat.leave());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final rect = _layout.resolve(viewport);
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: BackgroundOpacity(
                    opacity: _layout.backgroundOpacity,
                    child: _VirtualChatWindow(
                      editing: _hostState.interactive,
                      onCycleLocale: widget.onCycleLocale,
                      signedIn: _authState.status == TwitchAuthStatus.signedIn,
                      contentOpacity: _layout.contentOpacity,
                      showConnectionIndicator: _layout.showConnectionIndicator,
                      gifPlayCount: _layout.gifPlayCount,
                      settingsOpen: _settingsOpen,
                      onSettings: _toggleSettings,
                      onMove: (delta) =>
                          _updateLayout(_layout.moveBy(delta, viewport)),
                      onResize: (handle, delta) => _updateLayout(
                        _layout.resizeBy(handle, delta, viewport),
                      ),
                      onGestureEnd: _saveLayout,
                      onLock: () =>
                          unawaited(widget.overlayHost.setInteractive(false)),
                      connectionStatus: _chatState.status,
                      child: ChatPanel(
                        showViewerCount: _layout.showViewerCount,
                        showConnectionIndicator:
                            _layout.showConnectionIndicator,
                        chatFontSize: _layout.chatFontSize,
                        chatFontWeight: _layout.chatFontWeight,
                        messageFooter: UpdateNotice(
                          interactive: _hostState.interactive,
                          onUpdate: widget.overlayHost.openUpdater,
                        ),
                        authState: _authState,
                        chatState: _chatState,
                        messageLifetimeMinutes: _layout.messageLifetimeMinutes,
                        interactive: _hostState.interactive,
                        onSignIn: () async {
                          await widget.overlayHost.setInteractive(false);
                          await widget.twitchAuth.signIn();
                        },
                        onSignOut: widget.twitchAuth.signOut,
                        onSend: widget.twitchChat.send,
                        onDeleteMessage: widget.twitchChat.deleteMessage,
                        onLoadEmotes: widget.twitchChat.loadEmotes,
                      ),
                    ),
                  ),
                ),
                if (_hostState.interactive)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 18,
                    child: IgnorePointer(child: _EditModeBanner()),
                  ),
                if (_settingsOpen && _hostState.interactive)
                  Positioned.fromRect(
                    rect: OverlaySettingsPanel.placeBeside(rect, viewport),
                    child: OverlaySettingsPanel(
                      key: const ValueKey('overlay-settings-panel'),
                      layout: _layout,
                      onChanged: _updateLayout,
                      onChangeEnd: _saveLayout,
                      onClose: _closeSettings,
                      onCaptureExclusionChanged: (value) =>
                          unawaited(_changeCaptureExclusion(value)),
                      changingCaptureExclusion: _changingCaptureExclusion,
                      captureExclusionFailed: _captureExclusionFailed,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openSettingsFromTray() async {
    await widget.overlayHost.setInteractive(true);
    if (mounted && widget.overlayHost.state.interactive) {
      setState(() => _settingsOpen = true);
    }
  }

  void _toggleSettings() {
    if (_settingsOpen) {
      _closeSettings();
    } else {
      setState(() => _settingsOpen = true);
    }
  }

  void _closeSettings() {
    if (!_settingsOpen) return;
    _saveLayout();
    setState(() => _settingsOpen = false);
  }

  KeyEventResult _handleSettingsKey(KeyEvent event) {
    if (_settingsOpen && event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _closeSettings();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  static void _reportTrayError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'overlay tray localization',
      ),
    );
  }

  void _updateLayout(OverlayLayout value) {
    setState(() => _layout = value);
    widget.twitchChat.setEmoteOptions(value.emoteOptions);
  }

  void _saveLayout() {
    unawaited(widget.layoutStore.save(_layout));
  }

  Future<void> _changeCaptureExclusion(bool excluded) async {
    if (_changingCaptureExclusion) return;
    setState(() {
      _changingCaptureExclusion = true;
      _captureExclusionFailed = false;
    });
    try {
      await widget.overlayHost.setExcludedFromCapture(excluded);
    } on PlatformException {
      if (mounted) setState(() => _captureExclusionFailed = true);
      return;
    } finally {
      if (mounted) setState(() => _changingCaptureExclusion = false);
    }
    if (!mounted) return;
    setState(() => _layout = _layout.withExcludedFromCapture(excluded));
    _saveLayout();
  }

  void _onAuthState(TwitchAuthState state) {
    if (mounted) setState(() => _authState = state);
    final token = state.token;
    if (state.status == TwitchAuthStatus.signedIn && token != null) {
      unawaited(widget.twitchChat.join(broadcasterId: token.userId));
    } else if (state.status == TwitchAuthStatus.signedOut ||
        state.status == TwitchAuthStatus.failure) {
      unawaited(widget.twitchChat.leave());
    }
  }
}

class _EditModeBanner extends StatelessWidget {
  const _EditModeBanner();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xE61F1F23),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF9146FF)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            AppLocalizations.of(context).layoutModeBanner,
            style: const TextStyle(
              shadows: chatTextShadows,
              fontSize: 12,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _VirtualChatWindow extends StatelessWidget {
  const _VirtualChatWindow({
    required this.editing,
    required this.signedIn,
    required this.contentOpacity,
    required this.showConnectionIndicator,
    required this.gifPlayCount,
    required this.settingsOpen,
    required this.onSettings,
    required this.onMove,
    required this.onResize,
    required this.onGestureEnd,
    required this.onLock,
    required this.onCycleLocale,
    required this.connectionStatus,
    required this.child,
  });

  final bool editing;
  final bool signedIn;
  final double contentOpacity;
  final bool showConnectionIndicator;
  final int gifPlayCount;
  final bool settingsOpen;
  final VoidCallback onSettings;
  final ValueChanged<Offset> onMove;
  final void Function(ResizeHandle handle, Offset delta) onResize;
  final VoidCallback onGestureEnd;
  final VoidCallback onLock;
  final VoidCallback? onCycleLocale;
  final ChatConnectionStatus connectionStatus;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Positioned.fill(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Opacity(
              opacity: contentOpacity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: BackgroundOpacity.colorOf(
                    context,
                    const Color(0xFF111114),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: editing
                        ? const Color(0xFF9146FF)
                        : BackgroundOpacity.colorOf(
                            context,
                            const Color(0x339146FF),
                          ),
                    width: editing ? 2 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 18,
                      color: BackgroundOpacity.colorOf(
                        context,
                        const Color(0x66000000),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(editing ? 2 : 1),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(editing ? 10 : 11),
                child: Column(
                  children: [
                    if (editing || !signedIn)
                      Opacity(
                        opacity: editing ? 1 : contentOpacity,
                        child: _ChatHeader(
                          editing: editing,
                          showConnectionIndicator:
                              editing || showConnectionIndicator,
                          settingsOpen: settingsOpen,
                          onSettings: onSettings,
                          onMove: onMove,
                          onGestureEnd: onGestureEnd,
                          onLock: onLock,
                          onCycleLocale: onCycleLocale,
                          connectionStatus: connectionStatus,
                        ),
                      ),
                    Expanded(
                      child: Opacity(
                        key: const ValueKey('chat-content-opacity'),
                        opacity: contentOpacity,
                        child: GifPlayback(
                          playCount: gifPlayCount,
                          child: child,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      if (editing)
        for (final handle in ResizeHandle.values)
          _ResizeHandle(
            handle: handle,
            onResize: (delta) => onResize(handle, delta),
            onGestureEnd: onGestureEnd,
          ),
    ],
  );
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.showConnectionIndicator,
    required this.editing,
    required this.settingsOpen,
    required this.onSettings,
    required this.onMove,
    required this.onGestureEnd,
    required this.onLock,
    required this.onCycleLocale,
    required this.connectionStatus,
  });

  final bool editing;
  final bool settingsOpen;
  final VoidCallback onSettings;
  final bool showConnectionIndicator;
  final ValueChanged<Offset> onMove;
  final VoidCallback onGestureEnd;
  final VoidCallback onLock;
  final VoidCallback? onCycleLocale;
  final ChatConnectionStatus connectionStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: editing ? (details) => onMove(details.delta) : null,
      onPanEnd: editing ? (_) => onGestureEnd() : null,
      child: Container(
        key: const ValueKey('chat-header'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: BackgroundOpacity.colorOf(context, const Color(0xF21F1F23)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.chat_bubble_rounded,
              shadows: chatTextShadows,
              size: 17,
            ),
            const Gap(8),
            Expanded(
              child: Text(
                l10n.twitchChatTitle,
                style: const TextStyle(
                  shadows: chatTextShadows,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            if (showConnectionIndicator)
              Container(
                key: const ValueKey('chat-header-connection-indicator'),
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _connectionColor(connectionStatus),
                  shape: BoxShape.circle,
                ),
              ),
            if (!editing) ...[
              const Gap(10),
              const Text(
                'Ctrl+Shift+O',
                style: TextStyle(
                  shadows: chatTextShadows,
                  fontSize: 10,
                  color: Colors.white,
                ),
              ),
            ],
            if (editing) ...[
              const Gap(12),
              if (onCycleLocale != null) ...[
                OverlayActionButton(
                  key: const ValueKey('locale-toggle'),
                  onPressed: onCycleLocale!,
                  child: AutoSizeText(
                    l10n.localeName.toUpperCase(),
                    maxLines: 1,
                    minFontSize: 1,
                    maxFontSize: 10,
                    stepGranularity: 0.5,
                    wrapWords: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      shadows: chatTextShadows,
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Gap(4),
              ],
              OverlayActionButton(
                key: const ValueKey('settings-toggle'),
                tooltip: l10n.overlaySettings,
                selected: settingsOpen,
                onPressed: onSettings,
                child: Icon(
                  settingsOpen
                      ? Icons.settings_rounded
                      : Icons.settings_outlined,
                  shadows: chatTextShadows,
                  size: 17,
                ),
              ),
              const Gap(4),
              OverlayActionButton(
                key: const ValueKey('lock-overlay'),
                tooltip: l10n.lockOverlay,
                onPressed: onLock,
                child: const Icon(
                  Icons.lock_outline_rounded,
                  shadows: chatTextShadows,
                  size: 17,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static Color _connectionColor(ChatConnectionStatus status) {
    return switch (status) {
      ChatConnectionStatus.connected => const Color(0xFF52D273),
      ChatConnectionStatus.failure => const Color(0xFFFF7676),
      ChatConnectionStatus.connecting ||
      ChatConnectionStatus.reconnecting => const Color(0xFFFFB31A),
      ChatConnectionStatus.idle => const Color(0xFF6F6F78),
    };
  }
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({
    required this.handle,
    required this.onResize,
    required this.onGestureEnd,
  });

  static const double _thickness = 14;
  static const double _cornerSize = 28;
  static const double _edgeInset = _cornerSize - _thickness / 2;

  final ResizeHandle handle;
  final ValueChanged<Offset> onResize;
  final VoidCallback onGestureEnd;

  @override
  Widget build(BuildContext context) {
    final corner = _isCorner(handle);
    final horizontal =
        handle == ResizeHandle.top || handle == ResizeHandle.bottom;
    final vertical =
        handle == ResizeHandle.left || handle == ResizeHandle.right;

    return Positioned(
      left: _onLeft(handle)
          ? -_thickness / 2
          : horizontal
          ? _edgeInset
          : null,
      right: _onRight(handle)
          ? -_thickness / 2
          : horizontal
          ? _edgeInset
          : null,
      top: _onTop(handle)
          ? -_thickness / 2
          : vertical
          ? _edgeInset
          : null,
      bottom: _onBottom(handle)
          ? -_thickness / 2
          : vertical
          ? _edgeInset
          : null,
      width: corner ? _cornerSize : (vertical ? _thickness : null),
      height: corner ? _cornerSize : (horizontal ? _thickness : null),
      child: MouseRegion(
        cursor: _cursor(handle),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanUpdate: (details) => onResize(details.delta),
          onPanEnd: (_) => onGestureEnd(),
          child: corner
              ? CustomPaint(
                  painter: _CornerGripPainter(
                    flipX: _onRight(handle),
                    flipY: _onBottom(handle),
                  ),
                  child: const SizedBox.expand(),
                )
              : const SizedBox.expand(),
        ),
      ),
    );
  }

  static bool _isCorner(ResizeHandle value) => switch (value) {
    ResizeHandle.topLeft ||
    ResizeHandle.topRight ||
    ResizeHandle.bottomRight ||
    ResizeHandle.bottomLeft => true,
    _ => false,
  };

  static bool _onLeft(ResizeHandle value) => switch (value) {
    ResizeHandle.topLeft ||
    ResizeHandle.left ||
    ResizeHandle.bottomLeft => true,
    _ => false,
  };

  static bool _onRight(ResizeHandle value) => switch (value) {
    ResizeHandle.topRight ||
    ResizeHandle.right ||
    ResizeHandle.bottomRight => true,
    _ => false,
  };

  static bool _onTop(ResizeHandle value) => switch (value) {
    ResizeHandle.topLeft || ResizeHandle.top || ResizeHandle.topRight => true,
    _ => false,
  };

  static bool _onBottom(ResizeHandle value) => switch (value) {
    ResizeHandle.bottomLeft ||
    ResizeHandle.bottom ||
    ResizeHandle.bottomRight => true,
    _ => false,
  };

  static MouseCursor _cursor(ResizeHandle handle) {
    return switch (handle) {
      ResizeHandle.topLeft ||
      ResizeHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      ResizeHandle.topRight ||
      ResizeHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
      ResizeHandle.top ||
      ResizeHandle.bottom => SystemMouseCursors.resizeUpDown,
      ResizeHandle.left ||
      ResizeHandle.right => SystemMouseCursors.resizeLeftRight,
    };
  }
}

class _CornerGripPainter extends CustomPainter {
  const _CornerGripPainter({required this.flipX, required this.flipY});

  final bool flipX;
  final bool flipY;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF9146FF)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(flipX ? size.width : 0, flipY ? size.height : 0);
    canvas.scale(flipX ? -1 : 1, flipY ? -1 : 1);
    // The frame sits 7 px inside the handle; keep both strokes inside its arc.
    canvas.drawLine(const Offset(13, 21), const Offset(21, 13), paint);
    canvas.drawLine(const Offset(13, 16), const Offset(16, 13), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CornerGripPainter oldDelegate) =>
      flipX != oldDelegate.flipX || flipY != oldDelegate.flipY;
}
