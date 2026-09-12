/// Font size of ordinary chat messages, in logical pixels.
abstract final class ChatFontSize {
  static const double defaultSize = 13.5;
  static const double minimum = 12;
  static const double maximum = 24;
  static const double step = 0.25;
  static const int divisions = 48;

  static double normalize(double value) => value.isFinite
      ? (value.clamp(minimum, maximum) / step).round() * step
      : defaultSize;
}
