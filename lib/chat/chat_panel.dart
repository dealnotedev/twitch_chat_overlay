import 'dart:async';

import 'package:twitch_chat_overlay/chat/chat_font_weight.dart';

import 'package:twitch_chat_overlay/chat/chat_font_size.dart';

import 'package:twitch_chat_overlay/chat/viewer_count.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:observable_state/observable_state.dart';
import 'package:twitch_chat_overlay/chat/chat_composer.dart';
import 'package:twitch_chat_overlay/chat/chat_panel_view_model.dart';
import 'package:twitch_chat_overlay/chat/chat_message_actions.dart';
import 'package:twitch_chat_overlay/chat/chat_emote_picker.dart';
import 'package:twitch_chat_overlay/chat/chat_emote.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';
import 'package:twitch_chat_overlay/chat/chat_emote_scope.dart';
import 'package:twitch_chat_overlay/chat/chat_message_entrance.dart';
import 'package:twitch_chat_overlay/chat/chat_message_retention.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/chat/streamer_mention.dart';
import 'package:twitch_chat_overlay/chat/chat_message_content.dart';
import 'package:twitch_chat_overlay/chat/chat_event_card.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';
import 'package:twitch_chat_overlay/twitch/twitch_auth.dart';
import 'package:twitch_chat_overlay/twitch/twitch_badges.dart';
import 'package:twitch_chat_overlay/twitch/twitch_chat_session.dart';
import 'package:twitch_chat_overlay/twitch/twitch_helix_client.dart';

