// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Twitch Chat Overlay';

  @override
  String get trayConfigure => 'Configure overlay';

  @override
  String get exitApp => 'Exit';

  @override
  String get twitchChatTitle => 'TWITCH CHAT';

  @override
  String get layoutModeBanner => 'Layout mode · Ctrl+Shift+O — lock';

  @override
  String get setupMode => 'setup';

  @override
  String get backgroundTransparency => 'Background transparency';

  @override
  String get lockOverlay => 'Lock overlay';

  @override
  String get checkingTwitchSession => 'Checking Twitch session…';

  @override
  String get finishSignInInBrowser => 'Finish signing in in your browser…';

  @override
  String get connectingEventSub => 'Connecting to EventSub…';

  @override
  String get reconnectingChat => 'Reconnecting chat…';

  @override
  String get chatConnectionFailed => 'Could not connect to chat';

  @override
  String get waitingForConnection => 'Waiting for connection…';

  @override
  String get reconnecting => 'reconnecting';

  @override
  String get messageRejected => 'Message was rejected';

  @override
  String get unknownError => 'Unknown error';

  @override
  String get connectTwitchDescription =>
      'Connect Twitch to view your channel chat.';

  @override
  String get signInWithTwitch => 'Sign in with Twitch';

  @override
  String get openControlsShortcut => 'Ctrl+Shift+O — open controls';

  @override
  String get signOutOfTwitch => 'Sign out of Twitch';

  @override
  String get sendMessageHint => 'Send a message…';

  @override
  String get send => 'Send';

  @override
  String get emotes => 'Emotes';

  @override
  String get highlightedMessage => 'Highlighted message';

  @override
  String get searchEmotes => 'Search emotes';

  @override
  String get noEmotes => 'No emotes available';

  @override
  String get noMatchingEmotes => 'No matching emotes';

  @override
  String get emotesLoadFailed => 'Could not load emotes';

  @override
  String get emotesPermissionRequired =>
      'Connect your Twitch emotes to choose the ones available to you.';

  @override
  String get enableEmotes => 'Connect emotes';

  @override
  String get retry => 'Retry';

  @override
  String get refreshEmotes => 'Refresh emotes';

  @override
  String get closeEmotes => 'Close emotes';

  @override
  String get messageTooLong =>
      'This emote would exceed the 500-character limit.';

  @override
  String get gifLoading => 'Loading GIF…';

  @override
  String get gifUnavailable => 'GIF unavailable';

  @override
  String get twitchPermissionsChanged =>
      'Sign in to Twitch again to enable Channel Points rewards.';

  @override
  String get rewardSubscriptionFailed =>
      'Channel Points rewards are unavailable. Reconnect Twitch to retry.';

  @override
  String rewardRedeemedBy(String user) {
    return '$user redeemed a reward';
  }

  @override
  String channelPointsCost(int cost) {
    return '$cost Channel Points';
  }

  @override
  String raidFrom(String user) {
    return '$user is raiding!';
  }

  @override
  String raidViewers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count viewers',
      one: '1 viewer',
    );
    return '$_temp0';
  }

  @override
  String sharedChatOrigin(String channel) {
    return 'from shared chat: $channel';
  }

  @override
  String replyContext(String user, String message) {
    return '↳ $user: $message';
  }

  @override
  String storedSessionExpired(String details) {
    return 'Your saved Twitch session has expired: $details';
  }

  @override
  String twitchAuthorizationFailed(String details) {
    return 'Twitch authorization failed: $details';
  }

  @override
  String subscriptionRevoked(String type, String status) {
    return 'Twitch disabled the $type subscription: $status';
  }

  @override
  String get unknownEmoteOwner => 'Unavailable channel';
}
