// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'updater_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class UpdaterLocalizationsEn extends UpdaterLocalizations {
  UpdaterLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get windowTitle => 'Twitch Chat Overlay — Updates';

  @override
  String get heading => 'Updates';

  @override
  String get subtitle => 'Everything new for your chat, in one place.';

  @override
  String get installedLabel => 'INSTALLED';

  @override
  String get latestLabel => 'LATEST VERSION';

  @override
  String get whatsNew => 'What\'s new';

  @override
  String get stableRelease => 'STABLE RELEASE';

  @override
  String get loadingNotes => 'Getting release notes from GitHub.';

  @override
  String get noNotes => 'The author has not added release notes yet.';

  @override
  String get settingsHeading => 'Your chat stays yours';

  @override
  String get settingsDetail => 'Your Twitch sign-in and settings will be kept.';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get retry => 'Try again';

  @override
  String get openOverlay => 'Open overlay';

  @override
  String get updateOverlay => 'Update overlay';

  @override
  String get downloadingAction => 'Downloading…';

  @override
  String get checkingAction => 'Checking…';

  @override
  String get preparingAction => 'Preparing update…';

  @override
  String get checkingTitle => 'Checking for updates';

  @override
  String get checkingDetail => 'The overlay keeps running.';

  @override
  String get recoveryTitle => 'Restoring the previous version';

  @override
  String get recoveryDetail =>
      'The previous installation was interrupted. Please wait.';

  @override
  String get availableTitle => 'A new version is available';

  @override
  String packageSize(String size) {
    return 'Package: $size MB. Chat keeps running until installation.';
  }

  @override
  String get currentTitle => 'You\'re up to date';

  @override
  String get currentDetail => 'You can return to your chat.';

  @override
  String get downloadTitle => 'Downloading the update';

  @override
  String get downloadDetail =>
      'You can cancel the download. The overlay keeps running.';

  @override
  String downloadProgress(String received, String total) {
    return '$received / $total MB';
  }

  @override
  String get verifyTitle => 'Checking and extracting';

  @override
  String get verifyDetail => 'The SHA-256 checksum has been verified.';

  @override
  String get stopTitle => 'Saving and closing the overlay';

  @override
  String get stopDetail => 'Settings will be saved before replacing files.';

  @override
  String get installTitle => 'Installing the update';

  @override
  String get installDetail =>
      'Keep your computer on. The previous version is backed up.';

  @override
  String get doneTitle => 'Update installed';

  @override
  String get doneDetail =>
      'All done. Open the overlay and return to your chat.';

  @override
  String get errorTitle => 'Couldn\'t complete the update';

  @override
  String get cancelled =>
      'Update cancelled. Application files have not changed.';

  @override
  String get networkError =>
      'Couldn\'t connect to GitHub. Check your connection and try again.';

  @override
  String get fileError =>
      'Couldn\'t update application files. Check folder permissions and free disk space.';

  @override
  String get unexpectedError =>
      'Something went wrong. Restart the updater and try again.';

  @override
  String get invalidVersion => 'The version number has an unsupported format.';

  @override
  String get invalidUrl => 'The release contains an invalid download link.';

  @override
  String get rateLimited =>
      'GitHub has temporarily limited requests. Please try again later.';

  @override
  String get packageUnavailable =>
      'The release has no update package yet. Please try again later.';

  @override
  String get invalidMetadata =>
      'The update package has no valid size or SHA-256 checksum.';

  @override
  String get downloadSizeMismatch =>
      'The download size does not match the release.';

  @override
  String get checksumMismatch =>
      'The archive is damaged. SHA-256 verification failed.';

  @override
  String get unsafePath =>
      'The package contains a path outside the allowed installation area.';

  @override
  String get linksUnsupported =>
      'The update contains a symbolic link, or the installation folder uses one.';

  @override
  String get invalidPackage =>
      'The package is invalid or is not for Twitch Chat Overlay.';

  @override
  String get tooManyFiles => 'The update archive contains too many files.';

  @override
  String get packageTooLarge => 'The extracted update is too large.';

  @override
  String get versionMismatch =>
      'The package version does not match the selected release.';

  @override
  String get missingRuntime =>
      'The package is missing a required application file.';

  @override
  String get invalidInstallation =>
      'Overlay not found. Place the updater folder next to the overlay application.';

  @override
  String get recoveryRequired =>
      'The previous installation must be restored first. Try again.';

  @override
  String get invalidJournal =>
      'The recovery journal is damaged. The backup has been kept.';

  @override
  String get updateBusy => 'Another update is already in progress.';

  @override
  String get closeOverlay =>
      'Close the overlay using Exit in its tray menu, then try again.';

  @override
  String get linkOpenFailed => 'Could not open the link. Try again.';
}
