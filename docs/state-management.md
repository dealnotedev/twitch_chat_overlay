# State management

The overlay and updater keep UI state in `XxxViewModel` classes built on the
small local package `packages/observable_state`.

## Building blocks

- `ObservableValue<T>` owns a value. `set` publishes a new immutable snapshot;
  a value equal (`==`) to the current one is ignored. Notifications are
  synchronous by default (`sync: false` defers them) and nested changes are
  delivered in order.
- `Observable<T>` is the read-only side: `current` is the truth,
  `changes` only says that it changed. Read `current` when notified.
  - `Observable.value(x)` is a fixed snapshot (handy in tests).
  - `Observable.of(read, changes)` is a view over state owned elsewhere,
    e.g. a service's `state`/`states`. No copies to keep in sync.
  - `source.select(f)` is a projection that notifies only when `f` changes.
    Create selections once (fields), never inside `build`.
- `ObservableBuilder<T>(source:, builder:, child:)` renders `source.current`
  and rebuilds on change. Replacing `source` re-reads it.
- `FailableProcess<T>` describes an operation: `initial`, `loading`, `failed`.
  Success returns to `initial`; the result lives in another state field.
  `failed` carries a typed error for the UI plus `cause`/`stackTrace`.

## Writing a ViewModel

```dart
final class ExampleViewModel extends BaseViewModel {
  ExampleViewModel(this._repository) {
    _items = register(ObservableValue(current: const <Item>[]));
    observe(_repository.changes, (_) => _reload());
    unawaited(_reload());
  }

  final Repository _repository;
  late final ObservableValue<List<Item>> _items;
  Observable<List<Item>> get items => _items;

  Future<void> _reload() async {
    final items = await _repository.load();
    if (!isDisposed) _items.set(List.unmodifiable(items));
  }
}
```

- Observables are private; getters expose `Observable`. Only intent
  methods change state.
- The constructor creates initial values, subscribes, and starts requests.
- Group fields that change together into one observable; split parts with
  different UI subscribers (timeline vs. composer, state vs. download progress).
- After every `await`, check `isDisposed` (or a session generation) before
  writing. Writing to a disposed observable throws.
- `dispose()` calls `super.dispose()` first, then releases timers/children.
- Keep `BuildContext`, localization, text/focus/animation controllers in views.
  Errors in state are typed enums; views localize them.

## Ownership

A view creates its model in `initState` and disposes it in `dispose`.
`UpdaterApp.withViewModel` takes an external model and never disposes it.

## Current models

- `OverlayViewModel` — window frame (layout, host, settings, capture exclusion).
  Exposes the auth and chat services as views plus `signedIn` and
  `connectionStatus` selections, and joins/leaves chat on sign-in changes.
- `ChatPanelViewModel` — timeline, deletions and session presentation, read
  from its `auth`/`chat` sources. `update()` replaces sources or configuration;
  unchanged sources and display settings skip re-synchronization.
- `ChatComposerViewModel` — owned by the panel: draft feedback, reply target,
  emote picker and the single in-flight send.
- `LocaleViewModel` — selected locale; writes are serialized.
- `UpdateNoticeViewModel` — optional release check and the launch process.
- `UpdateViewModel` (updater) — installation state and separate download
  progress.
