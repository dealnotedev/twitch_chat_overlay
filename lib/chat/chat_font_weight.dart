import 'package:flutter/material.dart';
import 'package:twitch_chat_overlay/chat/chat_readability.dart';

/// Adjusts text weight only within the chat timeline.
class ChatFontWeight extends InheritedWidget {
  const ChatFontWeight({required this.value, required super.child, super.key});

  static const int defaultWeight = 500;
  static const int minimum = 300;
  static const int maximum = 900;
  static const int step = 100;
  static const int divisions = (maximum - minimum) ~/ step;

  final int value;

  static int normalize(int value) =>
      (value.clamp(minimum, maximum) / step).round() * step;

  static FontWeight resolve(
    BuildContext context, [
    FontWeight original = FontWeight.w500,
  ]) {
    final setting = context
        .dependOnInheritedWidgetOfExactType<ChatFontWeight>();
    final delta = normalize(setting?.value ?? defaultWeight) - defaultWeight;
    final weight = (original.value + delta).clamp(minimum, maximum);
    return FontWeight.values[weight ~/ step - 1];
  }

  static TextStyle readableStyleOf(BuildContext context) =>
      chatReadableStyle.copyWith(fontWeight: resolve(context));

  static TextStyle mentionStyleOf(BuildContext context) => streamerMentionStyle
      .copyWith(fontWeight: resolve(context, FontWeight.w700));

  @override
  bool updateShouldNotify(ChatFontWeight oldWidget) => value != oldWidget.value;
}
