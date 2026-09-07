import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/count_setting_control.dart';

class MessageLifetimeControl extends StatelessWidget {
  const MessageLifetimeControl({
    required this.minutes,
    required this.onChanged,
    super.key,
  });

  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return CountSettingControl(
      value: minutes,
      maximum: ChatMessageRetention.maximumMinutes,
      onChanged: onChanged,
      label: l10n.messageLifetime,
      increaseLabel: l10n.increaseMessageLifetime,
      decreaseLabel: l10n.decreaseMessageLifetime,
      description: (value) => value == 0
          ? l10n.messageLifetimeUnlimited
          : l10n.messageLifetimeMinutes(value),
      displayValue: minutes == 0 ? '∞' : l10n.messageLifetimeMinutes(minutes),
      icon: Icons.timer_outlined,
    );
  }
}
