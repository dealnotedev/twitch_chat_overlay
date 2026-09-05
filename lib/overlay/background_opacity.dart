import 'package:flutter/widgets.dart';

/// Changes painted backgrounds without fading text, emotes or Twitch artwork.
class BackgroundOpacity extends InheritedWidget {
  const BackgroundOpacity({
    required this.opacity,
    required super.child,
    super.key,
  });

  final double opacity;

  static Color colorOf(BuildContext context, Color color) {
    final opacity =
        context
            .dependOnInheritedWidgetOfExactType<BackgroundOpacity>()
            ?.opacity ??
        1.0;
    return color.withValues(alpha: color.a * opacity);
  }

  @override
  bool updateShouldNotify(BackgroundOpacity oldWidget) =>
      opacity != oldWidget.opacity;
}
