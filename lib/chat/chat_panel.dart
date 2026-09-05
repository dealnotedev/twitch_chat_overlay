import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_message_entrance.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_event_card.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';
import 'package:twitch_chat_overlay/twitch/twitch_rewards.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.authState,
    required this.chatState,
    required this.interactive,
    required this.onSignIn,
    required this.onSignOut,
    required this.onSend,
    super.key,
  });

  final TwitchAuthState authState;
  final ChatState chatState;
  final bool interactive;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;
  final Future<SendChatResult> Function(String message) onSend;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  bool _sending = false;
  String? _sendError;
  final Stopwatch _arrivalClock = Stopwatch()..start();
  final Map<String, Duration> _messageArrivals = {};

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final now = _arrivalClock.elapsed;
    final previousIds = oldWidget.chatState.items
        .map((item) => item.id)
        .toSet();
    final currentIds = widget.chatState.items.map((item) => item.id).toSet();
    _messageArrivals.removeWhere(
      (id, arrivedAt) =>
          !currentIds.contains(id) ||
          now - arrivedAt >= ChatMessageEntrance.duration,
    );
    for (final id in currentIds.difference(previousIds)) {
      _messageArrivals[id] = now;
    }
  }

  Duration? _entranceElapsed(String id) {
    final arrivedAt = _messageArrivals[id];
    return arrivedAt == null ? null : _arrivalClock.elapsed - arrivedAt;
  }

  @override
  void dispose() {
    _arrivalClock.stop();
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final body = switch (widget.authState.status) {
      TwitchAuthStatus.loading => _CenteredStatus(
        text: l10n.checkingTwitchSession,
        progress: true,
      ),
      TwitchAuthStatus.authorizing => _CenteredStatus(
        text: l10n.finishSignInInBrowser,
        progress: true,
      ),
      TwitchAuthStatus.signedOut || TwitchAuthStatus.failure => _SignedOutPanel(
        interactive: widget.interactive,
        error: _authError(l10n, widget.authState),
        onSignIn: widget.onSignIn,
      ),
      TwitchAuthStatus.signedIn => _connectedBody(l10n),
    };

    return Column(
      children: [
        if (widget.authState.status == TwitchAuthStatus.signedIn &&
            widget.chatState.rewardSubscriptionFailed)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.rewardSubscriptionFailed,
              style: const TextStyle(fontSize: 11, color: Color(0xFFFFB31A)),
            ),
          ),
        Expanded(
          child: DefaultTextStyle.merge(style: chatReadableStyle, child: body),
        ),
        if (widget.authState.status == TwitchAuthStatus.signedIn &&
            widget.interactive)
          _Composer(
            controller: _messageController,
            focusNode: _messageFocus,
            sending: _sending,
            error: _sendError,
            onSend: _send,
            onSignOut: widget.onSignOut,
          ),
      ],
    );
  }

  Widget _connectedBody(AppLocalizations l10n) {
    if (widget.chatState.items.isEmpty &&
        widget.chatState.status != ChatConnectionStatus.connected) {
      return _CenteredStatus(
        text: switch (widget.chatState.status) {
          ChatConnectionStatus.connecting => l10n.connectingEventSub,
          ChatConnectionStatus.reconnecting => l10n.reconnectingChat,
          ChatConnectionStatus.failure => l10n.chatConnectionFailed,
          _ => l10n.waitingForConnection,
        },
        progress:
            widget.chatState.status == ChatConnectionStatus.connecting ||
            widget.chatState.status == ChatConnectionStatus.reconnecting,
      );
    }

    final items = widget.chatState.items.reversed.toList(growable: false);
    final itemIndices = {
      for (var index = 0; index < items.length; index++) items[index].id: index,
    };

    return Stack(
      children: [
        ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          itemCount: items.length,
          reverse: true,
          findChildIndexCallback: (key) =>
              itemIndices[(key as ValueKey<String>).value],
          itemBuilder: (context, index) => RepaintBoundary(
            key: ValueKey(items[index].id),
            child: ChatMessageEntrance(
              elapsed: _entranceElapsed(items[index].id),
              child: _ChatItemView(
                item: items[index],
                badges: widget.chatState.badges,
                rewards: widget.chatState.rewards,
              ),
            ),
          ),
        ),
        if (widget.chatState.status == ChatConnectionStatus.reconnecting)
          Positioned(
            top: 5,
            right: 8,
            child: _ConnectionPill(text: l10n.reconnecting),
          ),
      ],
    );
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _sendError = null;
    });

    try {
      final result = await widget.onSend(text);
      if (!mounted) return;
      if (result.sent) {
        _messageController.clear();
        _messageFocus.requestFocus();
      } else {
        setState(() => _sendError = result.dropReason ?? l10n.messageRejected);
      }
    } catch (error) {
      if (mounted) setState(() => _sendError = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }
}

String? _authError(AppLocalizations l10n, TwitchAuthState state) {
  final details = state.errorDetails ?? l10n.unknownError;
  return switch (state.failure) {
    TwitchAuthFailure.storedSessionExpired => l10n.storedSessionExpired(
      details,
    ),
    TwitchAuthFailure.authorizationFailed => l10n.twitchAuthorizationFailed(
      details,
    ),
    TwitchAuthFailure.scopesChanged => l10n.twitchPermissionsChanged,
    null => null,
  };
}

class _SignedOutPanel extends StatelessWidget {
  const _SignedOutPanel({
    required this.interactive,
    required this.error,
    required this.onSignIn,
  });

