import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';

/// Expires rows locally without deleting messages from Twitch.
final class ChatMessageRetention extends ChangeNotifier {
  static const defaultMinutes = 0;
  // Zero disables automatic expiration.
  static const minimumMinutes = 0;
  static const maximumMinutes = 60;
  static const fadeDuration = Duration(milliseconds: 700);

  final Map<String, _RetainedMessage> _entries = {};
  List<ChatItem> _source = const [];
  int? _minutes;

  List<ChatItem> get items => [
    for (final item in _source)
      if (!_entries[item.id]!.hidden) item,
  ];

  bool isFading(String id) => _entries[id]?.fading ?? false;

  /// Synchronizes source messages and settings before the next UI build.
  void update(List<ChatItem> source, int minutes) {
    final ids = source.map((item) => item.id).toSet();
    _entries.removeWhere((id, entry) {
      if (ids.contains(id)) return false;
      entry.timer?.cancel();
      return true;
    });
    final changed = _minutes != minutes;
    _minutes = minutes;
    _source = source;
    final now = DateTime.now();
    for (final item in source) {
      final existing = _entries[item.id];
      // Hidden rows stay hidden. Disabling expiry also stops an active fade.
      if (existing != null &&
          (!changed || existing.hidden || (existing.fading && minutes != 0))) {
        continue;
      }
      final entry = _entries.putIfAbsent(item.id, _RetainedMessage.new);
      entry.timer?.cancel();
      if (minutes == 0) {
        entry.timer = null;
        entry.fading = false;
        continue;
      }
      final remaining = item.receivedAt
          .add(Duration(minutes: minutes))
          .difference(now);
      // Expired history must never flash on screen when it is first loaded.
      if (existing == null && item.isHistorical && remaining <= Duration.zero) {
        entry.hidden = true;
        continue;
      }
      entry.timer = Timer(remaining.isNegative ? Duration.zero : remaining, () {
        entry.fading = true;
        entry.timer = Timer(fadeDuration, () {
          entry.hidden = true;
          notifyListeners();
        });
        notifyListeners();
      });
    }
  }

  void clear() {
    for (final entry in _entries.values) {
      entry.timer?.cancel();
    }
    _entries.clear();
    _source = const [];
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}

final class _RetainedMessage {
  Timer? timer;
  bool fading = false;
  bool hidden = false;
}
