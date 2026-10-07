import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_composer_view_model.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_entrance.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';
import 'package:twitch_chat_overlay/chat/chat_panel_error.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';

export 'package:twitch_chat_overlay/chat/chat_composer_view_model.dart';
export 'package:twitch_chat_overlay/chat/chat_panel_error.dart';

/// Widget configuration; session data arrives only through the sources.
final class ChatPanelConfig {
  const ChatPanelConfig({
    required this.interactive,
    required this.messageLifetimeMinutes,
    required this.send,
    required this.loadEmotes,
    this.deleteMessage,
  });

  final bool interactive;
  final int messageLifetimeMinutes;
  final ChatSend send;
  final ChatLoadEmotes loadEmotes;
  final Future<void> Function(String messageId)? deleteMessage;
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

ChatPanelSessionState _presentation(TwitchAuthState auth, ChatState chat) => (
  auth: auth,
  status: chat.status,
  broadcasterId: chat.broadcasterId,
  viewerCount: chat.viewerCount,
  streamOffline: chat.streamOffline,
  badges: chat.badges,
  emoteCatalog: chat.emoteCatalog,
  rewardSubscriptionFailed: chat.rewardSubscriptionFailed,
);

/// Timeline, deletions, and session presentation; owns the [composer].
///
/// Session data is always read from the sources' `current`, so a late or
/// repeated notification only re-synchronizes with the latest snapshot.
final class ChatPanelViewModel extends BaseViewModel {
  ChatPanelViewModel({
    required Observable<TwitchAuthState> auth,
    required Observable<ChatState> chat,
    required ChatPanelConfig config,
  }) : _auth = auth,
       _chat = chat,
       _config = config,
       _authSnapshot = auth.current,
       _chatSnapshot = chat.current,
       composer = ChatComposerViewModel(
         send: config.send,
         loadEmotes: config.loadEmotes,
       ) {
    _recent.update(_chatSnapshot.items, config.messageLifetimeMinutes);
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
    _deletions = register(ObservableValue(current: ChatDeletionsState()));
    _session = register(
      ObservableValue(current: _presentation(_authSnapshot, _chatSnapshot)),
    );

    _recent.addListener(_onRecentChanged);
    _listen();
    if (initialMessages.items.isEmpty) _scheduleStartupHintFade();
  }

  final ChatComposerViewModel composer;
  late final ObservableValue<ChatTimelineState> _timeline;
  late final ObservableValue<ChatDeletionsState> _deletions;
  late final ObservableValue<ChatPanelSessionState> _session;

  Observable<ChatTimelineState> get timeline => _timeline;
  Observable<ChatDeletionsState> get deletions => _deletions;
  Observable<ChatPanelSessionState> get session => _session;

  static const startupHintDuration = Duration(seconds: 20);
  static const startupHintFadeDuration = Duration(milliseconds: 500);
  Observable<TwitchAuthState> _auth;
  Observable<ChatState> _chat;
  ChatPanelConfig _config;
  TwitchAuthState _authSnapshot;
  ChatState _chatSnapshot;
  final ChatMessageRetention _recent = ChatMessageRetention();
  final Stopwatch _arrivalClock = Stopwatch()..start();
  final Map<String, Duration> _messageArrivals = {};
  Timer? _startupHintTimer;
  int _actionGeneration = 0;
  StreamSubscription<TwitchAuthState>? _authSubscription;
  StreamSubscription<ChatState>? _chatSubscription;

  void _listen() {
    stopObserving(_authSubscription);
    stopObserving(_chatSubscription);
    _authSubscription = observe(_auth.changes, (_) => _sync());
    _chatSubscription = observe(_chat.changes, (_) => _sync());
  }

  void _scheduleStartupHintFade() {
    _startupHintTimer = Timer(startupHintDuration, () {
      if (isDisposed) return;
      _timeline.set(
        _timeline.current.copyWith(
          startupHint: const ChatStartupHintState(fading: true),
        ),
      );
      if (isDisposed) return;
      _startupHintTimer = Timer(startupHintFadeDuration, () {
        if (isDisposed) return;
        _timeline.set(
          _timeline.current.copyWith(
            startupHint: const ChatStartupHintState(visible: false),
          ),
        );
      });
    });
  }

