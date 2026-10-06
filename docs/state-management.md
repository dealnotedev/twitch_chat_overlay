# State management

The overlay and updater use `XxxViewModel` objects with `ObservableValue<T>`.
The shared implementation lives in `packages/observable_state`.

## ViewModel and ownership

`BaseViewModel` has no state type parameter and no shared `state` or `emit`.
Each model chooses its own observables, grouping fields that change together and
separating independently changing parts of the UI. Observable fields are private
and `final` (or `late final` when assigned in the constructor). Public getters
expose `StreamWithInitial<T>` for reading; only intent methods change the state.

The constructor creates initial values directly, registers their ownership,
wires subscriptions, and starts initial requests. There is no separate
`initialize()` call and no emission just to establish initial state.

```dart
final class ExampleViewModel extends BaseViewModel {
  ExampleViewModel(Repository repository) {
    _items = register(ObservableValue<List<Item>>(current: []));
    _process = register(ObservableValue<SimpleFailableProcess>(
      current: const SimpleFailableProcess.loading(),
    ));
    observe(repository.changes, _onChange);
    unawaited(_load(repository));
  }

  late final ObservableValue<List<Item>> _items;
  late final ObservableValue<SimpleFailableProcess> _process;
  StreamWithInitial<List<Item>> get items => _items;
  StreamWithInitial<SimpleFailableProcess> get process => _process;
  // Intent methods and asynchronous request handling belong here.
}
```

`register(observable)` returns the same observable and makes the base responsible
for closing it. `observe(stream, callback)` returns a tracked subscription;
`stopObserving(subscription)` cancels and unregisters it when replacing a source.
The base
marks the model disposed, cancels subscriptions, and closes every registered
observable. Disposal is idempotent. Call `super.dispose()` first, then release
model-specific timers and resources; check `isDisposed` after asynchronous work
before writing to an observable. Direct writes to a disposed observable throw.

A view creates its model in `initState` and disposes it in `dispose`. An injected,
externally owned model remains its caller's responsibility. Dependencies are
constructor parameters. Keep `BuildContext`, localization, text/focus controllers,
hover, and animation controllers in the view.

`UpdaterApp` creates and owns its model through `createViewModel` in `initState`.
`UpdaterApp.withViewModel` uses an externally owned model and never disposes it,
including when it is replaced by another injected model.

## Collections and updates

Use `set` to publish a new snapshot. Chat messages, fading IDs, user colors and
deletion processes expose unmodifiable collections. Earlier notifications retain
their values, and consumers cannot mutate a collection without notifying its owner.
Message snapshots are built directly from the retention model's lazy visible
items, avoiding a temporary list followed by `clear/addAll`. Building and comparing
the timeline still takes O(n); this is not a claim of measured memory or FPS gains.

`apply` remains available for privately owned mutable values. Its notifications
share the collection and are not historical snapshots; presentation models use
immutable snapshots instead. Small grouped values such as composer state or window
layout use `copyWith`; `Nullable<T>` distinguishes leaving a nullable field
unchanged from explicitly clearing it.

## StreamBuilder consumption

Subscribe near the part of the UI that needs the value. Every state
`StreamBuilder` supplies `current` as `initialData` and reads non-nullable data
with `requireData`:

```dart
StreamBuilder<ChatComposerState>(
  initialData: viewModel.composer.current,
  stream: viewModel.composer.changes,
  builder: (context, snapshot) => buildComposer(snapshot.requireData),
)
```

`StreamWithInitial<T>` provides the read-only `current` and `changes` contract
when passing state sources between components. The stream is stable and
broadcasts notifications; it does not replay old events. `current` changes
immediately. `ObservableValue` notifies synchronously by default; nested
notifications are queued until the preceding event reaches all listeners.
Pass `sync: false` for asynchronous notifications, as the existing Twitch chat
session does.
Event-only streams such as native close requests do not need initial data.

`ChatPanel` accepts only `authSource` and `chatSource`. For a snapshot without
events, pass `StreamWithInitial.value(snapshot)`. The model replaces subscriptions
when sources change and ignores events from the previous source. Its session
presentation is a record of the fields used by the view, excluding the timeline;
record equality suppresses message-only session notifications automatically.

## Failable processes and typed errors

`FailableProcess<T>` represents an operation as `initial`, `loading`, or `failed`.
Success returns to `initial`; the result belongs to another state field.
`T` is an optional operation token; `SimpleFailableProcess` has no token.
Derived flags such as `sending` read the process rather than storing duplicate
loading/error fields. Keep a process active through cleanup, so a retry cannot
race the previous operation.

Set operation guards, cancellation tokens and persistence queues before publishing
synchronous notifications: a listener can issue another intent immediately.
Installation becomes busy before download reset is published, and each locale
write is queued before its new locale is published.

Feature failures are typed (`ChatPanelError`, `OverlayFailure`,
`UpdateNoticeFailure`, `LocaleFailure`, or `UpdateIssue`). `FailedProcess.error`
holds that value, while `cause` and `stackTrace` retain original diagnostics.
Views localize typed failures and do not display exception text. Twitch message
rejection details remain separate server-provided feedback.

Independent operations have independent processes. Chat deletions use a map
from message ID to process; dismissing a failed deletion preserves pending ones.
Composer validation has a separate field because a draft can change while a
submitted message is in flight. Locale writes are serialized and use a generation
so an old failure cannot replace the latest process. Keep session generations
and request identity checks to reject completions from earlier sessions.

## Current models

- `OverlayViewModel`: window frame/layout, auth, chat, connection status, and
  capture exclusion process. Its constructor applies emote options before
  reading the initial chat snapshot, subscribes, and starts host/auth requests.
  Move and resize intents derive their deltas from the current layout, so multiple
  pointer events before a frame accumulate correctly.
- `ChatPanelViewModel`: separate observables for messages, composer, deletions,
  emote picker, startup hint, and session presentation. Message-only changes
  update the list without rebuilding the composer or window frame.
- `LocaleViewModel`: selected locale and save process. Persistence completion
  does not rebuild `MaterialApp`.
- `UpdateNoticeViewModel`: the small coherent notice state; the constructor
  starts its optional release check, which stays silent on failure.
- `UpdateViewModel`: installation phase/process and a separate download progress
  observable. The constructor starts checking; `check()` joins an active check
  or retries. Download notifications rebuild only the status block.

`TwitchAuth`, `TwitchChatSession`, and `OverlayHost` retain their existing
`state`/`states` contracts and use `ObservableValue` internally. Their service
initialization methods remain service APIs invoked by the model where needed.
