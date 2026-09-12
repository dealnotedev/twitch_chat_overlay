import 'package:flutter/material.dart';

import 'package:twitch_chat_overlay/chat/chat_font_weight.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context);

    final weight = ChatFontWeight.normalize(value);
    final label = weight.toString();
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xF21F1F23),
      child: Row(
        children: [
          Text(
            l10n.chatFontWeight,
            style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
          ),
          Expanded(
            child: Semantics(
              label: l10n.chatFontWeight,
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
                  key: const ValueKey('chat-font-weight-slider'),
                  value: weight.toDouble(),
                  min: ChatFontWeight.minimum.toDouble(),
                  max: ChatFontWeight.maximum.toDouble(),
                  divisions: ChatFontWeight.divisions,
                  label: label,
                  semanticFormatterCallback: (value) =>
                      value.round().toString(),
                  onChanged: (value) =>
                      onChanged(ChatFontWeight.normalize(value.round())),
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
