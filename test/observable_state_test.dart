import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';

void main() {
  test(
    'notifications are synchronous by default and nested changes stay ordered',
    () async {
      final value = ObservableValue<int>(current: 0);
      addTearDown(value.dispose);
      final received = <int>[];
      final first = value.changes.listen((next) {
        if (next == 1) value.set(2);
      });
      final second = value.changes.listen(received.add);
      value.set(1);
      expect(value.current, 2);
      expect(received, [1, 2]);
      await first.cancel();
      await second.cancel();
    },
  );

  test(
    'a synchronous listener can dispose the value during delivery',
    () async {
      final value = ObservableValue<int>(current: 0);
      final done = Completer<void>();
      value.changes.listen((_) => value.dispose(), onDone: done.complete);
      value.set(1);
      await done.future;
      expect(value.current, 1);
      expect(() => value.set(2), throwsStateError);
    },
  );

  testWidgets(
    'late-mounted builders render the latest value on their first frame',
    (tester) async {
      final value = ObservableValue<int>(current: 1, sync: false);
      addTearDown(value.dispose);
      value.set(2); // No listener existed when this update happened.
      final rendered = <int>[];
      await tester.pumpWidget(
        StreamBuilder<int>(
          initialData: value.current,
          stream: value.changes,
          builder: (context, snapshot) {
            rendered.add(snapshot.requireData);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(rendered, [2]);
      value.set(3);
      expect(value.current, 3);
      await tester.pumpAndSettle();
      expect(rendered.last, 3);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'async consumers receive deferred changes and disposal closes both streams',
    () async {
      final value = ObservableValue<int>(current: 0, sync: false);
      final first = <int>[];
      final second = <int>[];
      final firstDone = Completer<void>();
      final secondDone = Completer<void>();
      value.changes.listen(first.add, onDone: firstDone.complete);
      value.changes.listen(second.add, onDone: secondDone.complete);
      value.set(1);
      value.set(2);
      expect(value.current, 2);
      expect(first, isEmpty);
      expect(second, isEmpty);
      value.dispose();
      value.dispose();
      await Future.wait([firstDone.future, secondDone.future]);
      expect(first, [1, 2]);
      expect(second, first);
      expect(() => value.set(3), throwsStateError);
    },
  );

  test(
    'disposing a ViewModel cancels subscriptions and ignores late work',
    () async {
      final source = StreamController<int>();
      final viewModel = _ViewModel(source.stream);
      final events = <int>[];
      final subscription = viewModel.state.changes.listen(events.add);
      final stateDone = Completer<void>();
      final listDone = Completer<void>();
      viewModel.state.changes.listen((_) {}, onDone: stateDone.complete);
      viewModel.items.changes.listen((_) {}, onDone: listDone.complete);
      final pending = Completer<int>();
      final work = viewModel.load(pending.future);
      source.add(1);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.state.current, 1);
      viewModel.dispose();
      viewModel.dispose();
      expect(source.hasListener, isFalse);
      pending.complete(2);
      await work;
      source.add(3);
      await source.close();
      await Future.wait([stateDone.future, listDone.future]);
      expect(viewModel.state.current, 1);
      expect(events, [1]);
      expect(
        () => viewModel.items.apply((items) => items.add(1)),
        throwsStateError,
      );
      await subscription.cancel();
    },
  );

  test('apply keeps the collection and notifies independent consumers', () {
    final items = <int>[1];
    final value = ObservableValue(current: items);
    addTearDown(value.dispose);
    final first = <List<int>>[];
    final second = <List<int>>[];
    value.changes.listen(first.add);
    value.changes.listen(second.add);
    value.apply((current) => current.add(2));
    expect(value.current, same(items));
    expect(value.current, [1, 2]);
    expect(first.single, same(items));
    expect(second.single, same(items));
    value.dispose();
    expect(() => value.apply((current) => current.clear()), throwsStateError);
    expect(items, [1, 2]);
  });
}

final class _ViewModel extends BaseViewModel {
  _ViewModel(Stream<int> source) {
    state = register(ObservableValue(current: 0));
    items = register(ObservableValue<List<int>>(current: []));
    observe(source, state.set);
  }
  late final ObservableValue<int> state;
  late final ObservableValue<List<int>> items;

  Future<void> load(Future<int> operation) async {
    final result = await operation;
    if (!isDisposed) state.set(result);
  }
}
