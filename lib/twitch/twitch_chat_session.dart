import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';
import 'package:twitch_chat_overlay/emotes/third_party_emotes.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_rewards.dart';
import 'package:twitch_chat_overlay/twitch/twitch_recent_messages.dart';
import 'package:web_socket_channel/io.dart';

enum ChatConnectionStatus { idle, connecting, connected, reconnecting, failure }

final class ChatState {
  const ChatState({
    required this.status,
    required this.items,
    this.error,
    this.viewerCount,
    this.streamOffline = false,
    this.broadcasterId,
    this.badges = const TwitchBadges(),
    this.rewards = const {},
    this.rewardSubscriptionFailed = false,
    this.emoteCatalog = const EmoteCatalog.empty(),
    this.emoteOptions = const ThirdPartyEmoteOptions(),
  });

  const ChatState.idle()
    : status = ChatConnectionStatus.idle,
      items = const [],
      badges = const TwitchBadges(),
      rewards = const {},
      rewardSubscriptionFailed = false,
      emoteCatalog = const EmoteCatalog.empty(),
      emoteOptions = const ThirdPartyEmoteOptions(),
      broadcasterId = null,
      viewerCount = null,
      streamOffline = false,
      error = null;

  final ChatConnectionStatus status;
  final List<ChatItem> items;
  final String? error;
  final int? viewerCount;
  final bool streamOffline;
  final String? broadcasterId;
  final TwitchBadges badges;
  final Map<String, TwitchRewardAppearance> rewards;
  final bool rewardSubscriptionFailed;
  final EmoteCatalog emoteCatalog;
  final ThirdPartyEmoteOptions emoteOptions;
}

abstract interface class TwitchChatSession {
  ChatState get state;
  Stream<ChatState> get states;

  Future<void> join({required String broadcasterId});
  Future<void> leave();
  Future<List<ChatEmote>> loadEmotes({bool refresh = false});
  void setEmoteOptions(ThirdPartyEmoteOptions options);
  Future<SendChatResult> send(String message, {String? replyTo});
  Future<void> deleteMessage(String messageId);
}

final class EventSubTwitchChatSession implements TwitchChatSession {
  EventSubTwitchChatSession(
    this._auth,
    this._helix, {
    this.eventSubUrl = _defaultEventSubUrl,
    this.history,
    this.thirdPartyEmotes,
    this._emoteOptions = const ThirdPartyEmoteOptions(),
  });

  static const String _defaultEventSubUrl =
      'wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=10';
  static const _connectTimeout = Duration(seconds: 15);
  static const _welcomeTimeout = Duration(seconds: 10);
  static const _subscriptionTimeout = Duration(seconds: 20);
  final String eventSubUrl;
  final TwitchRecentMessages? history;
  final ThirdPartyEmotes? thirdPartyEmotes;
  ThirdPartyEmoteOptions _emoteOptions;
  int _emoteOptionsRevision = 0;
  EmoteCatalog _emoteCatalog = const EmoteCatalog.empty();
  bool _historyStarted = false;
  List<ChatMutation>? _historyJournal;

  final TwitchAuth _auth;
  final TwitchHelixClient _helix;
  final TwitchChatEventMapper _mapper = const TwitchChatEventMapper();
  final ChatTimeline _timeline = ChatTimeline();
  final Queue<String> _messageIdOrder = Queue();
  final Set<String> _messageIds = {};
  final Random _random = Random();

  final ObservableValue<ChatState> _observable = ObservableValue(
    current: const ChatState.idle(),
    sync: false,
  );

  ChatState get _state => _observable.current;
  _EventSubSocket? _active;
  _EventSubSocket? _candidate;
  _EventSubConnectAttempt? _connecting;
  Timer? _retryTimer;
  Timer? _viewerTimer;
  Timer? _emoteTimer;
  int? _viewerCount;
  bool _streamOffline = false;
  CancelToken? _viewerRequest;
  String? _broadcasterId;
  int _retryAttempt = 0;
  int _generation = 0;
  final Map<String, TwitchBadgeSet> _badgeChannels = {};
  final Set<String> _badgeLoads = {};
  final Map<String, DateTime> _badgeRetryAt = {};
  Map<String, TwitchRewardAppearance> _rewards = const {};
  bool _rewardLoadInFlight = false;
  bool _rewardSubscriptionFailed = false;
  DateTime? _rewardsRefreshAt;

