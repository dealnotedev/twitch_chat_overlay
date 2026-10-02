import 'package:flutter/widgets.dart';
import 'package:twitch_chat_overlay/chat/emote_catalog.dart';

class ChatEmoteScope extends InheritedWidget {
  const ChatEmoteScope({
    required this.catalog,
    required super.child,
    super.key,
  });

  final EmoteCatalog catalog;

  static EmoteCatalog of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatEmoteScope>()?.catalog ??
      const EmoteCatalog.empty();

  @override
  bool updateShouldNotify(ChatEmoteScope oldWidget) =>
      catalog != oldWidget.catalog;
}
