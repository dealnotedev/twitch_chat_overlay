import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlay_updater/launch_options.dart';
import 'package:overlay_updater/l10n/generated/updater_localizations.dart';
import 'package:overlay_updater/platform/updater_host.dart';
import 'package:overlay_updater/update_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('updater/host');
  LaunchOptions parse(
    List<String> args, [
    Locale system = const Locale('uk'),
  ]) => LaunchOptions.parse(
    args,
    executable: p.join(
      Directory.systemTemp.path,
      'Overlay App',
      'updater',
      'overlay_updater.exe',
    ),
    systemLocale: system,
  );

  test('standalone finds the parent installation and uses system locale', () {
    expect(p.basename(parse([]).directory), 'Overlay App');
    expect(parse([]).locale, const Locale('uk'));
    expect(parse([], const Locale('fr')).locale, const Locale('en'));
  });
  test('arguments work in either order and normalize regional locales', () {
    final dir = p.join(Directory.systemTemp.path, 'Other Overlay');
    expect(parse(['--locale', 'en-US', '--install-dir', dir]).directory, dir);
    expect(
      parse(['--locale', 'en-US', '--install-dir', dir]).locale,
      const Locale('en'),
    );
    expect(
      parse(['--install-dir', dir, '--locale', 'uk_UA']).locale,
      const Locale('uk'),
    );
    expect(parse(['--locale', 'de']).locale, const Locale('en'));
    expect(parse(['--locale', '--install-dir', dir]).directory, dir);
    expect(parse(['--locale']).locale, const Locale('uk'));
  });
  for (final language in ['en', 'uk']) {
    test(
      '$language localizes the native window title and controller errors',
      () async {
        final strings = lookupUpdaterLocalizations(Locale(language));
        final calls = <MethodCall>[];
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          calls.add(call);
          return null;
        });
        addTearDown(
          () => binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final dir = Directory.systemTemp.createTempSync('updater-locale-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final controller = UpdateController(
          directory: dir.path,
          host: WindowsUpdaterHost(title: strings.windowTitle),
          strings: strings,
        );
        addTearDown(controller.dispose);
        expect(controller.title, strings.checkingTitle);
        await controller.check();
        expect(calls.single.method, 'initialize');
        expect(calls.single.arguments, {
          'directory': dir.path,
          'title': strings.windowTitle,
        });
        expect(controller.phase, UpdatePhase.error);
        expect(controller.title, strings.errorTitle);
        expect(controller.detail, strings.invalidInstallation);
        expect(controller.action, strings.retry);
      },
    );
  }
}
