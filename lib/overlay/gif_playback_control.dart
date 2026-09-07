import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/gif_playback.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/count_setting_control.dart';

class GifPlaybackControl extends StatelessWidget {
  const GifPlaybackControl({
    required this.playCount,
    required this.onChanged,
    super.key,
  });

  final int playCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CountSettingControl(
      value: playCount,
      maximum: GifPlayback.maximumCount,
      minimum: GifPlayback.unlimitedCount,
      onChanged: onChanged,
      label: l10n.gifPlayCount,
      increaseLabel: l10n.increaseGifPlayCount,
      decreaseLabel: l10n.decreaseGifPlayCount,
      description: (value) => value == GifPlayback.unlimitedCount
          ? l10n.gifPlayCountUnlimited
          : value == 0
          ? l10n.gifPlaybackDisabled
          : l10n.gifPlayCountValue(value),
      displayValue: playCount == GifPlayback.unlimitedCount
          ? '∞'
          : '$playCount',
      icon: Icons.repeat_rounded,
    );
  }
}
