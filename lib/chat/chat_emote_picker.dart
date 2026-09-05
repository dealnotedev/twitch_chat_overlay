import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:twitch_chat_overlay/chat/chat_composer.dart';
import 'package:twitch_chat_overlay/l10n/generated/app_localizations.dart';
import 'package:twitch_chat_overlay/twitch/twitch_emotes.dart';

class ChatEmotePicker extends StatefulWidget {
  const ChatEmotePicker({
    required this.emotes,
    required this.tapGroup,
    required this.onSelected,
    required this.onReload,
    required this.onAuthorize,
    required this.onClose,
    super.key,
  });

  final Future<List<TwitchEmote>> emotes;
  final Object tapGroup;
  final ValueChanged<TwitchEmote> onSelected;
  final VoidCallback onReload;
  final VoidCallback onAuthorize;
  final VoidCallback onClose;

  @override
  State<ChatEmotePicker> createState() => _ChatEmotePickerState();
}

class _ChatEmotePickerState extends State<ChatEmotePicker> {
  final ScrollController _scroll = ScrollController();
  String _query = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TapRegion(
      groupId: widget.tapGroup,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        },
        child: Material(
          key: const ValueKey('chat-emote-picker'),
          color: const Color(0xFF18181B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFF46464F)),
          ),
          clipBehavior: Clip.antiAlias,
          child: DefaultTextStyle(
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: Color(0xFFEFEFF1),
            ),
            child: FutureBuilder<List<TwitchEmote>>(
              future: widget.emotes,
              builder: (context, snapshot) {
                final emotes = (snapshot.data ?? const <TwitchEmote>[])
                    .where(
                      (emote) =>
                          emote.name.toLowerCase().contains(_query) ||
                          emote.ownerName.toLowerCase().contains(_query),
                    )
                    .toList();
                return CustomScrollView(
                  controller: _scroll,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 12, right: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.emotes,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ChatIconButton(
                              key: const ValueKey('refresh-emotes'),
                              label: l10n.refreshEmotes,
                              showTooltip: false,
                              icon: Icons.refresh_rounded,
                              onPressed:
                                  snapshot.connectionState ==
                                      ConnectionState.waiting
                                  ? null
                                  : widget.onReload,
                            ),
                            ChatIconButton(
                              key: const ValueKey('close-emotes'),
                              label: l10n.closeEmotes,
                              showTooltip: false,
                              icon: Icons.close_rounded,
                              onPressed: widget.onClose,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (snapshot.connectionState == ConnectionState.done &&
                        !snapshot.hasError)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                          child: TextField(
                            groupId: widget.tapGroup,
                            style: const TextStyle(fontSize: 12),
                            onChanged: (query) {
                              setState(
                                () => _query = query.trim().toLowerCase(),
                              );
                              if (_scroll.hasClients) _scroll.jumpTo(0);
                            },
                            decoration: InputDecoration(
                              hintText: l10n.searchEmotes,
                              isDense: true,
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 17,
                              ),
                              prefixIconConstraints: const BoxConstraints(
                                minWidth: 32,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              filled: true,
                              fillColor: const Color(0xFF25252C),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: const BorderSide(
                                  color: Color(0xFF46464F),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(5),
                                borderSide: const BorderSide(
                                  color: Color(0xFF9146FF),
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (snapshot.connectionState != ConnectionState.done)
                      const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFBF94FF),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (snapshot.connectionState == ConnectionState.done &&
                        snapshot.hasError)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                snapshot.error is TwitchEmotePermissionRequired
                                    ? l10n.emotesPermissionRequired
                                    : l10n.emotesLoadFailed,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFBF94FF),
                                ),
                                onPressed:
                                    snapshot.error
                                        is TwitchEmotePermissionRequired
                                    ? widget.onAuthorize
                                    : widget.onReload,
                                child: Text(
                                  snapshot.error
                                          is TwitchEmotePermissionRequired
                                      ? l10n.enableEmotes
                                      : l10n.retry,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (snapshot.connectionState == ConnectionState.done &&
                        !snapshot.hasError)
                      if (emotes.isEmpty)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              _query.isEmpty
                                  ? l10n.noEmotes
                                  : l10n.noMatchingEmotes,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      else
                        ..._emoteSlivers(emotes, l10n),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Iterable<Widget> _emoteSlivers(
    List<TwitchEmote> emotes,
    AppLocalizations l10n,
  ) sync* {
    final groups = <String, List<TwitchEmote>>{};
    for (final emote in emotes) {
      groups.putIfAbsent(emote.ownerId, () => []).add(emote);
    }
    String ownerName(TwitchEmote emote) => emote.ownerId.isEmpty
        ? 'Twitch'
        : emote.ownerName.isEmpty
        ? l10n.unknownEmoteOwner
        : emote.ownerName;
    final owners = groups.values.toList()
      ..sort((a, b) {
        final first = a.first;
        final second = b.first;
        // Channel collections first, then Twitch's platform-wide emotes.
        if (first.ownerId.isEmpty != second.ownerId.isEmpty) {
          return first.ownerId.isEmpty ? 1 : -1;
        }
        final owner = ownerName(first)
            .toLowerCase()
            .compareTo(ownerName(second).toLowerCase());
        if (owner != 0) return owner;
        return first.ownerId.compareTo(second.ownerId);
      });
    for (final group in owners) {
      group.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      yield SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Text(
            ownerName(group.first),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
      yield SliverPadding(
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        sliver: SliverGrid.builder(
          itemCount: group.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 44,
            mainAxisSpacing: 3,
            crossAxisSpacing: 3,
          ),
          itemBuilder: (context, index) {
            final emote = group[index];
            return Semantics(
              key: ValueKey('emote-${emote.id}'),
              label: emote.name,
              button: true,
              child: InkWell(
                onTap: () => widget.onSelected(emote),
                borderRadius: BorderRadius.circular(5),
                splashFactory: NoSplash.splashFactory,
                hoverColor: const Color(0xFF35353D),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: CachedNetworkImage(
                    imageUrl: emote.imageUrl,
                    fit: BoxFit.contain,
                    fadeInDuration: Duration.zero,
                    placeholder: (_, _) => const Icon(
                      Icons.more_horiz,
                      size: 16,
                      color: Color(0xFFADADB8),
                    ),
                    errorWidget: (_, _, _) => const Icon(
                      Icons.image_not_supported_outlined,
                      size: 17,
                      color: Color(0xFFADADB8),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
  }
}
