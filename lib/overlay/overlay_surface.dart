import 'dart:async';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/widgets/overlay_action_button.dart';
import 'package:twitch_chat_overlay/chat/chat_panel.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/chat/gif_playback.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/overlay/overlay_layout.dart';
import 'package:twitch_chat_overlay/overlay/overlay_view_model.dart';
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
  late final OverlayViewModel _viewModel;
  OverlayTray? _tray;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleSettingsKey);
    _viewModel = OverlayViewModel(
      initialLayout: widget.initialLayout,
      layoutStore: widget.layoutStore,
      host: widget.overlayHost,
      auth: widget.twitchAuth,
      chat: widget.twitchChat,
    );
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
      onConfigure: _viewModel.openSettings,
      beforeExit: () async {
        await _viewModel.saveLayout();
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
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ObservableBuilder<OverlayFrameState>(
    source: _viewModel.frame,
    builder: (context, state, _) => _buildSurface(context, state),
  );

  Widget _buildSurface(BuildContext context, OverlayFrameState state) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ColoredBox(
        color: Colors.transparent,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = constraints.biggest;
            final rect = state.layout.resolve(viewport);
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: BackgroundOpacity(
                    opacity: state.layout.backgroundOpacity,
                    child: _VirtualChatWindow(
                      editing: state.host.interactive,
                      onCycleLocale: widget.onCycleLocale,
                      signedIn: _viewModel.signedIn,
                      contentOpacity: state.layout.contentOpacity,
                      showConnectionIndicator:
                          state.layout.showConnectionIndicator,
                      gifPlayCount: state.layout.gifPlayCount,
                      settingsOpen: state.settingsOpen,
                      onSettings: _viewModel.toggleSettings,
                      onMove: (delta) => _viewModel.move(delta, viewport),
                      onResize: (handle, delta) =>
                          _viewModel.resize(handle, delta, viewport),
                      onGestureEnd: _viewModel.saveLayout,
                      onLock: () => unawaited(_viewModel.lock()),
                      connectionStatus: _viewModel.connectionStatus,
                      child: ChatPanel(
                        showViewerCount: state.layout.showViewerCount,
                        showConnectionIndicator:
                            state.layout.showConnectionIndicator,
                        chatFontSize: state.layout.chatFontSize,
                        chatFontWeight: state.layout.chatFontWeight,
                        messageFooter: UpdateNotice(
                          interactive: state.host.interactive,
                          onUpdate: widget.overlayHost.openUpdater,
                        ),
                        authSource: _viewModel.authState,
                        chatSource: _viewModel.chatState,
                        messageLifetimeMinutes:
                            state.layout.messageLifetimeMinutes,
                        interactive: state.host.interactive,
                        onSignIn: _viewModel.signIn,
                        onSignOut: _viewModel.signOut,
                        onSend: widget.twitchChat.send,
                        onDeleteMessage: widget.twitchChat.deleteMessage,
                        onLoadEmotes: widget.twitchChat.loadEmotes,
                      ),
                    ),
                  ),
                ),
                if (state.host.interactive)
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: 18,
                    child: IgnorePointer(child: _EditModeBanner()),
                  ),
                if (state.settingsOpen && state.host.interactive)
                  Positioned.fromRect(
                    rect: OverlaySettingsPanel.placeBeside(rect, viewport),
                    child: OverlaySettingsPanel(
                      key: const ValueKey('overlay-settings-panel'),
                      layout: state.layout,
                      onChanged: _viewModel.updateLayout,
                      onChangeEnd: _viewModel.saveLayout,
                      onClose: _viewModel.closeSettings,
                      onCaptureExclusionChanged: (value) =>
                          unawaited(_viewModel.changeCaptureExclusion(value)),
                      changingCaptureExclusion:
                          state.captureExclusionProcess.isActive,
                      captureExclusionFailed:
                          state.captureExclusionProcess.error ==
                          OverlayFailure.captureExclusion,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  KeyEventResult _handleSettingsKey(KeyEvent event) {
    if (_viewModel.frame.current.settingsOpen &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _viewModel.closeSettings();
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
  final Observable<bool> signedIn;
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
  final Observable<ChatConnectionStatus> connectionStatus;
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
                    ObservableBuilder<bool>(
                      source: signedIn,
                      builder: (context, signedIn, _) => editing || !signedIn
                          ? Opacity(
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
                            )
                          : const SizedBox.shrink(),
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
  final Observable<ChatConnectionStatus> connectionStatus;

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
              ObservableBuilder<ChatConnectionStatus>(
                source: connectionStatus,
                builder: (context, status, _) => Container(
                  key: const ValueKey('chat-header-connection-indicator'),
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: _connectionColor(status),
                    shape: BoxShape.circle,
                  ),
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
