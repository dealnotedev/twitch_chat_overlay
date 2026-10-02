import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:twitch_chat_overlay/platform/overlay_tray.dart';

class FakeTrayFactory extends Fake implements TrayFactory {
  final icon = FakeTrayIcon();
  final image = FakeTrayImage();
  final menu = FakeTrayMenu();
  final items = <FakeTrayItem>[];
  int creations = 0;
  String? imageAsset;
  bool failMenu = false;
  @override
  tray.TrayIcon createIcon() {
    creations++;
    return icon;
  }

  @override
  tray.Image loadImage(String asset) {
    imageAsset = asset;
    return image;
  }

  @override
  tray.Menu createMenu() {
    if (failMenu) throw StateError('menu_failed');
    return menu;
  }

  @override
  tray.MenuItem createItem(String label) {
    final item = FakeTrayItem(label);
    items.add(item);
    return item;
  }
}

class FakeTrayIcon extends Fake implements tray.TrayIcon {
  @override
  tray.Image? icon;
  @override
  void setTooltip(String? value) {
    tooltip = value;
  }

  String? tooltip;
  tray.ContextMenuTrigger? trigger;
  tray.Menu? menu;
  bool visible = false;
  int opens = 0;
  int disposals = 0;
  void Function()? onDispose;
  void Function(tray.TrayIconEvent)? listener;
  @override
  void setContextMenuTrigger(tray.ContextMenuTrigger value) {
    trigger = value;
  }

  @override
  void setContextMenu(tray.Menu? value) {
    menu = value;
  }

  @override
  bool setVisible(bool value) {
    visible = value;
    return true;
  }

  @override
  bool openContextMenu() {
    opens++;
    return true;
  }

  @override
  bool closeContextMenu() => true;
  @override
  tray.ListenerId addListener(void Function(tray.TrayIconEvent) callback) {
    listener = callback;
    return 1;
  }

  @override
  bool removeListener(tray.ListenerId id) {
    listener = null;
    return true;
  }

  @override
  void dispose() {
    disposals++;
    onDispose?.call();
  }

  void click() =>
      listener?.call(const tray.TrayIconClickedEvent(trayIconId: 1));
  void rightClick() =>
      listener?.call(const tray.TrayIconRightClickedEvent(trayIconId: 1));
}

class FakeTrayImage extends Fake implements tray.Image {
  int disposals = 0;
  @override
  void dispose() {
    disposals++;
  }
}

class FakeTrayMenu extends Fake implements tray.Menu {
  final entries = <tray.MenuItem?>[];
  int disposals = 0;
  @override
  void addItem(tray.MenuItem? item) {
    entries.add(item);
  }

  @override
  void addSeparator() {
    entries.add(null);
  }

  @override
  void dispose() {
    disposals++;
  }
}

class FakeTrayItem extends Fake implements tray.MenuItem {
  FakeTrayItem(this.label);
  @override
  String? label;
  int disposals = 0;
  void Function(tray.MenuEvent)? listener;
  @override
  tray.ListenerId addListener(void Function(tray.MenuEvent) callback) {
    listener = callback;
    return 1;
  }

  @override
  bool removeListener(tray.ListenerId id) {
    listener = null;
    return true;
  }

  @override
  void dispose() {
    disposals++;
  }

  void click() => listener?.call(const tray.MenuItemClickedEvent(itemId: 1));
}
