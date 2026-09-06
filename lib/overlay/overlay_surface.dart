import 'dart:async';

import 'package:twitch_chat_overlay/updates/update_notice.dart';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/overlay/message_lifetime_control.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout_store.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/platform/overlay_tray.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

class OverlaySurface extends StatefulWidget {
  const OverlaySurface({
    required this.initialLayout,
    required this.layoutStore,
    required this.overlayHost,
    required this.twitchAuth,
    required this.twitchChat,
    this.onCycleLocale,
    this.beforeExit,
    super.key,
  });

  final OverlayLayout initialLayout;
  final OverlayLayoutStore layoutStore;
  final OverlayHost overlayHost;
  final TwitchAuth twitchAuth;
  final TwitchChatSession twitchChat;
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

  @override
  void initState() {
    super.initState();
    _layout = widget.initialLayout;
    _hostState = widget.overlayHost.state;
    _authState = widget.twitchAuth.state;
    _chatState = widget.twitchChat.state;
    _hostSubscription = widget.overlayHost.states.listen((state) {
      if (mounted) setState(() => _hostState = state);
    });
    _authSubscription = widget.twitchAuth.states.listen(_onAuthState);
    _chatSubscription = widget.twitchChat.states.listen((state) {
      if (mounted) setState(() => _chatState = state);
    });
    unawaited(widget.overlayHost.initialize());
    unawaited(widget.twitchAuth.initialize());
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
      host: widget.overlayHost,
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
                      backgroundOpacity: _layout.backgroundOpacity,
                      messageLifetimeMinutes: _layout.messageLifetimeMinutes,
                      onMessageLifetimeChanged: (value) {
                        _updateLayout(
                          _layout.withMessageLifetimeMinutes(value),
                        );
                        _saveLayout();
                      },
                      onOpacityChanged: (value) =>
                          _updateLayout(_layout.withBackgroundOpacity(value)),
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
              ],
            );
          },
        ),
      ),
    );
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
  }

  void _saveLayout() {
    unawaited(widget.layoutStore.save(_layout));
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
            style: const TextStyle(fontSize: 12, color: Colors.white),
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
    required this.backgroundOpacity,
    required this.messageLifetimeMinutes,
    required this.onMessageLifetimeChanged,
    required this.onOpacityChanged,
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
  final double backgroundOpacity;
  final int messageLifetimeMinutes;
  final ValueChanged<int> onMessageLifetimeChanged;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<Offset> onMove;
  final void Function(ResizeHandle handle, Offset delta) onResize;
  final VoidCallback onGestureEnd;
  final VoidCallback onLock;
  final VoidCallback? onCycleLocale;
  final ChatConnectionStatus connectionStatus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: Container(
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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(editing ? 10 : 11),
              child: Column(
                children: [
                  if (editing || !signedIn)
                    _ChatHeader(
                      editing: editing,
                      onMove: onMove,
                      onGestureEnd: onGestureEnd,
                      onLock: onLock,
                      onCycleLocale: onCycleLocale,
                      connectionStatus: connectionStatus,
                    ),
                  if (editing)
                    _BackgroundTransparencySlider(
                      opacity: backgroundOpacity,
                      onChanged: onOpacityChanged,
                      onChangeEnd: onGestureEnd,
                    ),
                  if (editing)
                    MessageLifetimeControl(
                      minutes: messageLifetimeMinutes,
                      onChanged: onMessageLifetimeChanged,
                    ),
                  Expanded(child: child),
                ],
              ),
            ),
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
}

class _BackgroundTransparencySlider extends StatelessWidget {
  const _BackgroundTransparencySlider({
    required this.opacity,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final double opacity;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final label = AppLocalizations.of(context).backgroundTransparency;
    final transparency = 1 - opacity;
    final percent = '${(transparency * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: const Color(0xF21F1F23),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
          ),
          Expanded(
            child: Semantics(
              label: label,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  activeTrackColor: const Color(0xFFBF94FF),
                  thumbColor: const Color(0xFFBF94FF),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  value: transparency,
                  divisions: 100,
                  label: percent,
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()}%',
                  onChanged: (value) => onChanged(1 - value),
                  onChangeEnd: (_) => onChangeEnd(),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              percent,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.editing,
    required this.onMove,
    required this.onGestureEnd,
    required this.onLock,
    required this.onCycleLocale,
    required this.connectionStatus,
  });

  final bool editing;
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
            const Icon(Icons.chat_bubble_rounded, size: 17),
            const Gap(8),
            Expanded(
              child: Text(
                l10n.twitchChatTitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                ),
              ),
            ),
            Container(
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
                style: TextStyle(fontSize: 10, color: Color(0xFFADADB8)),
              ),
            ],
            if (editing) ...[
              const Gap(12),
              if (onCycleLocale != null)
                TextButton(
                  key: const ValueKey('locale-toggle'),
                  onPressed: onCycleLocale,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFBF94FF),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(l10n.localeName.toUpperCase()),
                ),
              const Gap(4),
              IconButton(
                style: IconButton.styleFrom(
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                tooltip: l10n.lockOverlay,
                onPressed: onLock,
                icon: const Icon(Icons.lock_outline_rounded, size: 17),
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
