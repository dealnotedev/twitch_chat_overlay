import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';

ChatItem notice(String id, {Duration age = Duration.zero}) => ChatNotice(
  id: id,
  receivedAt: DateTime.now().subtract(age),
  noticeType: 'announcement',
  systemMessage: id,
  userName: null,
  color: null,
  badges: const [],
  fragments: const [],
);

void main() {
  testWidgets('default lifetime keeps even old messages indefinitely', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    final item = notice('old', age: const Duration(days: 1));
    expect(ChatMessageRetention.defaultMinutes, 0);
    recent.update([item], ChatMessageRetention.defaultMinutes);
    await tester.pump(const Duration(days: 7));
    expect(recent.items, [item]);
    expect(recent.isFading(item.id), isFalse);
    recent.dispose();
  });

  testWidgets('disabling lifetime cancels waiting and active expiration', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    final waiting = notice('waiting');
    final fading = notice('fading', age: const Duration(minutes: 2));
    recent.update([waiting, fading], 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(recent.isFading(fading.id), isTrue);
    recent.update([waiting, fading], 0);
    await tester.pump(const Duration(days: 1));
    expect(recent.items, [waiting, fading]);
    expect(recent.isFading(fading.id), isFalse);
    recent.dispose();
  });

  testWidgets('enabling expiry from unlimited applies to existing rows', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    final item = notice('old', age: const Duration(minutes: 2));
    recent.update([item], 0);
    recent.update([item], 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(recent.isFading(item.id), isTrue);
    await tester.pump(ChatMessageRetention.fadeDuration);
    recent.update([item], 0);
    expect(recent.items, isEmpty);
    recent.dispose();
  });
  testWidgets('idle messages fade at expiry, then leave the list', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    final item = notice('first');
    recent.update([item], 1);
    await tester.pump(const Duration(seconds: 59));
    expect(recent.items, [item]);
    expect(recent.isFading(item.id), isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(recent.isFading(item.id), isTrue);
    expect(recent.items, [item]);
    await tester.pump(ChatMessageRetention.fadeDuration);
    expect(recent.items, isEmpty);
    recent.update([item], 60);
    expect(recent.items, isEmpty);
    recent.dispose();
  });

  testWidgets('new arrivals and updates do not reset older timers', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    final first = notice('first');
    recent.update([first], 1);
    await tester.pump(const Duration(seconds: 30));
    final second = notice('second');
    recent.update([first, second], 1);
    await tester.pump(const Duration(seconds: 30));
    expect(recent.isFading(first.id), isTrue);
    expect(recent.isFading(second.id), isFalse);
    await tester.pump(ChatMessageRetention.fadeDuration);
    expect(recent.items, [second]);
    recent.dispose();
  });

  testWidgets('shorter lifetime applies to existing messages', (tester) async {
    final recent = ChatMessageRetention();
    final old = notice('old', age: const Duration(minutes: 2));
    final fresh = notice('fresh');
    recent.update([old, fresh], 5);
    expect(recent.isFading(old.id), isFalse);
    recent.update([old, fresh], 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(recent.isFading(old.id), isTrue);
    expect(recent.isFading(fresh.id), isFalse);
    recent.update([old, fresh], 60);
    await tester.pump(ChatMessageRetention.fadeDuration);
    expect(recent.items, [fresh]);
    recent.dispose();
  });

  testWidgets('longer lifetime reschedules rows that have not expired', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    final item = notice('first', age: const Duration(seconds: 59));
    recent.update([item], 1);
    recent.update([item], 2);
    await tester.pump(const Duration(seconds: 2));
    expect(recent.isFading(item.id), isFalse);
    await tester.pump(const Duration(seconds: 59));
    expect(recent.isFading(item.id), isTrue);
    recent.dispose();
  });

  testWidgets('moderation and channel reset cancel pending expiry', (
    tester,
  ) async {
    final recent = ChatMessageRetention();
    var updates = 0;
    recent.addListener(() => updates++);
    recent.update([notice('first')], 1);
    recent.update([], 1);
    await tester.pump(const Duration(minutes: 2));
    expect(updates, 0);
    recent.update([notice('second')], 1);
    recent.clear();
    await tester.pump(const Duration(minutes: 2));
    expect(updates, 0);
    recent.dispose();
  });
}
