import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlay_updater/core/app_version.dart';
import 'package:overlay_updater/core/release_client.dart';
import 'package:overlay_updater/core/update_package.dart';
import 'package:overlay_updater/platform/updater_host.dart';
import 'package:overlay_updater/update_controller.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  late FakeHost host;
  late UpdateController controller;
  const target = AppVersion(1, 1, 0, 3);
  var corrupt = false;
  var tag = '1.1.0';
  var missingPackage = false;
  var noRelease = false;

  setUp(() {
    corrupt = false;
    tag = '1.1.0';
    missingPackage = false;
    noRelease = false;
    directory = Directory.systemTemp.createTempSync('updater-controller-');
    File(p.join(directory.path, overlayExecutable)).writeAsStringSync('old');
    File(p.join(directory.path, manifestName)).writeAsStringSync(
      jsonEncode(
        const PackageManifest(
          version: AppVersion(1, 0, 0),
          roots: [overlayExecutable, manifestName],
        ).toJson(),
      ),
    );
    host = FakeHost();
    final archive = Archive();
    final files = {
      overlayExecutable: 'new',
      'flutter_windows.dll': 'engine',
      'data/app.so': 'app',
      'data/icudtl.dat': 'icu',
      'data/flutter_assets/AssetManifest.bin': 'manifest',
      manifestName: jsonEncode(
        PackageManifest(
          version: target,
          roots: [
            overlayExecutable,
            'flutter_windows.dll',
            'data',
            manifestName,
          ],
        ).toJson(),
      ),
    };
    for (final entry in files.entries) {
      archive.addFile(ArchiveFile.string(entry.key, entry.value));
    }
    final bytes = ZipEncoder().encode(archive);
    final dio = Dio()
      ..httpClientAdapter = Responses((options) {
        if (options.uri.host == 'api.github.com') {
          if (noRelease) return ResponseBody.fromString('', 404);
          return ResponseBody.fromString(
            jsonEncode({
              'tag_name': tag,
              'draft': false,
              'prerelease': false,
              'body': 'Release notes',
              'assets': [
                if (!missingPackage)
                  {
                    'name': 'update.zip',
                    'size': bytes.length,
                    'digest':
                        'sha256:${corrupt ? '0' * 64 : sha256.convert(bytes)}',
                    'browser_download_url': 'https://github.com/dealnotedev/twitch_chat_overlay/releases/download/1.1.0/update.zip',
                  },
              ],
            }),
            200,
            headers: {
              Headers.contentTypeHeader: ['application/json'],
            },
          );
        }
        return ResponseBody.fromBytes(bytes, 200);
      });
    controller = UpdateController(
      directory: directory.path,
      host: host,
      client: ReleaseClient(dio: dio),
    );
  });
  tearDown(() {
    controller.dispose();
    directory.deleteSync(recursive: true);
  });

  test('check, download, validate, stop, install and open through Flutter controller', () async {
    await controller.check();
    expect(controller.phase, UpdatePhase.available);
    expect(host.calls, ['initialize', 'version']);
    await controller.activate();
    expect(controller.phase, UpdatePhase.done);
    expect(controller.busy, false);
    expect(controller.current, target);
    expect(
      File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
      'new',
    );
    expect(host.calls, ['initialize', 'version', 'begin', 'stop', 'end']);
    await controller.activate();
    expect(host.calls.sublist(host.calls.length - 2), ['start', 'close']);
  });

  for (final scenario in [
    (installed: target, tag: '1.1.0', reinstall: true),
    (installed: target, tag: '1.1.0+3', reinstall: true),
    (installed: const AppVersion(2, 0, 0, 9), tag: '1.1.0', reinstall: false),
    (installed: const AppVersion(1, 1, 0, 4), tag: '1.1.0+3', reinstall: false),
  ]) {
    test('installs ${scenario.tag} over ${scenario.installed}', () async {
      host.version = scenario.installed;
      tag = scenario.tag;
      await controller.check();
      expect(controller.phase, UpdatePhase.available);
      expect(
        controller.action,
        scenario.reinstall
            ? controller.strings.reinstallOverlay
            : controller.strings.downgradeOverlay(tag),
      );
      expect(host.calls, ['initialize', 'version']);
      expect(
        File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
        'old',
      );
      await controller.activate();
      expect(controller.phase, UpdatePhase.done);
      expect(controller.current, target);
      expect(
        File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
        'new',
      );
      expect(host.calls, ['initialize', 'version', 'begin', 'stop', 'end']);
      expect(controller.action, controller.strings.openOverlay);
      await controller.activate();
      expect(host.calls.sublist(host.calls.length - 2), ['start', 'close']);
    });
  }
  test(
    'reinstallation still verifies the checksum before closing the overlay',
    () async {
      host.version = target;
      corrupt = true;
      await controller.check();
      await controller.activate();
      expect(controller.phase, UpdatePhase.error);
      expect(host.calls, ['initialize', 'version']);
      expect(
        File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
        'old',
      );
    },
  );
  test('missing package cannot reinstall or downgrade', () async {
    host.version = const AppVersion(2, 0, 0);
    missingPackage = true;
    await controller.check();
    expect(controller.phase, UpdatePhase.error);
    expect(controller.detail, controller.strings.packageUnavailable);
    expect(host.calls, ['initialize', 'version']);
  });
  test(
    'no GitHub release still offers opening the installed overlay',
    () async {
      noRelease = true;
      await controller.check();
      expect(controller.phase, UpdatePhase.current);
      expect(controller.action, controller.strings.openOverlay);
      await controller.activate();
      expect(host.calls, ['initialize', 'version', 'start', 'close']);
    },
  );

  test('bad checksum never closes the overlay or replaces files', () async {
    corrupt = true;
    await controller.check();
    await controller.activate();
    expect(controller.phase, UpdatePhase.error);
    expect(host.calls, ['initialize', 'version']);
    expect(
      File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
      'old',
    );
  });
  test('unresponsive overlay releases gate without replacing files', () async {
    host.failStop = true;
    await controller.check();
    await controller.activate();
    expect(controller.phase, UpdatePhase.error);
    expect(controller.critical, false);
    expect(host.calls, ['initialize', 'version', 'begin', 'stop', 'end']);
    expect(
      File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
      'old',
    );
  });
  test('another updater holding the lock prevents installation', () async {
    host.lockAvailable = false;
    await controller.check();
    await controller.activate();
    expect(controller.phase, UpdatePhase.error);
    expect(host.calls, ['initialize', 'version', 'begin']);
    expect(
      File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
      'old',
    );
  });
  test('cancelling download keeps overlay running', () async {
    await controller.check();
    controller.addListener(() {
      if (controller.phase == UpdatePhase.downloading &&
          controller.received > 0) {
        controller.cancel();
      }
    });
    await controller.activate();
    expect(controller.phase, UpdatePhase.error);
    expect(host.calls, ['initialize', 'version']);
    expect(
      File(p.join(directory.path, overlayExecutable)).readAsStringSync(),
      'old',
    );
  });
}

final class FakeHost implements UpdaterHost {
  final calls = <String>[];
  AppVersion version = const AppVersion(1, 0, 1, 2);
  bool failStop = false;
  bool lockAvailable = true;
  @override
  Future<void> initialize(String directory) async {
    calls.add('initialize');
  }

  @override
  Future<AppVersion> readVersion() async {
    calls.add('version');
    return version;
  }

  @override
  Future<bool> beginInstall() async {
    calls.add('begin');
    return lockAvailable;
  }

  @override
  Future<void> endInstall() async {
    calls.add('end');
  }

  @override
  Future<void> stopOverlay() async {
    calls.add('stop');
    if (failStop) throw const FormatException('Close overlay manually');
  }

  @override
  Future<void> startOverlay() async {
    calls.add('start');
  }

  @override
  Future<void> close() async {
    calls.add('close');
  }
}

final class Responses implements HttpClientAdapter {
  Responses(this.respond);
  final ResponseBody Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);
  @override
  void close({bool force = false}) {}
}
