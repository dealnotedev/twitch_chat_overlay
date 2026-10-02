import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_font_weight.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/setting_slider.dart';

class ChatFontWeightControl extends StatelessWidget {
  const ChatFontWeightControl({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });
  final int value;
  final ValueChanged<int> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final weight = ChatFontWeight.normalize(value);
    return SettingSlider(
      sliderKey: const ValueKey('chat-font-weight-slider'),
      label: AppLocalizations.of(context).chatFontWeight,
      valueLabel: weight.toString(),
      value: weight.toDouble(),
      minimum: ChatFontWeight.minimum.toDouble(),
      maximum: ChatFontWeight.maximum.toDouble(),
      divisions: ChatFontWeight.divisions,
      semanticFormatter: (value) => value.round().toString(),
      onChanged: (value) => onChanged(ChatFontWeight.normalize(value.round())),
      onChangeEnd: onChangeEnd,
    );
  }
}
