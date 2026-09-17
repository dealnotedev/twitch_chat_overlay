import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

class ComponentVisibilityControl extends StatelessWidget {
  const ComponentVisibilityControl({
    required this.showViewerCount,
    required this.showConnectionIndicator,
    required this.onShowViewerCountChanged,
    required this.onShowConnectionIndicatorChanged,
    super.key,
  });

  final bool showViewerCount;
  final bool showConnectionIndicator;
  final ValueChanged<bool> onShowViewerCountChanged;
  final ValueChanged<bool> onShowConnectionIndicatorChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.nonInteractiveComponents, style: _labelStyle),
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _checkbox(
                label: l10n.viewerCountComponent,
                value: showViewerCount,
                onChanged: onShowViewerCountChanged,
              ),
              _checkbox(
                label: l10n.connectionIndicatorComponent,
                value: showConnectionIndicator,
                onChanged: onShowConnectionIndicatorChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const _labelStyle = TextStyle(
    shadows: chatTextShadows,
    fontSize: 11,
    color: Colors.white,
  );

  Widget _checkbox({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => MergeSemantics(
    child: InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: value,
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
            activeColor: const Color(0xFFBF94FF),
            checkColor: const Color(0xFF111114),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Flexible(child: Text(label, style: _labelStyle)),
        ],
      ),
    ),
  );
}
