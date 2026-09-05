import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';

/// Inserts the emote code at the selection, with Twitch token boundaries.
/// Returns null if the complete emote would exceed the message limit.
TextEditingValue? insertChatEmote(TextEditingValue value, String name) {
  final selection = value.selection;
  final valid = selection.isValid && selection.end <= value.text.length;
  final start = valid ? selection.start : value.text.length;
  final end = valid ? selection.end : value.text.length;
  final before = value.text.substring(0, start);
  final after = value.text.substring(end);
  final prefix = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before)
      ? ' '
      : '';
  final suffix = after.isEmpty || !RegExp(r'^\s').hasMatch(after) ? ' ' : '';
  final insertion = '$prefix$name$suffix';
  final text = '$before$insertion$after';
  if (text.characters.length > 500) return null;
  return TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: start + insertion.length),
  );
}

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.error,
    required this.emotesOpen,
    required this.tapGroup,
    required this.onSend,
    required this.onSignOut,
    required this.onToggleEmotes,
    required this.onCloseEmotes,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final String? error;
  final bool emotesOpen;
  final Object tapGroup;
  final VoidCallback onSend;
  final VoidCallback onSignOut;
  final VoidCallback onToggleEmotes;
  final VoidCallback onCloseEmotes;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  bool _hovering = false;

  void _submit() {
    if (!widget.sending &&
        widget.controller.text.trim().isNotEmpty &&
        widget.controller.value.composing.isCollapsed) {
      widget.onSend();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TapRegion(
      groupId: widget.tapGroup,
      onTapOutside: (_) => widget.onCloseEmotes(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
        color: BackgroundOpacity.colorOf(context, const Color(0xF21F1F23)),
        child: ListenableBuilder(
          listenable: Listenable.merge([widget.controller, widget.focusNode]),
          builder: (context, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    widget.error!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFFF7676),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ChatIconButton(
                    label: l10n.signOutOfTwitch,
                    icon: Icons.logout_rounded,
                    onPressed: widget.onSignOut,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _hovering = true),
                      onExit: (_) => setState(() => _hovering = false),
                      child: Container(
                        key: const ValueKey('chat-input-frame'),
                        constraints: const BoxConstraints(minHeight: 40),
                        decoration: BoxDecoration(
                          color: BackgroundOpacity.colorOf(
                            context,
                            const Color(0xFF18181B),
                          ),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            width: 2,
                            color: widget.focusNode.hasFocus
                                ? const Color(0xFF9146FF)
                                : _hovering
                                ? const Color(0xFF777780)
                                : const Color(0xFF48484F),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 2, 8),
                                child: CallbackShortcuts(
                                  bindings: {
                                    const SingleActivator(
                                      LogicalKeyboardKey.enter,
                                    ): _submit,
                                    const SingleActivator(
                                      LogicalKeyboardKey.numpadEnter,
                                    ): _submit,
                                    const SingleActivator(
                                      LogicalKeyboardKey.escape,
                                    ): widget.onCloseEmotes,
                                  },
                                  child: TextField(
                                    key: const ValueKey('chat-message-input'),
                                    groupId: widget.tapGroup,
                                    controller: widget.controller,
                                    focusNode: widget.focusNode,
                                    minLines: 1,
                                    maxLines: 5,
                                    inputFormatters: [
                                      LengthLimitingTextInputFormatter(500),
                                    ],
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    cursorColor: const Color(0xFFBF94FF),
                                    style: const TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFFEFEFF1),
                                    ),
                                    decoration: InputDecoration(
                                      isCollapsed: true,
                                      border: InputBorder.none,
                                      isDense: true,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      hintText: l10n.sendMessageHint,
                                      hintStyle: const TextStyle(
                                        color: Color(0xFFADADB8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ChatIconButton(
                              label: l10n.emotes,
                              icon: Icons.sentiment_satisfied_alt_outlined,
                              selected: widget.emotesOpen,
                              onPressed: widget.onToggleEmotes,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  ChatIconButton(
                    label: l10n.send,
                    icon: Icons.send_rounded,
                    accent: true,
                    busy: widget.sending,
                    onPressed:
                        widget.sending || widget.controller.text.trim().isEmpty
                        ? null
                        : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatIconButton extends StatelessWidget {
  const ChatIconButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.accent = false,
    this.selected = false,
    this.busy = false,
    this.showTooltip = true,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool accent;
  final bool selected;
  final bool busy;
  final bool showTooltip;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 36,
    child: IconButton(
      tooltip: showTooltip ? label : null,
      onPressed: onPressed,
      style: ButtonStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        splashFactory: NoSplash.splashFactory,
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? const Color(0xFF85858F)
              : const Color(0xFFEFEFF1),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return const Color(0xFF29292E);
          }
          if (accent) {
            return states.contains(WidgetState.hovered)
                ? const Color(0xFF772CE8)
                : const Color(0xFF9146FF);
          }
          if (selected || states.contains(WidgetState.hovered)) {
            return const Color(0xFF35353D);
          }
          return Colors.transparent;
        }),
      ),
      icon: busy
          ? const SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFBF94FF),
              ),
            )
          : Icon(icon, size: 19, semanticLabel: showTooltip ? null : label),
    ),
  );
}
