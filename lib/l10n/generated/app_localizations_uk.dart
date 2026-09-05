// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class AppLocalizationsUk extends AppLocalizations {
  AppLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get appTitle => 'Twitch Chat Overlay';

  @override
  String get trayConfigure => 'Налаштувати оверлей';

  @override
  String get exitApp => 'Вийти';

  @override
  String get twitchChatTitle => 'ЧАТ TWITCH';

  @override
  String get layoutModeBanner =>
      'Режим налаштування · Ctrl+Shift+O — заблокувати';

  @override
  String get setupMode => 'налаштування';

  @override
  String get backgroundTransparency => 'Прозорість фону';

  @override
  String get lockOverlay => 'Заблокувати оверлей';

  @override
  String get checkingTwitchSession => 'Перевіряємо сесію Twitch…';

  @override
  String get finishSignInInBrowser => 'Завершіть вхід у браузері…';

  @override
  String get connectingEventSub => 'Підключаємося до EventSub…';

  @override
  String get reconnectingChat => 'Перепідключаємо чат…';

  @override
  String get chatConnectionFailed => 'Не вдалося підключити чат';

  @override
  String get chatConnected => 'Чат підключено';

  @override
  String get noChatMessages =>
      'Повідомлень поки немає.\nЧекаємо на першого чатера.';

  @override
  String get waitingForConnection => 'Очікуємо на підключення…';

  @override
  String get reconnecting => 'перепідключення';

  @override
  String get messageRejected => 'Повідомлення відхилено';

  @override
  String get unknownError => 'Невідома помилка';

  @override
  String get connectTwitchDescription =>
      'Підключіть Twitch, щоб переглядати чат свого каналу.';

  @override
  String get signInWithTwitch => 'Увійти через Twitch';

  @override
  String get openControlsShortcut => 'Ctrl+Shift+O — відкрити керування';

  @override
  String get signOutOfTwitch => 'Вийти з Twitch';

  @override
  String get sendMessageHint => 'Напишіть щось…';

  @override
  String get send => 'Надіслати';

  @override
  String get emotes => 'Смайли';

  @override
  String get highlightedMessage => 'Важливе повідомлення';

  @override
  String get searchEmotes => 'Пошук смайлів';

  @override
  String get noEmotes => 'Немає доступних смайлів';

  @override
  String get noMatchingEmotes => 'Смайлів не знайдено';

  @override
  String get emotesLoadFailed => 'Не вдалося завантажити смайли';

  @override
  String get retry => 'Повторити';

  @override
  String get refreshEmotes => 'Оновити смайли';

  @override
  String get closeEmotes => 'Закрити смайли';

  @override
  String get messageTooLong => 'Цей смайл перевищить ліміт у 500 символів.';

  @override
  String get gifLoading => 'Завантаження GIF…';

  @override
  String get gifUnavailable => 'GIF недоступна';

  @override
  String get rewardSubscriptionFailed =>
      'Нагороди за бали каналу недоступні. Перепідключіть Twitch, щоб повторити спробу.';

  @override
  String get rewardRedemptionAction => 'бере';

  @override
  String get rewardRedemptionFor => 'за';

  @override
  String channelPointsCost(int cost) {
    String _temp0 = intl.Intl.pluralLogic(
      cost,
      locale: localeName,
      other: '$cost бала каналу',
      many: '$cost балів каналу',
      few: '$cost бали каналу',
      one: '$cost бал каналу',
    );
    return '$_temp0';
  }

  @override
  String raidFrom(String user) {
    return '$user починає рейд!';
  }

  @override
  String raidViewers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count глядача',
      many: '$count глядачів',
      few: '$count глядачі',
      one: '$count глядач',
    );
    return '$_temp0';
  }

  @override
  String sharedChatOrigin(String channel) {
    return 'зі спільного чату: $channel';
  }

  @override
  String replyContext(String user, String message) {
    return '↳ $user: $message';
  }

  @override
  String storedSessionExpired(String details) {
    return 'Збережена сесія Twitch завершилася: $details';
  }

  @override
  String twitchAuthorizationFailed(String details) {
    return 'Не вдалося авторизуватися у Twitch: $details';
  }

  @override
  String subscriptionRevoked(String type, String status) {
    return 'Twitch вимкнув підписку $type: $status';
  }

  @override
  String get unknownEmoteOwner => 'Недоступний канал';

  @override
  String get copyMessage => 'Скопіювати';

  @override
  String get replyToMessage => 'Відповісти';

  @override
  String get deleteMessage => 'Видалити';

  @override
  String replyingTo(String user) {
    return 'Відповідь $user';
  }

  @override
  String get cancelReply => 'Скасувати відповідь';

  @override
  String get replyUnavailable =>
      'Повідомлення, на яке ви відповідали, більше недоступне. Чернетку збережено.';

  @override
  String get deleteFailed =>
      'Не вдалося видалити повідомлення. Спробуйте ще раз.';

  @override
  String get deleteNotAllowed => 'Twitch не дозволяє видалити це повідомлення.';

  @override
  String get messageUnavailable =>
      'Повідомлення вже видалено або термін його видалення минув.';

  @override
  String get dismiss => 'Закрити';
}
