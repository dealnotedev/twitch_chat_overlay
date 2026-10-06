import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twitch_chat_overlay/l10n/locale_view_model.dart';

void main() {
  test('a synchronous listener cannot persist an older locale last', () async {
    final writes = <String>[];
    final viewModel = LocaleViewModel(
      _Preferences((locale) async {
        writes.add(locale);
        return true;
      }),
    );
    addTearDown(viewModel.dispose);
    Future<void>? nestedSave;
    final subscription = viewModel.locale.changes.listen((locale) {
      if (locale.languageCode == 'en') nestedSave = viewModel.cycle();
    });
    addTearDown(subscription.cancel);
    await viewModel.cycle();
    await nestedSave;
    await viewModel.flush();
    expect(writes, ['en', 'uk']);
    expect(viewModel.locale.current.languageCode, writes.last);
    expect(viewModel.saveProcess.current.isActive, isFalse);
  });

  test(
    'an older failed save cannot replace the latest saving process',
    () async {
      final first = Completer<bool>();
      final second = Completer<bool>();
      final writes = <String>[];
      final preferences = _Preferences((locale) {
        writes.add(locale);
        return writes.length == 1 ? first.future : second.future;
      });
      final viewModel = LocaleViewModel(preferences);
      addTearDown(viewModel.dispose);
      final firstSave = viewModel.cycle();
      final firstFailure = expectLater(
        firstSave,
        throwsA(isA<LocalePersistenceException>()),
      );
      final lastSave = viewModel.cycle();
      first.complete(false);
      await firstFailure;
      expect(viewModel.saveProcess.current.isActive, isTrue);
      expect(viewModel.saveProcess.current.error, isNull);
      second.complete(true);
      await lastSave;
      expect(writes, ['en', 'uk']);
      expect(viewModel.locale.current.languageCode, 'uk');
      expect(viewModel.saveProcess.current, isA<InitialProcess<void>>());
    },
  );

  test(
    'a failed latest save is typed and a subsequent save can recover',
    () async {
      var succeed = false;
      final viewModel = LocaleViewModel(_Preferences((_) async => succeed));
      addTearDown(viewModel.dispose);
      await expectLater(
        viewModel.cycle(),
        throwsA(isA<LocalePersistenceException>()),
      );
      final failed = viewModel.saveProcess.current as FailedProcess<void>;
      expect(failed.error, LocaleFailure.persistence);
      expect(failed.cause, isA<StateError>());
      expect(failed.stackTrace, isNotNull);
      expect(viewModel.locale.current.languageCode, 'en');
      succeed = true;
      await viewModel.cycle();
      await viewModel.flush();
      expect(viewModel.saveProcess.current, isA<InitialProcess<void>>());
    },
  );
}

final class _Preferences extends Fake implements SharedPreferences {
  _Preferences(this.save);
  final Future<bool> Function(String value) save;
  @override
  String? getString(String key) => null;
  @override
  Future<bool> setString(String key, String value) => save(value);
}
