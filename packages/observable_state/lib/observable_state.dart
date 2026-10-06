import 'dart:async';
import 'dart:collection';

import 'package:meta/meta.dart';

export 'failable_process.dart';

/// Read-only state with a synchronous snapshot and a stable change stream.
abstract interface class StreamWithInitial<T> {
  /// An immutable source for a value that changes when its owner replaces it.
  const factory StreamWithInitial.value(T current) = _FixedValue<T>;

  T get current;
  Stream<T> get changes;
}

final class _FixedValue<T> implements StreamWithInitial<T> {
  const _FixedValue(this.current);
  @override
  final T current;
  @override
  Stream<T> get changes => const Stream.empty(broadcast: true);
}

extension StreamWithInitialSelection<T> on StreamWithInitial<T> {
  /// A stable read-only projection, notifying only when its selected value changes.
  /// Create it once; it follows the source's lifetime and exposes no writes.
  StreamWithInitial<R> select<R>(R Function(T value) select) =>
      _SelectedValue(this, select);
}

final class _SelectedValue<T, R> implements StreamWithInitial<R> {
  _SelectedValue(this._source, this._select) {
    changes = Stream<R>.multi((controller) {
      var previous = current;
      final subscription = _source.changes.listen(
        (value) {
          try {
            final next = _select(value);
            if (next == previous) return;
            previous = next;
            controller.addSync(next);
          } catch (error, stack) {
            controller.addErrorSync(error, stack);
          }
        },
        onError: controller.addErrorSync,
        onDone: controller.closeSync,
      );
      controller.onCancel = subscription.cancel;
    }, isBroadcast: true);
  }

  final StreamWithInitial<T> _source;
  final R Function(T value) _select;

  @override
  R get current => _select(_source.current);

  @override
  late final Stream<R> changes;
}

/// Owns a value with a current snapshot and change notifications.
///
/// Supply [current] as StreamBuilder.initialData, including when a consumer
/// subscribes after earlier changes. Changes are notifications, not a replay log.
/// Notifications are synchronous by default; pass `sync: false` to defer them.
final class ObservableValue<T> implements StreamWithInitial<T> {
  ObservableValue({required T current, bool sync = true})
    : _current = current,
      _changes = StreamController<T>.broadcast(sync: sync);

  T _current;
  final StreamController<T> _changes;
  final Queue<T> _notifications = Queue<T>();
  bool _notifying = false;
  bool _disposed = false;

  @override
  T get current => _current;

  @override
  Stream<T> get changes => _changes.stream;

  void set(T value, {bool notify = true}) {
    if (_disposed) throw StateError('ObservableValue is disposed');
    _current = value;
    if (!notify) return;
    _notifications.add(value);
    if (_notifying) return;
    _notifying = true;
    try {
      // A synchronous listener may issue another intent. Deliver its change
      // only after every listener has received the preceding notification.
      while (_notifications.isNotEmpty && !_disposed) {
        _changes.add(_notifications.removeFirst());
      }
    } finally {
      _notifying = false;
      if (_disposed) unawaited(_changes.close());
    }
  }

  /// Mutate the current collection in place and notify without copying it.
  /// Notifications share the same collection; they are not historical copies.
  void apply(void Function(T current) update) {
    if (_disposed) throw StateError('ObservableValue is disposed');
    update(_current);
    set(_current);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _notifications.clear();
    if (!_notifying) unawaited(_changes.close());
  }
}

/// Distinguishes an unchanged nullable field from one explicitly cleared.
final class Nullable<T> {
  const Nullable(this.value);
  final T? value;
}

extension NullableFallback<T> on Nullable<T>? {
  T? getOr(T? previous) => this == null ? previous : this!.value;
}

/// Owns registered observables and subscriptions for one presentation flow.
///
/// Subclasses dispose their timers/resources and call super.dispose() first so
/// pending asynchronous operations can check [isDisposed] before publishing.
/// Models initialize their final observables, wire subscriptions, and start
/// requests in the constructor. The base imposes no particular state shape.
abstract class BaseViewModel {
  final Set<ObservableValue<dynamic>> _observables = {};
  final Set<StreamSubscription<dynamic>> _subscriptions = {};
  bool _disposed = false;

  bool get isDisposed => _disposed;

  @protected
  ObservableValue<T> register<T>(ObservableValue<T> observable) {
    if (_disposed) throw StateError('ViewModel is disposed');
    _observables.add(observable);
    return observable;
  }

  @protected
  StreamSubscription<V> observe<V>(
    Stream<V> source,
    void Function(V value) onData,
  ) {
    if (_disposed) throw StateError('ViewModel is disposed');
    final subscription = source.listen((value) {
      if (!_disposed) onData(value);
    });
    _subscriptions.add(subscription);
    return subscription;
  }

  @protected
  void stopObserving(StreamSubscription<dynamic>? subscription) {
    if (subscription == null) return;
    _subscriptions.remove(subscription);
    unawaited(subscription.cancel());
  }

  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    for (final observable in _observables) {
      observable.dispose();
    }
    _observables.clear();
  }
}
