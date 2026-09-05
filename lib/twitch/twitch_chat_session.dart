import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_emotes.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_rewards.dart';
import 'package:web_socket_channel/io.dart';

enum ChatConnectionStatus { idle, connecting, connected, reconnecting, failure }

final class ChatState {
  const ChatState({
    required this.status,
    required this.items,
    this.error,
    this.badges = const TwitchBadges(),
    this.rewards = const {},
    this.rewardSubscriptionFailed = false,
  });

  const ChatState.idle()
    : status = ChatConnectionStatus.idle,
      items = const [],
      badges = const TwitchBadges(),
      rewards = const {},
      rewardSubscriptionFailed = false,
      error = null;

  final ChatConnectionStatus status;
  final List<ChatItem> items;
  final String? error;
  final TwitchBadges badges;
  final Map<String, TwitchRewardAppearance> rewards;
  final bool rewardSubscriptionFailed;
}

abstract interface class TwitchChatSession {
  ChatState get state;
  Stream<ChatState> get states;

  Future<void> join({required String broadcasterId});
  Future<void> leave();
  Future<List<TwitchEmote>> loadEmotes({bool refresh = false});
  Future<SendChatResult> send(String message, {String? replyTo});
}

final class EventSubTwitchChatSession implements TwitchChatSession {
  EventSubTwitchChatSession(
    this._auth,
    this._helix, {
    this.eventSubUrl = _defaultEventSubUrl,
  });

  static const String _defaultEventSubUrl =
      'wss://eventsub.wss.twitch.tv/ws?keepalive_timeout_seconds=30';
  final String eventSubUrl;

  final TwitchAuth _auth;
  final TwitchHelixClient _helix;
  final TwitchChatEventMapper _mapper = const TwitchChatEventMapper();
  final ChatTimeline _timeline = ChatTimeline();
  final StreamController<ChatState> _states =
      StreamController<ChatState>.broadcast(sync: true);
  final Queue<String> _messageIdOrder = Queue();
  final Set<String> _messageIds = {};
  final Random _random = Random();

  ChatState _state = const ChatState.idle();
  _EventSubSocket? _active;
  _EventSubSocket? _candidate;
  Timer? _retryTimer;
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
  Stream<ChatState> get states => _states.stream;

  @override
  Future<void> join({required String broadcasterId}) async {
    if (_broadcasterId == broadcasterId &&
        _state.status != ChatConnectionStatus.idle &&
        _state.status != ChatConnectionStatus.failure) {
      return;
    }

    await leave();
    _broadcasterId = broadcasterId;
    _timeline.clear();
    _messageIds.clear();
    _messageIdOrder.clear();
    _retryAttempt = 0;
    _emit(ChatConnectionStatus.connecting);
    unawaited(_loadBadges(''));
    unawaited(_loadBadges(broadcasterId));
    await _connect(eventSubUrl, inheritedSubscriptions: false);
  }

  @override
  Future<void> leave() async {
    _generation++;
    _badgeChannels.clear();
    _badgeLoads.clear();
    _badgeRetryAt.clear();
    _rewards = const {};
    _rewardLoadInFlight = false;
    _rewardSubscriptionFailed = false;
    _rewardsRefreshAt = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    final active = _active;
    final candidate = _candidate;
    _active = null;
    _candidate = null;
    await Future.wait([
      if (active != null) active.close(),
      if (candidate != null) candidate.close(),
    ]);
    _broadcasterId = null;
    _emit(ChatConnectionStatus.idle);
  }

  @override
  Future<List<TwitchEmote>> loadEmotes({bool refresh = false}) async {
    final broadcasterId = _broadcasterId;
    final generation = _generation;
    if (broadcasterId == null) throw StateError('Chat is not connected');
    final emotes = await _helix.getUserEmotes(
      broadcasterId: broadcasterId,
      refresh: refresh,
    );
    if (generation != _generation || broadcasterId != _broadcasterId) {
      throw StateError('Chat changed while loading emotes');
    }
    return emotes;
  }

  @override
  Future<SendChatResult> send(String message, {String? replyTo}) async {
    final broadcasterId = _broadcasterId;
    if (broadcasterId == null) throw StateError('Chat is not connected');
    final token = await _auth.validToken();
    return _helix.sendMessage(
      broadcasterId: broadcasterId,
      senderId: token.userId,
      message: message,
      replyParentMessageId: replyTo,
    );
  }

