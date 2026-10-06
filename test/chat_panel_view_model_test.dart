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

ChatPanelInput _input({
  String broadcasterId = 'sender',
  List<ChatItem> items = const [],
  Future<SendChatResult> Function(String, {String? replyTo})? send,
  Future<void> Function(String)? delete,
}) => ChatPanelInput(
  auth: TwitchAuthState(
    status: TwitchAuthStatus.signedIn,
    token: fixtures.makeToken(),
  ),
  chat: ChatState(
    status: ChatConnectionStatus.connected,
    broadcasterId: broadcasterId,
    items: items,
  ),
  interactive: true,
  messageLifetimeMinutes: 0,
  send: send ?? (_, {String? replyTo}) async => _sent,
  loadEmotes: ({bool refresh = false}) async => [],
  deleteMessage: delete,
);

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
    final viewModel = ChatPanelViewModel(
      _input(send: (_, {String? replyTo}) => pending.future),
    );
    addTearDown(viewModel.dispose);
    viewModel.toggleEmotes();
    final request = viewModel.editor.current.emotes.request;
    final events = <ChatEditorState>[];
    final subscription = viewModel.editor.changes.listen(events.add);
    addTearDown(subscription.cancel);
    final sending = viewModel.send('draft');
    expect(events, hasLength(1));
    expect(events.single.sending, isTrue);
    expect(events.single.emotes.open, isFalse);
    expect(events.single.emotes.request, same(request));
    pending.complete(_sent);
    expect(await sending, isTrue);
  });

  test('starting a reply closes the picker in one editor notification', () {
    final viewModel = ChatPanelViewModel(_input());
    addTearDown(viewModel.dispose);
    viewModel.toggleEmotes();
    final events = <ChatEditorState>[];
    final subscription = viewModel.editor.changes.listen(events.add);
    addTearDown(subscription.cancel);
    viewModel.startReply(_message('reply'));
    expect(events, hasLength(1));
    expect(events.single.replyTo?.parentMessageId, 'reply');
    expect(events.single.emotes.open, isFalse);
  });

  test('the first message and hidden startup hint share one snapshot', () {
    final input = _input();
    final viewModel = ChatPanelViewModel(input);
    addTearDown(viewModel.dispose);
    final events = <ChatTimelineState>[];
    final subscription = viewModel.timeline.changes.listen(events.add);
    addTearDown(subscription.cancel);
    viewModel.update(
      input.withSession(
        chat: ChatState(
          status: input.chat.status,
          broadcasterId: input.chat.broadcasterId,
          items: [_message('new')],
        ),
      ),
    );
    expect(events, hasLength(1));
    expect(events.single.messages.items.single.id, 'new');
    expect(events.single.startupHint.visible, isFalse);
  });

  testWidgets('startup hint transitions reuse the message snapshot', (
    tester,
  ) async {
    final viewModel = ChatPanelViewModel(_input());
    addTearDown(viewModel.dispose);
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
      final viewModel = ChatPanelViewModel(
        _input(
          send: (_, {String? replyTo}) {
            if (fail) throw exception;
            return retry.future;
          },
        ),
      );
      addTearDown(viewModel.dispose);

      expect(await viewModel.send('draft'), isFalse);
      final failed = viewModel.editor.current;
      expect(failed.sendError?.failure, ChatPanelFailure.network);
      expect(failed.sendError?.details, isNull);
      expect(failed.sending, isFalse);
      final process = failed.sendProcess as FailedProcess<void>;
      expect(process.cause, same(exception));
      expect(process.stackTrace, isNotNull);

      fail = false;
      final sending = viewModel.send('draft');
      expect(viewModel.editor.current.sending, isTrue);
      expect(viewModel.editor.current.sendError, isNull);
      retry.complete(_sent);
      expect(await sending, isTrue);
      expect(viewModel.editor.current.sendProcess, isA<InitialProcess<void>>());
      expect(failed.sendProcess, same(process));
    },
  );

  test(
    'editing a reply during a send keeps the operation single-flight',
    () async {
      final pending = Completer<SendChatResult>();
      var calls = 0;
      final viewModel = ChatPanelViewModel(
        _input(
          send: (_, {String? replyTo}) {
            calls++;
            return pending.future;
          },
        ),
      );
      addTearDown(viewModel.dispose);
      viewModel.startReply(_message('first'));
      final sending = viewModel.send('draft');
      viewModel.startReply(_message('second'));
      viewModel.emoteInserted(accepted: false);
      expect(viewModel.editor.current.sending, isTrue);
      expect(
        viewModel.editor.current.composerError?.failure,
        ChatPanelFailure.messageTooLong,
      );
      expect(await viewModel.send('duplicate'), isFalse);
      expect(calls, 1);
      pending.complete(_sent);
      expect(await sending, isTrue);
      expect(viewModel.editor.current.replyTo?.parentMessageId, 'second');
    },
  );

  test(
    'dismissing a deletion failure preserves another pending deletion',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final viewModel = ChatPanelViewModel(
        _input(delete: (id) => id == 'first' ? first.future : second.future),
      );
      addTearDown(viewModel.dispose);
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
      final viewModel = ChatPanelViewModel(
        _input(
          send: (_, {String? replyTo}) {
            requests++;
            return pending.future;
          },
        ),
      );
      addTearDown(viewModel.dispose);
      viewModel.startReply(_message('reply'));
      final first = viewModel.send('draft');
      expect(viewModel.editor.current.sending, isTrue);
      expect(await viewModel.send('duplicate'), isFalse);
      expect(requests, 1);
      viewModel.update(_input(broadcasterId: 'another'));
      final nextSession = viewModel.editor.current;
      expect(nextSession.sending, isFalse);
      expect(nextSession.replyTo, isNull);
      pending.complete(_sent);
      expect(await first, isFalse);
      expect(viewModel.editor.current, same(nextSession));
    },
  );

  test('disposing during a send does not accept its late success', () async {
    final pending = Completer<SendChatResult>();
    final viewModel = ChatPanelViewModel(
      _input(send: (_, {String? replyTo}) => pending.future),
    );
    final operation = viewModel.send('draft');
    final beforeDispose = viewModel.editor.current;
    viewModel.dispose();
    pending.complete(_sent);
    expect(await operation, isFalse);
    expect(viewModel.editor.current, same(beforeDispose));
  });

  test('concurrent deletions keep independent immutable snapshots', () async {
    final first = Completer<void>();
    final second = Completer<void>();
    final viewModel = ChatPanelViewModel(
      _input(delete: (id) => id == 'first' ? first.future : second.future),
    );
    addTearDown(viewModel.dispose);
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
    final input = _input(send: (_, {String? replyTo}) => pending.future);
    final viewModel = ChatPanelViewModel(input);
    addTearDown(viewModel.dispose);
    final items = viewModel.timeline.current.messages.items;
    var messageChanges = 0;
    var composerChanges = 0;
    var sessionChanges = 0;
    viewModel.timeline.changes.listen((_) => messageChanges++);
    viewModel.editor.changes.listen((_) => composerChanges++);
    viewModel.session.changes.listen((_) => sessionChanges++);
    final sending = viewModel.send('draft');
    expect(composerChanges, 1);
    expect(messageChanges, 0);
    viewModel.update(
      input.withSession(
        chat: ChatState(
          status: input.chat.status,
          broadcasterId: input.chat.broadcasterId,
          items: [_message('new')],
        ),
      ),
    );
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
}
