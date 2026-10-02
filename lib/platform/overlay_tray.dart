import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';

/// Creates the native resources; tests can supply handles without calling FFI.
class TrayFactory {
  const TrayFactory();

  tray.TrayIcon createIcon() =>
      tray.TrayIcon.create() ??
      (throw StateError('Unable to create the tray icon'));
  tray.Image loadImage(String asset) =>
      tray.ImageAsset.fromAsset(asset) ??
      (throw StateError('Unable to load the tray icon: $asset'));
  tray.Menu createMenu() =>
      tray.Menu.create() ??
      (throw StateError('Unable to create the tray menu'));
  tray.MenuItem createItem(String label) =>
      tray.MenuItem.createWithLabelAndType(label, tray.MenuItemType.normal) ??
      (throw StateError('Unable to create tray menu item: $label'));
}

/// Owns one tray icon, its menu, listeners, and the application actions.
final class OverlayTray {
  OverlayTray({
    required this.host,
    required this.beforeExit,
    this.onConfigure,
    this.factory = const TrayFactory(),
  });

  static const iconAsset = 'windows/runner/resources/app_icon.ico';
  final OverlayHost host;
  final Future<void> Function() beforeExit;
  final Future<void> Function()? onConfigure;
  final TrayFactory factory;
  Future<void>? _initialization;
  Future<void>? _disposal;
  late AppLocalizations _strings;
  StreamSubscription<void>? _closeSubscription;
  tray.TrayIcon? _icon;
  tray.Image? _image;
  tray.Menu? _menu;
  tray.ListenerId? _iconListener;
  final _items = <tray.MenuItem, tray.ListenerId>{};
  late tray.MenuItem _visibilityItem;
  late tray.MenuItem _configureItem;
  late tray.MenuItem _updateItem;
  late tray.MenuItem _exitItem;
  bool _visible = true;
  bool _disposed = false;
  bool _exiting = false;

  Future<void> initialize(AppLocalizations strings) =>
      _initialization ??= _initialize(strings);

  Future<void> _initialize(AppLocalizations strings) async {
    _strings = strings;
    try {
      final icon = _icon = factory.createIcon();
      _image = factory.loadImage(iconAsset);
      icon.icon = _image;
      // Refresh Show/Hide from the host before opening the native menu.
      icon.setContextMenuTrigger(tray.ContextMenuTrigger.none);
      _menu = factory.createMenu();
      _visibilityItem = _addItem(
        _strings.trayHide,
        () => unawaited(host.setVisible(!_visible).catchError(_reportError)),
      );
      _configureItem = _addItem(
        _strings.trayConfigure,
        () => unawaited(
          (onConfigure?.call() ?? host.setInteractive(true)).catchError(
            _reportError,
          ),
        ),
      );
      _updateItem = _addItem(
        _strings.trayUpdate,
        () => unawaited(
          host.openUpdater(_strings.localeName).catchError(_reportError),
        ),
      );
      _menu!.addSeparator();
      _exitItem = _addItem(_strings.exitApp, _requestExit);
      icon.setContextMenu(_menu);
      _iconListener = icon.addListener(_onIconEvent);
      _closeSubscription = host.closeRequests.listen((_) => _requestExit());
      await _updateMenu();
      if (!_disposed && !icon.setVisible(true)) {
        throw StateError('Unable to show the tray icon');
      }
    } catch (_) {
      _releaseNativeResources();
      rethrow;
    }
  }

  tray.MenuItem _addItem(String label, VoidCallback action) {
    final item = factory.createItem(label);
    final listener = item.addListener((event) {
      if (event is! tray.MenuItemClickedEvent) return;
      // Native callbacks must return before an action can release their handles.
      scheduleMicrotask(() {
        if (!_disposed && !_exiting) action();
      });
    });
    _items[item] = listener;
    _menu!.addItem(item);
    return item;
  }

  Future<void> updateLocalizations(AppLocalizations strings) async {
    _strings = strings;
    await _initialization;
    await _updateMenu();
  }

  Future<void> _updateMenu() async {
    if (_disposed || _exiting) return;
    final visible = await host.isVisible();
    if (_disposed || _exiting) return;
    _visible = visible;
    _icon!.setTooltip(_strings.appTitle);
    // Keep native items and listeners alive; only their labels need updating.
    _visibilityItem.label = visible ? _strings.trayHide : _strings.trayShow;
    _configureItem.label = _strings.trayConfigure;
    _updateItem.label = _strings.trayUpdate;
    _exitItem.label = _strings.exitApp;
  }

  void _onIconEvent(tray.TrayIconEvent event) {
    if (_disposed || _exiting) return;
    switch (event) {
      case tray.TrayIconClickedEvent():
        unawaited(host.setVisible(true).catchError(_reportError));
      case tray.TrayIconRightClickedEvent():
        unawaited(_openMenu().catchError(_reportError));
      case tray.TrayIconDoubleClickedEvent():
        break;
    }
  }

  Future<void> _openMenu() async {
    await _updateMenu();
    if (_disposed || _exiting) return;
    _icon!.openContextMenu();
  }

  Future<void> dispose() {
    _disposed = true;
    unawaited(_closeSubscription?.cancel());
    _closeSubscription = null;
    return _disposal ??= _destroy();
  }

  Future<void> _destroy() async {
    try {
      await _initialization;
    } catch (_) {
      // Initialization has already released partially created native resources.
      return;
    }
    _releaseNativeResources();
  }

  void _releaseNativeResources() {
    unawaited(_closeSubscription?.cancel());
    _closeSubscription = null;
    final icon = _icon;
    if (icon != null) {
      if (_iconListener case final listener?) icon.removeListener(listener);
      _iconListener = null;
      icon.closeContextMenu();
      icon.setContextMenu(null);
      icon.setVisible(false);
      icon.dispose();
      _icon = null;
    }
    for (final entry in _items.entries) {
      entry.key.removeListener(entry.value);
      entry.key.dispose();
    }
    _items.clear();
    _menu?.dispose();
    _menu = null;
    _image?.dispose();
    _image = null;
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
