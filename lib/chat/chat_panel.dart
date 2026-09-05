import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_composer.dart';
import 'package:twitch_chat_overlay/chat/chat_message_actions.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_actions.dart';
import 'package:twitch_chat_overlay/chat/chat_emote_picker.dart';
import 'package:twitch_chat_overlay/twitch/twitch_emotes.dart';
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

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.authState,
    required this.chatState,
    required this.interactive,
    required this.onSignIn,
    required this.onSignOut,
    required this.onSend,
    required this.onLoadEmotes,
    this.onDeleteMessage,
    super.key,
  });

  final TwitchAuthState authState;
  final ChatState chatState;
  final bool interactive;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;
  final Future<SendChatResult> Function(String message, {String? replyTo})
  onSend;
  final Future<void> Function(String messageId)? onDeleteMessage;
  final Future<List<TwitchEmote>> Function({bool refresh}) onLoadEmotes;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  bool _sending = false;
  String? _sendError;
  ChatReply? _replyTo;
  String? _deleteError;
  final Set<String> _deletingIds = {};
  int _actionGeneration = 0;
  bool _emotesOpen = false;
  Future<List<TwitchEmote>>? _emotesFuture;
  final Object _emoteTapGroup = Object();
  final Stopwatch _arrivalClock = Stopwatch()..start();
  final Map<String, Duration> _messageArrivals = {};

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.authState.status != TwitchAuthStatus.signedIn ||
        oldWidget.authState.token?.userId != widget.authState.token?.userId) {
      _emotesFuture = null;
      _emotesOpen = false;
    }
    if (oldWidget.authState.token?.userId != widget.authState.token?.userId ||
        oldWidget.chatState.broadcasterId != widget.chatState.broadcasterId ||
        widget.authState.status == TwitchAuthStatus.signedOut) {
      _actionGeneration++;
      _replyTo = null;
      _sendError = null;
      _deleteError = null;
      _deletingIds.clear();
      _sending = false;
    }
    if (!widget.interactive) _emotesOpen = false;
    final now = _arrivalClock.elapsed;
    final previousIds = oldWidget.chatState.items
        .map((item) => item.id)
        .toSet();
    final currentIds = widget.chatState.items.map((item) => item.id).toSet();
    if (_replyTo case final reply?) {
      if (previousIds.contains(reply.parentMessageId) &&
          !currentIds.contains(reply.parentMessageId)) {
        _replyTo = null;
        _sendError = AppLocalizations.of(context).replyUnavailable;
      }
    }
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
          child: DefaultTextStyle.merge(
            style: chatReadableStyle,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                children: [
                  Positioned.fill(child: body),
                  if (_emotesOpen &&
                      _emotesFuture != null &&
                      widget.interactive &&
                      widget.authState.status == TwitchAuthStatus.signedIn)
                    Positioned(
                      left: 8,
                      right: 8,
                      bottom: 8,
                      height: (constraints.maxHeight - 16).clamp(0.0, 280.0),
                      child: ChatEmotePicker(
                        emotes: _emotesFuture!,
                        tapGroup: _emoteTapGroup,
                        onSelected: _insertEmote,
                        onReload: _reloadEmotes,
                        onClose: () {
                          _closeEmotes();
                          _messageFocus.requestFocus();
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (widget.interactive && _deleteError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _deleteError!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFFF7676),
                        ),
                      ),
                    ),
                    ChatIconButton(
                      label: l10n.dismiss,
                      icon: Icons.close_rounded,
                      size: 26,
                      iconSize: 15,
                      onPressed: () => setState(() {
                        _deleteError = null;
                      }),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (widget.authState.status == TwitchAuthStatus.signedIn &&
            widget.interactive)
          ChatComposer(
            controller: _messageController,
            focusNode: _messageFocus,
            sending: _sending,
            error: _sendError,
            emotesOpen: _emotesOpen,
            tapGroup: _emoteTapGroup,
            onSend: _send,
            onSignOut: () => unawaited(widget.onSignOut()),
            onToggleEmotes: _toggleEmotes,
            onCloseEmotes: _closeEmotes,
            replyTo: _replyTo,
            onCancelReply: _cancelReply,
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

    // Redemption events have no color; reuse the latest chat color by user ID.
    final userColors = <String, Color?>{
      for (final message in widget.chatState.items.whereType<ChatUserMessage>())
        message.userId: message.color == null || message.color!.isEmpty
            ? null
            : _parseColor(message.color),
    };
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
                canCopy: widget.interactive,
                badges: widget.chatState.badges,
                userColor: switch (items[index]) {
                  ChatRewardRedemption(:final userId) => userColors[userId],
                  _ => null,
                },
                onReply:
                    widget.interactive &&
                        widget.authState.status == TwitchAuthStatus.signedIn
                    ? _startReply
                    : null,
                onDelete:
                    widget.interactive &&
                        items[index] is ChatUserMessage &&
                        _canDelete(items[index] as ChatUserMessage)
                    ? (message) => unawaited(_deleteMessage(message))
                    : null,
                deleting: _deletingIds.contains(items[index].id),
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

  Future<List<TwitchEmote>> _requestEmotes({bool refresh = false}) {
    final request = Future<List<TwitchEmote>>.sync(
      () => widget.onLoadEmotes(refresh: refresh),
    );
    // Keep late errors handled if the picker closes before the next frame.
    request.ignore();
    return request;
  }

  void _toggleEmotes() {
    setState(() {
      _emotesOpen = !_emotesOpen;
      if (_emotesOpen) _emotesFuture = _requestEmotes();
    });
  }

  void _reloadEmotes() {
    setState(() {
      _emotesFuture = _requestEmotes(refresh: true);
    });
  }

  void _closeEmotes() {
    if (_emotesOpen) setState(() => _emotesOpen = false);
  }

  void _insertEmote(TwitchEmote emote) {
    final value = insertChatEmote(_messageController.value, emote.name);
    if (value == null) {
      setState(() => _sendError = AppLocalizations.of(context).messageTooLong);
      return;
    }
    _messageController.value = value;
    setState(() => _sendError = null);
    _messageFocus.requestFocus();
  }

  bool _canDelete(ChatUserMessage message) {
    final broadcasterId = widget.chatState.broadcasterId;
    return widget.authState.status == TwitchAuthStatus.signedIn &&
        broadcasterId != null &&
        widget.authState.token?.userId == broadcasterId &&
        widget.onDeleteMessage != null &&
        canDeleteTwitchMessage(message, broadcasterId);
  }

  void _startReply(ChatUserMessage message) {
    setState(() {
      _replyTo = ChatReply(
        parentMessageId: message.id,
        parentUserName: message.userName,
        parentMessageBody: message.fragments
            .map((fragment) => fragment.text)
            .join(),
      );
      _sendError = null;
      _emotesOpen = false;
    });
    _messageFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTo = null);
    _messageFocus.requestFocus();
  }

  Future<void> _deleteMessage(ChatUserMessage message) async {
    if (!_canDelete(message) || _deletingIds.contains(message.id)) return;
    final generation = _actionGeneration;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _deletingIds.add(message.id);
      _deleteError = null;
    });
    try {
      await widget.onDeleteMessage!(message.id);
    } catch (error) {
      if (!mounted || generation != _actionGeneration) return;
      setState(() {
        final failure = error is TwitchChatActionException
            ? error.failure
            : null;
        _deleteError = switch (failure) {
          TwitchChatActionFailure.forbidden => l10n.deleteNotAllowed,
          TwitchChatActionFailure.messageUnavailable => l10n.messageUnavailable,
          _ => l10n.deleteFailed,
        };
      });
    } finally {
      if (mounted && generation == _actionGeneration) {
        setState(() => _deletingIds.remove(message.id));
      }
    }
  }

  Future<void> _send() async {
    final draft = _messageController.text;
    final reply = _replyTo;
    final generation = _actionGeneration;
    final text = draft.trim();
    if (text.isEmpty || _sending) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _sending = true;
      _emotesOpen = false;
      _sendError = null;
    });

    try {
      final result = await widget.onSend(text, replyTo: reply?.parentMessageId);
      if (!mounted || generation != _actionGeneration) return;
      if (result.sent) {
        if (_messageController.text == draft) _messageController.clear();
        if (identical(_replyTo, reply)) setState(() => _replyTo = null);
        _messageFocus.requestFocus();
      } else {
        setState(() => _sendError = result.dropReason ?? l10n.messageRejected);
      }
    } catch (error) {
      if (mounted && generation == _actionGeneration) {
        setState(
          () => _sendError =
              error is TwitchChatActionException &&
                  error.failure == TwitchChatActionFailure.messageUnavailable
              ? l10n.replyUnavailable
              : error.toString(),
        );
      }
    } finally {
      if (mounted && generation == _actionGeneration) {
        setState(() => _sending = false);
      }
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
    this.canCopy = false,
    this.userColor,
    this.onReply,
    this.onDelete,
    this.deleting = false,
  });

  final ChatItem item;
  final TwitchBadges badges;
  final Color? userColor;
  final bool canCopy;
  final ValueChanged<ChatUserMessage>? onReply;
  final ValueChanged<ChatUserMessage>? onDelete;
  final bool deleting;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      ChatRewardRedemption redemption => RewardRedemptionCard(
        redemption: redemption,
        userColor: userColor,
      ),
      ChatRaid raid => RaidCard(raid: raid),
      ChatUserMessage message => ChatMessageActions(
        messageId: message.id,
        copyText: canCopy
            ? message.fragments.map((fragment) => fragment.text).join()
            : null,
        onReply: onReply == null ? null : () => onReply!(message),
        onDelete: onDelete == null ? null : () => onDelete!(message),
        deleting: deleting,
        child: _UserMessageView(message: message, badges: badges),
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
    final highlighted =
        message.messageType != 'text' &&
        message.messageType != 'power_ups_gigantified_emote';
    final channelPointsHighlight =
        message.messageType == 'channel_points_highlighted';
    return Container(
      key: channelPointsHighlight
          ? ValueKey('highlighted-message-${message.id}')
          : null,
      margin: EdgeInsets.symmetric(vertical: channelPointsHighlight ? 5 : 2),
      padding: channelPointsHighlight
          ? const EdgeInsets.fromLTRB(10, 8, 10, 9)
          : highlighted
          ? const EdgeInsets.all(7)
          : const EdgeInsets.all(3),
      decoration: highlighted
          ? BoxDecoration(
              color: BackgroundOpacity.colorOf(
                context,
                const Color(0x269146FF),
              ),
              borderRadius: BorderRadius.circular(
                channelPointsHighlight ? 4 : 6,
              ),
              border: channelPointsHighlight
                  ? const Border(
                      left: BorderSide(color: Color(0xFF9146FF), width: 3),
                      top: BorderSide(color: Color(0xFF9146FF)),
                      right: BorderSide(color: Color(0xFF9146FF)),
                      bottom: BorderSide(color: Color(0xFF9146FF)),
                    )
                  : null,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (channelPointsHighlight)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.highlight_alt_rounded,
                    size: 14,
                    color: Color(0xFFBF94FF),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      l10n.highlightedMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: chatReadableStyle.merge(
                        const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFBF94FF),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
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
            gigantifyEmote:
                message.messageType == 'power_ups_gigantified_emote',
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
