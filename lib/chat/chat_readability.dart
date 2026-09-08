import 'package:flutter/material.dart';

/// A soft shadow keeps text legible without thickening the glyph outlines.
const chatReadableStyle = TextStyle(
  color: Colors.white,
  fontWeight: FontWeight.w400,
  shadows: [
    Shadow(color: Color(0x99000000), blurRadius: 2, offset: Offset(0, 1)),
  ],
);

/// Keep Twitch hues with at least 4.5:1 contrast against black.
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

/// Shared emphasis for the broadcaster in mentions and reply attribution.
const streamerMentionStyle = TextStyle(
  color: Color(0xFFF0E6FF),
  fontWeight: FontWeight.w700,
  decoration: TextDecoration.underline,
  decorationColor: Color(0xFFBF94FF),
  decorationThickness: 1.5,
);
