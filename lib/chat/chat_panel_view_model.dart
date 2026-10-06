import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';
import 'package:twitch_chat_overlay/chat/chat_message_entrance.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

final class ChatPanelInput {
  const ChatPanelInput({
    required this.auth,
    required this.chat,
    required this.interactive,
    required this.messageLifetimeMinutes,
    required this.send,
    required this.loadEmotes,
    this.deleteMessage,
  });

  final TwitchAuthState auth;
  final ChatState chat;
  final bool interactive;
  final int messageLifetimeMinutes;
  final Future<SendChatResult> Function(String message, {String? replyTo}) send;
  final Future<List<ChatEmote>> Function({bool refresh}) loadEmotes;
  final Future<void> Function(String messageId)? deleteMessage;

  ChatPanelInput withSession({TwitchAuthState? auth, ChatState? chat}) =>
      ChatPanelInput(
        auth: auth ?? this.auth,
        chat: chat ?? this.chat,
        interactive: interactive,
        messageLifetimeMinutes: messageLifetimeMinutes,
        send: send,
        loadEmotes: loadEmotes,
        deleteMessage: deleteMessage,
      );
}

enum ChatPanelFailure {
  messageTooLong,
  replyUnavailable,
  messageRejected,
  deleteNotAllowed,
  messageUnavailable,
  deleteFailed,
  sendNotAllowed,
  network,
  rateLimited,
  sessionChanged,
  sendFailed,
}

final class ChatPanelError {
  const ChatPanelError(this.failure, [this.details]);
  final ChatPanelFailure failure;
  final String? details;
}

final class ChatMessagesState {
  ChatMessagesState({
    required Iterable<ChatItem> items,
    required Iterable<String> fadingIds,
    required Map<String, String?> userColors,
  }) : items = List.unmodifiable(items),
       fadingIds = Set.unmodifiable(fadingIds),
       userColors = Map.unmodifiable(userColors);
  final List<ChatItem> items;
  final Set<String> fadingIds;
  final Map<String, String?> userColors;
}

final class ChatEditorState {
  const ChatEditorState({
    this.sendProcess = const SimpleFailableProcess.initial(),
    this.composerError,
    this.replyTo,
    this.emotes = const ChatEmotePickerState(),
  });
  final SimpleFailableProcess sendProcess;
  final ChatPanelError? composerError;
  final ChatReply? replyTo;
  final ChatEmotePickerState emotes;

  bool get sending => sendProcess.isActive;
  ChatPanelError? get sendError =>
      composerError ??
      switch (sendProcess.error) {
        ChatPanelError error => error,
        _ => null,
      };

  ChatEditorState copyWith({
    SimpleFailableProcess? sendProcess,
    Nullable<ChatPanelError>? composerError,
    Nullable<ChatReply>? replyTo,
    ChatEmotePickerState? emotes,
  }) => ChatEditorState(
    sendProcess: sendProcess ?? this.sendProcess,
    composerError: composerError.getOr(this.composerError),
    replyTo: replyTo.getOr(this.replyTo),
    emotes: emotes ?? this.emotes,
  );
}

final class ChatDeletionsState {
  ChatDeletionsState({Map<String, SimpleFailableProcess> processes = const {}})
    : processes = Map.unmodifiable(processes);

  final Map<String, SimpleFailableProcess> processes;

  bool isDeleting(String id) => processes[id]?.isActive ?? false;
  Set<String> get deletingIds => {
    for (final entry in processes.entries)
      if (entry.value.isActive) entry.key,
  };
  ChatPanelError? get error {
    ChatPanelError? latest;
    for (final process in processes.values) {
      if (process.error case final ChatPanelError error) latest = error;
    }
    return latest;
  }
}

final class ChatEmotePickerState {
  const ChatEmotePickerState({this.open = false, this.request});
  final bool open;
  final Future<List<ChatEmote>>? request;
}

final class ChatStartupHintState {
  const ChatStartupHintState({this.visible = true, this.fading = false});
  final bool visible;
  final bool fading;
}

final class ChatTimelineState {
  const ChatTimelineState({
    required this.messages,
    this.startupHint = const ChatStartupHintState(),
  });

