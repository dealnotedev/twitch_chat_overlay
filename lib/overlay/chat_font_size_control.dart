import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:twitch_chat_overlay/chat/chat_font_size.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

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
    final label = format.format(size);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xF21F1F23),
      child: Row(
        children: [
          Text(
            l10n.chatFontSize,
            style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
          ),
          Expanded(
            child: Semantics(
              label: l10n.chatFontSize,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  activeTrackColor: const Color(0xFFBF94FF),
                  thumbColor: const Color(0xFFBF94FF),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                ),
                child: Slider(
                  key: const ValueKey('chat-font-size-slider'),
                  value: size,
                  min: ChatFontSize.minimum,
                  max: ChatFontSize.maximum,
                  divisions: ChatFontSize.divisions,
                  label: label,
                  semanticFormatterCallback: format.format,
                  onChanged: (value) =>
                      onChanged(ChatFontSize.normalize(value)),
                  onChangeEnd: (_) => onChangeEnd(),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 36,
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
            ),
          ),
        ],
      ),
    );
  }
}
