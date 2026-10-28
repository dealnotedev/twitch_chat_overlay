import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chatters.dart';
import 'package:twitch_chat_overlay/widgets/twitch_auth_button.dart';

class ChatterNotificationsControl extends StatelessWidget {
  const ChatterNotificationsControl({
    required this.enabled,
    required this.onChanged,
    this.issue,
    this.onReconnect,
    super.key,
  });

  final bool enabled;
  final ValueChanged<bool> onChanged;
  final NewChatterIssue? issue;
  final VoidCallback? onReconnect;

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
                      l10n.newChatterNotificationsLabel,
                      style: const TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                ),
                Semantics(
                  label: l10n.newChatterNotificationsLabel,
                  child: Switch(
                    key: const ValueKey('new-chatter-notifications-switch'),
                    value: enabled,
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
              l10n.newChatterNotificationsDescription,
              style: const TextStyle(fontSize: 11, color: Color(0xFFAAA2B6)),
            ),
          ),
          if (enabled && issue != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      issue == NewChatterIssue.authorizationRequired
                          ? l10n.newChatterAuthorizationRequired
                          : l10n.newChatterUnavailable,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFFB4AB),
                      ),
                    ),
                  ),
                  if (issue == NewChatterIssue.authorizationRequired &&
                      onReconnect != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TwitchAuthButton(
                        onPressed: onReconnect!,
                        label: l10n.reconnectTwitch,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
