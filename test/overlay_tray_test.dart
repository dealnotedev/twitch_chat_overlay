import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/platform/overlay_tray.dart';

import 'support/fake_tray_factory.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const hostChannel = MethodChannel('overlay/window');
  late OverlayTray controller;
  late MethodChannelOverlayHost host;
  late FakeTrayFactory factory;
  late AppLocalizations ukrainian;
  late List<MethodCall> hostCalls;
  late bool visible;
  late List<String> actions;
  late Completer<void> closed;

  Future<void> click(int item) async {
    factory.items[item].click();
    await pumpEventQueue();
  }

  Future<void> openMenu() async {
    factory.icon.rightClick();
    await pumpEventQueue();
  }

  setUp(() async {
    visible = true;
    actions = [];
    hostCalls = [];
    closed = Completer<void>();
    factory = FakeTrayFactory();
    factory.icon.onDispose = () => actions.add('destroy');
    ukrainian = await AppLocalizations.delegate.load(const Locale('uk'));
    host = MethodChannelOverlayHost();
    controller = OverlayTray(
      host: host,
      factory: factory,
      beforeExit: () async => actions.add('save'),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(hostChannel, (
      call,
    ) async {
      hostCalls.add(call);
      if (call.method == 'isVisible') return visible;
      if (call.method == 'setVisible') visible = call.arguments as bool;
      if (call.method == 'setInteractive' && call.arguments == true) {
        visible = true;
      }
      if (call.method == 'close') {
        actions.add('close');
        closed.complete();
      }
      return null;
    });
    await host.initialize();
    hostCalls.clear();
  });
  tearDown(() async {
    await controller.dispose();
    expect(factory.icon.listener, isNull);
    expect(factory.items.every((item) => item.listener == null), isTrue);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(hostChannel, null);
  });

  test('native icon routes localized menu and clicks', () async {
    await controller.initialize(ukrainian);
    expect(factory.imageAsset, OverlayTray.iconAsset);
    expect(factory.icon.icon, same(factory.image));
    expect(factory.icon.visible, isTrue);
    expect(factory.icon.trigger, tray.ContextMenuTrigger.none);
    expect(factory.icon.tooltip, ukrainian.appTitle);
    expect(factory.items.map((item) => item.label), [
      'Приховати оверлей',
      'Налаштувати оверлей',
      'Перевірити оновлення…',
      'Вийти',
    ]);
    expect(factory.menu.entries, [
      factory.items[0],
      factory.items[1],
      factory.items[2],
      null,
      factory.items[3],
    ]);
    await openMenu();
    expect(factory.icon.opens, 1);
    expect(host.state.interactive, isFalse);
    await click(0);
    expect(visible, isFalse);
    await openMenu();
    expect(factory.items.first.label, 'Показати оверлей');
    await click(0);
    expect(visible, isTrue);
    await openMenu();
    expect(factory.items.first.label, 'Приховати оверлей');
    expect(host.state.interactive, isFalse);
    await click(1);
    expect(host.state.interactive, isTrue);
    await host.setInteractive(false);
    await host.setVisible(false);
    hostCalls.clear();
    factory.icon.click();
    await pumpEventQueue();
    expect(visible, isTrue);
    expect(host.state.interactive, isFalse);
    expect(hostCalls.single.method, 'setVisible');
    factory.icon.click();
    await pumpEventQueue();
    expect(host.state.interactive, isFalse);
  });

  test('configure routes to the settings callback', () async {
    var configured = 0;
    controller = OverlayTray(
      host: host,
      factory: factory,
      beforeExit: () async {},
      onConfigure: () async {
        configured++;
        await host.setInteractive(true);
      },
    );
    await controller.initialize(ukrainian);
    await click(1);
    expect(configured, 1);
    expect(host.state.interactive, isTrue);
    expect(
      hostCalls.where((call) => call.method == 'setInteractive').length,
      1,
    );
  });

  test(
    'refreshes visibility and locale without recreating native handles',
    () async {
      await controller.initialize(ukrainian);
      for (var index = 0; index < 20; index++) {
        visible = index.isEven; // includes changes made by the global hotkey
        await openMenu();
        expect(
          factory.items.first.label,
          visible ? ukrainian.trayHide : ukrainian.trayShow,
        );
      }
      final english = await AppLocalizations.delegate.load(const Locale('en'));
      await controller.updateLocalizations(english);
      expect(factory.items.first.label, english.trayShow);
      expect(factory.items[1].label, english.trayConfigure);
      expect(factory.creations, 1);
      expect(factory.items.length, 4);
      expect(factory.menu.entries.length, 5);
      expect(factory.icon.disposals, 0);
      hostCalls.clear();
      await click(2);
      expect(hostCalls.map((call) => call.method), [
        'setInteractive',
        'openUpdater',
      ]);
      expect(hostCalls.first.arguments, false);
      expect(hostCalls.last.arguments, 'en');
    },
  );

  test('updater exits interaction while leaving overlay running', () async {
    await controller.initialize(ukrainian);
    await host.setInteractive(true);
    hostCalls.clear();
    await click(2);
    expect(hostCalls.map((call) => call.method), [
      'setInteractive',
      'openUpdater',
    ]);
    expect(hostCalls.first.arguments, false);
    expect(hostCalls.last.arguments, 'uk');
    expect(host.state.interactive, isFalse);
    expect(actions, isEmpty);
  });

  test('updater shutdown saves, releases handles, then closes', () async {
    await controller.initialize(ukrainian);
    binding.channelBuffers.push(
      'overlay/window',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('closeRequested'),
      ),
      (_) {},
    );
    await closed.future;
    expect(actions, ['save', 'destroy', 'close']);
    expect(factory.icon.menu, isNull);
    expect(factory.image.disposals, 1);
    expect(factory.menu.disposals, 1);
    expect(factory.items.every((item) => item.disposals == 1), isTrue);
  });

  test('exit waits for saving and closes only once', () async {
    final saved = Completer<void>();
    controller = OverlayTray(
      host: host,
      factory: factory,
      beforeExit: () {
        actions.add('save');
        return saved.future;
      },
    );
    await controller.initialize(ukrainian);
    await click(3);
    await click(3);
    expect(actions, ['save']);
    saved.complete();
    await closed.future;
    expect(actions, ['save', 'destroy', 'close']);
    await controller.dispose();
    expect(factory.icon.disposals, 1);
  });

  test('dispose during initialization releases every resource', () async {
    final ready = Completer<bool>();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hostChannel,
      (call) async => call.method == 'isVisible' ? ready.future : null,
    );
    final initialization = controller.initialize(ukrainian);
    final disposal = controller.dispose();
    ready.complete(true);
    await initialization;
    await disposal;
    expect(factory.icon.visible, isFalse);
    expect(factory.icon.disposals, 1);
    expect(factory.image.disposals, 1);
    expect(factory.menu.disposals, 1);
    factory.icon.click();
    await pumpEventQueue();
    expect(host.state.interactive, isFalse);
  });

  test('failed menu creation cleans up partially created resources', () async {
    factory.failMenu = true;
    await expectLater(controller.initialize(ukrainian), throwsStateError);
    await controller.dispose();
    expect(factory.icon.disposals, 1);
    expect(factory.image.disposals, 1);
    expect(factory.menu.disposals, 0);
  });
}