  final bool interactive;
  final String? error;
  final Future<void> Function() onSignIn;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.account_circle_outlined,
              size: 32,
              color: Color(0xFFBF94FF),
            ),
            const SizedBox(height: 9),
            Text(
              error ?? l10n.connectTwitchDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFFD7D7DC)),
            ),
            const SizedBox(height: 12),
            if (interactive)
              FilledButton(
                onPressed: () => unawaited(onSignIn()),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9146FF),
                ),
                child: Text(l10n.signInWithTwitch),
              )
            else
              Text(
                l10n.openControlsShortcut,
                style: const TextStyle(fontSize: 11, color: Color(0xFFADADB8)),
              ),
          ],
        ),
      ),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({required this.text, this.progress = false});

  final String text;
  final bool progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (progress) ...[
              const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 10),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Color(0xFFADADB8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.error,
    required this.onSend,
    required this.onSignOut,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String? error;
  final VoidCallback onSend;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 8),
      decoration: BoxDecoration(
        color: BackgroundOpacity.colorOf(context, const Color(0xF21F1F23)),
        border: const Border(top: BorderSide(color: Color(0x333F3F46))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Color(0xFFFF7676)),
              ),
            ),
          Row(
            children: [
              IconButton(
                tooltip: l10n.signOutOfTwitch,
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(onSignOut()),
                icon: const Icon(Icons.logout_rounded, size: 17),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLength: 500,
                  maxLines: 3,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: l10n.sendMessageHint,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                tooltip: l10n.send,
                onPressed: sending ? null : onSend,
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF9146FF),
                ),
                icon: sending
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 17),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE61F1F23),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 9, color: Color(0xFFFFB31A)),
        ),
      ),
    );
  }
}

class _ChatItemView extends StatelessWidget {
  const _ChatItemView({
    required this.item,
    required this.badges,
    required this.rewards,
  });

  final ChatItem item;
  final TwitchBadges badges;
  final Map<String, TwitchRewardAppearance> rewards;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      ChatRewardRedemption redemption => RewardRedemptionCard(
        redemption: redemption,
        appearance: rewards[redemption.rewardId],
      ),
      ChatRaid raid => RaidCard(raid: raid),
      ChatUserMessage message => _UserMessageView(
        message: message,
        badges: badges,
      ),
      ChatNotice notice => _NoticeView(notice: notice, badges: badges),
      ChatSubscriptionRevoked revoked => _SubscriptionRevokedView(
        revoked: revoked,
      ),
    };
  }
}

class _UserMessageView extends StatelessWidget {
  const _UserMessageView({required this.message, required this.badges});

  final ChatUserMessage message;
  final TwitchBadges badges;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final highlighted = message.messageType != 'text';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: highlighted ? const EdgeInsets.all(7) : const EdgeInsets.all(3),
      decoration: highlighted
          ? BoxDecoration(
              color: BackgroundOpacity.colorOf(
                context,
                const Color(0x269146FF),
              ),
              borderRadius: BorderRadius.circular(6),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.reply case final reply?)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                l10n.replyContext(
                  reply.parentUserName,
                  reply.parentMessageBody,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFFADADB8),
                ),
              ),
            ),
          ChatMessageContent(
            fragments: message.fragments,
            prefix: [
              for (final badge in message.badges) _badgeSpan(badge, badges),
              TextSpan(
                text: '${message.userName}: ',
                style: TextStyle(
                  color: _parseColor(message.color),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            style: const TextStyle(fontSize: 13.5, height: 1.32),
          ),
          if (message.sourceChannel case final source?)
            Text(
              l10n.sharedChatOrigin(source),
              style: const TextStyle(fontSize: 9, color: Color(0xFFADADB8)),
            ),
        ],
      ),
    );
  }
}

class _NoticeView extends StatelessWidget {
  const _NoticeView({required this.notice, required this.badges});

  final ChatNotice notice;
  final TwitchBadges badges;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: BackgroundOpacity.colorOf(context, const Color(0x339146FF)),
        borderRadius: BorderRadius.circular(7),
        border: Border(
          left: BorderSide(
            color: BackgroundOpacity.colorOf(context, const Color(0xFF9146FF)),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            notice.systemMessage,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          if (notice.fragments.isNotEmpty) ...[
            const SizedBox(height: 3),
            ChatMessageContent(
              fragments: notice.fragments,
              prefix: [
                for (final badge in notice.badges) _badgeSpan(badge, badges),
                if (notice.userName case final name?)
                  TextSpan(
                    text: '$name: ',
                    style: TextStyle(
                      color: _parseColor(notice.color),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _SubscriptionRevokedView extends StatelessWidget {
  const _SubscriptionRevokedView({required this.revoked});

  final ChatSubscriptionRevoked revoked;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Text(
        AppLocalizations.of(context)
            .subscriptionRevoked(revoked.subscriptionType, revoked.status),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10.5, color: Color(0xFFFF7676)),
      ),
    );
  }
}

InlineSpan _badgeSpan(ChatBadge badge, TwitchBadges badges) {
  final image = badges.resolve(badge);
  if (image == null) return const TextSpan(text: '');
  return WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.only(right: 3),
      child: Tooltip(
        message: image.title,
        child: Semantics(
          label: image.title,
          image: true,
          child: CachedNetworkImage(
            imageUrl: image.url,
            width: 18,
            height: 18,
            fit: BoxFit.contain,
            placeholder: (_, _) => const SizedBox.square(dimension: 18),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
        ),
      ),
    ),
  );
}

Color _parseColor(String? value) {
  if (value == null || value.isEmpty) return const Color(0xFFB8B8FF);
  final hex = value.replaceFirst('#', '');
  final parsed = int.tryParse(hex, radix: 16);
  return parsed == null
      ? const Color(0xFFB8B8FF)
      : readableChatColor(Color(0xFF000000 | parsed));
}
