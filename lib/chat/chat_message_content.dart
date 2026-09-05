import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';

/// Keeps inline text/emotes in order and gives each GIF its own media block.
class ChatMessageContent extends StatelessWidget {
  const ChatMessageContent({
    required this.fragments,
    required this.style,
    this.prefix = const [],
    super.key,
  });

  final List<ChatFragment> fragments;
  final TextStyle style;
  final List<InlineSpan> prefix;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var spans = <InlineSpan>[...prefix];
    void flushText() {
      if (spans.isEmpty) return;
      children.add(Text.rich(TextSpan(children: spans), style: style));
      spans = [];
    }

    for (final fragment in fragments) {
      if (fragment is ChatGifFragment) {
        flushText();
        children.add(ChatGifImage(fragment: fragment));
      } else {
        spans.add(_fragmentSpan(fragment));
      }
    }
    flushText();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class ChatGifImage extends StatelessWidget {
  const ChatGifImage({required this.fragment, super.key});

  final ChatGifFragment fragment;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(240.0, constraints.maxWidth);
        // Reserve space before loading so animations do not move the timeline.
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Semantics(
              label: fragment.text.isEmpty ? 'GIF' : fragment.text,
              image: true,
              child: CachedNetworkImage(
                imageUrl: fragment.url,
                width: width,
                height: width * 2 / 3,
                fit: BoxFit.contain,
                fadeInDuration: Duration.zero,
                placeholder: (_, _) => ColoredBox(
                  color: BackgroundOpacity.colorOf(
                    context,
                    const Color(0x331F1F23),
                  ),
                  child: Center(
                    child: Text(
                      l10n.gifLoading,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFADADB8),
                      ),
                    ),
                  ),
                ),
                errorWidget: (_, _, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      fragment.text.isEmpty
                          ? l10n.gifUnavailable
                          : '${l10n.gifUnavailable}\n${fragment.text}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFADADB8),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

InlineSpan _fragmentSpan(ChatFragment fragment) {
  return switch (fragment) {
    ChatTextFragment() ||
    ChatUnknownFragment() => TextSpan(text: fragment.text),
    ChatMentionFragment() => TextSpan(
      text: fragment.text,
      style: const TextStyle(
        color: Color(0xFFBF94FF),
        fontWeight: FontWeight.w600,
      ),
    ),
    ChatCheermoteFragment() => TextSpan(
      text: fragment.text,
      style: const TextStyle(
        color: Color(0xFFFFC83D),
        fontWeight: FontWeight.w700,
      ),
    ),
    ChatEmoteFragment() => _emoteSpan(fragment),
    ChatGifFragment() => throw StateError('GIFs are rendered as media blocks'),
  };
}

InlineSpan _emoteSpan(ChatEmoteFragment fragment) => WidgetSpan(
  alignment: PlaceholderAlignment.middle,
  child: Semantics(
    label: fragment.text,
    image: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: CachedNetworkImage(
        imageUrl: fragment.imageUrl,
        width: 28,
        height: 28,
        fit: BoxFit.contain,
        errorWidget: (_, _, _) => Text(fragment.text),
      ),
    ),
  ),
);
