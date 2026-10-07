import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_panel_view_model.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

import 'twitch_emotes_test.dart' as fixtures;

const _sent = SendChatResult(sent: true, messageId: 'sent', dropReason: null);

final _auth = Observable.value(
  TwitchAuthState(
    status: TwitchAuthStatus.signedIn,
    token: fixtures.makeToken(),
  ),
);

ChatState _chat({
  String broadcasterId = 'sender',
  List<ChatItem> items = const [],
}) => ChatState(
  status: ChatConnectionStatus.connected,
  broadcasterId: broadcasterId,
  items: items,
);

ChatPanelConfig _config({
  ChatSend? send,
  Future<void> Function(String)? delete,
  int messageLifetimeMinutes = 0,
}) => ChatPanelConfig(
  interactive: true,
  messageLifetimeMinutes: messageLifetimeMinutes,
  send: send ?? (_, {String? replyTo}) async => _sent,
  loadEmotes: ({bool refresh = false}) async => [],
  deleteMessage: delete,
);

ChatPanelViewModel _model({
  Observable<ChatState>? chat,
  ChatSend? send,
  Future<void> Function(String)? delete,
}) {
  final viewModel = ChatPanelViewModel(
    auth: _auth,
    chat: chat ?? Observable.value(_chat()),
    config: _config(send: send, delete: delete),
  );
  addTearDown(viewModel.dispose);
  return viewModel;
}

ObservableValue<ChatState> _source({bool sync = true}) {
  final source = ObservableValue(current: _chat(), sync: sync);
  addTearDown(source.dispose);
  return source;
}

ChatUserMessage _message(String id) => ChatUserMessage(
  id: id,
  receivedAt: DateTime.now(),
  userId: 'viewer',
  userName: 'Viewer',
  color: null,
  badges: const [],
  fragments: const [ChatTextFragment(text: 'Hello')],
  messageType: 'text',
  bits: null,
  reply: null,
  sourceChannel: null,
);

