import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_composer.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';

/// Actions float over the message without changing its layout or hit area.
class ChatMessageActions extends StatefulWidget {
  const ChatMessageActions({
    required this.child,
    required this.messageId,
    this.onReply,
    this.onDelete,
    this.deleting = false,
    super.key,
  });
  final Widget child;
  final String messageId;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;
  final bool deleting;

  @override
  State<ChatMessageActions> createState() => _ChatMessageActionsState();
}

class _ChatMessageActionsState extends State<ChatMessageActions> {
  bool _hovering = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onReply == null && widget.onDelete == null) return widget.child;
    final l10n = AppLocalizations.of(context);
    final visible = _hovering || _focused || widget.deleting;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Focus(
        canRequestFocus: false,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned(
              top: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: visible ? 1 : 0,
                duration: const Duration(milliseconds: 100),
                child: IgnorePointer(
                  ignoring: !visible,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xF21F1F23),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChatIconButton(
                          key: ValueKey('reply-${widget.messageId}'),
                          label: l10n.replyToMessage,
                          icon: Icons.reply_rounded,
                          size: 26,
                          iconSize: 17,
                          onPressed: widget.onReply,
                        ),
                        if (widget.onDelete != null)
                          ChatIconButton(
                            key: ValueKey('delete-${widget.messageId}'),
                            label: l10n.deleteMessage,
                            icon: Icons.delete_outline_rounded,
                            size: 26,
                            iconSize: 16,
                            destructive: true,
                            busy: widget.deleting,
                            onPressed: widget.deleting ? null : widget.onDelete,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