  final ChatMessagesState messages;
  final ChatStartupHintState startupHint;

  ChatTimelineState copyWith({
    ChatMessagesState? messages,
    ChatStartupHintState? startupHint,
  }) => ChatTimelineState(
    messages: messages ?? this.messages,
    startupHint: startupHint ?? this.startupHint,
  );
}

typedef ChatPanelSessionState = ({
  TwitchAuthState auth,
  ChatConnectionStatus status,
  String? broadcasterId,
  int? viewerCount,
  bool streamOffline,
  TwitchBadges badges,
  EmoteCatalog emoteCatalog,
  bool rewardSubscriptionFailed,
});

ChatPanelSessionState _presentation(ChatPanelInput input) => (
  auth: input.auth,
  status: input.chat.status,
  broadcasterId: input.chat.broadcasterId,
  viewerCount: input.chat.viewerCount,
  streamOffline: input.chat.streamOffline,
  badges: input.chat.badges,
  emoteCatalog: input.chat.emoteCatalog,
  rewardSubscriptionFailed: input.chat.rewardSubscriptionFailed,
);

final class ChatPanelViewModel extends BaseViewModel {
  ChatPanelViewModel(
    this._input, {
    StreamWithInitial<TwitchAuthState>? authSource,
    StreamWithInitial<ChatState>? chatSource,
  }) {
    _recent.update(_input.chat.items, _input.messageLifetimeMinutes);
    final initialMessages = _messagesState();
    _timeline = register(
      ObservableValue(
        current: ChatTimelineState(
          messages: initialMessages,
          startupHint: ChatStartupHintState(
            visible: initialMessages.items.isEmpty,
          ),
        ),
      ),
    );
    _editor = register(ObservableValue(current: const ChatEditorState()));
    _deletions = register(ObservableValue(current: ChatDeletionsState()));
    _session = register(ObservableValue(current: _presentation(_input)));

    _recent.addListener(_onRecentChanged);
    _watchSources(authSource, chatSource);
    if (initialMessages.items.isEmpty) {
      _startupHintTimer = Timer(startupHintDuration, () {
        if (isDisposed) return;
        _timeline.set(
          _timeline.current.copyWith(
            startupHint: const ChatStartupHintState(fading: true),
          ),
        );
        if (isDisposed) return;
        _startupHintTimer = Timer(startupHintFadeDuration, () {
          if (!isDisposed) {
            _timeline.set(
              _timeline.current.copyWith(
                startupHint: const ChatStartupHintState(visible: false),
              ),
            );
          }
        });
      });
    }
  }

  late final ObservableValue<ChatTimelineState> _timeline;
  late final ObservableValue<ChatEditorState> _editor;
  late final ObservableValue<ChatDeletionsState> _deletions;
  late final ObservableValue<ChatPanelSessionState> _session;

  StreamWithInitial<ChatTimelineState> get timeline => _timeline;
  StreamWithInitial<ChatEditorState> get editor => _editor;
  StreamWithInitial<ChatDeletionsState> get deletions => _deletions;
  StreamWithInitial<ChatPanelSessionState> get session => _session;

  static const startupHintDuration = Duration(seconds: 20);
  static const startupHintFadeDuration = Duration(milliseconds: 500);
  ChatPanelInput _input;
  final ChatMessageRetention _recent = ChatMessageRetention();
  final Stopwatch _arrivalClock = Stopwatch()..start();
  final Map<String, Duration> _messageArrivals = {};
  Timer? _startupHintTimer;
  int _actionGeneration = 0;
  StreamWithInitial<TwitchAuthState>? _authSource;
  StreamWithInitial<ChatState>? _chatSource;
  StreamSubscription<TwitchAuthState>? _authSubscription;
  StreamSubscription<ChatState>? _chatSubscription;

