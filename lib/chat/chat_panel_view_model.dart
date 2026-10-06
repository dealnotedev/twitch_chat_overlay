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

final class ChatComposerState {
  const ChatComposerState({
    this.sendProcess = const SimpleFailableProcess.initial(),
    this.composerError,
    this.replyTo,
  });
  final SimpleFailableProcess sendProcess;
  final ChatPanelError? composerError;
  final ChatReply? replyTo;

  bool get sending => sendProcess.isActive;
  ChatPanelError? get sendError =>
      composerError ??
      switch (sendProcess.error) {
        ChatPanelError error => error,
        _ => null,
      };

  ChatComposerState copyWith({
    SimpleFailableProcess? sendProcess,
    Nullable<ChatPanelError>? composerError,
    Nullable<ChatReply>? replyTo,
  }) => ChatComposerState(
    sendProcess: sendProcess ?? this.sendProcess,
    composerError: composerError.getOr(this.composerError),
    replyTo: replyTo.getOr(this.replyTo),
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
    _messages = register(ObservableValue(current: initialMessages));
    _composer = register(ObservableValue(current: const ChatComposerState()));
    _deletions = register(ObservableValue(current: ChatDeletionsState()));
    _emotes = register(ObservableValue(current: const ChatEmotePickerState()));
    _startupHint = register(
      ObservableValue(
        current: ChatStartupHintState(visible: initialMessages.items.isEmpty),
      ),
    );
    _session = register(ObservableValue(current: _presentation(_input)));

    _recent.addListener(_onRecentChanged);
    _watchSources(authSource, chatSource);
    if (initialMessages.items.isEmpty) {
      _startupHintTimer = Timer(startupHintDuration, () {
        if (isDisposed) return;
        _startupHint.set(const ChatStartupHintState(fading: true));
        if (isDisposed) return;
        _startupHintTimer = Timer(startupHintFadeDuration, () {
          if (!isDisposed) {
            _startupHint.set(const ChatStartupHintState(visible: false));
          }
        });
      });
    }
  }

  late final ObservableValue<ChatMessagesState> _messages;
  late final ObservableValue<ChatComposerState> _composer;
  late final ObservableValue<ChatDeletionsState> _deletions;
  late final ObservableValue<ChatEmotePickerState> _emotes;
  late final ObservableValue<ChatStartupHintState> _startupHint;
  late final ObservableValue<ChatPanelSessionState> _session;

  StreamWithInitial<ChatMessagesState> get messages => _messages;
  StreamWithInitial<ChatComposerState> get composer => _composer;
  StreamWithInitial<ChatDeletionsState> get deletions => _deletions;
  StreamWithInitial<ChatEmotePickerState> get emotes => _emotes;
  StreamWithInitial<ChatStartupHintState> get startupHint => _startupHint;
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
    if (input.auth.status != TwitchAuthStatus.signedIn || sessionChanged) {
      if (_emotes.current.open || _emotes.current.request != null) {
        _emotes.set(const ChatEmotePickerState());
      }
    } else if (previous.chat.emoteOptions != input.chat.emoteOptions) {
      _emotes.set(
        ChatEmotePickerState(
          open: _emotes.current.open,
          request: _emotes.current.open ? _requestEmotes() : null,
        ),
      );
    }
    if (sessionChanged) {
      _actionGeneration++;
      _recent.clear();
      _composer.set(const ChatComposerState());
      _deletions.set(ChatDeletionsState());
    }
    _recent.update(input.chat.items, input.messageLifetimeMinutes);
    if (_recent.visibleItems.isNotEmpty ||
        (previous.chat.status == ChatConnectionStatus.connected &&
            input.chat.status != ChatConnectionStatus.connected)) {
      _hideStartupHint();
    }
    if (!input.interactive) closeEmotes();
    final previousIds = previous.chat.items.map((item) => item.id).toSet();
    final currentIds = input.chat.items.map((item) => item.id).toSet();
    if (_composer.current.replyTo case final reply?) {
      if (previousIds.contains(reply.parentMessageId) &&
          !currentIds.contains(reply.parentMessageId)) {
        _replyUnavailable();
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
    _publishRecent();
    if (isDisposed) return;
    final presentation = _presentation(input);
    if (_session.current != presentation) _session.set(presentation);
  }

  void _hideStartupHint() {
    _startupHintTimer?.cancel();
    if (_startupHint.current.visible) {
      _startupHint.set(const ChatStartupHintState(visible: false));
    }
  }

  void _replyUnavailable() {
    _composer.set(
      _composer.current.copyWith(
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

  void _publishRecent() {
    if (isDisposed) return;
    final next = _messagesState();
    if (listEquals(_messages.current.items, next.items) &&
        setEquals(_messages.current.fadingIds, next.fadingIds) &&
        mapEquals(_messages.current.userColors, next.userColors)) {
      return;
    }
    _messages.set(next);
  }

  void _onRecentChanged() {
    if (isDisposed) return;
    if (_composer.current.replyTo case final reply?) {
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
    final open = !_emotes.current.open;
    _emotes.set(
      ChatEmotePickerState(
        open: open,
        request: open ? _requestEmotes() : _emotes.current.request,
      ),
    );
  }

  void reloadEmotes() {
    if (!isDisposed) {
      _emotes.set(
        ChatEmotePickerState(
          open: _emotes.current.open,
          request: _requestEmotes(refresh: true),
        ),
      );
    }
  }

  void closeEmotes() {
    if (!isDisposed && _emotes.current.open) {
      _emotes.set(ChatEmotePickerState(request: _emotes.current.request));
    }
  }

  void emoteInserted({required bool accepted}) {
    if (isDisposed) return;
    _composer.set(
      _composer.current.copyWith(
        sendProcess: _composer.current.sending
            ? _composer.current.sendProcess
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
    _composer.set(
      _composer.current.copyWith(
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
        sendProcess: _composer.current.sending
            ? _composer.current.sendProcess
            : const SimpleFailableProcess.initial(),
      ),
    );
    closeEmotes();
  }

  void cancelReply() {
    if (!isDisposed) {
      _composer.set(_composer.current.copyWith(replyTo: const Nullable(null)));
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
    if (isDisposed || text.isEmpty || _composer.current.sending) return false;
    final reply = _composer.current.replyTo;
    final generation = _actionGeneration;
    _composer.set(
      _composer.current.copyWith(
        sendProcess: const SimpleFailableProcess.loading(),
        composerError: const Nullable(null),
      ),
    );
    closeEmotes();
    try {
      final result = await _input.send(text, replyTo: reply?.parentMessageId);
      if (!_isCurrent(generation)) return false;
      if (result.sent) {
        _composer.set(
          _composer.current.copyWith(
            sendProcess: const SimpleFailableProcess.initial(),
            replyTo: identical(_composer.current.replyTo, reply)
                ? const Nullable(null)
                : null,
          ),
        );
        return true;
      }
      _composer.set(
        _composer.current.copyWith(
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
      _composer.set(
        _composer.current.copyWith(
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
