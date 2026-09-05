import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

/// Compact viewer count for the status row above chat.
class ViewerCount extends StatelessWidget {
  const ViewerCount({required this.count, required this.offline, super.key});

  final int? count;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final value = offline
        ? l10n.streamOffline
        : count == null
        ? '—'
        : NumberFormat.decimalPattern(l10n.localeName).format(count);
    const color = Color(0xFFADADB8);
    return Semantics(
      label: '${l10n.viewerCountLabel}: $value',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.visibility_outlined,
            size: 14,
            color: color,
            shadows: chatReadableStyle.shadows,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: chatReadableStyle.copyWith(
                fontSize: 11,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
