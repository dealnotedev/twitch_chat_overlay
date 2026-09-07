import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_item.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';
import 'package:twitch_chat_overlay/chat/chat_gif_provider.dart';
import 'package:twitch_chat_overlay/chat/gif_playback.dart';
import 'package:twitch_chat_overlay/chat/streamer_mention.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/overlay/background_opacity.dart';

/// Keeps inline content in order, with media blocks for GIFs and giant emotes.
class ChatMessageContent extends StatelessWidget {
  const ChatMessageContent({
    required this.fragments,
    required this.style,
    this.prefix = const [],
    this.gigantifyEmote = false,
    this.mentionTarget,
    super.key,
  });

  final List<ChatFragment> fragments;
  final TextStyle style;
  final List<InlineSpan> prefix;
  final bool gigantifyEmote;
  final StreamerMentionTarget? mentionTarget;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    var spans = <InlineSpan>[...prefix];
    void flushText() {
      if (spans.isEmpty) return;
      children.add(
        Text.rich(
          TextSpan(children: spans),
          style: chatReadableStyle.merge(style),
        ),
      );
      spans = [];
    }

    // EventSub flags the message; the last emote occurrence is the target.
    final giantIndex = gigantifyEmote
        ? fragments.lastIndexWhere((fragment) => fragment is ChatEmoteFragment)
        : -1;
    for (var index = 0; index < fragments.length; index++) {
      if (index == giantIndex) continue;
      final fragment = fragments[index];
      if (fragment is ChatGifFragment) {
        flushText();
        children.add(ChatGifImage(fragment: fragment));
      } else {
        spans.add(_fragmentSpan(fragment, mentionTarget));
      }
    }
    flushText();
    if (giantIndex != -1) {
      children.add(
        ChatGiantEmoteImage(
          fragment: fragments[giantIndex] as ChatEmoteFragment,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class ChatGiantEmoteImage extends StatelessWidget {
  const ChatGiantEmoteImage({required this.fragment, super.key});

  final ChatEmoteFragment fragment;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = math.min(112.0, constraints.maxWidth);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Semantics(
          label: fragment.text,
          image: true,
          child: SizedBox.square(
            dimension: size,
            child: CachedNetworkImage(
              imageUrl: fragment.giantImageUrl,
              fit: BoxFit.contain,
              fadeInDuration: Duration.zero,
              placeholder: (_, _) => const SizedBox.expand(),
              errorWidget: (_, _, _) => Center(
                child: Text(
                  fragment.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: chatReadableStyle.merge(
                    const TextStyle(fontSize: 13.5),
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

class ChatGifImage extends StatefulWidget {
  const ChatGifImage({required this.fragment, super.key});

  final ChatGifFragment fragment;

  @override
  State<ChatGifImage> createState() => _ChatGifImageState();
}

class _ChatGifImageState extends State<ChatGifImage>
    with AutomaticKeepAliveClientMixin {
  late ChatGifProvider _image;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final count = GifPlayback.countOf(context);
    if (_initialized && _image.playCount == count) return;
    if (_initialized) _image.evict();
    _image = ChatGifProvider(widget.fragment.url, playCount: count);
    _initialized = true;
    updateKeepAlive();
  }

  bool _initialized = false;

  // Preserve finite playback when ListView moves this message offscreen. Removing
  // the message from the list still disposes its row and last frame.
  @override
  bool get wantKeepAlive => _initialized && _image.playCount > 0;

  @override
  void didUpdateWidget(ChatGifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fragment.url != widget.fragment.url) {
      _image.evict();
      _image = ChatGifProvider(
        widget.fragment.url,
        playCount: _image.playCount,
      );
    }
  }

  @override
  void dispose() {
    _image.evict();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fragment = widget.fragment;
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
              child: SizedBox(
                width: width,
                height: width * 2 / 3,
                child: Image(
                  image: _image,
                  fit: BoxFit.contain,
                  frameBuilder: (_, child, frame, _) => frame != null
                      ? child
                      : ColoredBox(
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
                  errorBuilder: (_, _, _) => Center(
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
          ),
        );
      },
    );
  }
}

InlineSpan _fragmentSpan(
  ChatFragment fragment,
  StreamerMentionTarget? mentionTarget,
) {
  final pattern = mentionTarget?.textPattern;
  if (fragment is ChatTextFragment && pattern != null) {
    final spans = <InlineSpan>[];
    var end = 0;
    for (final match in pattern.allMatches(fragment.text)) {
      spans.add(TextSpan(text: fragment.text.substring(end, match.start)));
      spans.add(TextSpan(text: match.group(0), style: streamerMentionStyle));
      end = match.end;
    }
    spans.add(TextSpan(text: fragment.text.substring(end)));
    return TextSpan(children: spans);
  }
  return switch (fragment) {
    ChatTextFragment() ||
    ChatUnknownFragment() => TextSpan(text: fragment.text),
    ChatMentionFragment() => TextSpan(
      text: fragment.text,
      style: (mentionTarget?.matchesMention(fragment) ?? false)
          ? streamerMentionStyle
          : const TextStyle(
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
