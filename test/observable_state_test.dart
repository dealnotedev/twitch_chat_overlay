import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';

void main() {
  test(
    'selection errors reach consumers without stopping later changes',
    () async {
      final source = ObservableValue<int>(current: 0);
      addTearDown(source.dispose);
      final selected = source.select((value) {
        if (value == 1) throw const FormatException('cannot select value');
        return value;
      });
      final values = <int>[];
      final errors = <Object>[];
      final subscription = selected.changes.listen(
        values.add,
        onError: errors.add,
      );
      source.set(1);
      expect(errors.single, isA<FormatException>());
      expect(values, isEmpty);
      source.set(2);
      expect(values, [2]);
      await subscription.cancel();
    },
  );

  test(
    'a selection reads current state before its own listener runs',
    () async {
      final source = ObservableValue<int>(current: 0);
      addTearDown(source.dispose);
      final selected = source.select((value) => value.isEven);
      final currentValues = <bool>[];
      final upstream = source.changes.listen(
        (_) => currentValues.add(selected.current),
      );
      final events = <bool>[];
      final subscription = selected.changes.listen(events.add);
      source.set(1);
      expect(currentValues, [false]);
      expect(events, [false]);
      expect(selected.changes, same(selected.changes));
      await upstream.cancel();
      await subscription.cancel();
    },
  );

  test('selection filters from each subscriber snapshot and follows source disposal', () async {
    final source = ObservableValue<int>(current: 0);
    final selected = source.select((value) => value ~/ 10);
    final first = <int>[];
    final second = <int>[];
    final firstDone = Completer<void>();
    final secondDone = Completer<void>();
    final subscription = selected.changes.listen(
      first.add,
      onDone: firstDone.complete,
    );
    source.set(1);
    expect(first, isEmpty);
    source.set(10);
    expect(first, [1]);
    selected.changes.listen(second.add, onDone: secondDone.complete);
    source.set(11);
    expect(second, isEmpty);
    source.set(20);
    expect(first, [1, 2]);
    expect(second, [2]);
    await subscription.cancel();
    source.set(30);
    expect(first, [1, 2]);
    expect(second, [2, 3]);
    source.dispose();
    await secondDone.future;
    expect(firstDone.isCompleted, isFalse);
    expect(selected.current, 3);
    expect(selected.changes.isBroadcast, isTrue);
  });

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
        ObservableBuilder<int>(
          source: value,
          builder: (context, current, _) {
            rendered.add(current);
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

  testWidgets('a builder renders the newest snapshot once for stale events', (
    tester,
  ) async {
    final value = ObservableValue<int>(current: 0, sync: false);
    addTearDown(value.dispose);
    final rendered = <int>[];
    await tester.pumpWidget(
      ObservableBuilder<int>(
        source: value,
        builder: (context, current, _) {
          rendered.add(current);
          return const SizedBox.shrink();
        },
      ),
    );
    value.set(1);
    value.set(2);
    await tester.pumpAndSettle();
    expect(rendered, [0, 2]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'replacing a builder source re-reads it and ignores the old one',
    (tester) async {
      final first = ObservableValue<int>(current: 1);
      final second = ObservableValue<int>(current: 10);
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      Widget build(Observable<int> source) => Directionality(
        textDirection: TextDirection.ltr,
        child: ObservableBuilder<int>(
          source: source,
          builder: (context, current, _) => Text('$current'),
        ),
      );
      await tester.pumpWidget(build(first));
      await tester.pumpWidget(build(second));
      expect(find.text('10'), findsOneWidget);
      first.set(2);
      await tester.pump();
      expect(find.text('10'), findsOneWidget);
      second.set(11);
      await tester.pump();
      expect(find.text('11'), findsOneWidget);
      await tester.pumpWidget(build(const Observable.value(5)));
      expect(find.text('5'), findsOneWidget);
    },
  );

  test('setting an equal value changes nothing and notifies nobody', () {
    final value = ObservableValue<String>(current: 'a');
    addTearDown(value.dispose);
    final received = <String>[];
    value.changes.listen(received.add);
    value.set('a');
    value.set('b');
    value.set('b');
    expect(received, ['b']);
  });

  test('a delegated source reads its owner without copying state', () {
    var state = 1;
    final changes = StreamController<int>.broadcast(sync: true);
    addTearDown(changes.close);
    final source = Observable.of(() => state, changes.stream);
    final selected = source.select((value) => value.isEven);
    final events = <bool>[];
    selected.changes.listen(events.add);
    state = 2;
    expect(source.current, 2);
    expect(selected.current, isTrue);
    changes.add(2);
    expect(events, [true]);
  });

  test(
    'a selection over a deferred source reports the newest value once',
    () async {
      final value = ObservableValue<int>(current: 0, sync: false);
      addTearDown(value.dispose);
      final selected = value.select((current) => current * 10);
      final events = <int>[];
      selected.changes.listen(events.add);
      value.set(1);
      value.set(2);
      await Future<void>.delayed(Duration.zero);
      expect(events, [20]);
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
      expect(() => viewModel.items.set([1]), throwsStateError);
      await subscription.cancel();
    },
  );
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
