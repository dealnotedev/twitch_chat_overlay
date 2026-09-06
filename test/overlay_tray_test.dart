import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart' as tray;
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/platform/overlay_host.dart';
import 'package:twitch_chat_overlay/platform/overlay_tray.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const trayChannel = MethodChannel('tray_manager');
  const hostChannel = MethodChannel('overlay/window');
  const codec = StandardMethodCodec();
  late OverlayTray controller;
  late MethodChannelOverlayHost host;
  late AppLocalizations ukrainian;
  late List<MethodCall> trayCalls;
  late List<MethodCall> hostCalls;
  late bool visible;
  late List<String> actions;
  late Completer<void> closed;

  Future<void> sendEvent(String method, [Object? arguments]) async {
    final reply = Completer<void>();
    binding.channelBuffers.push(
      'tray_manager',
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) => reply.complete(),
    );
    await reply.future;
    await pumpEventQueue();
  }

  List<dynamic> menuItems() =>
      (trayCalls.lastWhere((call) => call.method == 'setContextMenu').arguments
              as Map)['menu']['items']
          as List<dynamic>;

  Future<void> clickMenu(String key) {
    final item = menuItems().firstWhere((item) => item['key'] == key);
    return sendEvent('onTrayMenuItemClick', {'id': item['id']});
  }

  setUp(() async {
    trayCalls = [];
    hostCalls = [];
    visible = true;
    actions = [];
    closed = Completer<void>();
    ukrainian = await AppLocalizations.delegate.load(const Locale('uk'));
    host = MethodChannelOverlayHost();
    controller = OverlayTray(
      host: host,
      beforeExit: () async => actions.add('save'),
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(trayChannel, (
      call,
    ) async {
      trayCalls.add(call);
      if (call.method == 'destroy') actions.add('destroy');
      return true;
    });
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
  });

  tearDown(() async {
    await controller.dispose();
    expect(tray.trayManager.hasListeners, isFalse);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(trayChannel, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(hostChannel, null);
  });

  test(
    'bundles the icon and routes localized native menu and clicks',
    () async {
      await controller.initialize(ukrainian);
      expect(
        ((trayCalls.first.arguments as Map)['iconPath'] as String).replaceAll(
          r'\',
          '/',
        ),
        endsWith('/data/flutter_assets/${OverlayTray.iconAsset}'),
      );
      expect(menuItems().map((item) => item['label']), [
        'Приховати оверлей',
        'Налаштувати оверлей',
        '',
        'Вийти',
      ]);
      expect(menuItems()[2]['type'], 'separator');

      await sendEvent('onTrayIconRightMouseDown');
      expect(trayCalls.last.method, 'popUpContextMenu');
      expect(trayCalls.last.arguments, {'bringAppToFront': true});
      expect(host.state.interactive, isFalse);

      await clickMenu('hide');
      expect(visible, isFalse);
      await sendEvent('onTrayIconRightMouseDown');
      expect(menuItems().map((item) => item['key']), [
        'show',
        'configure',
        null,
        'exit',
      ]);
      expect(menuItems().first['label'], 'Показати оверлей');
      await clickMenu('show');
      expect(visible, isTrue);
      await sendEvent('onTrayIconRightMouseDown');
      expect(menuItems().map((item) => item['key']), [
        'hide',
        'configure',
        null,
        'exit',
      ]);
      expect(
        hostCalls
            .where((call) => call.method == 'setVisible')
            .map((call) => call.arguments),
        [false, true],
      );
      expect(host.state.interactive, isFalse);

      await clickMenu('configure');
      expect(host.state.interactive, isTrue);
      await host.setInteractive(false);
      await host.setVisible(false);
      hostCalls.clear();
      await sendEvent('onTrayIconMouseDown');
      expect(visible, isTrue);
      expect(host.state.interactive, isFalse);
      expect(hostCalls.single.method, 'setVisible');
      expect(hostCalls.single.arguments, isTrue);

      // A second click keeps the visible overlay locked.
      await sendEvent('onTrayIconMouseDown');
      expect(visible, isTrue);
      expect(host.state.interactive, isFalse);
    },
  );

  test(
    'menu reads native visibility after a hotkey shows the overlay',
    () async {
      await controller.initialize(ukrainian);
      await clickMenu('hide');
      await sendEvent('onTrayIconRightMouseDown');
      expect(menuItems().first['key'], 'show');

      // Native hotkey changes visibility outside the Dart tray controller.
      visible = true;
      await sendEvent('onTrayIconRightMouseDown');
      expect(menuItems().first['key'], 'hide');
      expect(menuItems().length, 4);
    },
  );

  test(
    'exit waits for saving, removes the icon, then closes only once',
    () async {
      final saved = Completer<void>();
      controller = OverlayTray(
        host: host,
        beforeExit: () {
          actions.add('save');
          return saved.future;
        },
      );
      await controller.initialize(ukrainian);
      await clickMenu('exit');
      await clickMenu('exit');
      expect(actions, ['save']);
      saved.complete();
      await closed.future;
      expect(actions, ['save', 'destroy', 'close']);
      await controller.dispose();
      expect(actions, ['save', 'destroy', 'close']);
    },
  );

  test(
    'disposing during startup removes the pending icon and listener',
    () async {
      final iconReady = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(trayChannel, (
        call,
      ) async {
        trayCalls.add(call);
        if (call.method == 'setIcon') await iconReady.future;
        return true;
      });
      final initialization = controller.initialize(ukrainian);
      final disposal = controller.dispose();
      iconReady.complete();
      await initialization;
      await disposal;
      expect(trayCalls.last.method, 'destroy');
      await sendEvent('onTrayIconMouseDown');
      expect(host.state.interactive, isFalse);
    },
  );

  test(
    'failed menu creation removes the icon and leaves no listener',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(trayChannel, (
        call,
      ) async {
        trayCalls.add(call);
        if (call.method == 'setContextMenu') {
          throw PlatformException(code: 'menu_failed');
        }
        return true;
      });
      await expectLater(
        controller.initialize(ukrainian),
        throwsA(isA<PlatformException>()),
      );
      expect(trayCalls.last.method, 'destroy');
      expect(tray.trayManager.hasListeners, isFalse);
    },
  );
}
