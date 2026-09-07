// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get viewerCountLabel => 'Viewers';

  @override
  String get streamOffline => 'Offline';

  @override
  String get appTitle => 'Twitch Chat Overlay';

  @override
  String get trayConfigure => 'Configure overlay';

  @override
  String get trayUpdate => 'Check for updates…';

  @override
  String get trayShow => 'Show overlay';

  @override
  String get trayHide => 'Hide overlay';

  @override
  String get exitApp => 'Exit';

  @override
  String get twitchChatTitle => 'TWITCH CHAT';

  @override
  String get layoutModeBanner => 'Layout mode · Ctrl+Shift+O — lock';

  @override
  String get setupMode => 'setup';

  @override
  String get gifPlaybackDisabled => 'Do not animate GIFs';

  @override
  String get gifPlayCount => 'GIF plays';

  @override
  String get gifPlayCountUnlimited => 'Repeat GIFs indefinitely';

  @override
  String gifPlayCountValue(int count) {
    return '$count plays';
  }

  @override
  String get increaseGifPlayCount => 'Increase GIF plays';

  @override
  String get decreaseGifPlayCount => 'Decrease GIF plays';

  @override
  String get messageLifetime => 'Message lifetime';

  @override
  String get messageLifetimeUnlimited => 'Keep messages indefinitely';

  @override
  String messageLifetimeMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get increaseMessageLifetime => 'Increase message lifetime';

  @override
  String get decreaseMessageLifetime => 'Decrease message lifetime';

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
  String get chatConnected => 'Chat connected';

  @override
  String get noChatMessages =>
      'No recent messages.\nNew messages will appear here.';

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
  String get rewardSubscriptionFailed =>
      'Channel Points rewards are unavailable. Reconnect Twitch to retry.';

  @override
  String get rewardRedemptionAction => 'redeems';

  @override
  String get rewardRedemptionFor => 'for';

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

  @override
  String get copyMessage => 'Copy';

  @override
  String get replyToMessage => 'Reply';

  @override
  String get deleteMessage => 'Delete message';

  @override
  String replyingTo(String user) {
    return 'Replying to $user';
  }

  @override
  String get cancelReply => 'Cancel reply';

  @override
  String get replyUnavailable =>
      'The message you were replying to is no longer available. Your draft is saved.';

  @override
  String get deleteFailed => 'Could not delete the message. Try again.';

  @override
  String get deleteNotAllowed => 'Twitch does not allow deleting this message.';

  @override
  String get messageUnavailable =>
      'The message was deleted or is too old to delete.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get powerUpMessageEffect => 'Message Effects';

  @override
  String get powerUpGigantifyEmote => 'Gigantify an Emote';

  @override
  String get powerUpCelebration => 'On-Screen Celebration';

  @override
  String bitsAmount(int amount) {
    return '$amount Bits';
  }

  @override
  String updateNoticeTitle(String version) {
    return 'Version $version is available';
  }

  @override
  String get updateNoticeDetail => 'A fresh update for your overlay.';

  @override
  String get updateNoticeShortcut => 'Press Ctrl+Shift+O to update.';

  @override
  String get updateNow => 'Update';

  @override
  String get updateOpening => 'Opening…';

  @override
  String get updateDismiss => 'Remind me next time';

  @override
  String get updateLaunchFailed => 'Couldn\'t open the updater. Try again.';
}
