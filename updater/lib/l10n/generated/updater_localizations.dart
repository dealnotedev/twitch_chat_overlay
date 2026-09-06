import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'updater_localizations_en.dart';
import 'updater_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of UpdaterLocalizations
/// returned by `UpdaterLocalizations.of(context)`.
///
/// Applications need to include `UpdaterLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/updater_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: UpdaterLocalizations.localizationsDelegates,
///   supportedLocales: UpdaterLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the UpdaterLocalizations.supportedLocales
/// property.
abstract class UpdaterLocalizations {
  UpdaterLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static UpdaterLocalizations of(BuildContext context) {
    return Localizations.of<UpdaterLocalizations>(
      context,
      UpdaterLocalizations,
    )!;
  }

  static const LocalizationsDelegate<UpdaterLocalizations> delegate =
      _UpdaterLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('uk'),
  ];

  /// No description provided for @windowTitle.
  ///
  /// In en, this message translates to:
  /// **'Twitch Chat Overlay — Updates'**
  String get windowTitle;

  /// No description provided for @heading.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get heading;

  /// No description provided for @subtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything new for your chat, in one place.'**
  String get subtitle;

  /// No description provided for @installedLabel.
  ///
  /// In en, this message translates to:
  /// **'INSTALLED'**
  String get installedLabel;

  /// No description provided for @latestLabel.
  ///
  /// In en, this message translates to:
  /// **'LATEST VERSION'**
  String get latestLabel;

  /// No description provided for @whatsNew.
  ///
  /// In en, this message translates to:
  /// **'What\'s new'**
  String get whatsNew;

  /// No description provided for @stableRelease.
  ///
  /// In en, this message translates to:
  /// **'STABLE RELEASE'**
  String get stableRelease;

  /// No description provided for @loadingNotes.
  ///
  /// In en, this message translates to:
  /// **'Getting release notes from GitHub.'**
  String get loadingNotes;

  /// No description provided for @noNotes.
  ///
  /// In en, this message translates to:
  /// **'The author has not added release notes yet.'**
  String get noNotes;

  /// No description provided for @settingsHeading.
  ///
  /// In en, this message translates to:
  /// **'Your chat stays yours'**
  String get settingsHeading;

  /// No description provided for @settingsDetail.
  ///
  /// In en, this message translates to:
  /// **'Your Twitch sign-in and settings will be kept.'**
  String get settingsDetail;

  /// No description provided for @cancelDownload.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get cancelDownload;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @openOverlay.
  ///
  /// In en, this message translates to:
  /// **'Open overlay'**
  String get openOverlay;

  /// No description provided for @updateOverlay.
  ///
  /// In en, this message translates to:
  /// **'Update overlay'**
  String get updateOverlay;

  /// No description provided for @downloadingAction.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get downloadingAction;

  /// No description provided for @checkingAction.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get checkingAction;

  /// No description provided for @preparingAction.
  ///
  /// In en, this message translates to:
  /// **'Preparing update…'**
  String get preparingAction;

  /// No description provided for @checkingTitle.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates'**
  String get checkingTitle;

  /// No description provided for @checkingDetail.
  ///
  /// In en, this message translates to:
  /// **'The overlay keeps running.'**
  String get checkingDetail;

  /// No description provided for @recoveryTitle.
  ///
  /// In en, this message translates to:
  /// **'Restoring the previous version'**
  String get recoveryTitle;

  /// No description provided for @recoveryDetail.
  ///
  /// In en, this message translates to:
  /// **'The previous installation was interrupted. Please wait.'**
  String get recoveryDetail;

  /// No description provided for @availableTitle.
  ///
  /// In en, this message translates to:
  /// **'A new version is available'**
  String get availableTitle;

  /// No description provided for @packageSize.
  ///
  /// In en, this message translates to:
  /// **'Package: {size} MB. Chat keeps running until installation.'**
  String packageSize(String size);

  /// No description provided for @currentTitle.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date'**
  String get currentTitle;

  /// No description provided for @currentDetail.
  ///
  /// In en, this message translates to:
  /// **'You can return to your chat.'**
  String get currentDetail;

  /// No description provided for @downloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Downloading the update'**
  String get downloadTitle;

  /// No description provided for @downloadDetail.
  ///
  /// In en, this message translates to:
  /// **'You can cancel the download. The overlay keeps running.'**
  String get downloadDetail;

  /// No description provided for @downloadProgress.
  ///
  /// In en, this message translates to:
  /// **'{received} / {total} MB'**
  String downloadProgress(String received, String total);

  /// No description provided for @verifyTitle.
  ///
  /// In en, this message translates to:
  /// **'Checking and extracting'**
  String get verifyTitle;

  /// No description provided for @verifyDetail.
  ///
  /// In en, this message translates to:
  /// **'The SHA-256 checksum has been verified.'**
  String get verifyDetail;

  /// No description provided for @stopTitle.
  ///
  /// In en, this message translates to:
  /// **'Saving and closing the overlay'**
  String get stopTitle;

  /// No description provided for @stopDetail.
  ///
  /// In en, this message translates to:
  /// **'Settings will be saved before replacing files.'**
  String get stopDetail;

  /// No description provided for @installTitle.
  ///
  /// In en, this message translates to:
  /// **'Installing the update'**
  String get installTitle;

  /// No description provided for @installDetail.
  ///
  /// In en, this message translates to:
  /// **'Keep your computer on. The previous version is backed up.'**
  String get installDetail;

  /// No description provided for @doneTitle.
  ///
  /// In en, this message translates to:
  /// **'Update installed'**
  String get doneTitle;

  /// No description provided for @doneDetail.
  ///
  /// In en, this message translates to:
  /// **'All done. Open the overlay and return to your chat.'**
  String get doneDetail;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete the update'**
  String get errorTitle;

  /// No description provided for @cancelled.
  ///
  /// In en, this message translates to:
  /// **'Update cancelled. Application files have not changed.'**
  String get cancelled;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t connect to GitHub. Check your connection and try again.'**
  String get networkError;

  /// No description provided for @fileError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update application files. Check folder permissions and free disk space.'**
  String get fileError;

  /// No description provided for @unexpectedError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong. Restart the updater and try again.'**
  String get unexpectedError;

  /// No description provided for @invalidVersion.
  ///
  /// In en, this message translates to:
  /// **'The version number has an unsupported format.'**
  String get invalidVersion;

  /// No description provided for @invalidUrl.
  ///
  /// In en, this message translates to:
  /// **'The release contains an invalid download link.'**
  String get invalidUrl;

  /// No description provided for @rateLimited.
  ///
  /// In en, this message translates to:
  /// **'GitHub has temporarily limited requests. Please try again later.'**
  String get rateLimited;

  /// No description provided for @packageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The release has no update package yet. Please try again later.'**
  String get packageUnavailable;

  /// No description provided for @invalidMetadata.
  ///
  /// In en, this message translates to:
  /// **'The update package has no valid size or SHA-256 checksum.'**
  String get invalidMetadata;

  /// No description provided for @downloadSizeMismatch.
  ///
  /// In en, this message translates to:
  /// **'The download size does not match the release.'**
  String get downloadSizeMismatch;

  /// No description provided for @checksumMismatch.
  ///
  /// In en, this message translates to:
  /// **'The archive is damaged. SHA-256 verification failed.'**
  String get checksumMismatch;

  /// No description provided for @unsafePath.
  ///
  /// In en, this message translates to:
  /// **'The package contains a path outside the allowed installation area.'**
  String get unsafePath;

  /// No description provided for @linksUnsupported.
  ///
  /// In en, this message translates to:
  /// **'The update contains a symbolic link, or the installation folder uses one.'**
  String get linksUnsupported;

  /// No description provided for @invalidPackage.
  ///
  /// In en, this message translates to:
  /// **'The package is invalid or is not for Twitch Chat Overlay.'**
  String get invalidPackage;

  /// No description provided for @tooManyFiles.
  ///
  /// In en, this message translates to:
  /// **'The update archive contains too many files.'**
  String get tooManyFiles;

  /// No description provided for @packageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The extracted update is too large.'**
  String get packageTooLarge;

  /// No description provided for @versionMismatch.
  ///
  /// In en, this message translates to:
  /// **'The package version does not match the selected release.'**
  String get versionMismatch;

  /// No description provided for @missingRuntime.
  ///
  /// In en, this message translates to:
  /// **'The package is missing a required application file.'**
  String get missingRuntime;

  /// No description provided for @invalidInstallation.
  ///
  /// In en, this message translates to:
  /// **'Overlay not found. Place the updater folder next to the overlay application.'**
  String get invalidInstallation;

  /// No description provided for @recoveryRequired.
  ///
  /// In en, this message translates to:
  /// **'The previous installation must be restored first. Try again.'**
  String get recoveryRequired;

  /// No description provided for @invalidJournal.
  ///
  /// In en, this message translates to:
  /// **'The recovery journal is damaged. The backup has been kept.'**
  String get invalidJournal;

  /// No description provided for @updateBusy.
  ///
  /// In en, this message translates to:
  /// **'Another update is already in progress.'**
  String get updateBusy;

  /// No description provided for @closeOverlay.
  ///
  /// In en, this message translates to:
  /// **'Close the overlay using Exit in its tray menu, then try again.'**
  String get closeOverlay;

  /// No description provided for @linkOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the link. Try again.'**
  String get linkOpenFailed;

  /// No description provided for @reinstallOverlay.
  ///
  /// In en, this message translates to:
  /// **'Reinstall overlay'**
  String get reinstallOverlay;

  /// No description provided for @reinstallTitle.
  ///
  /// In en, this message translates to:
  /// **'This version is already installed'**
  String get reinstallTitle;

  /// No description provided for @downgradeOverlay.
  ///
  /// In en, this message translates to:
  /// **'Downgrade to {version}'**
  String downgradeOverlay(String version);

  /// No description provided for @downgradeTitle.
  ///
  /// In en, this message translates to:
  /// **'Your version is newer than the GitHub release'**
  String get downgradeTitle;
}

class _UpdaterLocalizationsDelegate
    extends LocalizationsDelegate<UpdaterLocalizations> {
  const _UpdaterLocalizationsDelegate();

  @override
  Future<UpdaterLocalizations> load(Locale locale) {
    return SynchronousFuture<UpdaterLocalizations>(
      lookupUpdaterLocalizations(locale),
    );
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_UpdaterLocalizationsDelegate old) => false;
}

UpdaterLocalizations lookupUpdaterLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return UpdaterLocalizationsEn();
    case 'uk':
      return UpdaterLocalizationsUk();
  }

  throw FlutterError(
    'UpdaterLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
