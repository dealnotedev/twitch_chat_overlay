import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:intl/intl.dart';

import 'core/update_failure.dart';
import 'l10n/generated/updater_localizations.dart';
import 'l10n/failure_message.dart';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'core/app_version.dart';
import 'core/installation.dart';
import 'core/release_client.dart';
import 'core/update_package.dart';
import 'platform/updater_host.dart';

void _recover(Installation installation) => installation.recover();
void _prepare(Installation installation) => installation.prepare();
void _clean(Installation installation) => installation.cleanWork();
void _apply((Installation, PackageManifest) args) => args.$1.apply(args.$2);
PackageManifest _extract((String, String, AppVersion) args) =>
    extractPackage(args.$1, args.$2, args.$3);

enum UpdatePhase {
  checking,
  current,
  available,
  downloading,
  verifying,
  stopping,
  installing,
  recovering,
  done,
  error,
}

final class UpdateController extends ChangeNotifier {
  UpdateController({
    required this.directory,
    required this.host,
    ReleaseClient? client,
    UpdaterLocalizations? strings,
  }) : strings = strings ?? lookupUpdaterLocalizations(const Locale('en')),
       client = client ?? ReleaseClient();

  final UpdaterLocalizations strings;
  final String directory;
  final UpdaterHost host;
  final ReleaseClient client;
  Installation? _installation;
  CancelToken _cancellation = CancelToken();
  bool _disposed = false;
  bool busy = false;
  bool critical = false;
  AppVersion? current;
  Release? release;
  UpdatePhase phase = UpdatePhase.checking;
  late String title = strings.checkingTitle;
  late String detail = strings.checkingDetail;
  double? progress;
  int received = 0;

  bool get canInstall => release?.download != null && current != null;

  int get _releaseComparison => current!.matchesRelease(release!.version)
      ? 0
      : release!.version.compareTo(current!);

  String get _installAction => switch (_releaseComparison) {
    > 0 => strings.updateOverlay,
    0 => strings.reinstallOverlay,
    _ => strings.downgradeOverlay(release!.version.toString()),
  };

  String get _offerTitle => switch (_releaseComparison) {
    > 0 => strings.availableTitle,
    0 => strings.reinstallTitle,
    _ => strings.downgradeTitle,
  };
  String get action => switch (phase) {
    UpdatePhase.error => strings.retry,
    UpdatePhase.current || UpdatePhase.done => strings.openOverlay,
    UpdatePhase.available => _installAction,
    UpdatePhase.downloading => strings.downloadingAction,
    UpdatePhase.checking => strings.checkingAction,
    _ => strings.preparingAction,
  };

  void _status(
    UpdatePhase value,
    String heading,
    String description, {
    double? fraction,
  }) {
    phase = value;
    title = heading;
    detail = description;
    progress = fraction;
    if (!_disposed) notifyListeners();
  }

  Future<void> check() async {
    if (busy) return;
    busy = true;
    _cancellation = CancelToken();
    _status(
      UpdatePhase.checking,
      strings.checkingTitle,
      strings.checkingDetail,
    );
    try {
      await host.initialize(directory);
      final installation = await compute(Installation.new, directory);
      _installation = installation;
      if (installation.needsRecovery) {
        await _withInstallLock(() async {
          _status(
            UpdatePhase.recovering,
            strings.recoveryTitle,
            strings.recoveryDetail,
          );
          await host.stopOverlay();
          await compute(_recover, installation);
        });
      }
      current = await host.readVersion();
      release = await client.latest(_cancellation);
      if (release != null) {
        if (release!.download == null) {
          throw const UpdateFailure(UpdateIssue.packageUnavailable);
        }
        _status(
          UpdatePhase.available,
          _offerTitle,
          strings.packageSize(_megabytes(release!.size)),
          fraction: 0,
        );
      } else {
        _status(
          UpdatePhase.current,
          strings.currentTitle,
          strings.currentDetail,
          fraction: 1,
        );
      }
    } catch (error) {
      _error(error);
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> activate() async {
    if (busy) return;
    if (phase == UpdatePhase.error) {
      await check();
      return;
    }
    if (!canInstall || phase == UpdatePhase.done) {
      try {
        await host.startOverlay();
        await host.close();
      } catch (error) {
        _error(error);
      }
      return;
    }
    await _install();
  }

  Future<void> _install() async {
    final installation = _installation!;
    final target = release!;
    busy = true;
    _cancellation = CancelToken();
    _status(
      UpdatePhase.downloading,
      strings.downloadTitle,
      strings.downloadDetail,
      fraction: 0,
    );
    try {
      await compute(_prepare, installation);
      await client.download(target, installation.archive, _cancellation, (
        count,
        total,
      ) {
        received = count;
        _status(
          UpdatePhase.downloading,
          strings.downloadTitle,
          strings.downloadProgress(_megabytes(count), _megabytes(total)),
          fraction: count / total,
        );
      });
      _status(UpdatePhase.verifying, strings.verifyTitle, strings.verifyDetail);
      final package = await compute(_extract, (
        installation.archive,
        installation.stage,
        target.version,
      ));
      if (_cancellation.isCancelled) throw _cancellation.cancelError!;
      await _withInstallLock(() async {
        _status(UpdatePhase.stopping, strings.stopTitle, strings.stopDetail);
        await host.stopOverlay();
        _status(
          UpdatePhase.installing,
          strings.installTitle,
          strings.installDetail,
        );
        await compute(_apply, (installation, package));
      });
      current = package.version;
      _status(
        UpdatePhase.done,
        strings.doneTitle,
        strings.doneDetail,
        fraction: 1,
      );
    } catch (error) {
      _error(error);
    } finally {
      try {
        await compute(_clean, installation);
      } on FileSystemException {
        /* Keep recoverable files. */
      }
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _withInstallLock(Future<void> Function() operation) async {
    if (!await host.beginInstall()) {
      throw const UpdateFailure(UpdateIssue.updateBusy);
    }
    critical = true;
    try {
      await operation();
    } finally {
      await host.endInstall();
      critical = false;
    }
  }

  void cancel() {
    if (!critical) _cancellation.cancel('User cancelled');
  }

  String _megabytes(int bytes) =>
      NumberFormat('0.0', strings.localeName).format(bytes / 1048576);

  void _error(Object error) {
    final description = switch (error) {
      UpdateFailure e => failureMessage(strings, e.issue),
      UpdateFileFailure e => failureMessage(strings, e.issue),
      DioException e when CancelToken.isCancel(e) => strings.cancelled,
      DioException() || HttpException() => strings.networkError,
      FileSystemException() => strings.fileError,
      FormatException() => strings.invalidPackage,
      _ => strings.unexpectedError,
    };
    _status(UpdatePhase.error, strings.errorTitle, description, fraction: 0);
  }

  @override
  void dispose() {
    _disposed = true;
    _cancellation.cancel();
    client.close();
    super.dispose();
  }
}
