import 'package:flutter/widgets.dart';

/// Number of complete GIF cycles: -1 means unlimited; zero shows the first frame.
class GifPlayback extends InheritedWidget {
  const GifPlayback({required this.playCount, required super.child, super.key})
    : assert(playCount >= unlimitedCount && playCount <= maximumCount);

  static const unlimitedCount = -1;
  static const defaultCount = unlimitedCount;
  static const maximumCount = 60;
  final int playCount;

  static int countOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GifPlayback>()?.playCount ??
      defaultCount;

  @override
  bool updateShouldNotify(GifPlayback oldWidget) =>
      playCount != oldWidget.playCount;
}
