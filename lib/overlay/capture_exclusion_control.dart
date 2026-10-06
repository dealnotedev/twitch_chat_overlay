import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

class CaptureExclusionControl extends StatelessWidget {
  const CaptureExclusionControl({
    required this.value,
    required this.onChanged,
    this.failed = false,
    super.key,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      l10n.captureExclusionLabel,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
                Semantics(
                  label: l10n.captureExclusionLabel,
                  child: Switch(
                    key: const ValueKey('capture-exclusion-switch'),
                    value: value,
                    onChanged: onChanged,
                    activeThumbColor: const Color(0xFFBF94FF),
                    activeTrackColor: const Color(0xFF604280),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Text(
              l10n.captureExclusionDescription,
              style: const TextStyle(fontSize: 11, color: Color(0xFFAAA2B6)),
            ),
          ),
          if (failed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  l10n.captureExclusionFailed,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFFB4AB),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