  @override
  ChatState get state => _state;

  @override
  Stream<ChatState> get states => _observable.changes;

  @override
  Future<void> join({required String broadcasterId}) async {
    if (_broadcasterId == broadcasterId &&
        _state.status != ChatConnectionStatus.idle &&
        _state.status != ChatConnectionStatus.failure) {
      return;
    }

    final leaving = leave();
    final generation = _generation;
    await leaving;
    if (generation != _generation) return;
    _broadcasterId = broadcasterId;
    _timeline.clear();
    // Capture moderation as soon as subscriptions can start delivering events.
    _historyJournal = history == null ? null : [];
    _messageIds.clear();
    _messageIdOrder.clear();
    _retryAttempt = 0;
    _emit(ChatConnectionStatus.connecting);
    unawaited(_refreshViewerCount());
    _viewerTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(_refreshViewerCount());
    });
    unawaited(_loadBadges(''));
    unawaited(_loadBadges(broadcasterId));
    unawaited(_loadThirdPartyEmotes());
    _updateEmoteTimer();
    await _connect(eventSubUrl, inheritedSubscriptions: false);
  }

  @override
  Future<void> leave() async {
    final generation = ++_generation;
    _broadcasterId = null;
    _emoteCatalog = const EmoteCatalog.empty();
    _emoteTimer?.cancel();
    _emoteTimer = null;
    _historyStarted = false;
    _historyJournal = null;
    _viewerTimer?.cancel();
    _viewerTimer = null;
    _viewerCount = null;
    _streamOffline = false;
    _viewerRequest?.cancel('Chat session ended');
    _viewerRequest = null;
    _badgeChannels.clear();
    _badgeLoads.clear();
    _badgeRetryAt.clear();
    _rewards = const {};
    _rewardLoadInFlight = false;
    _rewardSubscriptionFailed = false;
    _rewardsRefreshAt = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    await _closeConnections();
    if (generation == _generation) _emit(ChatConnectionStatus.idle);
  }

  @override
  Future<List<ChatEmote>> loadEmotes({bool refresh = false}) async {
    final broadcasterId = _broadcasterId;
    final generation = _generation;
    final optionsRevision = _emoteOptionsRevision;
    if (broadcasterId == null) throw StateError('Chat is not connected');
    Object? twitchError;
    final results = await Future.wait<List<ChatEmote>>([
      (() async {
        try {
          return await _helix.getUserEmotes(
            broadcasterId: broadcasterId,
            refresh: refresh,
          );
        } catch (error) {
          twitchError = error;
          return <ChatEmote>[];
        }
      })(),
      _loadThirdPartyEmotes(refresh: refresh).then((catalog) => catalog.emotes),
    ]);
    if (generation != _generation ||
        broadcasterId != _broadcasterId ||
        optionsRevision != _emoteOptionsRevision) {
      throw StateError('Chat changed while loading emotes');
    }
    if (results.every((list) => list.isEmpty) && twitchError != null) {
      throw twitchError!;
    }
    // Native Twitch names retain precedence in the picker as in incoming chat.
    final twitchNames = results.first.map((emote) => emote.name).toSet();
    return List.unmodifiable([
      ...results.first,
      ...results.last.where((emote) => !twitchNames.contains(emote.name)),
    ]);
  }

  Future<EmoteCatalog> _loadThirdPartyEmotes({bool refresh = false}) async {
    final source = thirdPartyEmotes;
    final broadcasterId = _broadcasterId;
    final generation = _generation;
    final optionsRevision = _emoteOptionsRevision;
    if (source == null || broadcasterId == null || !_emoteOptions.enabled) {
      return const EmoteCatalog.empty();
    }
    final catalog = await source.load(
      broadcasterId,
      options: _emoteOptions,
      refresh: refresh,
    );
    if (generation == _generation &&
        broadcasterId == _broadcasterId &&
        optionsRevision == _emoteOptionsRevision) {
      _emoteCatalog = catalog;
      _emit(_state.status, error: _state.error);
    }
    return catalog;
  }

  @override
  void setEmoteOptions(ThirdPartyEmoteOptions options) {
    if (options == _emoteOptions) return;
    _emoteOptions = options;
    _emoteOptionsRevision++;
    // Remove disabled providers immediately, before any pending HTTP reply.
    _emoteCatalog = EmoteCatalog(
      _emoteCatalog.emotes.where((emote) => options.allows(emote.provider)),
    );
    _updateEmoteTimer();
    _emit(_state.status, error: _state.error);
    unawaited(_loadThirdPartyEmotes());
  }

  void _updateEmoteTimer() {
    _emoteTimer?.cancel();
    _emoteTimer = null;
    if (_broadcasterId != null &&
        thirdPartyEmotes != null &&
        _emoteOptions.enabled) {
      _emoteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        unawaited(_loadThirdPartyEmotes());
      });
    }
  }

  @override
  Future<SendChatResult> send(String message, {String? replyTo}) async {
    final broadcasterId = _broadcasterId;
    final generation = _generation;
    if (broadcasterId == null) throw StateError('Chat is not connected');
    final token = await _auth.validToken();
    if (generation != _generation) {
      throw const TwitchChatActionException(
        TwitchChatActionFailure.sessionChanged,
      );
    }
    if (replyTo != null &&
        !_timeline.items.any(
          (item) => item is ChatUserMessage && item.id == replyTo,
        )) {
      throw const TwitchChatActionException(
        TwitchChatActionFailure.messageUnavailable,
      );
    }
    return _helix.sendMessage(
      broadcasterId: broadcasterId,
      senderId: token.userId,
      message: message,
      replyParentMessageId: replyTo,
    );
  }

  @override
  Future<void> deleteMessage(String messageId) async {
    final broadcasterId = _broadcasterId;
    final generation = _generation;
    if (broadcasterId == null) {
      throw const TwitchChatActionException(
        TwitchChatActionFailure.sessionChanged,
      );
    }
    final token = await _auth.validToken();
    if (generation != _generation) {
      throw const TwitchChatActionException(
        TwitchChatActionFailure.sessionChanged,
      );
    }
    final message = _timeline.items
        .whereType<ChatUserMessage>()
        .where((item) => item.id == messageId)
        .firstOrNull;
    if (message == null) {
      throw const TwitchChatActionException(
        TwitchChatActionFailure.messageUnavailable,
      );
    }
    if (!canDeleteTwitchMessage(message, broadcasterId)) {
      throw const TwitchChatActionException(TwitchChatActionFailure.forbidden);
    }
    await _helix.deleteMessage(
      broadcasterId: broadcasterId,
      moderatorId: token.userId,
      messageId: messageId,
    );
    if (generation == _generation &&
        _applyMutation(DeleteChatMessage(messageId))) {
      _emit(_state.status, error: _state.error);
    }
  }

  Future<void> _connect(
    String url, {
    required bool inheritedSubscriptions,
  }) async {
    if (_broadcasterId == null || _connecting != null) return;
    final generation = _generation;
    final attempt = _EventSubConnectAttempt(_connectTimeout);
    _connecting = attempt;
    try {
      final pending = WebSocket.connect(url, customClient: attempt.client);
      // A timed-out handshake may complete after its HTTP response detached.
      // Close that late transport instead of leaking or adopting it.
      unawaited(
        pending.then((webSocket) async {
          if (attempt.cancelled) {
            await webSocket.close(WebSocketStatus.normalClosure);
          }
        }, onError: (Object _, StackTrace _) {}),
      );
      final webSocket = await pending.timeout(_connectTimeout);
      if (generation != _generation ||
          _broadcasterId == null ||
          attempt != _connecting ||
          attempt.cancelled) {
        await webSocket.close(WebSocketStatus.normalClosure);
        return;
      }
      // EventSub permits Pong replies only. Dart answers server Ping itself.
      late final _EventSubSocket socket;
      socket = _EventSubSocket(
        webSocket: webSocket,
        inheritedSubscriptions: inheritedSubscriptions,
        generation: generation,
        onTimeout: (error) => _handleSocketFailure(socket, error),
      );
      if (inheritedSubscriptions) {
        _candidate = socket;
      } else {
        _active = socket;
      }
      socket.subscription = socket.channel.stream.listen(
        (raw) => _handleFrame(socket, raw),
        onError: (Object error, StackTrace stackTrace) {
          _handleSocketFailure(socket, error);
        },
        onDone: () => _handleSocketFailure(socket, 'Connection closed'),
      );
      socket.welcomeTimer = Timer(_welcomeTimeout, () {
        _handleSocketFailure(
          socket,
          TimeoutException('EventSub welcome timeout'),
        );
      });
    } catch (error) {
      if (generation != _generation ||
          attempt != _connecting ||
          attempt.cancelled) {
        return;
      }
      attempt.cancel();
      _connecting = null;
      if (inheritedSubscriptions) {
        _handleReconnectFailure(error);
      } else {
        _scheduleReconnect(error);
      }
    } finally {
      attempt.client.close(force: true);
      if (_connecting == attempt) _connecting = null;
    }
  }

  Future<void> _handleFrame(_EventSubSocket socket, Object? raw) async {
    if (socket.closed ||
        socket.failureHandled ||
        socket.generation != _generation ||
        (socket != _active && socket != _candidate)) {
      return;
    }
    try {
      await _processFrame(socket, raw);
    } catch (error) {
      _handleSocketFailure(socket, error);
    }
  }

  Future<void> _processFrame(_EventSubSocket socket, Object? raw) async {
    if (raw is! String) return;
    final envelope = (jsonDecode(raw) as Map).cast<String, Object?>();
    final metadata = _map(envelope['metadata']);
    final messageId = metadata['message_id'] as String?;
    socket.touch();
    if (messageId != null && !_rememberMessageId(messageId)) return;
    switch (metadata['message_type']) {
      case 'session_welcome':
        await _handleWelcome(socket, envelope);
        return;
      case 'session_keepalive':
        return;
      case 'notification':
        final mutation = _mapper.map(envelope);
        if (mutation != null && _applyMutation(mutation)) {
          unawaited(_loadBadges(''));
          if (_broadcasterId case final channel?) {
            unawaited(_loadBadges(channel));
          }
          if (mutation case AddChatItem(:final item)) {
            if (item is ChatRewardRedemption) unawaited(_loadRewards());
            final badges = switch (item) {
              ChatUserMessage() => item.badges,
              ChatNotice() => item.badges,
              _ => const <ChatBadge>[],
            };
            for (final channel
                in badges.map((b) => b.broadcasterId).nonNulls.toSet()) {
              unawaited(_loadBadges(channel));
            }
          }
          _emit(_state.status, error: _state.error);
        }
        return;
      case 'session_reconnect':
        final reconnectUrl =
            _map(_map(envelope['payload'])['session'])['reconnect_url']
                as String?;
        if (socket == _active && reconnectUrl != null && _candidate == null) {
          _emit(ChatConnectionStatus.reconnecting);
          await _connect(reconnectUrl, inheritedSubscriptions: true);
        }
        return;
      case 'revocation':
        final subscription = _map(_map(envelope['payload'])['subscription']);
        final type = subscription['type'] as String? ?? 'unknown';
        final status = subscription['status'] as String? ?? 'revoked';
        _applyMutation(
          AddChatItem(
            ChatSubscriptionRevoked(
              id:
                  messageId ??
                  'revocation-${DateTime.now().microsecondsSinceEpoch}',
              receivedAt: DateTime.now().toUtc(),
              subscriptionType: type,
              status: status,
            ),
          ),
        );
        final error = 'EventSub subscription revoked: $type ($status)';
        final requiredChat = TwitchHelixClient.chatSubscriptionTypes.contains(
          type,
        );
        if (status == 'authorization_revoked' ||
            (requiredChat &&
                (status == 'user_removed' || status == 'version_removed'))) {
          _retryTimer?.cancel();
          _retryTimer = null;
          unawaited(_closeConnections());
          _emit(ChatConnectionStatus.failure, error: error);
          if (status == 'authorization_revoked') await _auth.signOut();
        } else if (requiredChat) {
          _handleReconnectFailure(error);
        } else {
          if (type == TwitchHelixClient.rewardSubscriptionType) {
            _rewardSubscriptionFailed = true;
          }
          _emit(_state.status, error: _state.error);
        }
        return;
      default:
        return;
    }
  }

  Future<void> _handleWelcome(
    _EventSubSocket socket,
    Map<String, Object?> envelope,
  ) async {
    if (socket.sessionId != null) return;
    final session = _map(_map(envelope['payload'])['session']);
    socket.sessionId = session['id'] as String?;
    if (socket.sessionId == null || socket.sessionId!.isEmpty) {
      throw const FormatException('EventSub welcome is missing session ID');
    }
    socket.keepaliveSeconds =
        session['keepalive_timeout_seconds'] as int? ?? 30;
    if (socket.keepaliveSeconds < 1) {
      throw const FormatException('Invalid EventSub keepalive timeout');
    }
    socket.welcomeTimer?.cancel();
    socket.touch();

    if (socket.inheritedSubscriptions) {
      final old = _active;
      _active = socket;
      _candidate = null;
      if (old != null) unawaited(old.close());
      _markConnected();
      return;
    }

    final broadcasterId = _broadcasterId;
    final sessionId = socket.sessionId;
    if (socket != _active || broadcasterId == null || sessionId == null) return;

    try {
      await (() async {
        final token = await _auth.validToken();
        if (socket != _active || socket.closed) return;
        await _helix.createChatSubscriptions(
          sessionId: sessionId,
          broadcasterId: broadcasterId,
          userId: token.userId,
        );
        if (socket != _active || socket.closed) return;
        await _helix.createBitsSubscription(
          sessionId: sessionId,
          broadcasterId: broadcasterId,
        );
      })().timeout(_subscriptionTimeout);
      if (socket == _active) {
        _markConnected();
        unawaited(_loadHistory());
        unawaited(_subscribeRewards(socket, broadcasterId, sessionId));
      }
    } catch (error) {
      _handleSocketFailure(socket, error);
    }
  }

  void _markConnected() {
    final recovered = _state.status == ChatConnectionStatus.reconnecting;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    _emit(ChatConnectionStatus.connected);
    if (recovered) unawaited(_refreshViewerCount(refresh: true));
  }

  void _handleSocketFailure(_EventSubSocket socket, Object error) {
    if (socket.failureHandled) return;
    socket.failureHandled = true;

    if (socket == _candidate) {
      _handleReconnectFailure(error);
      return;
    }
    if (socket != _active) return;

    _active = null;
    unawaited(socket.close());
    if (_candidate == null && _connecting == null) {
      _scheduleReconnect(error);
    } else {
      _emit(ChatConnectionStatus.reconnecting, error: error.toString());
    }
  }

  Future<void> _subscribeRewards(
    _EventSubSocket socket,
    String broadcasterId,
    String sessionId,
  ) async {
    try {
      await _helix.createRewardSubscription(
        sessionId: sessionId,
        broadcasterId: broadcasterId,
      );
      if (socket != _active) return;
      _rewardSubscriptionFailed = false;
      unawaited(_loadRewards());
    } catch (_) {
      if (socket != _active) return;
      // A channel without access to rewards must still receive normal chat.
      _rewardSubscriptionFailed = true;
    }
    _emit(_state.status, error: _state.error);
  }

  bool _applyMutation(ChatMutation mutation) {
    _historyJournal?.add(mutation);
    return _timeline.apply(mutation);
  }

  Future<void> _loadHistory() async {
    final source = history;
    final broadcasterId = _broadcasterId;
    if (source == null || broadcasterId == null || _historyStarted) return;
    _historyStarted = true;
    final generation = _generation;
    final journal = _historyJournal ?? [];
    _historyJournal = journal;
    try {
      final items = await (() async {
        final login = await _helix.getChannelLogin(
          broadcasterId: broadcasterId,
        );
        if (generation != _generation || !identical(_historyJournal, journal)) {
          return <ChatItem>[];
        }
        return source.load(login);
      })().timeout(const Duration(seconds: 20));
      if (generation != _generation) return;
      _timeline.restoreHistory(items, journal);
      for (final item in _timeline.items) {
        final badges = switch (item) {
          ChatUserMessage() => item.badges,
          ChatNotice() => item.badges,
          _ => const <ChatBadge>[],
        };
        for (final channel
            in badges.map((b) => b.broadcasterId).nonNulls.toSet()) {
          unawaited(_loadBadges(channel));
        }
      }
      _emit(_state.status, error: _state.error);
    } catch (_) {
      // History is optional: outages or an untracked channel never stop chat.
    } finally {
      if (generation == _generation) _historyJournal = null;
    }
  }

  Future<void> _loadRewards() async {
    final broadcasterId = _broadcasterId;
    final refreshAt = _rewardsRefreshAt;
    if (broadcasterId == null ||
        _rewardLoadInFlight ||
        (refreshAt != null && DateTime.now().isBefore(refreshAt))) {
      return;
    }
    final generation = _generation;
    _rewardLoadInFlight = true;
    try {
      final rewards = await _helix.getRewards(broadcasterId: broadcasterId);
      if (generation != _generation) return;
      _rewards = rewards;
      _rewardsRefreshAt = DateTime.now().add(const Duration(minutes: 1));
      _emit(_state.status, error: _state.error);
    } catch (_) {
      if (generation == _generation) {
        _rewardsRefreshAt = DateTime.now().add(const Duration(seconds: 30));
      }
    } finally {
      if (generation == _generation) _rewardLoadInFlight = false;
    }
  }

  Future<void> _closeConnections() async {
    _connecting?.cancel();
    _connecting = null;
    final active = _active;
    final candidate = _candidate;
    _active = null;
    _candidate = null;
    await Future.wait([
      if (active != null) active.close(),
      if (candidate != null) candidate.close(),
    ]);
  }

  void _handleReconnectFailure(Object error) {
    unawaited(_closeConnections());
    _scheduleReconnect(error);
  }

  void _scheduleReconnect(Object error) {
    if (_broadcasterId == null ||
        _retryTimer != null ||
        _state.status == ChatConnectionStatus.failure) {
      return;
    }
    // Continue probing a restored network without a 30-second backoff tail.
    final exponential = min(5, 1 << min(_retryAttempt, 3));
    final delay = Duration(
      milliseconds: exponential * 1000 + _random.nextInt(500),
    );
    _retryAttempt++;
    _emit(ChatConnectionStatus.reconnecting, error: error.toString());
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_connect(eventSubUrl, inheritedSubscriptions: false));
    });
  }

  bool _rememberMessageId(String id) {
    if (!_messageIds.add(id)) return false;
    _messageIdOrder.addLast(id);
    while (_messageIdOrder.length > 2000) {
      _messageIds.remove(_messageIdOrder.removeFirst());
    }
    return true;
  }

  Future<void> _loadBadges(String channel) async {
    if (_broadcasterId == null ||
        _badgeChannels.containsKey(channel) ||
        _badgeLoads.contains(channel)) {
      return;
    }
    final retryAt = _badgeRetryAt[channel];
    if (retryAt != null && DateTime.now().isBefore(retryAt)) return;
    final generation = _generation;
    _badgeLoads.add(channel);
    try {
      final badges = await _helix.getBadges(
        broadcasterId: channel.isEmpty ? null : channel,
      );
      if (generation != _generation) return;
      _badgeChannels[channel] = badges;
      _badgeRetryAt.remove(channel);
      _emit(_state.status, error: _state.error);
    } catch (_) {
      // An optional image catalog must never interrupt incoming chat.
      if (generation == _generation) {
        _badgeRetryAt[channel] = DateTime.now().add(
          const Duration(seconds: 30),
        );
      }
    } finally {
      if (generation == _generation) _badgeLoads.remove(channel);
    }
  }

  Future<void> _refreshViewerCount({bool refresh = false}) async {
    final broadcasterId = _broadcasterId;
    if (broadcasterId == null || (_viewerRequest != null && !refresh)) return;
    final generation = _generation;
    // Reconnection must not wait for an HTTP request from the previous network.
    _viewerRequest?.cancel('Refreshing after reconnect');
    final request = CancelToken();
    _viewerRequest = request;
    try {
      final count = await _helix.getViewerCount(
        broadcasterId: broadcasterId,
        cancelToken: request,
      );
      if (generation != _generation || _viewerRequest != request) return;
      _viewerCount = count;
      _streamOffline = count == null;
    } catch (_) {
      if (generation != _generation || _viewerRequest != request) return;
      // Never present an old count as current, or interrupt chat on failure.
      _viewerCount = null;
      _streamOffline = false;
    } finally {
      if (_viewerRequest == request) _viewerRequest = null;
    }
    _emit(_state.status, error: _state.error);
  }

  void _emit(ChatConnectionStatus status, {String? error}) {
    final next = ChatState(
      status: status,
      broadcasterId: _broadcasterId,
      viewerCount: _viewerCount,
      streamOffline: _streamOffline,
      items: _timeline.items,
      error: error,
      badges: TwitchBadges(Map.unmodifiable(_badgeChannels)),
      rewards: _rewards,
      rewardSubscriptionFailed: _rewardSubscriptionFailed,
      emoteCatalog: _emoteCatalog,
      emoteOptions: _emoteOptions,
    );
    _observable.set(next);
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    return const {};
  }
}

