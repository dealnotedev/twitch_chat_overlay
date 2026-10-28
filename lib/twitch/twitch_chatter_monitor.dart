import 'dart:async';

import 'package:dio/dio.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chatters.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

/// Only Helix snapshots produce arrivals. Activity merely suppresses them.
final class TwitchChatterMonitor {
  TwitchChatterMonitor({
    required this._auth,
    required this._helix,
    required this.onArrivals,
    required this.onIssue,
    this._enabled = false,
  });

  static const interval = Duration(seconds: 30);
  final TwitchAuth _auth;
  final TwitchHelixClient _helix;
  final void Function(String sessionId, List<TwitchChatter>) onArrivals;
  final void Function(NewChatterIssue?) onIssue;
  // Retain the latest broadcast per channel only for this monitor's lifetime.
  final Map<String, _ChatterContext> _broadcasts = {};
  final Map<String, DateTime> _activity = {};
  String? _broadcasterId;
  _ChatterContext? _context;
  bool _enabled;
  bool _baselineReady = false;
  int _generation = 0;
  Timer? _timer;
  CancelToken? _request;
  NewChatterIssue? _issue;

  void start(String broadcasterId) {
    stop();
    _broadcasterId = broadcasterId;
    _context = _ChatterContext.offline();
    if (_enabled) _startPolling();
  }

  void setEnabled(bool enabled) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _cancelPolling();
    _baselineReady = false;
    _setIssue(null);
    if (enabled && _broadcasterId != null) _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  void _cancelPolling() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _request?.cancel('Chatter monitoring stopped');
    _request = null;
  }

  void stop() {
    _cancelPolling();
    _broadcasterId = null;
    _context = null;
    _activity.clear();
    _baselineReady = false;
    _setIssue(null);
  }

  void recordActivity(String userId, DateTime at) {
    if (_broadcasterId == null || userId.isEmpty) return;
    final previous = _activity[userId];
    if (previous != null && !at.isAfter(previous)) return;
    _activity[userId] = at;
    final context = _context;
    if (context != null && !at.isBefore(context.startedAt)) {
      context.knownUserIds.add(userId);
    }
  }

  Future<void> refresh() async {
    final broadcasterId = _broadcasterId;
    if (!_enabled || broadcasterId == null || _request != null) return;
    final generation = _generation;
    final request = CancelToken();
    _request = request;
    bool current() => generation == _generation && identical(_request, request);
    try {
      final token = await _auth.validToken();
      if (!current()) return;
      if (token.userId != broadcasterId ||
          !token.scopes.contains('moderator:read:chatters')) {
        throw const TwitchChattersAuthorizationRequired();
      }
      final broadcast = await _helix.getLiveBroadcast(
        broadcasterId: broadcasterId,
        cancelToken: request,
      );
      if (!current()) return;
      final previous = _context;
      final _ChatterContext context;
      if (broadcast != null) {
        final remembered = _broadcasts[broadcasterId];
        context = remembered?.id == broadcast.id
            ? remembered!
            : _ChatterContext(
                id: broadcast.id,
                startedAt: broadcast.startedAt,
                isLive: true,
              );
        _broadcasts[broadcasterId] = context;
      } else {
        context = previous != null && !previous.isLive
            ? previous
            : _ChatterContext.offline();
      }
      if (previous?.id != context.id) {
        _context = context;
        _activity.removeWhere((_, at) => at.isBefore(context.startedAt));
        _baselineReady = false;
      }
      final users = await _helix.getChatters(
        broadcasterId: broadcasterId,
        cancelToken: request,
      );
      if (!current()) return;
      final initialSnapshot = !_baselineReady;
      // Activity may have arrived while any page was loading.
      for (final entry in _activity.entries) {
        if (!entry.value.isBefore(context.startedAt)) {
          context.knownUserIds.add(entry.key);
        }
      }
      context.knownUserIds.add(broadcasterId);
      final arrivals = <TwitchChatter>[];
      for (final user in users) {
        final unseen = context.knownUserIds.add(user.id);
        // Remember the entire first snapshot without announcing existing users.
        if (!initialSnapshot && unseen) arrivals.add(user);
      }
      _baselineReady = true;
      _setIssue(null);
      final silentArrivals = arrivals.where((user) {
        final activityAt = _activity[user.id];
        return activityAt == null || activityAt.isBefore(context.startedAt);
      }).toList();
      if (silentArrivals.isNotEmpty) onArrivals(context.id, silentArrivals);
    } catch (error) {
      if (!current()) return;
      final permission =
          error is TwitchChattersAuthorizationRequired ||
          (error is DioException && error.response?.statusCode == 403);
      _setIssue(
        permission
            ? NewChatterIssue.authorizationRequired
            : NewChatterIssue.unavailable,
      );
    } finally {
      if (current()) _request = null;
    }
  }

  void _setIssue(NewChatterIssue? issue) {
    if (_issue == issue) return;
    _issue = issue;
    onIssue(issue);
  }
}

final class _ChatterContext {
  _ChatterContext({
    required this.id,
    required this.startedAt,
    required this.isLive,
  });

  factory _ChatterContext.offline() {
    final now = DateTime.now().toUtc();
    return _ChatterContext(
      id: 'offline:${now.microsecondsSinceEpoch}',
      startedAt: now,
      isLive: false,
    );
  }

  final String id;
  final DateTime startedAt;
  final bool isLive;
  final Set<String> knownUserIds = {};
}
