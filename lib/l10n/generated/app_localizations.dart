import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_uk.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
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
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

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

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Twitch Chat Overlay'**
  String get appTitle;

  /// No description provided for @trayConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure overlay'**
  String get trayConfigure;

  /// No description provided for @exitApp.
  ///
  /// In en, this message translates to:
  /// **'Exit'**
  String get exitApp;

  /// No description provided for @twitchChatTitle.
  ///
  /// In en, this message translates to:
  /// **'TWITCH CHAT'**
  String get twitchChatTitle;

  /// No description provided for @layoutModeBanner.
  ///
  /// In en, this message translates to:
  /// **'Layout mode · Ctrl+Shift+O — lock'**
  String get layoutModeBanner;

  /// No description provided for @setupMode.
  ///
  /// In en, this message translates to:
  /// **'setup'**
  String get setupMode;

  /// No description provided for @backgroundTransparency.
  ///
  /// In en, this message translates to:
  /// **'Background transparency'**
  String get backgroundTransparency;

  /// No description provided for @lockOverlay.
  ///
  /// In en, this message translates to:
  /// **'Lock overlay'**
  String get lockOverlay;

  /// No description provided for @checkingTwitchSession.
  ///
  /// In en, this message translates to:
  /// **'Checking Twitch session…'**
  String get checkingTwitchSession;

  /// No description provided for @finishSignInInBrowser.
  ///
  /// In en, this message translates to:
  /// **'Finish signing in in your browser…'**
  String get finishSignInInBrowser;

  /// No description provided for @connectingEventSub.
  ///
  /// In en, this message translates to:
  /// **'Connecting to EventSub…'**
  String get connectingEventSub;

  /// No description provided for @reconnectingChat.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting chat…'**
  String get reconnectingChat;

  /// No description provided for @chatConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to chat'**
  String get chatConnectionFailed;

  /// No description provided for @waitingForConnection.
  ///
  /// In en, this message translates to:
  /// **'Waiting for connection…'**
  String get waitingForConnection;

  /// No description provided for @reconnecting.
  ///
  /// In en, this message translates to:
  /// **'reconnecting'**
  String get reconnecting;

  /// No description provided for @messageRejected.
  ///
  /// In en, this message translates to:
  /// **'Message was rejected'**
  String get messageRejected;

  /// No description provided for @unknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get unknownError;

  /// No description provided for @connectTwitchDescription.
  ///
  /// In en, this message translates to:
  /// **'Connect Twitch to view your channel chat.'**
  String get connectTwitchDescription;

  /// No description provided for @signInWithTwitch.
  ///
  /// In en, this message translates to:
  /// **'Sign in with Twitch'**
  String get signInWithTwitch;

  /// No description provided for @openControlsShortcut.
  ///
  /// In en, this message translates to:
  /// **'Ctrl+Shift+O — open controls'**
  String get openControlsShortcut;

  /// No description provided for @signOutOfTwitch.
  ///
  /// In en, this message translates to:
  /// **'Sign out of Twitch'**
  String get signOutOfTwitch;

  /// No description provided for @sendMessageHint.
  ///
  /// In en, this message translates to:
  /// **'Send a message…'**
  String get sendMessageHint;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @emotes.
  ///
  /// In en, this message translates to:
  /// **'Emotes'**
  String get emotes;

  /// No description provided for @highlightedMessage.
  ///
  /// In en, this message translates to:
  /// **'Highlighted message'**
  String get highlightedMessage;

  /// No description provided for @searchEmotes.
  ///
  /// In en, this message translates to:
  /// **'Search emotes'**
  String get searchEmotes;

  /// No description provided for @noEmotes.
  ///
  /// In en, this message translates to:
  /// **'No emotes available'**
  String get noEmotes;

  /// No description provided for @noMatchingEmotes.
  ///
  /// In en, this message translates to:
  /// **'No matching emotes'**
  String get noMatchingEmotes;

  /// No description provided for @emotesLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load emotes'**
  String get emotesLoadFailed;

  /// No description provided for @emotesPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Connect your Twitch emotes to choose the ones available to you.'**
  String get emotesPermissionRequired;

  /// No description provided for @enableEmotes.
  ///
  /// In en, this message translates to:
  /// **'Connect emotes'**
  String get enableEmotes;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @refreshEmotes.
  ///
  /// In en, this message translates to:
  /// **'Refresh emotes'**
  String get refreshEmotes;

  /// No description provided for @closeEmotes.
  ///
  /// In en, this message translates to:
  /// **'Close emotes'**
  String get closeEmotes;

  /// No description provided for @messageTooLong.
  ///
  /// In en, this message translates to:
  /// **'This emote would exceed the 500-character limit.'**
  String get messageTooLong;

  /// No description provided for @gifLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading GIF…'**
  String get gifLoading;

  /// No description provided for @gifUnavailable.
  ///
  /// In en, this message translates to:
  /// **'GIF unavailable'**
  String get gifUnavailable;

  /// No description provided for @twitchPermissionsChanged.
  ///
  /// In en, this message translates to:
  /// **'Sign in to Twitch again to enable Channel Points rewards.'**
  String get twitchPermissionsChanged;

  /// No description provided for @rewardSubscriptionFailed.
  ///
  /// In en, this message translates to:
  /// **'Channel Points rewards are unavailable. Reconnect Twitch to retry.'**
  String get rewardSubscriptionFailed;

  /// No description provided for @rewardRedemptionAction.
  ///
  /// In en, this message translates to:
  /// **'redeems'**
  String get rewardRedemptionAction;

  /// No description provided for @rewardRedemptionFor.
  ///
  /// In en, this message translates to:
  /// **'for'**
  String get rewardRedemptionFor;

  /// No description provided for @channelPointsCost.
  ///
  /// In en, this message translates to:
  /// **'{cost} Channel Points'**
  String channelPointsCost(int cost);

  /// No description provided for @raidFrom.
  ///
  /// In en, this message translates to:
  /// **'{user} is raiding!'**
  String raidFrom(String user);

  /// No description provided for @raidViewers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 viewer} other{{count} viewers}}'**
  String raidViewers(int count);

  /// No description provided for @sharedChatOrigin.
  ///
  /// In en, this message translates to:
  /// **'from shared chat: {channel}'**
  String sharedChatOrigin(String channel);

  /// No description provided for @replyContext.
  ///
  /// In en, this message translates to:
  /// **'↳ {user}: {message}'**
  String replyContext(String user, String message);

  /// No description provided for @storedSessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your saved Twitch session has expired: {details}'**
  String storedSessionExpired(String details);

  /// No description provided for @twitchAuthorizationFailed.
  ///
  /// In en, this message translates to:
  /// **'Twitch authorization failed: {details}'**
  String twitchAuthorizationFailed(String details);

  /// No description provided for @subscriptionRevoked.
  ///
  /// In en, this message translates to:
  /// **'Twitch disabled the {type} subscription: {status}'**
  String subscriptionRevoked(String type, String status);

  /// No description provided for @unknownEmoteOwner.
  ///
  /// In en, this message translates to:
  /// **'Unavailable channel'**
  String get unknownEmoteOwner;

  /// No description provided for @replyToMessage.
  ///
  /// In en, this message translates to:
  /// **'Reply'**
  String get replyToMessage;

  /// No description provided for @deleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete message'**
  String get deleteMessage;

  /// No description provided for @replyingTo.
  ///
  /// In en, this message translates to:
  /// **'Replying to {user}'**
  String replyingTo(String user);

  /// No description provided for @cancelReply.
  ///
  /// In en, this message translates to:
  /// **'Cancel reply'**
  String get cancelReply;

  /// No description provided for @replyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The message you were replying to is no longer available. Your draft is saved.'**
  String get replyUnavailable;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the message. Try again.'**
  String get deleteFailed;

  /// No description provided for @deleteNotAllowed.
  ///
  /// In en, this message translates to:
  /// **'Twitch does not allow deleting this message.'**
  String get deleteNotAllowed;

  /// No description provided for @messageUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The message was deleted or is too old to delete.'**
  String get messageUnavailable;

  /// No description provided for @moderationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Allow message deletion in Twitch to use this action.'**
  String get moderationPermissionRequired;

  /// No description provided for @enableModeration.
  ///
  /// In en, this message translates to:
  /// **'Enable deletion'**
  String get enableModeration;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'uk'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'uk':
      return AppLocalizationsUk();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
