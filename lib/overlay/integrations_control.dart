import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/emotes/emote_options.dart';

class IntegrationsControl extends StatelessWidget {
  const IntegrationsControl({
    required this.options,
    required this.onChanged,
    super.key,
  });

  final ThirdPartyEmoteOptions options;
  final ValueChanged<ThirdPartyEmoteOptions> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      children: [
        _toggle(
          key: 'integration-7tv',
          label: '7TV',
          value: options.sevenTv,
          onChanged: (value) => onChanged(options.copyWith(sevenTv: value)),
        ),
        _toggle(
          key: 'integration-bttv',
          label: 'BetterTTV',
          value: options.betterTtv,
          onChanged: (value) => onChanged(options.copyWith(betterTtv: value)),
        ),
      ],
    ),
  );

  Widget _toggle({
    required String key,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        Expanded(
          child: ExcludeSemantics(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ),
        ),
        Semantics(
          label: label,
          child: Switch(
            key: ValueKey(key),
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFBF94FF),
            activeTrackColor: const Color(0xFF604280),
          ),
        ),
      ],
    ),
  );
}