  void _watchSources(
    StreamWithInitial<TwitchAuthState>? authSource,
    StreamWithInitial<ChatState>? chatSource,
  ) {
    if (!identical(_authSource, authSource)) {
      stopObserving(_authSubscription);
      _authSource = authSource;
      _authSubscription = authSource == null
          ? null
          : observe(authSource.changes, (auth) {
              if (identical(_authSource, authSource)) {
                update(
                  _input.withSession(auth: auth),
                  authSource: _authSource,
                  chatSource: _chatSource,
                );
              }
            });
    }
    if (!identical(_chatSource, chatSource)) {
      stopObserving(_chatSubscription);
      _chatSource = chatSource;
      _chatSubscription = chatSource == null
          ? null
          : observe(chatSource.changes, (chat) {
              if (identical(_chatSource, chatSource)) {
                update(
                  _input.withSession(chat: chat),
                  authSource: _authSource,
                  chatSource: _chatSource,
                );
              }
            });
    }
  }

  void update(
    ChatPanelInput input, {
    StreamWithInitial<TwitchAuthState>? authSource,
    StreamWithInitial<ChatState>? chatSource,
  }) {
    if (isDisposed) return;
    _watchSources(authSource, chatSource);
    final previous = _input;
    _input = input;
    final sessionChanged =
        previous.auth.token?.userId != input.auth.token?.userId ||
        previous.chat.broadcasterId != input.chat.broadcasterId ||
        input.auth.status == TwitchAuthStatus.signedOut;
    var editor = _editor.current;
    if (sessionChanged) {
      _actionGeneration++;
      _recent.clear();
      editor = const ChatEditorState();
    }
    if (input.auth.status != TwitchAuthStatus.signedIn || sessionChanged) {
      if (editor.emotes.open || editor.emotes.request != null) {
        editor = editor.copyWith(emotes: const ChatEmotePickerState());
      }
    } else if (previous.chat.emoteOptions != input.chat.emoteOptions) {
      editor = editor.copyWith(
        emotes: ChatEmotePickerState(
          open: editor.emotes.open,
          request: editor.emotes.open ? _requestEmotes() : null,
        ),
      );
    }
    if (!input.interactive && editor.emotes.open) {
      editor = editor.copyWith(
        emotes: ChatEmotePickerState(request: editor.emotes.request),
      );
    }
    if (sessionChanged) {
      _deletions.set(ChatDeletionsState());
    }
    if (isDisposed) return;
    _recent.update(input.chat.items, input.messageLifetimeMinutes);
    final hideStartupHint =
        _recent.visibleItems.isNotEmpty ||
        (previous.chat.status == ChatConnectionStatus.connected &&
            input.chat.status != ChatConnectionStatus.connected);
    final previousIds = previous.chat.items.map((item) => item.id).toSet();
    final currentIds = input.chat.items.map((item) => item.id).toSet();
    if (editor.replyTo case final reply?) {
      if (previousIds.contains(reply.parentMessageId) &&
          !currentIds.contains(reply.parentMessageId)) {
        editor = editor.copyWith(
          replyTo: const Nullable(null),
          composerError: const Nullable(
            ChatPanelError(ChatPanelFailure.replyUnavailable),
          ),
        );
      }
    }
    final now = _arrivalClock.elapsed;
    _messageArrivals.removeWhere(
      (id, arrivedAt) =>
          !currentIds.contains(id) ||
          now - arrivedAt >= ChatMessageEntrance.duration,
    );
    for (final item in input.chat.items) {
      if (!item.isHistorical && !previousIds.contains(item.id)) {
        _messageArrivals[item.id] = now;
      }
    }
    if (!identical(editor, _editor.current)) _editor.set(editor);
    if (isDisposed) return;
    _publishRecent(hideStartupHint: hideStartupHint);
    if (isDisposed) return;
    final presentation = _presentation(input);
    if (_session.current != presentation) _session.set(presentation);
  }

  void _replyUnavailable() {
    _editor.set(
      _editor.current.copyWith(
        replyTo: const Nullable(null),
        composerError: const Nullable(
          ChatPanelError(ChatPanelFailure.replyUnavailable),
        ),
      ),
    );
  }

  Duration? entranceElapsed(String id) {
    final arrivedAt = _messageArrivals[id];
    return arrivedAt == null ? null : _arrivalClock.elapsed - arrivedAt;
  }

  ChatMessagesState _messagesState() => ChatMessagesState(
    items: _recent.visibleItems,
    fadingIds: _recent.visibleItems
        .where((item) => _recent.isFading(item.id))
        .map((item) => item.id),
    userColors: {
      for (final message in _input.chat.items.whereType<ChatUserMessage>())
        message.userId: message.color,
    },
  );

