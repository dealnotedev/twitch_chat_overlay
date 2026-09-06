import 'package:flutter/services.dart';

import '../core/app_version.dart';
import '../core/update_failure.dart';

abstract interface class UpdaterHost {
  Future<void> initialize(String directory);
  Future<AppVersion> readVersion();
  Future<bool> beginInstall();
  Future<void> endInstall();
  Future<void> stopOverlay();
  Future<void> startOverlay();
  Future<void> close();
}

final class WindowsUpdaterHost implements UpdaterHost {
  WindowsUpdaterHost({required this.title});
  final String title;
  static const _channel = MethodChannel('updater/host');

  @override
  Future<void> initialize(String directory) => _channel.invokeMethod<void>(
    'initialize',
    {'directory': directory, 'title': title},
  );
  @override
  Future<AppVersion> readVersion() async =>
      AppVersion.parse((await _channel.invokeMethod<String>('readVersion'))!);
  @override
  Future<bool> beginInstall() async =>
      await _channel.invokeMethod<bool>('beginInstall') ?? false;
  @override
  Future<void> endInstall() => _channel.invokeMethod<void>('endInstall');
  @override
  Future<void> startOverlay() => _channel.invokeMethod<void>('startOverlay');
  @override
  Future<void> close() => _channel.invokeMethod<void>('close');

  @override
  Future<void> stopOverlay() async {
    await _channel.invokeMethod<void>('requestOverlayExit');
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (await _channel.invokeMethod<bool>('isOverlayRunning') == true) {
      if (DateTime.now().isAfter(deadline)) {
        throw const UpdateFailure(UpdateIssue.closeOverlay);
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
}
