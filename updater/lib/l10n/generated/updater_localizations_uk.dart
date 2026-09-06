// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'updater_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ukrainian (`uk`).
class UpdaterLocalizationsUk extends UpdaterLocalizations {
  UpdaterLocalizationsUk([String locale = 'uk']) : super(locale);

  @override
  String get windowTitle => 'Twitch Chat Overlay — Оновлення';

  @override
  String get heading => 'Оновлення';

  @override
  String get subtitle => 'Усе нове для вашого чату — в одному місці.';

  @override
  String get installedLabel => 'ВСТАНОВЛЕНО';

  @override
  String get latestLabel => 'ОСТАННЯ ВЕРСІЯ';

  @override
  String get whatsNew => 'Що нового';

  @override
  String get stableRelease => 'СТАБІЛЬНИЙ РЕЛІЗ';

  @override
  String get loadingNotes => 'Отримуємо опис останнього релізу з GitHub.';

  @override
  String get noNotes => 'Автор ще не додав опис цього релізу.';

  @override
  String get settingsHeading => 'Ваш чат залишається вашим';

  @override
  String get settingsDetail => 'Вхід у Twitch і налаштування збережуться.';

  @override
  String get cancelDownload => 'Скасувати завантаження';

  @override
  String get retry => 'Спробувати ще';

  @override
  String get openOverlay => 'Відкрити оверлей';

  @override
  String get updateOverlay => 'Оновити оверлей';

  @override
  String get downloadingAction => 'Завантажуємо…';

  @override
  String get checkingAction => 'Перевіряємо…';

  @override
  String get preparingAction => 'Готуємо оновлення…';

  @override
  String get checkingTitle => 'Перевіряємо оновлення';

  @override
  String get checkingDetail => 'Оверлей продовжує працювати.';

  @override
  String get recoveryTitle => 'Відновлюємо попередню версію';

  @override
  String get recoveryDetail =>
      'Попереднє встановлення було перервано. Зачекайте, будь ласка.';

  @override
  String get availableTitle => 'Доступна нова версія';

  @override
  String packageSize(String size) {
    return 'Пакет: $size МБ. Чат працюватиме до встановлення.';
  }

  @override
  String get currentTitle => 'У вас актуальна версія';

  @override
  String get currentDetail => 'Можна повертатися до чату.';

  @override
  String get downloadTitle => 'Завантажуємо оновлення';

  @override
  String get downloadDetail =>
      'Можна скасувати завантаження. Оверлей продовжує працювати.';

  @override
  String downloadProgress(String received, String total) {
    return '$received / $total МБ';
  }

  @override
  String get verifyTitle => 'Перевіряємо та розпаковуємо';

  @override
  String get verifyDetail => 'Контрольна сума SHA-256 підтверджена.';

  @override
  String get stopTitle => 'Зберігаємо та закриваємо оверлей';

  @override
  String get stopDetail => 'Налаштування буде збережено перед заміною файлів.';

  @override
  String get installTitle => 'Встановлюємо оновлення';

  @override
  String get installDetail =>
      'Не вимикайте комп’ютер. Попередню версію збережено для відновлення.';

  @override
  String get doneTitle => 'Оновлення встановлено';

  @override
  String get doneDetail =>
      'Усе готово. Відкрийте оверлей і повертайтеся до чату.';

  @override
  String get errorTitle => 'Не вдалося завершити оновлення';

  @override
  String get cancelled => 'Оновлення скасовано. Файли програми не змінено.';

  @override
  String get networkError =>
      'Не вдалося підключитися до GitHub. Перевірте інтернет і повторіть спробу.';

  @override
  String get fileError =>
      'Не вдалося оновити файли програми. Перевірте доступ до папки та вільне місце.';

  @override
  String get unexpectedError =>
      'Сталася помилка під час оновлення. Перезапустіть апдейтер і спробуйте ще раз.';

  @override
  String get invalidVersion => 'Непідтримуваний формат номера версії.';

  @override
  String get invalidUrl => 'Реліз містить невірне посилання на оновлення.';

  @override
  String get rateLimited =>
      'GitHub тимчасово обмежив запити. Спробуйте пізніше.';

  @override
  String get packageUnavailable =>
      'У релізі ще немає пакета оновлення. Спробуйте пізніше.';

  @override
  String get invalidMetadata =>
      'У пакета немає коректного розміру або суми SHA-256.';

  @override
  String get downloadSizeMismatch =>
      'Розмір завантаження не відповідає релізу.';

  @override
  String get checksumMismatch =>
      'Архів пошкоджено. Перевірка SHA-256 не пройдена.';

  @override
  String get unsafePath =>
      'Пакет містить шлях поза дозволеною областю встановлення.';

  @override
  String get linksUnsupported =>
      'Оновлення містить символічне посилання, або папка встановлення використовує його.';

  @override
  String get invalidPackage =>
      'Пакет некоректний або не призначений для Twitch Chat Overlay.';

  @override
  String get tooManyFiles => 'Архів оновлення містить забагато файлів.';

  @override
  String get packageTooLarge => 'Розпаковане оновлення завелике.';

  @override
  String get versionMismatch => 'Версія пакета не відповідає вибраному релізу.';

  @override
  String get missingRuntime => 'У пакеті відсутній необхідний файл програми.';

  @override
  String get invalidInstallation =>
      'Оверлей не знайдено. Папка updater має лежати поруч із програмою.';

  @override
  String get recoveryRequired =>
      'Спочатку потрібно відновити попереднє встановлення. Повторіть спробу.';

  @override
  String get invalidJournal =>
      'Журнал відновлення пошкоджено. Резервну копію збережено.';

  @override
  String get updateBusy => 'Інше оновлення вже виконується.';

  @override
  String get closeOverlay =>
      'Закрийте оверлей через «Вийти» у треї та повторіть оновлення.';

  @override
  String get linkOpenFailed => 'Не вдалося відкрити посилання. Спробуйте ще.';
}