  void _publishRecent({bool hideStartupHint = false}) {
    if (isDisposed) return;
    if (hideStartupHint) _startupHintTimer?.cancel();
    final current = _timeline.current;
    final next = _messagesState();
    final messagesChanged =
        !listEquals(current.messages.items, next.items) ||
        !setEquals(current.messages.fadingIds, next.fadingIds) ||
        !mapEquals(current.messages.userColors, next.userColors);
    final hintChanged = hideStartupHint && current.startupHint.visible;
    if (!messagesChanged && !hintChanged) return;
    _timeline.set(
      current.copyWith(
        messages: messagesChanged ? next : null,
        startupHint: hintChanged
            ? const ChatStartupHintState(visible: false)
            : null,
      ),
    );
  }

  void _onRecentChanged() {
    if (isDisposed) return;
    if (_editor.current.replyTo case final reply?) {
      if (!_recent.visibleItems.any(
        (item) => item.id == reply.parentMessageId,
      )) {
        _replyUnavailable();
      }
    }
    _publishRecent();
  }

  Future<List<ChatEmote>> _requestEmotes({bool refresh = false}) {
    final request = Future<List<ChatEmote>>.sync(
      () => _input.loadEmotes(refresh: refresh),
    );
    request.ignore();
    return request;
  }

