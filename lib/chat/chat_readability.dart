import 'package:flutter/material.dart';

/// Opaque glyph protection, independent of the panel background opacity.
/// Sharp shadows preserve inline emotes and a single text layout.
const chatReadableStyle = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w500,
  shadows: [
    Shadow(color: Color(0xE6000000), blurRadius: 4),
    Shadow(color: Colors.black, offset: Offset(-1, 0)),
    Shadow(color: Colors.black, offset: Offset(1, 0)),
    Shadow(color: Colors.black, offset: Offset(0, -1)),
    Shadow(color: Colors.black, offset: Offset(0, 1)),
    Shadow(color: Colors.black, offset: Offset(-0.75, -0.75)),
    Shadow(color: Colors.black, offset: Offset(0.75, -0.75)),
    Shadow(color: Colors.black, offset: Offset(-0.75, 0.75)),
    Shadow(color: Colors.black, offset: Offset(0.75, 0.75)),
  ],
);

/// Keep Twitch hues with at least 4.5:1 contrast against the black contour.
Color readableChatColor(Color color) {
  final opaque = color.withValues(alpha: 1);
  if (opaque.computeLuminance() >= 0.175) return opaque;
  var low = 0.0;
  var high = 1.0;
  for (var i = 0; i < 12; i++) {
    final mix = (low + high) / 2;
    if (Color.lerp(opaque, Colors.white, mix)!.computeLuminance() < 0.175) {
      low = mix;
    } else {
      high = mix;
    }
  }
  return Color.lerp(opaque, Colors.white, high)!;
}
