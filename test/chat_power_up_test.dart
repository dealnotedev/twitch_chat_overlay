import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twitch_chat_overlay/chat/chat_event_card.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_mutation.dart';
import 'package:twitch_chat_overlay/chat/chat_timeline.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/twitch/chat_event_mapper.dart';

void main() {
  const mapper = TwitchChatEventMapper();
  for (final entry in {
    'message_effect': ChatPowerUpType.messageEffect,
    'gigantify_an_emote': ChatPowerUpType.gigantifyEmote,
    'celebration': ChatPowerUpType.celebration,
  }.entries) {
    test('maps exact Bits for ${entry.key}, without duplicating chat text', () {
      final item =
          (mapper.map(envelope(entry.key)) as AddChatItem).item as ChatPowerUp;
      expect(item.type, entry.value);
      expect(item.bits, 321);
      expect(item.userName, 'Viewer');
      expect(item.id, 'bits:delivery');
      expect(item.emote?.id, '25');
      expect(item.emote?.text, 'Kappa');
      expect(item.receivedAt, DateTime.utc(2026, 9, 5, 10));
    });
  }
  test('ignores cheers, custom power-ups and unsupported types', () {
    for (final type in ['cheer', 'custom_power_up']) {
      expect(mapper.map(envelope('celebration', type: type)), isNull);
    }
    expect(mapper.map(envelope('unknown')), isNull);
  });
  test('does not invent payments from missing, zero or malformed amounts', () {
    for (final bits in <Object?>[null, 0, -1, '100', 1.5]) {
      expect(mapper.map(envelope('celebration', bits: bits)), isNull);
    }
    final missingId = envelope('celebration');
    (missingId['metadata'] as Map).remove('message_id');
    expect(mapper.map(missingId), isNull);
  });
  test('deduplicates receipts and respects user clearing', () {
    final mutation = mapper.map(envelope('celebration'))!;
    final timeline = ChatTimeline();
    expect(timeline.apply(mutation), isTrue);
    expect(timeline.apply(mutation), isFalse);
    expect(timeline.items, hasLength(1));
    expect(timeline.apply(const ClearUserMessages('other')), isFalse);
    expect(timeline.apply(const ClearUserMessages('viewer')), isTrue);
    expect(timeline.items, isEmpty);
  });
  for (final locale in ['en', 'uk']) {
    testWidgets('receipt wraps with transparent background ($locale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(locale),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: BackgroundOpacity(
              opacity: 0,
              child: Center(
                child: SizedBox(
                  width: 130,
                  child: PowerUpCard(
                    powerUp: ChatPowerUp(
                      id: 'receipt',
                      receivedAt: DateTime.utc(2026),
                      userId: 'viewer',
                      userName: 'Viewer',
                      type: ChatPowerUpType.celebration,
                      bits: 321,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('321 Bits', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Viewer', findRichText: true), findsOneWidget);
      expect(find.byIcon(Icons.diamond_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

Map<String, Object?> envelope(
  String powerUpType, {
  Object? bits = 321,
  String type = 'power_up',
}) => {
  'metadata': {
    'subscription_type': 'channel.bits.use',
    'message_id': 'delivery',
    'message_timestamp': '2026-09-05T10:00:00Z',
  },
  'payload': {
    'event': {
      'user_id': 'viewer',
      'user_name': 'Viewer',
      'type': type,
      'bits': bits,
      'power_up': {
        'type': powerUpType,
        'emote': {'id': '25', 'name': 'Kappa'},
      },
      'message': {'text': 'Do not repeat this chat message'},
    },
  },
};