  void toggleEmotes() {
    if (isDisposed) return;
    final open = !_editor.current.emotes.open;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(
          open: open,
          request: open ? _requestEmotes() : _editor.current.emotes.request,
        ),
      ),
    );
  }

  void reloadEmotes() {
    if (!isDisposed) {
      _editor.set(
        _editor.current.copyWith(
          emotes: ChatEmotePickerState(
            open: _editor.current.emotes.open,
            request: _requestEmotes(refresh: true),
          ),
        ),
      );
    }
  }

  void closeEmotes() {
    if (!isDisposed && _editor.current.emotes.open) {
      _editor.set(
        _editor.current.copyWith(
          emotes: ChatEmotePickerState(request: _editor.current.emotes.request),
        ),
      );
    }
  }

  void emoteInserted({required bool accepted}) {
    if (isDisposed) return;
    _editor.set(
      _editor.current.copyWith(
        sendProcess: _editor.current.sending
            ? _editor.current.sendProcess
            : const SimpleFailableProcess.initial(),
        composerError: Nullable(
          accepted
              ? null
              : const ChatPanelError(ChatPanelFailure.messageTooLong),
        ),
      ),
    );
  }

  bool canDelete(ChatUserMessage message) {
    final broadcasterId = _input.chat.broadcasterId;
    return !isDisposed &&
        _input.auth.status == TwitchAuthStatus.signedIn &&
        broadcasterId != null &&
        _input.auth.token?.userId == broadcasterId &&
        _input.deleteMessage != null &&
        canDeleteTwitchMessage(message, broadcasterId);
  }

  void startReply(ChatUserMessage message) {
    if (isDisposed) return;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(request: _editor.current.emotes.request),
        replyTo: Nullable(
          ChatReply(
            parentMessageId: message.id,
            parentUserName: message.userName,
            parentMessageBody: message.fragments
                .map((part) => part.text)
                .join(),
          ),
        ),
        composerError: const Nullable(null),
        sendProcess: _editor.current.sending
            ? _editor.current.sendProcess
            : const SimpleFailableProcess.initial(),
      ),
    );
  }

  void cancelReply() {
    if (!isDisposed) {
      _editor.set(_editor.current.copyWith(replyTo: const Nullable(null)));
    }
  }

  void dismissDeleteError() {
    if (!isDisposed && _deletions.current.error != null) {
      _deletions.set(
        ChatDeletionsState(
          processes: {
            for (final entry in _deletions.current.processes.entries)
              if (!entry.value.isFailed) entry.key: entry.value,
          },
        ),
      );
    }
  }

  void _setDeletion(String id, SimpleFailableProcess process) {
    _deletions.set(
      ChatDeletionsState(
        processes: {
          for (final entry in _deletions.current.processes.entries)
            if (entry.key != id) entry.key: entry.value,
          if (process is! InitialProcess<void>) id: process,
        },
      ),
    );
  }

  Future<void> deleteMessage(ChatUserMessage message) async {
    if (!canDelete(message) || _deletions.current.isDeleting(message.id)) {
      return;
    }
    final generation = _actionGeneration;
    _deletions.set(
      ChatDeletionsState(
        processes: {
          for (final entry in _deletions.current.processes.entries)
            if (!entry.value.isFailed) entry.key: entry.value,
          message.id: const SimpleFailableProcess.loading(),
        },
      ),
    );
    try {
      await _input.deleteMessage!(message.id);
      if (_isCurrent(generation)) {
        _setDeletion(message.id, const SimpleFailableProcess.initial());
      }
    } catch (error, stack) {
      if (!_isCurrent(generation)) return;
      final failure = error is TwitchChatActionException ? error.failure : null;
      _setDeletion(
        message.id,
        SimpleFailableProcess.failed(
          ChatPanelError(switch (failure) {
            TwitchChatActionFailure.forbidden =>
              ChatPanelFailure.deleteNotAllowed,
            TwitchChatActionFailure.messageUnavailable =>
              ChatPanelFailure.messageUnavailable,
            TwitchChatActionFailure.sessionChanged =>
              ChatPanelFailure.sessionChanged,
            _ => ChatPanelFailure.deleteFailed,
          }),
          cause: error,
          stackTrace: stack,
        ),
      );
    }
  }

  Future<bool> send(String draft) async {
    final text = draft.trim();
    if (isDisposed || text.isEmpty || _editor.current.sending) return false;
    final reply = _editor.current.replyTo;
    final generation = _actionGeneration;
    _editor.set(
      _editor.current.copyWith(
        emotes: ChatEmotePickerState(request: _editor.current.emotes.request),
        sendProcess: const SimpleFailableProcess.loading(),
        composerError: const Nullable(null),
      ),
    );
    if (!_isCurrent(generation)) return false;
    try {
      final result = await _input.send(text, replyTo: reply?.parentMessageId);
      if (!_isCurrent(generation)) return false;
      if (result.sent) {
        _editor.set(
          _editor.current.copyWith(
            sendProcess: const SimpleFailableProcess.initial(),
            replyTo: identical(_editor.current.replyTo, reply)
                ? const Nullable(null)
                : null,
          ),
        );
        return true;
      }
      _editor.set(
        _editor.current.copyWith(
          sendProcess: SimpleFailableProcess.failed(
            ChatPanelError(ChatPanelFailure.messageRejected, result.dropReason),
          ),
        ),
      );
    } catch (error, stack) {
      if (!_isCurrent(generation)) return false;
      final failure = switch (error) {
        TwitchChatActionException(
          failure: TwitchChatActionFailure.messageUnavailable,
        ) =>
          ChatPanelFailure.replyUnavailable,
        TwitchChatActionException(failure: TwitchChatActionFailure.forbidden) =>
          ChatPanelFailure.sendNotAllowed,
        TwitchChatActionException(
          failure: TwitchChatActionFailure.sessionChanged,
        ) =>
          ChatPanelFailure.sessionChanged,
        DioException(response: final response)
            when response?.statusCode == 403 =>
          ChatPanelFailure.sendNotAllowed,
        DioException(response: final response)
            when response?.statusCode == 429 =>
          ChatPanelFailure.rateLimited,
        DioException(response: null) ||
        IOException() ||
        TimeoutException() => ChatPanelFailure.network,
        _ => ChatPanelFailure.sendFailed,
      };
      _editor.set(
        _editor.current.copyWith(
          sendProcess: SimpleFailableProcess.failed(
            ChatPanelError(failure),
            cause: error,
            stackTrace: stack,
          ),
        ),
      );
    }
    return false;
  }

  bool _isCurrent(int generation) =>
      !isDisposed && generation == _actionGeneration;

  @override
  void dispose() {
    if (isDisposed) return;
    super.dispose();
    _startupHintTimer?.cancel();
    _recent.dispose();
    _arrivalClock.stop();
  }
}
