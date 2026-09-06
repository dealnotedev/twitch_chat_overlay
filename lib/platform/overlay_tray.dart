import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';

/// Owns the package's tray icon, native menu and their application actions.
final class OverlayTray with tray.TrayListener {
  OverlayTray({required this.host, required this.beforeExit});

  static const iconAsset = 'windows/runner/resources/app_icon.ico';

  final OverlayHost host;
  final Future<void> Function() beforeExit;
  Future<void>? _initialization;
  Future<void>? _disposal;
  late AppLocalizations _strings;
  StreamSubscription<void>? _closeSubscription;
  bool _iconCreated = false;
  bool _disposed = false;
  bool _exiting = false;

  Future<void> initialize(AppLocalizations strings) =>
      _initialization ??= _initialize(strings);

  Future<void> _initialize(AppLocalizations strings) async {
    _strings = strings;
    try {
      await tray.trayManager.setIcon(iconAsset);
      _iconCreated = true;
      await tray.trayManager.setToolTip(strings.appTitle);
      await _updateMenu();
      if (!_disposed) {
        tray.trayManager.addListener(this);
        _closeSubscription = host.closeRequests.listen((_) => _requestExit());
      }
    } catch (_) {
      await _destroyIcon();
      rethrow;
    }
  }

  Future<void> updateLocalizations(AppLocalizations strings) async {
    _strings = strings;
    await _initialization;
    if (_disposed || _exiting) return;
    await tray.trayManager.setToolTip(_strings.appTitle);
    await _updateMenu();
  }

  Future<void> _updateMenu() async {
    final visible = await host.isVisible();
    if (_disposed || _exiting) return;
    await tray.trayManager.setContextMenu(
      tray.Menu(
        items: [
          if (visible)
            tray.MenuItem(key: 'hide', label: _strings.trayHide)
          else
            tray.MenuItem(key: 'show', label: _strings.trayShow),
          tray.MenuItem(key: 'configure', label: _strings.trayConfigure),
          tray.MenuItem(key: 'update', label: _strings.trayUpdate),
          tray.MenuItem.separator(),
          tray.MenuItem(key: 'exit', label: _strings.exitApp),
        ],
      ),
    );
  }

  Future<void> dispose() {
    _disposed = true;
    tray.trayManager.removeListener(this);
    unawaited(_closeSubscription?.cancel());
    _closeSubscription = null;
    return _disposal ??= _destroy();
  }

  Future<void> _destroy() async {
    try {
      await _initialization;
    } catch (_) {
      // Initialization cleaned up; its caller receives the original failure.
      return;
    }
    await _destroyIcon();
  }

  Future<void> _destroyIcon() async {
    if (_iconCreated) {
      _iconCreated = false;
      await tray.trayManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() {
    if (_disposed || _exiting) return;
    unawaited(host.setVisible(true).catchError(_reportError));
  }

  @override
  void onTrayIconRightMouseDown() {
    if (_disposed || _exiting) return;
    unawaited(_openMenu().catchError(_reportError));
  }

  Future<void> _openMenu() async {
    // Read native visibility on every opening, including after the hotkey.
    await _updateMenu();
    if (_disposed || _exiting) return;
    // Windows needs the menu owner in the foreground to dismiss the native
    // popup on an outside click, including while the overlay is click-through.
    await tray.trayManager.popUpContextMenu(
      // ignore: deprecated_member_use
      bringAppToFront: true,
    );
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    if (_disposed || _exiting) return;
    switch (menuItem.key) {
      case 'show':
        unawaited(host.setVisible(true).catchError(_reportError));
      case 'hide':
        unawaited(host.setVisible(false).catchError(_reportError));
      case 'configure':
        _configure();
      case 'update':
        unawaited(
          host.openUpdater(_strings.localeName).catchError(_reportError),
        );
      case 'exit':
        _requestExit();
    }
  }

  void _configure() {
    if (_disposed || _exiting) return;
    unawaited(host.setInteractive(true).catchError(_reportError));
  }

  void _requestExit() {
    if (_disposed || _exiting) return;
    _exiting = true;
    unawaited(_exit().catchError(_reportError));
  }

  Future<void> _exit() async {
    try {
      await beforeExit();
    } finally {
      try {
        await dispose();
      } finally {
        await host.close();
      }
    }
  }

  static void _reportError(Object error, StackTrace stack) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'overlay tray',
      ),
    );
  }
}