  Future<void> _connect(
    String url, {
    required bool inheritedSubscriptions,
  }) async {
    final generation = _generation;
    try {
      final webSocket = await WebSocket.connect(url);
      if (generation != _generation || _broadcasterId == null) {
        await webSocket.close();
        return;
      }
      webSocket.pingInterval = const Duration(seconds: 10);
      final socket = _EventSubSocket(
        channel: IOWebSocketChannel(webSocket),
        inheritedSubscriptions: inheritedSubscriptions,
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
    } catch (error) {
      if (inheritedSubscriptions) {
        await _handleReconnectFailure(error);
      } else {
        _scheduleReconnect(error);
      }
    }
  }

  Future<void> _handleFrame(_EventSubSocket socket, Object? raw) async {
    if (raw is! String) return;
    final envelope = (jsonDecode(raw) as Map).cast<String, Object?>();
    final metadata = _map(envelope['metadata']);
    final messageId = metadata['message_id'] as String?;
    if (messageId != null && !_rememberMessageId(messageId)) return;

    socket.touch();
    switch (metadata['message_type']) {
      case 'session_welcome':
        await _handleWelcome(socket, envelope);
        return;
      case 'session_keepalive':
        return;
      case 'notification':
        final mutation = _mapper.map(envelope);
        if (mutation != null && _timeline.apply(mutation)) {
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
          _emit(ChatConnectionStatus.connected);
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
        _timeline.apply(
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
        _emit(ChatConnectionStatus.connected);
        return;
      default:
        return;
    }
  }

  Future<void> _handleWelcome(
    _EventSubSocket socket,
    Map<String, Object?> envelope,
  ) async {
    final session = _map(_map(envelope['payload'])['session']);
    socket.sessionId = session['id'] as String?;
    socket.keepaliveSeconds =
        session['keepalive_timeout_seconds'] as int? ?? 30;
    socket.touch();

    if (socket.inheritedSubscriptions) {
      final old = _active;
      _active = socket;
      _candidate = null;
      await old?.close();
      _retryAttempt = 0;
      _emit(ChatConnectionStatus.connected);
      return;
    }

    final broadcasterId = _broadcasterId;
    final sessionId = socket.sessionId;
    if (socket != _active || broadcasterId == null || sessionId == null) return;

    try {
      final token = await _auth.validToken();
      await _helix.createChatSubscriptions(
        sessionId: sessionId,
        broadcasterId: broadcasterId,
        userId: token.userId,
      );
      if (socket == _active) {
        _retryAttempt = 0;
        _emit(ChatConnectionStatus.connected);
        unawaited(_subscribeRewards(socket, broadcasterId, sessionId));
      }
    } catch (error) {
      _handleSocketFailure(socket, error);
    }
  }

  void _handleSocketFailure(_EventSubSocket socket, Object error) {
    if (socket.failureHandled) return;
    socket.failureHandled = true;

    if (socket == _candidate) {
      _candidate = null;
      unawaited(socket.close());
      unawaited(_handleReconnectFailure(error));
      return;
    }
    if (socket != _active) return;

    _active = null;
    unawaited(socket.close());
    if (_candidate == null) _scheduleReconnect(error);
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

  Future<void> _handleReconnectFailure(Object error) async {
    final active = _active;
    _active = null;
    await active?.close();
    _scheduleReconnect(error);
  }

  void _scheduleReconnect(Object error) {
    if (_broadcasterId == null || _retryTimer != null) return;
    final exponential = min(30, 1 << min(_retryAttempt, 5));
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

  void _emit(ChatConnectionStatus status, {String? error}) {
    final next = ChatState(
      status: status,
      items: _timeline.items,
      error: error,
      badges: TwitchBadges(Map.unmodifiable(_badgeChannels)),
      rewards: _rewards,
      rewardSubscriptionFailed: _rewardSubscriptionFailed,
    );
    _state = next;
    _states.add(next);
  }

  static Map<String, Object?> _map(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.cast<String, Object?>();
    return const {};
  }
}

final class _EventSubSocket {
  _EventSubSocket({
    required this.channel,
    required this.inheritedSubscriptions,
  });

  final IOWebSocketChannel channel;
  final bool inheritedSubscriptions;
  StreamSubscription<Object?>? subscription;
  Timer? watchdog;
  String? sessionId;
  int keepaliveSeconds = 30;
  bool failureHandled = false;
  bool closed = false;

  void touch() {
    watchdog?.cancel();
    watchdog = Timer(Duration(seconds: keepaliveSeconds + 2), () {
      channel.sink.close(WebSocketStatus.goingAway, 'Keepalive timeout');
    });
  }

  Future<void> close() async {
    if (closed) return;
    closed = true;
    watchdog?.cancel();
    await subscription?.cancel();
    await channel.sink.close(WebSocketStatus.normalClosure);
  }
}
