import 'package:twitch_chat_overlay/chat/chat_emote.dart';

final class ThirdPartyEmoteOptions {
  const ThirdPartyEmoteOptions({this.sevenTv = false, this.betterTtv = false});

  final bool sevenTv;
  final bool betterTtv;

  bool get enabled => sevenTv || betterTtv;

  bool allows(EmoteProvider provider) => switch (provider) {
    EmoteProvider.twitch => true,
    EmoteProvider.sevenTv => sevenTv,
    EmoteProvider.betterTtv => betterTtv,
  };

  ThirdPartyEmoteOptions copyWith({bool? sevenTv, bool? betterTtv}) =>
      ThirdPartyEmoteOptions(
        sevenTv: sevenTv ?? this.sevenTv,
        betterTtv: betterTtv ?? this.betterTtv,
      );

  @override
  bool operator ==(Object other) =>
      other is ThirdPartyEmoteOptions &&
      sevenTv == other.sevenTv &&
      betterTtv == other.betterTtv;

  @override
  int get hashCode => Object.hash(sevenTv, betterTtv);
}