final class _EventSubConnectAttempt {
  _EventSubConnectAttempt(Duration timeout)
    : client = HttpClient()..connectionTimeout = timeout;

  final HttpClient client;
  bool cancelled = false;

  void cancel() {
    cancelled = true;
    client.close(force: true);
  }
}

final class _EventSubSocket {
  _EventSubSocket({
    required WebSocket webSocket,
    required this.inheritedSubscriptions,
    required this.generation,
    required this.onTimeout,
  }) : _webSocket = webSocket,
       channel = IOWebSocketChannel(webSocket);

  final WebSocket _webSocket;
  final IOWebSocketChannel channel;
  final bool inheritedSubscriptions;
  final int generation;
  final void Function(Object) onTimeout;
  StreamSubscription<Object?>? subscription;
  Timer? welcomeTimer;
  Timer? watchdog;
  String? sessionId;
  int keepaliveSeconds = 30;
  bool failureHandled = false;
  bool closed = false;
  Future<void>? _closing;

  void touch() {
    if (closed || sessionId == null) return;
    watchdog?.cancel();
    watchdog = Timer(Duration(seconds: keepaliveSeconds + 2), () {
      onTimeout(TimeoutException('EventSub keepalive timeout'));
    });
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    closed = true;
    welcomeTimer?.cancel();
    watchdog?.cancel();
    return _closing = _close();
  }

  Future<void> _close() async {
    try {
      await subscription?.cancel();
      await channel.sink.close(WebSocketStatus.normalClosure);
    } finally {
      // Close the native transport even if the channel adapter failed cleanup.
      await _webSocket.close(WebSocketStatus.normalClosure);
    }
  }
}
