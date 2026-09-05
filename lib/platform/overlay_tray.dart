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
  bool _iconCreated = false;
  bool _disposed = false;
  bool _exiting = false;

  Future<void> initialize(AppLocalizations strings) =>
      _initialization ??= _initialize(strings);

  Future<void> _initialize(AppLocalizations strings) async {
    try {
      await tray.trayManager.setIcon(iconAsset);
      _iconCreated = true;
      await tray.trayManager.setToolTip(strings.appTitle);
      await tray.trayManager.setContextMenu(
        tray.Menu(
          items: [
            tray.MenuItem(key: 'configure', label: strings.trayConfigure),
            tray.MenuItem.separator(),
            tray.MenuItem(key: 'exit', label: strings.exitApp),
          ],
        ),
      );
      if (!_disposed) tray.trayManager.addListener(this);
    } catch (_) {
      await _destroyIcon();
      rethrow;
    }
  }

  Future<void> dispose() {
    _disposed = true;
    tray.trayManager.removeListener(this);
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
  void onTrayIconMouseDown() => _configure();

  @override
  void onTrayIconRightMouseDown() {
    if (_disposed || _exiting) return;
    // Windows needs the menu owner in the foreground to dismiss the native
    // popup on an outside click, including while the overlay is click-through.
    unawaited(
      tray.trayManager
          .popUpContextMenu(
            // ignore: deprecated_member_use
            bringAppToFront: true,
          )
          .catchError(_reportError),
    );
  }

  @override
  void onTrayMenuItemClick(tray.MenuItem menuItem) {
    switch (menuItem.key) {
      case 'configure':
        _configure();
      case 'exit':
        if (_disposed || _exiting) return;
        _exiting = true;
        unawaited(_exit().catchError(_reportError));
    }
  }

  void _configure() {
    if (_disposed || _exiting) return;
    unawaited(host.setInteractive(true).catchError(_reportError));
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