typedef _ChatAccessState = ({
  TwitchAuthState auth,
  bool rewardSubscriptionFailed,
});
typedef _ChatContentState = ({
  ChatConnectionStatus status,
  String? broadcasterId,
  TwitchBadges badges,
  EmoteCatalog emoteCatalog,
});
typedef _ChatStatusState = ({
  ChatConnectionStatus status,
  int? viewerCount,
  bool streamOffline,
});

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    required this.authSource,
    required this.chatSource,
    required this.interactive,
    required this.onSignIn,
    required this.onSignOut,
    required this.onSend,
    required this.onLoadEmotes,
    this.onDeleteMessage,
    this.messageFooter,
    this.showViewerCount = true,
    this.showConnectionIndicator = true,
    this.chatFontSize = ChatFontSize.defaultSize,
    this.chatFontWeight = ChatFontWeight.defaultWeight,
    this.messageLifetimeMinutes = ChatMessageRetention.defaultMinutes,
    super.key,
  });

  final Widget? messageFooter;
  final double chatFontSize;
  final int chatFontWeight;
  final StreamWithInitial<TwitchAuthState> authSource;
  final StreamWithInitial<ChatState> chatSource;
  final int messageLifetimeMinutes;
  final bool showViewerCount;
  final bool showConnectionIndicator;
  final bool interactive;
  final Future<void> Function() onSignIn;
  final Future<void> Function() onSignOut;
  final Future<SendChatResult> Function(String message, {String? replyTo})
  onSend;
  final Future<void> Function(String messageId)? onDeleteMessage;
  final Future<List<ChatEmote>> Function({bool refresh}) onLoadEmotes;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocus = FocusNode();
  late final ChatPanelViewModel _viewModel;
  late final StreamWithInitial<_ChatAccessState> _access;
  late final StreamWithInitial<_ChatContentState> _content;
  late final StreamWithInitial<_ChatStatusState> _status;
  final Object _emoteTapGroup = Object();

  ChatPanelInput get _input => ChatPanelInput(
    auth: widget.authSource.current,
    chat: widget.chatSource.current,
    interactive: widget.interactive,
    messageLifetimeMinutes: widget.messageLifetimeMinutes,
    send: widget.onSend,
    loadEmotes: widget.onLoadEmotes,
    deleteMessage: widget.onDeleteMessage,
  );

  @override
  void initState() {
    super.initState();
    _viewModel = ChatPanelViewModel(
      _input,
      authSource: widget.authSource,
      chatSource: widget.chatSource,
    );
    _access = _viewModel.session.select(
      (session) => (
        auth: session.auth,
        rewardSubscriptionFailed: session.rewardSubscriptionFailed,
      ),
    );
    _content = _viewModel.session.select(
      (session) => (
        status: session.status,
        broadcasterId: session.broadcasterId,
        badges: session.badges,
        emoteCatalog: session.emoteCatalog,
      ),
    );
    _status = _viewModel.session.select(
      (session) => (
        status: session.status,
        viewerCount: session.viewerCount,
        streamOffline: session.streamOffline,
      ),
    );
  }

  @override
  void didUpdateWidget(ChatPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _viewModel.update(
      _input,
      authSource: widget.authSource,
      chatSource: widget.chatSource,
    );
  }

  @override
  void dispose() {
    _viewModel.dispose();
    _messageController.dispose();
    _messageFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<_ChatAccessState>(
    initialData: _access.current,
    stream: _access.changes,
    builder: (context, snapshot) => _buildPanel(context, snapshot.requireData),
  );

  Widget _buildPanel(BuildContext context, _ChatAccessState viewSession) {
    final l10n = AppLocalizations.of(context);
    final body = switch (viewSession.auth.status) {
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
        error: _authError(l10n, viewSession.auth),
        onSignIn: widget.onSignIn,
      ),
      TwitchAuthStatus.signedIn => _connectedBody(l10n),
    };

    return Column(
      children: [
        if (viewSession.auth.status == TwitchAuthStatus.signedIn &&
            viewSession.rewardSubscriptionFailed)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              l10n.rewardSubscriptionFailed,
              style: const TextStyle(
                shadows: chatTextShadows,
                fontSize: 11,
                color: Color(0xFFFFB31A),
              ),
            ),
          ),
        Expanded(
          child: DefaultTextStyle.merge(
            style: chatReadableStyle,
            child: LayoutBuilder(
              builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(child: body),
                  StreamBuilder<ChatEditorState>(
                    initialData: _viewModel.editor.current,
                    stream: _viewModel.editor.changes,
                    builder: (context, snapshot) {
                      final emotes = snapshot.requireData.emotes;
                      if (!emotes.open ||
                          emotes.request == null ||
                          !widget.interactive ||
                          viewSession.auth.status !=
                              TwitchAuthStatus.signedIn) {
                        return const SizedBox.shrink();
                      }
                      return Positioned(
                        left: 8,
                        right: 8,
                        bottom: 8,
                        height: (constraints.maxHeight - 16).clamp(0.0, 280.0),
                        child: ChatEmotePicker(
                          emotes: emotes.request!,
                          tapGroup: _emoteTapGroup,
                          onSelected: _insertEmote,
                          onReload: _viewModel.reloadEmotes,
                          onClose: () {
                            _viewModel.closeEmotes();
                            _messageFocus.requestFocus();
                          },
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        ?widget.messageFooter,
        if (widget.interactive)
          StreamBuilder<ChatDeletionsState>(
            initialData: _viewModel.deletions.current,
            stream: _viewModel.deletions.changes,
            builder: (context, snapshot) {
              final error = snapshot.requireData.error;
              if (error == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _chatPanelError(l10n, error)!,
                            style: const TextStyle(
                              shadows: chatTextShadows,
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
                          onPressed: _viewModel.dismissDeleteError,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        if (viewSession.auth.status == TwitchAuthStatus.signedIn &&
            widget.interactive)
          StreamBuilder<ChatEditorState>(
            initialData: _viewModel.editor.current,
            stream: _viewModel.editor.changes,
            builder: (context, snapshot) => ChatComposer(
              controller: _messageController,
              focusNode: _messageFocus,
              sending: snapshot.requireData.sending,
              error: _chatPanelError(l10n, snapshot.requireData.sendError),
              emotesOpen: snapshot.requireData.emotes.open,
              tapGroup: _emoteTapGroup,
              onSend: _send,
              onSignOut: () => unawaited(widget.onSignOut()),
              onToggleEmotes: _viewModel.toggleEmotes,
              onCloseEmotes: _viewModel.closeEmotes,
              replyTo: snapshot.requireData.replyTo,
              onCancelReply: _cancelReply,
            ),
          ),
      ],
    );
  }

  Widget _connectedBody(AppLocalizations l10n) =>
      StreamBuilder<_ChatContentState>(
        initialData: _content.current,
        stream: _content.changes,
        builder: (context, contentSnapshot) => ChatEmoteScope(
          catalog: contentSnapshot.requireData.emoteCatalog,
          child: StreamBuilder<ChatTimelineState>(
            initialData: _viewModel.timeline.current,
            stream: _viewModel.timeline.changes,
            builder: (context, snapshot) => _buildMessages(
              context,
              l10n,
              snapshot.requireData,
              contentSnapshot.requireData,
            ),
          ),
        ),
      );

  Widget _buildMessages(
    BuildContext context,
    AppLocalizations l10n,
    ChatTimelineState timeline,
    _ChatContentState viewSession,
  ) {
    final state = timeline.messages;
    final recentItems = state.items;
    if (recentItems.isEmpty &&
        viewSession.status != ChatConnectionStatus.connected) {
      return _CenteredStatus(
        text: switch (viewSession.status) {
          ChatConnectionStatus.connecting => l10n.connectingEventSub,
          ChatConnectionStatus.reconnecting => l10n.reconnectingChat,
          ChatConnectionStatus.failure => l10n.chatConnectionFailed,
          _ => l10n.waitingForConnection,
        },
        progress:
            viewSession.status == ChatConnectionStatus.connecting ||
            viewSession.status == ChatConnectionStatus.reconnecting,
      );
    }

    // Redemption events have no color; reuse the latest chat color by user ID.
    final userColors = {
      for (final entry in state.userColors.entries)
        entry.key: entry.value == null || entry.value!.isEmpty
            ? null
            : _parseColor(entry.value),
    };
    final items = recentItems;
    final broadcasterId = viewSession.broadcasterId;
    final token = _access.current.auth.token;
    final mentionTarget = broadcasterId == null
        ? null
        : StreamerMentionTarget(
            userId: broadcasterId,
            login: token?.userId == broadcasterId ? token?.userLogin : null,
          );
    final itemIndices = {
      for (var index = 0; index < items.length; index++)
        items[index].id: items.length - 1 - index,
    };

    return Stack(
      children: [
        // Scale only timeline content, leaving surrounding controls unchanged.
        MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(
              ChatFontSize.normalize(widget.chatFontSize) /
                  ChatFontSize.defaultSize,
            ),
          ),
          child: ChatFontWeight(
            value: widget.chatFontWeight,
            child: Builder(
              builder: (context) => DefaultTextStyle.merge(
                style: TextStyle(
                  shadows: chatTextShadows,
                  fontWeight: ChatFontWeight.resolve(context),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: items.length,
                  reverse: true,
                  findChildIndexCallback: (key) =>
                      itemIndices[(key as ValueKey<String>).value],
                  itemBuilder: (context, index) {
                    final item = items[items.length - 1 - index];
                    return RepaintBoundary(
                      key: ValueKey(item.id),
                      child: IgnorePointer(
                        ignoring: state.fadingIds.contains(item.id),
                        child: AnimatedOpacity(
                          key: ValueKey('message-fade-${item.id}'),
                          opacity: state.fadingIds.contains(item.id) ? 0 : 1,
                          duration: MediaQuery.disableAnimationsOf(context)
                              ? Duration.zero
                              : ChatMessageRetention.fadeDuration,
                          curve: Curves.easeInOut,
                          child: ChatMessageEntrance(
                            elapsed: _viewModel.entranceElapsed(item.id),
                            child: StreamBuilder<ChatDeletionsState>(
                              initialData: _viewModel.deletions.current,
                              stream: _viewModel.deletions.changes,
                              builder: (context, snapshot) => _ChatItemView(
                                item: item,
                                canCopy: widget.interactive,
                                badges: viewSession.badges,
                                mentionTarget: mentionTarget,
                                userColor: switch (item) {
                                  ChatRewardRedemption(:final userId) =>
                                    userColors[userId],
                                  ChatPowerUp(:final userId) =>
                                    userColors[userId],
                                  _ => null,
                                },
                                onReply:
                                    widget.interactive &&
                                        _access.current.auth.status ==
                                            TwitchAuthStatus.signedIn
                                    ? _startReply
                                    : null,
                                onDelete:
                                    widget.interactive &&
                                        item is ChatUserMessage &&
                                        _viewModel.canDelete(item)
                                    ? (message) => unawaited(
                                        _viewModel.deleteMessage(message),
                                      )
                                    : null,
                                deleting: snapshot.requireData.isDeleting(
                                  item.id,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        if (items.isEmpty &&
            (widget.interactive || timeline.startupHint.visible))
          Positioned.fill(
            child: AnimatedOpacity(
              key: const ValueKey('startup-chat-hint'),
              opacity: !widget.interactive && timeline.startupHint.fading
                  ? 0
                  : 1,
              duration:
                  widget.interactive || MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : ChatPanelViewModel.startupHintFadeDuration,
              curve: Curves.easeInOut,
              child: _CenteredStatus(
                text: l10n.noChatMessages,
                hint: widget.interactive ? null : l10n.openControlsShortcut,
              ),
            ),
          ),
        if (!widget.interactive &&
            (widget.showViewerCount || widget.showConnectionIndicator))
          StreamBuilder<_ChatStatusState>(
            initialData: _status.current,
            stream: _status.changes,
            builder: (context, snapshot) => Positioned(
              top: 8,
              left: 12,
              right: 8,
              child: IgnorePointer(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Row(
                    key: const ValueKey('chat-status-row'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.showViewerCount)
                        Flexible(
                          child: ViewerCount(
                            count: snapshot.requireData.viewerCount,
                            offline: snapshot.requireData.streamOffline,
                          ),
                        ),
                      if (widget.showViewerCount &&
                          widget.showConnectionIndicator)
                        const Gap(8),
                      if (widget.showConnectionIndicator)
                        Flexible(
                          child: _ChatConnectionIndicator(
                            status: snapshot.requireData.status,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else if (widget.interactive &&
            viewSession.status == ChatConnectionStatus.reconnecting)
          Positioned(
            top: 5,
            right: 8,
            child: _ConnectionPill(text: l10n.reconnecting),
          ),
      ],
    );
  }

  void _insertEmote(ChatEmote emote) {
    final value = insertChatEmote(_messageController.value, emote.name);
    _viewModel.emoteInserted(accepted: value != null);
    if (value == null) return;
    _messageController.value = value;
    _messageFocus.requestFocus();
  }

  void _startReply(ChatUserMessage message) {
    _viewModel.startReply(message);
    _messageFocus.requestFocus();
  }

  void _cancelReply() {
    _viewModel.cancelReply();
    _messageFocus.requestFocus();
  }

  Future<void> _send() async {
    final draft = _messageController.text;
    final sent = await _viewModel.send(draft);
    if (!mounted || !sent) return;
    if (_messageController.text == draft) _messageController.clear();
    _messageFocus.requestFocus();
  }
}

String? _chatPanelError(AppLocalizations strings, ChatPanelError? error) =>
    error == null
    ? null
    : switch (error.failure) {
        ChatPanelFailure.messageTooLong => strings.messageTooLong,
        ChatPanelFailure.replyUnavailable => strings.replyUnavailable,
        ChatPanelFailure.messageRejected =>
          error.details ?? strings.messageRejected,
        ChatPanelFailure.deleteNotAllowed => strings.deleteNotAllowed,
        ChatPanelFailure.messageUnavailable => strings.messageUnavailable,
        ChatPanelFailure.deleteFailed => strings.deleteFailed,
        ChatPanelFailure.sendNotAllowed => strings.sendNotAllowed,
        ChatPanelFailure.network => strings.sendNetworkError,
        ChatPanelFailure.rateLimited => strings.sendRateLimited,
        ChatPanelFailure.sessionChanged => strings.chatSessionChanged,
        ChatPanelFailure.sendFailed => strings.sendFailed,
      };

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
              shadows: chatTextShadows,
              size: 32,
              color: Color(0xFFBF94FF),
            ),
            const Gap(9),
            Text(
              error ?? l10n.connectTwitchDescription,
              textAlign: TextAlign.center,
              style: const TextStyle(
                shadows: chatTextShadows,
                fontSize: 12.5,
                color: Colors.white,
              ),
            ),
            const Gap(12),
            if (interactive)
              _TwitchSignInButton(
                onPressed: () => unawaited(onSignIn()),
                label: l10n.signInWithTwitch,
              )
            else
              Text(
                l10n.openControlsShortcut,
                style: const TextStyle(
                  shadows: chatTextShadows,
                  fontSize: 11,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TwitchSignInButton extends StatelessWidget {
  const _TwitchSignInButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        side: WidgetStateProperty.resolveWith((states) {
          final focused = states.contains(WidgetState.focused);
          return BorderSide(
            color: focused || states.contains(WidgetState.hovered)
                ? const Color(0xFFBF94FF)
                : const Color(0xFF9146FF),
            width: focused ? 2 : 1,
          );
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF472675);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return const Color(0xFF30213F);
          }
          return const Color(0xF21F1F23);
        }),
        foregroundColor: const WidgetStatePropertyAll(Colors.white),
        iconColor: const WidgetStatePropertyAll(Color(0xFFBF94FF)),
        iconSize: const WidgetStatePropertyAll(17),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(
            shadows: chatTextShadows,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        animationDuration: const Duration(milliseconds: 120),
      ),
      icon: const Icon(Icons.login_rounded),
      label: Text(label, textAlign: TextAlign.center),
    );
  }
}

class _CenteredStatus extends StatelessWidget {
  const _CenteredStatus({required this.text, this.progress = false, this.hint});

  final String text;
  final bool progress;
  final String? hint;

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
              const Gap(10),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                shadows: chatTextShadows,
                fontSize: 12,
                color: Colors.white,
              ),
            ),
            if (hint != null) ...[
              const Gap(12),
              Text(
                hint!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  shadows: chatTextShadows,
                  fontSize: 11,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatConnectionIndicator extends StatelessWidget {
  const _ChatConnectionIndicator({required this.status});

  final ChatConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = switch (status) {
      ChatConnectionStatus.connected => l10n.chatConnected,
      ChatConnectionStatus.connecting => l10n.connectingEventSub,
      ChatConnectionStatus.reconnecting => l10n.reconnecting,
      ChatConnectionStatus.failure => l10n.chatConnectionFailed,
      ChatConnectionStatus.idle => l10n.waitingForConnection,
    };
    return Semantics(
      label: text,
      liveRegion: true,
      excludeSemantics: true,
      child: status == ChatConnectionStatus.connected
          ? Container(
              key: const ValueKey('chat-connected-dot'),
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF52D273),
                shape: BoxShape.circle,
              ),
            )
          : _ConnectionPill(
              text: text,
              color: switch (status) {
                ChatConnectionStatus.failure => const Color(0xFFFF7676),
                ChatConnectionStatus.idle => Colors.white,
                _ => const Color(0xFFFFB31A),
              },
            ),
    );
  }
}

class _ConnectionPill extends StatelessWidget {
  const _ConnectionPill({
    required this.text,
    this.color = const Color(0xFFFFB31A),
  });

  final String text;
  final Color color;

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
          style: TextStyle(shadows: chatTextShadows, fontSize: 9, color: color),
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
    this.mentionTarget,
  });

  final ChatItem item;
  final TwitchBadges badges;
  final Color? userColor;
  final bool canCopy;
  final ValueChanged<ChatUserMessage>? onReply;
  final ValueChanged<ChatUserMessage>? onDelete;
  final bool deleting;
  final StreamerMentionTarget? mentionTarget;

  @override
  Widget build(BuildContext context) {
    return switch (item) {
      ChatRewardRedemption redemption => RewardRedemptionCard(
        redemption: redemption,
        userColor: userColor,
      ),
      ChatPowerUp powerUp => PowerUpCard(
        powerUp: powerUp,
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
        child: _UserMessageView(
          message: message,
          badges: badges,
          mentionTarget: mentionTarget,
        ),
      ),
      ChatNotice notice => _NoticeView(notice: notice, badges: badges),
      ChatSubscriptionRevoked revoked => _SubscriptionRevokedView(
        revoked: revoked,
      ),
    };
  }
}

class _UserMessageView extends StatelessWidget {
  const _UserMessageView({
    required this.message,
    required this.badges,
    this.mentionTarget,
  });

  final ChatUserMessage message;
  final TwitchBadges badges;
  final StreamerMentionTarget? mentionTarget;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final powerUpType = switch (message.messageType) {
      'power_ups_gigantified_emote' => ChatPowerUpType.gigantifyEmote,
      'power_ups_message_effect' => ChatPowerUpType.messageEffect,
      _ => null,
    };
    final highlighted =
        message.messageType != 'text' &&
        message.messageType != 'power_ups_gigantified_emote';
    final channelPointsHighlight =
        message.messageType == 'channel_points_highlighted';
    final mentioned = mentionTarget?.isAddressedBy(message) ?? false;
    return Container(
      key: channelPointsHighlight
          ? ValueKey('highlighted-message-${message.id}')
          : mentioned
          ? ValueKey('streamer-mention-${message.id}')
          : null,
      margin: EdgeInsets.symmetric(vertical: channelPointsHighlight ? 5 : 2),
      padding: channelPointsHighlight
          ? const EdgeInsets.fromLTRB(10, 8, 10, 9)
          : highlighted || mentioned
          ? const EdgeInsets.all(7)
          : const EdgeInsets.all(3),
      decoration: highlighted || mentioned
          ? BoxDecoration(
              color: BackgroundOpacity.colorOf(
                context,
                const Color(0x269146FF),
              ),
              gradient: mentioned && !channelPointsHighlight
                  ? LinearGradient(
                      colors: [
                        BackgroundOpacity.colorOf(
                          context,
                          const Color(0x559146FF),
                        ),
                        BackgroundOpacity.colorOf(
                          context,
                          const Color(0x149146FF),
                        ),
                      ],
                    )
                  : null,
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
                  : mentioned
                  ? const Border(
                      left: BorderSide(color: Color(0xFFBF94FF), width: 3),
                    )
                  : null,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (powerUpType != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: PowerUpLabel(type: powerUpType),
            ),
          if (channelPointsHighlight)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.highlight_alt_rounded,
                    shadows: chatTextShadows,
                    size: 14,
                    color: Color(0xFFBF94FF),
                  ),
                  const Gap(6),
                  Expanded(
                    child: Text(
                      l10n.highlightedMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ChatFontWeight.readableStyleOf(context).merge(
                        TextStyle(
                          shadows: chatTextShadows,
                          fontSize: 11,
                          fontWeight: ChatFontWeight.resolve(
                            context,
                            FontWeight.w600,
                          ),
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
              child: Text.rich(
                _replyContextSpan(context, l10n, reply, mentionTarget),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  shadows: chatTextShadows,
                  fontSize: 10.5,
                  color: Colors.white,
                ),
              ),
            ),
          ChatMessageContent(
            fragments: message.displayFragments,
            mentionTarget: mentioned ? mentionTarget : null,
            gigantifyEmote:
                message.messageType == 'power_ups_gigantified_emote',
            prefix: [
              if (mentioned)
                TextSpan(
                  text: '@ ',
                  style: TextStyle(
                    shadows: chatTextShadows,
                    color: Color(0xFFBF94FF),
                    fontWeight: ChatFontWeight.resolve(
                      context,
                      FontWeight.w700,
                    ),
                  ),
                ),
              for (final badge in message.badges) _badgeSpan(badge, badges),
              TextSpan(
                text: '${message.userName}: ',
                style: TextStyle(
                  shadows: chatTextShadows,
                  color: _parseColor(message.color),
                  fontWeight: ChatFontWeight.resolve(context, FontWeight.w700),
                ),
              ),
            ],
            style: const TextStyle(
              shadows: chatTextShadows,
              fontSize: 13.5,
              height: 1.32,
            ),
          ),
          if (message.sourceChannel case final source?)
            Text(
              l10n.sharedChatOrigin(source),
              style: const TextStyle(
                shadows: chatTextShadows,
                fontSize: 9,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}

InlineSpan _replyContextSpan(
  BuildContext context,
  AppLocalizations l10n,
  ChatReply reply,
  StreamerMentionTarget? mentionTarget,
) {
  final text = l10n.replyContext(reply.parentUserName, reply.parentMessageBody);
  final start = text.indexOf(reply.parentUserName);
  if (!(mentionTarget?.matchesReply(reply) ?? false) ||
      reply.parentUserName.isEmpty ||
      start < 0) {
    return TextSpan(text: text);
  }
  return TextSpan(
    children: [
      TextSpan(text: text.substring(0, start)),
      TextSpan(
        text: reply.parentUserName,
        style: ChatFontWeight.mentionStyleOf(context),
      ),
      TextSpan(text: text.substring(start + reply.parentUserName.length)),
    ],
  );
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
            style: TextStyle(
              shadows: chatTextShadows,
              fontSize: 12,
              fontWeight: ChatFontWeight.resolve(context, FontWeight.w700),
            ),
          ),
          if (notice.fragments.isNotEmpty) ...[
            const Gap(3),
            ChatMessageContent(
              fragments: notice.fragments,
              prefix: [
                for (final badge in notice.badges) _badgeSpan(badge, badges),
                if (notice.userName case final name?)
                  TextSpan(
                    text: '$name: ',
                    style: TextStyle(
                      shadows: chatTextShadows,
                      color: _parseColor(notice.color),
                      fontWeight: ChatFontWeight.resolve(
                        context,
                        FontWeight.w700,
                      ),
                    ),
                  ),
              ],
              style: const TextStyle(shadows: chatTextShadows, fontSize: 12.5),
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
        style: const TextStyle(
          shadows: chatTextShadows,
          fontSize: 10.5,
          color: Color(0xFFFF7676),
        ),
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