void main() {
  test('sending closes the picker in the same editor notification', () async {
    final pending = Completer<SendChatResult>();
    final composer = _model(send: (_, {String? replyTo}) => pending.future)
        .composer;
    composer.toggleEmotes();
    final request = composer.editor.current.emotes.request;
    final events = <ChatEditorState>[];
    final subscription = composer.editor.changes.listen(events.add);
    addTearDown(subscription.cancel);
    final sending = composer.send('draft');
    expect(events, hasLength(1));
    expect(events.single.sending, isTrue);
    expect(events.single.emotes.open, isFalse);
    expect(events.single.emotes.request, same(request));
    pending.complete(_sent);
    expect(await sending, isTrue);
  });

  test('starting a reply closes the picker in one editor notification', () {
    final composer = _model().composer;
    composer.toggleEmotes();
    final events = <ChatEditorState>[];
    final subscription = composer.editor.changes.listen(events.add);
    addTearDown(subscription.cancel);
    composer.startReply(_message('reply'));
    expect(events, hasLength(1));
    expect(events.single.replyTo?.parentMessageId, 'reply');
    expect(events.single.emotes.open, isFalse);
  });

  test('the first message and hidden startup hint share one snapshot', () {
    final chat = _source();
    final viewModel = _model(chat: chat);
    final events = <ChatTimelineState>[];
    final subscription = viewModel.timeline.changes.listen(events.add);
    addTearDown(subscription.cancel);
    chat.set(_chat(items: [_message('new')]));
    expect(events, hasLength(1));
    expect(events.single.messages.items.single.id, 'new');
    expect(events.single.startupHint.visible, isFalse);
  });

  testWidgets('startup hint transitions reuse the message snapshot', (
    tester,
  ) async {
    final viewModel = _model();
    final messages = viewModel.timeline.current.messages;
    final events = <ChatTimelineState>[];
    final subscription = viewModel.timeline.changes.listen(events.add);
    addTearDown(subscription.cancel);
    await tester.pump(ChatPanelViewModel.startupHintDuration);
    expect(events.single.startupHint.fading, isTrue);
    expect(events.single.messages, same(messages));
    await tester.pump(ChatPanelViewModel.startupHintFadeDuration);
    expect(events.last.startupHint.visible, isFalse);
    expect(events.last.messages, same(messages));
  });

  test(
    'a failed send retains diagnostics and retry clears its feedback',
    () async {
      var fail = true;
      const exception = SocketException('private network diagnostics');
      final retry = Completer<SendChatResult>();
      final composer = _model(
        send: (_, {String? replyTo}) {
          if (fail) throw exception;
          return retry.future;
        },
      ).composer;

      expect(await composer.send('draft'), isFalse);
      final failed = composer.editor.current;
      expect(failed.sendError?.failure, ChatPanelFailure.network);
      expect(failed.sendError?.details, isNull);
      expect(failed.sending, isFalse);
      final process = failed.sendProcess as FailedProcess<void>;
      expect(process.cause, same(exception));
      expect(process.stackTrace, isNotNull);

      fail = false;
      final sending = composer.send('draft');
      expect(composer.editor.current.sending, isTrue);
      expect(composer.editor.current.sendError, isNull);
      retry.complete(_sent);
      expect(await sending, isTrue);
      expect(composer.editor.current.sendProcess, isA<InitialProcess<void>>());
      expect(failed.sendProcess, same(process));
    },
  );

  test(
    'editing a reply during a send keeps the operation single-flight',
    () async {
      final pending = Completer<SendChatResult>();
      var calls = 0;
      final composer = _model(
        send: (_, {String? replyTo}) {
          calls++;
          return pending.future;
        },
      ).composer;
      composer.startReply(_message('first'));
      final sending = composer.send('draft');
      composer.startReply(_message('second'));
      composer.emoteInserted(accepted: false);
      expect(composer.editor.current.sending, isTrue);
      expect(
        composer.editor.current.composerError?.failure,
        ChatPanelFailure.messageTooLong,
      );
      expect(await composer.send('duplicate'), isFalse);
      expect(calls, 1);
      pending.complete(_sent);
      expect(await sending, isTrue);
      expect(composer.editor.current.replyTo?.parentMessageId, 'second');
    },
  );

  test(
    'dismissing a deletion failure preserves another pending deletion',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final viewModel = _model(
        delete: (id) => id == 'first' ? first.future : second.future,
      );
      final deletingFirst = viewModel.deleteMessage(_message('first'));
      final deletingSecond = viewModel.deleteMessage(_message('second'));
      first.completeError(
        const TwitchChatActionException(TwitchChatActionFailure.forbidden),
      );
      await deletingFirst;
      final failed = viewModel.deletions.current.processes['first']!;
      expect(
        (failed.error as ChatPanelError).failure,
        ChatPanelFailure.deleteNotAllowed,
      );
      expect(viewModel.deletions.current.deletingIds, {'second'});
      viewModel.dismissDeleteError();
      expect(viewModel.deletions.current.error, isNull);
      expect(viewModel.deletions.current.deletingIds, {'second'});
      second.complete();
      await deletingSecond;
      expect(viewModel.deletions.current.processes, isEmpty);
      expect(
        (failed.error as ChatPanelError).failure,
        ChatPanelFailure.deleteNotAllowed,
      );
    },
  );

  test(
    'send is single-flight and a completion from a previous session is ignored',
    () async {
      final pending = Completer<SendChatResult>();
      var requests = 0;
      final chat = _source();
      final composer = _model(
        chat: chat,
        send: (_, {String? replyTo}) {
          requests++;
          return pending.future;
        },
      ).composer;
      composer.startReply(_message('reply'));
      final first = composer.send('draft');
      expect(composer.editor.current.sending, isTrue);
      expect(await composer.send('duplicate'), isFalse);
      expect(requests, 1);
      chat.set(_chat(broadcasterId: 'another'));
      final nextSession = composer.editor.current;
      expect(nextSession.sending, isFalse);
      expect(nextSession.replyTo, isNull);
      pending.complete(_sent);
      expect(await first, isFalse);
      expect(composer.editor.current, same(nextSession));
    },
  );

  test('disposing during a send does not accept its late success', () async {
    final pending = Completer<SendChatResult>();
    final viewModel = _model(send: (_, {String? replyTo}) => pending.future);
    final operation = viewModel.composer.send('draft');
    final beforeDispose = viewModel.composer.editor.current;
    viewModel.dispose();
    expect(viewModel.composer.isDisposed, isTrue);
    pending.complete(_sent);
    expect(await operation, isFalse);
    expect(viewModel.composer.editor.current, same(beforeDispose));
  });

  test('concurrent deletions keep independent immutable snapshots', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final viewModel = _model(
      delete: (id) => id == 'first' ? first.future : second.future,
    );
    final firstDeletion = viewModel.deleteMessage(_message('first'));
    final processes = viewModel.deletions.current.processes;
    expect(viewModel.deletions.current.deletingIds, {'first'});
    final secondDeletion = viewModel.deleteMessage(_message('second'));
    expect(viewModel.deletions.current.processes, isNot(same(processes)));
    expect(processes.keys, ['first']);
    expect(viewModel.deletions.current.deletingIds, {'first', 'second'});
    first.complete();
    await firstDeletion;
    expect(processes.keys, ['first']);
    expect(viewModel.deletions.current.deletingIds, {'second'});
    second.complete();
    await secondDeletion;
    expect(viewModel.deletions.current.processes, isEmpty);
    expect(processes.keys, ['first']);
    expect(() => processes.clear(), throwsUnsupportedError);
  });

  test('messages and composer notify independently with immutable message snapshots', () async {
    final pending = Completer<SendChatResult>();
    final chat = _source();
    final viewModel = _model(
      chat: chat,
      send: (_, {String? replyTo}) => pending.future,
    );
    final items = viewModel.timeline.current.messages.items;
    var messageChanges = 0;
    var composerChanges = 0;
    var sessionChanges = 0;
    viewModel.timeline.changes.listen((_) => messageChanges++);
    viewModel.composer.editor.changes.listen((_) => composerChanges++);
    viewModel.session.changes.listen((_) => sessionChanges++);
    final sending = viewModel.composer.send('draft');
    expect(composerChanges, 1);
    expect(messageChanges, 0);
    chat.set(_chat(items: [_message('new')]));
    expect(messageChanges, 1);
    expect(composerChanges, 1);
    expect(sessionChanges, 0);
    expect(viewModel.timeline.current.messages.items.single.id, 'new');
    expect(items, isEmpty);
    expect(
      () => viewModel.timeline.current.messages.items.clear(),
      throwsUnsupportedError,
    );
    pending.complete(_sent);
    expect(await sending, isTrue);
    expect(composerChanges, 2);
    expect(messageChanges, 1);
  });

  test(
    'a stale deferred notification cannot roll the timeline or reply back',
    () async {
      final chat = _source(sync: false);
      final viewModel = _model(chat: chat);
      final third = _message('third');
      chat.set(_chat(items: [_message('first')]));
      chat.set(_chat(items: [_message('first'), _message('second'), third]));
      // A display setting change re-reads the newest snapshot before the
      // queued notifications for both changes are delivered.
      viewModel.update(
        auth: _auth,
        chat: chat,
        config: _config(messageLifetimeMinutes: 5),
      );
      viewModel.composer.startReply(third);
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.timeline.current.messages.items, hasLength(3));
      expect(
        viewModel.composer.editor.current.replyTo?.parentMessageId,
        'third',
      );
      expect(viewModel.composer.editor.current.composerError, isNull);
    },
  );

  test('new callbacks apply without replacing the sources', () async {
    final sent = <String>[];
    final chat = _source();
    final viewModel = _model(chat: chat);
    viewModel.update(
      auth: _auth,
      chat: chat,
      config: _config(
        send: (message, {String? replyTo}) async {
          sent.add(message);
          return _sent;
        },
      ),
    );
    expect(await viewModel.composer.send('hello'), isTrue);
    expect(sent, ['hello']);
  });
}
