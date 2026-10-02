import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:twitch_chat_overlay/chat/chat_font_size.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/setting_slider.dart';

class ChatFontSizeControl extends StatelessWidget {
  const ChatFontSizeControl({
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
    super.key,
  });
  final double value;
  final ValueChanged<double> onChanged;
  final VoidCallback onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = NumberFormat('0.##', l10n.localeName);
    final size = ChatFontSize.normalize(value);
    return SettingSlider(
      sliderKey: const ValueKey('chat-font-size-slider'),
      label: l10n.chatFontSize,
      valueLabel: format.format(size),
      value: size,
      minimum: ChatFontSize.minimum,
      maximum: ChatFontSize.maximum,
      divisions: ChatFontSize.divisions,
      semanticFormatter: format.format,
      onChanged: (value) => onChanged(ChatFontSize.normalize(value)),
      onChangeEnd: onChangeEnd,
    );
  }
}