  /// Applies new widget configuration. Replacing a source re-reads its
  /// snapshot; unchanged sources and display settings need no re-sync.
  void update({
    required Observable<TwitchAuthState> auth,
    required Observable<ChatState> chat,
    required ChatPanelConfig config,
  }) {
    if (isDisposed) return;
    final previous = _config;
    _config = config;
    composer.configure(send: config.send, loadEmotes: config.loadEmotes);
    final sourcesChanged = !identical(auth, _auth) || !identical(chat, _chat);
    if (sourcesChanged) {
      _auth = auth;
      _chat = chat;
      _listen();
    }
    if (sourcesChanged ||
        previous.interactive != config.interactive ||
        previous.messageLifetimeMinutes != config.messageLifetimeMinutes) {
      _sync();
    }
  }

  void _sync() {
    if (isDisposed) return;
    final previousAuth = _authSnapshot;
    final previousChat = _chatSnapshot;
    final auth = _authSnapshot = _auth.current;
    final chat = _chatSnapshot = _chat.current;
    final sessionChanged =
        previousAuth.token?.userId != auth.token?.userId ||
        previousChat.broadcasterId != chat.broadcasterId ||
        auth.status == TwitchAuthStatus.signedOut;
    final previousIds = previousChat.items.map((item) => item.id).toSet();
    final currentIds = chat.items.map((item) => item.id).toSet();
    if (sessionChanged) {
      _actionGeneration++;
      _recent.clear();
      if (_deletions.current.processes.isNotEmpty) {
        _deletions.set(ChatDeletionsState());
      }
    }
    composer.syncSession(
      sessionChanged: sessionChanged,
      signedIn: auth.status == TwitchAuthStatus.signedIn,
      interactive: _config.interactive,
      emoteOptionsChanged: previousChat.emoteOptions != chat.emoteOptions,
      isRemoved: (id) => previousIds.contains(id) && !currentIds.contains(id),
    );
    if (isDisposed) return;
    _recent.update(chat.items, _config.messageLifetimeMinutes);
    final now = _arrivalClock.elapsed;
    _messageArrivals.removeWhere(
      (id, arrivedAt) =>
          !currentIds.contains(id) ||
          now - arrivedAt >= ChatMessageEntrance.duration,
    );
    for (final item in chat.items) {
      if (!item.isHistorical && !previousIds.contains(item.id)) {
        _messageArrivals[item.id] = now;
      }
    }
    // Messages and reconnects must never bring the startup hint back.
    _publishRecent(
      hideStartupHint:
          _recent.visibleItems.isNotEmpty ||
          (previousChat.status == ChatConnectionStatus.connected &&
              chat.status != ChatConnectionStatus.connected),
    );
    if (isDisposed) return;
    _session.set(_presentation(auth, chat));
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
      for (final message in _chatSnapshot.items.whereType<ChatUserMessage>())
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
    composer.keepReplyIf(
      (id) => _recent.visibleItems.any((item) => item.id == id),
    );
    _publishRecent();
  }

  bool canDelete(ChatUserMessage message) {
    final broadcasterId = _chatSnapshot.broadcasterId;
    return !isDisposed &&
        _authSnapshot.status == TwitchAuthStatus.signedIn &&
        broadcasterId != null &&
        _authSnapshot.token?.userId == broadcasterId &&
        _config.deleteMessage != null &&
        canDeleteTwitchMessage(message, broadcasterId);
  }

  void dismissDeleteError() {
    if (isDisposed || _deletions.current.error == null) return;
    _deletions.set(
      ChatDeletionsState(
        processes: {
          for (final entry in _deletions.current.processes.entries)
            if (!entry.value.isFailed) entry.key: entry.value,
        },
      ),
    );
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
    final delete = _config.deleteMessage;
    if (delete == null ||
        !canDelete(message) ||
        _deletions.current.isDeleting(message.id)) {
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
      await delete(message.id);
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

  bool _isCurrent(int generation) =>
      !isDisposed && generation == _actionGeneration;

  @override
  void dispose() {
    if (isDisposed) return;
    super.dispose();
    composer.dispose();
    _startupHintTimer?.cancel();
    _recent.dispose();
    _arrivalClock.stop();
  }
}
